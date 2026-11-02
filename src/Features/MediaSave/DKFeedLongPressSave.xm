// 作品长按面板：按开关加入无水印保存项；与原生「保存至相册」重叠时移除原生项，插件项放在原生项的位置。
#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import "DKMediaResolver.h"
#import "DKMediaSaveDiagnostics.h"
#import "DKMediaSaveRuntime.h"
#import "DKMediaSaveTask.h"
#import "DKMediaSelect.h"
#import "DKXSUtils.h"
#import "DKXSInterfaceDownload.h"
#import <objc/runtime.h>

// 原生「保存至相册」与「倍速」的 actionType；插件项用 7701 起的专用段。
static const unsigned long long DKNativeSaveAction = 121;
static const unsigned long long DKNativeSpeedAction = 31;
static const unsigned long long DKFeedActionBase = 7701;

typedef NS_ENUM(NSUInteger, DKFeedSaveKind) {
    DKFeedSaveMain,
    DKFeedSaveCurrent,
    DKFeedSaveAll,
    DKFeedSaveCover,
    DKFeedSaveMusic,
};

static NSArray<DKMediaSaveItem *> *DKFeedItems(id aweme, DKFeedSaveKind kind) {
    NSDictionary *dict = DKResolveAweme(aweme);
    DKMediaSaveItem *item = nil;
    switch (kind) {
        case DKFeedSaveCurrent: return DKSelectAlbumItems(dict, NO);
        case DKFeedSaveAll: return DKSelectAlbumItems(dict, YES);
        case DKFeedSaveMain: item = DKSelectAwemeMain(dict); break;
        case DKFeedSaveCover: item = DKSelectAwemeCover(dict); break;
        case DKFeedSaveMusic: item = DKSelectAwemeMusic(dict); break;
    }
    return item ? @[item] : @[];
}

// 先收起面板再开始保存；收起回调缺失时延时兜底，只执行一次。
static void DKFeedRun(id aweme, DKFeedSaveKind kind, NSString *source, UIWindowScene *scene) {
    __block BOOL started = NO;
    void (^run)(void) = ^{
        if (started) return;
        started = YES;
        DKMediaSaveRun(DKFeedItems(aweme, kind), source, scene);
    };
    Class managerClass = NSClassFromString(@"AWELongPressPanelManager");
    AWELongPressPanelManager *manager = [managerClass respondsToSelector:@selector(shareInstance)] ? [managerClass shareInstance] : nil;
    if ([manager respondsToSelector:@selector(dismissWithAnimation:completion:)]) {
        [manager dismissWithAnimation:YES completion:^{ dispatch_async(dispatch_get_main_queue(), run); }];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), run);
}

static AWELongPressPanelBaseViewModel *DKFeedViewModel(id aweme, NSString *title, unsigned long long action, DKFeedSaveKind kind, UIViewController *panel) {
    Class cls = NSClassFromString(@"AWELongPressPanelBaseViewModel");
    if (!cls) return nil;
    AWELongPressPanelBaseViewModel *model = [cls new];
    model.awemeModel = aweme;
    model.actionType = action;
    model.duxIconName = @"ic_boxarrowdownhigh_outlined";
    model.describeString = title;
    NSString *source = [@"长按面板·" stringByAppendingString:title];
    __weak UIViewController *weakPanel = panel;
    model.action = ^{ DKFeedRun(aweme, kind, source, DKPromptSceneForResponder(weakPanel)); };
    return model;
}

static AWELongPressPanelViewGroupModel *DKFeedGroup(id source, NSArray *items) {
    Class cls = NSClassFromString(@"AWELongPressPanelViewGroupModel");
    if (!cls) return nil;
    AWELongPressPanelViewGroupModel *group = [cls new];
    if ([source isKindOfClass:cls]) {
        AWELongPressPanelViewGroupModel *original = source;
        group.groupType = original.groupType;
        group.isModern = original.isModern;
        group.cellHeight = original.cellHeight;
        group.hasMore = original.hasMore;
        // 原生行数跟随条目数时同步新条目数，否则保持原值。
        long long rows = original.numberOfRowsInSection;
        group.numberOfRowsInSection = rows == (long long)original.groupArr.count ? (long long)items.count : rows;
    }
    group.groupArr = items;
    return group;
}

static unsigned long long DKFeedActionType(id item) {
    id value = DKMediaValue(item, @"actionType");
    return [value respondsToSelector:@selector(unsignedLongLongValue)] ? [value unsignedLongLongValue] : 0;
}

static NSArray *DKFeedMerge(NSArray *groups, NSArray *added, BOOL removeNative) {
    NSInteger nativeGroup = -1, nativeIndex = -1, speedGroup = -1;
    for (NSUInteger g = 0; g < groups.count; g++) {
        NSArray *items = DKMediaValue(groups[g], @"groupArr");
        if (![items isKindOfClass:NSArray.class]) continue;
        for (NSUInteger i = 0; i < items.count; i++) {
            unsigned long long type = DKFeedActionType(items[i]);
            if (type == DKNativeSaveAction && nativeGroup < 0) { nativeGroup = g; nativeIndex = i; }
            if (type == DKNativeSpeedAction && speedGroup < 0) speedGroup = g;
        }
    }
    NSMutableArray *out = [groups mutableCopy];
    if (nativeGroup >= 0) {
        NSMutableArray *items = [DKMediaValue(groups[nativeGroup], @"groupArr") mutableCopy];
        if (removeNative) [items removeObjectAtIndex:nativeIndex];
        NSUInteger at = removeNative ? nativeIndex : nativeIndex + 1;
        [items insertObjects:added atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(at, added.count)]];
        id group = DKFeedGroup(groups[nativeGroup], items);
        if (group) out[nativeGroup] = group;
    } else if (speedGroup >= 0) {
        NSMutableArray *items = [DKMediaValue(groups[speedGroup], @"groupArr") mutableCopy];
        [items addObjectsFromArray:added];
        id group = DKFeedGroup(groups[speedGroup], items);
        if (group) out[speedGroup] = group;
    } else {
        id last = groups.lastObject;
        NSArray *lastItems = DKMediaValue(last, @"groupArr");
        id group = DKFeedGroup(last, added);
        // 末组是空分组（作品长按菜单的原生项全部移除后留下的）时填入这一组，否则另起一组。
        if (group && [lastItems isKindOfClass:NSArray.class] && lastItems.count == 0) out[out.count - 1] = group;
        else if (group) [out addObject:group];
    }
    return out;
}

static char kDKFeedPanelCacheKey;

// 第 4 批合并段 4-L2 步骤 2：AWELongPressPanelViewGroupModel 分类声明（只声明不实现；
// 实现由同批 DKXSLongPressPanelHooks.xm 的 %property 提供）。
@interface AWELongPressPanelViewGroupModel (DKXSBatch4)
@property(nonatomic, assign) BOOL isDKXSCustomGroup;
@end

// 第 4 批合并段 4-L1：长按新增项与原始组处理（staging 原文，另含文末一处标明的接口保存接线增补）。
static BOOL DKXSLongPressGetBool(NSString *key) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

static void DKXSLongPressDismissPanel(void) {
    Class managerClass = NSClassFromString(@"AWELongPressPanelManager");
    id manager = [managerClass respondsToSelector:@selector(shareInstance)] ? [managerClass shareInstance] : nil;
    if ([manager respondsToSelector:@selector(dismissWithAnimation:completion:)]) {
        [manager dismissWithAnimation:YES completion:nil];
    }
}

static NSString *DKXSLongPressCleanShareURL(NSString *url) {
    // 上游 DYYYUtils cleanShareURL 原样：只去 ? 后的部分。
    if (!url || url.length == 0) return url;
    NSRange questionMarkRange = [url rangeOfString:@"?"];
    if (questionMarkRange.location != NSNotFound) return [url substringToIndex:questionMarkRange.location];
    return url;
}

static UIViewController *DKXSLongPressTopViewController(void) {
    return [DKXSUtils topView];
}

// 精简与按文本隐藏，作用于原始组（上游 Modern dataArray 前半段原样，键改名）。
// 精简开：返回空数组（原生项全清；DYxs 保存项与下面自定义组仍会追加，
// 与上游“只保留自定义功能”在 DYxs 语境下的对应物一致，见 REPORT.md）。
// 精简关且隐藏文本非空：按 describeString 精确或部分匹配（不区分大小写）过滤各组。
static NSArray *DKXSLongPressProcessOriginal(NSArray *original) {
    if (![original isKindOfClass:[NSArray class]]) return original;
    if (DKXSLongPressGetBool(@"DKXSSimplifyLongPressPanel")) return @[];
    NSString *hidePanelItems = [[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSHidePanelItems"];
    NSMutableSet<NSString *> *hideItemsLowerSet = [NSMutableSet set];
    if (hidePanelItems && hidePanelItems.length > 0) {
        NSString *normalizedItems = [hidePanelItems stringByReplacingOccurrencesOfString:@"，" withString:@","];
        for (NSString *item in [normalizedItems componentsSeparatedByString:@","]) {
            NSString *trimmedItem = [item stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmedItem.length > 0) [hideItemsLowerSet addObject:[trimmedItem lowercaseString]];
        }
    }
    if (hideItemsLowerSet.count == 0) return original;
    NSMutableArray *modifiedOriginalGroups = [NSMutableArray array];
    Class groupClass = NSClassFromString(@"AWELongPressPanelViewGroupModel");
    for (id group in original) {
        if (groupClass && [group isKindOfClass:groupClass]) {
            AWELongPressPanelViewGroupModel *groupModel = (AWELongPressPanelViewGroupModel *)group;
            NSMutableArray *filteredGroupArr = [NSMutableArray array];
            for (id item in groupModel.groupArr) {
                BOOL shouldHide = NO;
                if ([item respondsToSelector:@selector(describeString)]) {
                    NSString *descString = [item describeString];
                    if (descString && descString.length > 0) {
                        NSString *descLower = [descString lowercaseString];
                        if ([hideItemsLowerSet containsObject:descLower]) {
                            shouldHide = YES;
                        } else {
                            for (NSString *hideItemLower in hideItemsLowerSet) {
                                if ([descLower containsString:hideItemLower] || [hideItemLower containsString:descLower]) {
                                    shouldHide = YES;
                                    break;
                                }
                            }
                        }
                    }
                }
                if (!shouldHide) [filteredGroupArr addObject:item];
            }
            if (filteredGroupArr.count > 0) {
                AWELongPressPanelViewGroupModel *filteredGroup = [[groupClass alloc] init];
                filteredGroup.groupType = groupModel.groupType;
                filteredGroup.isModern = groupModel.isModern;
                filteredGroup.groupArr = filteredGroupArr;
                [modifiedOriginalGroups addObject:filteredGroup];
            }
        } else {
            [modifiedOriginalGroups addObject:group];
        }
    }
    return modifiedOriginalGroups;
}

static AWELongPressPanelBaseViewModel *DKXSLongPressMakeItem(id aweme, NSString *title, NSString *icon, unsigned long long actionType, void (^action)(void)) {
    Class cls = NSClassFromString(@"AWELongPressPanelBaseViewModel");
    if (!cls) return nil;
    AWELongPressPanelBaseViewModel *model = [cls new];
    model.awemeModel = aweme;
    model.actionType = actionType;
    model.duxIconName = icon;
    model.describeString = title;
    model.action = action;
    return model;
}

// 过滤用户：上游用 BottomAlertView + KeywordListView；本片段用系统弹窗实现同款功能。
// 存储格式与上游一致：逗号分隔的“昵称-短ID”，供以后过滤逻辑读取。
static void DKXSLongPressFilterUserAction(id aweme) {
    NSString *nickname = [aweme valueForKey:@"nickname"] ?: nil;
    id author = [aweme valueForKey:@"author"];
    if (author) {
        nickname = [author valueForKey:@"nickname"] ?: @"未知用户";
    } else {
        nickname = @"未知用户";
    }
    NSString *shortId = @"";
    if (author) shortId = [author valueForKey:@"shortID"] ?: @"";
    NSString *currentUserFilter = [NSString stringWithFormat:@"%@-%@", nickname, shortId];
    NSString *savedUsers = [[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSFilterUsers"] ?: @"";
    NSArray *userArray = savedUsers.length > 0 ? [savedUsers componentsSeparatedByString:@","] : @[];
    BOOL userExists = NO;
    for (NSString *userInfo in userArray) {
        NSArray *components = [userInfo componentsSeparatedByString:@"-"];
        if (components.count >= 2 && shortId.length > 0 && [[components lastObject] isEqualToString:shortId]) {
            userExists = YES;
            break;
        }
    }
    UIViewController *top = DKXSLongPressTopViewController();
    if (!top) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"过滤用户视频"
                                                                   message:[NSString stringWithFormat:@"用户: %@ (ID: %@)", nickname, shortId]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    NSString *toggleTitle = userExists ? @"取消过滤" : @"添加过滤";
    [alert addAction:[UIAlertAction actionWithTitle:toggleTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        NSMutableArray *updatedUsers = [userArray mutableCopy];
        if (userExists) {
            NSMutableArray *toRemove = [NSMutableArray array];
            for (NSString *userInfo in updatedUsers) {
                NSArray *components = [userInfo componentsSeparatedByString:@"-"];
                if (components.count >= 2 && [[components lastObject] isEqualToString:shortId]) [toRemove addObject:userInfo];
            }
            [updatedUsers removeObjectsInArray:toRemove];
            [DKXSUtils showToast:@"已从过滤列表中移除此用户"];
        } else {
            [updatedUsers addObject:currentUserFilter];
            [DKXSUtils showToast:@"已添加此用户到过滤列表"];
        }
        [[NSUserDefaults standardUserDefaults] setObject:[updatedUsers componentsJoinedByString:@","] forKey:@"DKXSFilterUsers"];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"管理过滤列表" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        UIViewController *top2 = DKXSLongPressTopViewController();
        if (!top2) return;
        UIAlertController *edit = [UIAlertController alertControllerWithTitle:@"过滤用户列表"
                                                                      message:@"每行一个“昵称-短ID”，用逗号分隔"
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [edit addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.text = [[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSFilterUsers"] ?: @"";
        }];
        [edit addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
            NSString *text = edit.textFields.firstObject.text ?: @"";
            [[NSUserDefaults standardUserDefaults] setObject:text forKey:@"DKXSFilterUsers"];
            [DKXSUtils showToast:@"过滤用户列表已更新"];
        }]];
        [edit addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [top2 presentViewController:edit animated:YES completion:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:alert animated:YES completion:nil];
}

// 过滤文案：上游用 FilterSettingsView（从文案中选词）+ KeywordListView；
// 本片段用系统输入框实现同款功能（用户输入关键词；管理入口可编辑已存关键词串）。
static void DKXSLongPressFilterKeywordAction(id aweme) {
    NSString *descText = [aweme valueForKey:@"descriptionString"] ?: @"";
    UIViewController *top = DKXSLongPressTopViewController();
    if (!top) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"过滤关键词调整"
                                                                   message:@"输入要过滤的关键词，保存后追加到过滤词列表"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = descText;
        textField.placeholder = @"输入关键词";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"添加过滤词" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        NSString *selectedText = alert.textFields.firstObject.text ?: @"";
        if (selectedText.length == 0) return;
        NSString *currentKeywords = [[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSFilterKeywords"] ?: @"";
        NSString *newKeywords = currentKeywords.length > 0
            ? [NSString stringWithFormat:@"%@,%@", currentKeywords, selectedText]
            : selectedText;
        [[NSUserDefaults standardUserDefaults] setObject:newKeywords forKey:@"DKXSFilterKeywords"];
        [DKXSUtils showToast:[NSString stringWithFormat:@"已添加过滤词: %@", selectedText]];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"管理关键词" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        UIViewController *top2 = DKXSLongPressTopViewController();
        if (!top2) return;
        UIAlertController *edit = [UIAlertController alertControllerWithTitle:@"设置过滤关键词"
                                                                      message:@"多个关键词用逗号分隔"
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [edit addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.text = [[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSFilterKeywords"] ?: @"";
        }];
        [edit addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
            NSString *text = edit.textFields.firstObject.text ?: @"";
            [[NSUserDefaults standardUserDefaults] setObject:text forKey:@"DKXSFilterKeywords"];
            [DKXSUtils showToast:@"过滤关键词已更新"];
        }]];
        [edit addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [top2 presentViewController:edit animated:YES completion:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:alert animated:YES completion:nil];
}

// 定时关闭：上游用 CustomInputView + ConfirmCloseView；本片段用系统弹窗实现同款功能。
// 到期确认点“关闭”即 exit(0)，与上游 ConfirmCloseView 的确认行为一致。
// 注意：定时器是进程内 dispatch_after，抖音被杀则定时丢失（上游同款限制）。
static void DKXSLongPressTimerCloseAction(void) {
    NSNumber *shutdownTime = [[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSTimerShutdownTime"];
    BOOL hasActiveTimer = shutdownTime != nil && [shutdownTime doubleValue] > [[NSDate date] timeIntervalSince1970];
    if (hasActiveTimer) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"DKXSTimerShutdownTime"];
        [DKXSUtils showToast:@"已取消定时关闭任务"];
        return;
    }
    NSInteger defaultMinutes = [[NSUserDefaults standardUserDefaults] integerForKey:@"DKXSTimerCloseMinutes"];
    if (defaultMinutes <= 0) defaultMinutes = 5;
    UIViewController *top = DKXSLongPressTopViewController();
    if (!top) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"设置定时关闭时间"
                                                                   message:@"请输入关闭时间（单位：分钟）"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = [NSString stringWithFormat:@"%ld", (long)defaultMinutes];
        textField.keyboardType = UIKeyboardTypeNumberPad;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        NSInteger minutes = [alert.textFields.firstObject.text integerValue];
        if (minutes <= 0) minutes = 5;
        [[NSUserDefaults standardUserDefaults] setInteger:minutes forKey:@"DKXSTimerCloseMinutes"];
        NSInteger seconds = minutes * 60;
        NSTimeInterval shutdownTimeValue = [[NSDate date] timeIntervalSince1970] + seconds;
        [[NSUserDefaults standardUserDefaults] setObject:@(shutdownTimeValue) forKey:@"DKXSTimerShutdownTime"];
        [DKXSUtils showToast:[NSString stringWithFormat:@"抖音将在%ld分钟后关闭...", (long)minutes]];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSNumber *currentShutdownTime = [[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSTimerShutdownTime"];
            if (currentShutdownTime != nil && [currentShutdownTime doubleValue] <= [[NSDate date] timeIntervalSince1970]) {
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"DKXSTimerShutdownTime"];
                UIViewController *top2 = DKXSLongPressTopViewController();
                if (!top2) return;
                UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"定时关闭"
                                                                                 message:@"定时关闭时间已到，是否关闭抖音？"
                                                                          preferredStyle:UIAlertControllerStyleAlert];
                [confirm addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
                    exit(0);
                }]];
                [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
                [top2 presentViewController:confirm animated:YES completion:nil];
            }
        });
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:alert animated:YES completion:nil];
}

// 构造本批新增的长按菜单项（不含保存/接口/制作，见文件头说明）。
// 调用方：DKFeedPanelData 的两个 dataArray hook（见片段 4-L2）。
// 返回自定义组数组（Modern 分两行、经典单组置顶），无启用项时返回 nil。
// 组标记 isDKXSCustomGroup 供 DKXSLongPressPanelHooks.xm 的单元格尺寸 hook 识别。
static NSArray *DKXSLongPressCustomGroups(id panel, id aweme, BOOL isModern) {
    NSMutableArray *viewModels = [NSMutableArray array];
    if (DKXSLongPressGetBool(@"DKXSLongPressCopyText")) {
        AWELongPressPanelBaseViewModel *item = DKXSLongPressMakeItem(aweme, @"复制文案", @"ic_xiaoxihuazhonghua_outlined", 671, ^{
            NSString *descText = [aweme valueForKey:@"descriptionString"];
            [[UIPasteboard generalPasteboard] setString:descText];
            [DKXSUtils showToast:@"文案已复制"];
            DKXSLongPressDismissPanel();
        });
        if (item) [viewModels addObject:item];
    }
    if (DKXSLongPressGetBool(@"DKXSLongPressCopyLink")) {
        AWELongPressPanelBaseViewModel *item = DKXSLongPressMakeItem(aweme, @"复制链接", @"ic_share_outlined", 672, ^{
            NSString *shareLink = [aweme valueForKey:@"shareURL"];
            [[UIPasteboard generalPasteboard] setString:DKXSLongPressCleanShareURL(shareLink)];
            [DKXSUtils showToast:@"分享链接已复制"];
            DKXSLongPressDismissPanel();
        });
        if (item) [viewModels addObject:item];
    }
    if (DKXSLongPressGetBool(@"DKXSLongPressFilterUser")) {
        AWELongPressPanelBaseViewModel *item = DKXSLongPressMakeItem(aweme, @"过滤用户", @"ic_userban_outlined_20", 674, ^{
            DKXSLongPressFilterUserAction(aweme);
        });
        if (item) [viewModels addObject:item];
    }
    if (DKXSLongPressGetBool(@"DKXSLongPressFilterTitle")) {
        AWELongPressPanelBaseViewModel *item = DKXSLongPressMakeItem(aweme, @"过滤文案", @"ic_funnel_outlined_20", 675, ^{
            DKXSLongPressFilterKeywordAction(aweme);
        });
        if (item) [viewModels addObject:item];
    }
    if (DKXSLongPressGetBool(@"DKXSLongPressTimerClose")) {
        NSNumber *shutdownTime = [[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSTimerShutdownTime"];
        BOOL hasActiveTimer = shutdownTime != nil && [shutdownTime doubleValue] > [[NSDate date] timeIntervalSince1970];
        AWELongPressPanelBaseViewModel *item = DKXSLongPressMakeItem(aweme, hasActiveTimer ? @"取消定时" : @"定时关闭", @"ic_c_alarm_outlined", 676, ^{
            DKXSLongPressDismissPanel();
            DKXSLongPressTimerCloseAction();
        });
        if (item) [viewModels addObject:item];
    }

    // 接线增补（落盘时加，非 staging 原文）：优先小批接口解析的调用方。
    // 门控为 DKXSInterfaceDownload 已填接口地址（未填则不出现，避免死菜单项）；
    // actionType 673 沿用上游接口保存项编号（本批 671/672/674/675/676 未占用 673，DYxs 7701+ 段不撞）。
    if ([[[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSInterfaceDownload"] length] > 0) {
        AWELongPressPanelBaseViewModel *item = DKXSLongPressMakeItem(aweme, @"接口保存", @"ic_boxarrowdown_outlined", 673, ^{
            NSString *shareLink = [aweme valueForKey:@"shareURL"];
            if ([shareLink isKindOfClass:[NSString class]] && shareLink.length > 0) {
                [DKXSInterfaceDownload parseAndDownloadWithShareLink:shareLink];
            }
        });
        if (item) [viewModels addObject:item];
    }
    if (viewModels.count == 0) return nil;
    Class groupClass = NSClassFromString(@"AWELongPressPanelViewGroupModel");
    if (!groupClass) return nil;
    if (!isModern) {
        // 经典面板：上游单组置顶（newGroupModel 置于数组首位）。
        AWELongPressPanelViewGroupModel *group = [[groupClass alloc] init];
        group.isDKXSCustomGroup = YES;
        group.groupArr = viewModels;
        return @[group];
    }
    // Modern 面板：上游两行分配阈值原样。
    NSInteger totalButtons = viewModels.count;
    NSInteger firstRowCount = 0, secondRowCount = 0;
    if (totalButtons <= 2) {
        firstRowCount = totalButtons;
    } else if (totalButtons <= 4) {
        firstRowCount = totalButtons / 2;
        secondRowCount = totalButtons - firstRowCount;
    } else if (totalButtons <= 5) {
        firstRowCount = 3;
        secondRowCount = totalButtons - firstRowCount;
    } else if (totalButtons <= 6) {
        firstRowCount = 4;
        secondRowCount = totalButtons - firstRowCount;
    } else if (totalButtons <= 8) {
        firstRowCount = 4;
        secondRowCount = totalButtons - firstRowCount;
    } else {
        firstRowCount = 5;
        secondRowCount = totalButtons - firstRowCount;
    }
    NSMutableArray *customGroups = [NSMutableArray array];
    if (firstRowCount > 0) {
        AWELongPressPanelViewGroupModel *firstRowGroup = [[groupClass alloc] init];
        firstRowGroup.isDKXSCustomGroup = YES;
        firstRowGroup.groupType = (firstRowCount <= 3) ? 11 : 12;
        firstRowGroup.isModern = YES;
        firstRowGroup.groupArr = [viewModels subarrayWithRange:NSMakeRange(0, firstRowCount)];
        [customGroups addObject:firstRowGroup];
    }
    if (secondRowCount > 0) {
        AWELongPressPanelViewGroupModel *secondRowGroup = [[groupClass alloc] init];
        secondRowGroup.isDKXSCustomGroup = YES;
        secondRowGroup.groupType = (secondRowCount <= 3) ? 11 : 12;
        secondRowGroup.isModern = YES;
        secondRowGroup.groupArr = [viewModels subarrayWithRange:NSMakeRange(firstRowCount, secondRowCount)];
        [customGroups addObject:secondRowGroup];
    }
    return customGroups;
}

static NSArray *DKFeedPanelData(UIViewController *panel, NSArray *original, DKMediaSaveEntry entry) {
    BOOL video = DKPrefBool(DKKeyMediaSaveVideo), current = DKPrefBool(DKKeyMediaSaveCurrentImage);
    BOOL all = DKPrefBool(DKKeyMediaSaveAllImages), cover = DKPrefBool(DKKeyMediaSaveCover), music = DKPrefBool(DKKeyMediaSaveMusic);
    if (!(video || current || all || cover || music) || ![original isKindOfClass:NSArray.class]) return original;
    id aweme = DKMediaValue(panel, @"awemeModel");
    if (![aweme isKindOfClass:NSClassFromString(@"AWEAwemeModel")]) return original;

    // 同一面板、同一作品、同一组开关与当前项时复用已建的插件项。
    NSUInteger mask = video | current << 1 | all << 2 | cover << 3 | music << 4;
    NSString *signature = [NSString stringWithFormat:@"%p|%lu|%@", aweme, (unsigned long)mask, DKMediaValue(aweme, @"currentImageIndex")];
    NSDictionary *cache = objc_getAssociatedObject(panel, &kDKFeedPanelCacheKey);
    if ([cache[@"signature"] isEqualToString:signature]) {
        NSArray *cached = cache[@"added"];
        return cached.count ? DKFeedMerge(original, cached, [cache[@"remove"] boolValue]) : original;
    }
    DKMediaSaveHit(entry);

    NSDictionary *dict = DKResolveAweme(aweme);
    BOOL album = DKSelectAwemeIsAlbum(dict);
    NSMutableArray *added = [NSMutableArray array];
    BOOL removeNative = NO;
    void (^add)(NSString *, NSUInteger, DKFeedSaveKind) = ^(NSString *title, NSUInteger offset, DKFeedSaveKind kind) {
        AWELongPressPanelBaseViewModel *model = DKFeedViewModel(aweme, title, DKFeedActionBase + offset, kind, panel);
        if (model) [added addObject:model];
    };
    if (!album && video && DKSelectAwemeMain(dict)) { add(DKSelectMainTitle(dict), 0, DKFeedSaveMain); removeNative = YES; }
    if (album && current && DKSelectAlbumItems(dict, NO).count) { add(DKSelectAlbumCurrentTitle(dict), 1, DKFeedSaveCurrent); removeNative = YES; }
    if (album && all && [dict[@"images"] count] > 1) add(DKSelectAlbumAllTitle(dict), 2, DKFeedSaveAll);
    if (!album && cover && DKSelectAwemeCover(dict)) add(@"保存封面", 3, DKFeedSaveCover);
    if (music && DKSelectAwemeMusic(dict)) add(@"保存音乐", 4, DKFeedSaveMusic);
    objc_setAssociatedObject(panel, &kDKFeedPanelCacheKey, @{@"signature": signature, @"added": [added copy], @"remove": @(removeNative)},
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return added.count ? DKFeedMerge(original, added, removeNative) : original;
}

%group DKFeedPanelHooks
%hook AWELongPressPanelTableViewController
- (NSArray *)dataArray {
    NSArray *original = DKXSLongPressProcessOriginal(%orig);
    NSArray *merged = DKFeedPanelData(self, original, DKMediaSaveEntryFeedPanel);
    id aweme = DKMediaValue(self, @"awemeModel");
    NSArray *extra = [aweme isKindOfClass:NSClassFromString(@"AWEAwemeModel")]
        ? DKXSLongPressCustomGroups(self, aweme, NO) : nil;
    return extra.count ? [extra arrayByAddingObjectsFromArray:merged] : merged;
}
%end
%end

%group DKFeedModernPanelHooks
%hook AWEModernLongPressPanelTableViewController
- (NSArray *)dataArray {
    NSArray *original = DKXSLongPressProcessOriginal(%orig);
    NSArray *merged = DKFeedPanelData(self, original, DKMediaSaveEntryFeedPanelModern);
    id aweme = DKMediaValue(self, @"awemeModel");
    NSArray *extra = [aweme isKindOfClass:NSClassFromString(@"AWEAwemeModel")]
        ? DKXSLongPressCustomGroups(self, aweme, YES) : nil;
    return extra.count ? [extra arrayByAddingObjectsFromArray:merged] : merged;
}
%end
%end

%ctor {
    DKSettingsRegister(DKKeyMediaSaveVideo, ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyMediaSaveVideo, @"保存视频",
                            @"长按视频出现「保存视频」，保存无水印的高清播放源（HEVC 或 H.264）；视频形式的实况存为实况。开启后移除原生「保存至相册」，作者禁止下载的作品同样可保存。");
    });
    DKSettingsRegister(DKKeyMediaSaveCurrentImage, ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyMediaSaveCurrentImage, @"保存当前图片",
                            @"长按图文出现「保存当前图片」，保存正在看的这一项：图片存原图，实况存为实况，混排视频存为视频，均无水印。开启后移除原生「保存至相册」。");
    });
    DKSettingsRegister(DKKeyMediaSaveAllImages, ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyMediaSaveAllImages, @"保存全部图片", @"长按多图图文出现「保存全部」，按顺序保存全部图片、实况与视频。");
    });
    DKSettingsRegister(DKKeyMediaSaveCover, ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyMediaSaveCover, @"保存封面", @"长按视频出现「保存封面」，保存视频封面图。");
    });
    DKSettingsRegister(DKKeyMediaSaveMusic, ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyMediaSaveMusic, @"保存音乐", @"长按作品出现「保存音乐」，下载背景音乐后用系统分享面板存到文件或发送。");
    });

    Class panel = NSClassFromString(@"AWELongPressPanelTableViewController");
    BOOL installed = DKMediaMethod(panel, @selector(dataArray), "@") && NSClassFromString(@"AWELongPressPanelBaseViewModel");
    if (installed) %init(DKFeedPanelHooks);
    DKMediaSaveInstalled(DKMediaSaveEntryFeedPanel, installed);
    Class modern = NSClassFromString(@"AWEModernLongPressPanelTableViewController");
    BOOL modernInstalled = DKMediaMethod(modern, @selector(dataArray), "@") && ![modern isSubclassOfClass:panel];
    if (modernInstalled) %init(DKFeedModernPanelHooks);
    DKMediaSaveInstalled(DKMediaSaveEntryFeedPanelModern, modernInstalled);
}
