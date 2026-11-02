//
//  DKTopChannelFilter.xm
//  功能：顶部频道 —— 扫描首页顶栏频道，按用户勾选移除。
//
//  实现：
//   - Hook AWEFeedChannelManager 的频道重建入口，过滤前把本次全部频道合并进目录。
//   - 勾选的频道从模型数组与当前 ID 列表中一起去掉；抖音标记为不可删除或主频道的不处理。
//   - 选中频道被移除时改选主频道；原方法执行后从 currentChannels 补记顶栏实际文案。
//   - 设置变更在抖音下一次重建频道（重启）时生效。
//

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKTopChannels.h"
#import "DKUtils.h"

#pragma mark - 目录

NSString *DKTopChannelHideKey(NSString *channelID) {
    return [DKKeyTopChannelHidePrefix stringByAppendingString:channelID ?: @""];
}

NSArray<NSDictionary *> *DKTopChannelCatalog(void) {
    id stored = [NSUserDefaults.standardUserDefaults objectForKey:DKKeyTopChannelCatalog];
    if (![stored isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *catalog = [NSMutableArray array];
    for (id entry in stored) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        id channelID = entry[DKTopChannelFieldID];
        if ([channelID isKindOfClass:NSString.class] && [channelID length]) [catalog addObject:entry];
    }
    return catalog;
}

NSInteger DKTopChannelHiddenCount(void) {
    NSInteger count = 0;
    for (NSDictionary *entry in DKTopChannelCatalog()) {
        if ([entry[DKTopChannelFieldLocked] boolValue]) continue;
        if (DKPrefBool(DKTopChannelHideKey(entry[DKTopChannelFieldID]))) count++;
    }
    return count;
}

static void DKTopChannelSave(NSArray *catalog, NSArray *old) {
    if ([catalog isEqualToArray:old]) return;
    [NSUserDefaults.standardUserDefaults setObject:catalog forKey:DKKeyTopChannelCatalog];
}

#pragma mark - 频道模型

static NSString *DKModelChannelID(id object) {
    if (![object respondsToSelector:@selector(channelID)]) return nil;
    id channelID = ((AWEHPTabNodeModel *)object).channelID;
    return [channelID isKindOfClass:NSString.class] && [channelID length] ? channelID : nil;
}

static BOOL DKModelIsMain(id object) {
    return [object respondsToSelector:@selector(isMainTab)] && ((AWEHPTabNodeModel *)object).isMainTab;
}

static BOOL DKModelLocked(id object) {
    BOOL deletable = ![object respondsToSelector:@selector(deletable)] || ((AWEHPTabNodeModel *)object).deletable;
    return !deletable || DKModelIsMain(object);
}

// 按本次顶栏顺序重写目录；以前记录过、这次没出现的追加在后面，标记 present=NO。
static void DKTopChannelRecord(NSArray *models, NSArray *channelIDs) {
    NSMutableDictionary<NSString *, id> *modelByID = [NSMutableDictionary dictionary];
    for (id model in models) {
        NSString *channelID = DKModelChannelID(model);
        if (channelID && !modelByID[channelID]) modelByID[channelID] = model;
    }

    NSArray<NSDictionary *> *old = DKTopChannelCatalog();
    NSMutableDictionary<NSString *, NSDictionary *> *oldByID = [NSMutableDictionary dictionary];
    for (NSDictionary *entry in old) oldByID[entry[DKTopChannelFieldID]] = entry;

    NSMutableArray *catalog = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id channelID in channelIDs) {
        if (![channelID isKindOfClass:NSString.class] || [seen containsObject:channelID]) continue;
        id model = modelByID[channelID];
        if (!model) continue;
        [seen addObject:channelID];

        id modelTitle = [model respondsToSelector:@selector(title)] ? ((AWEHPTabNodeModel *)model).title : nil;
        NSString *name = [modelTitle isKindOfClass:NSString.class] && [modelTitle length] ? modelTitle : channelID;
        id oldTitle = oldByID[channelID][DKTopChannelFieldTitle];
        NSString *title = [oldTitle isKindOfClass:NSString.class] && [oldTitle length] ? oldTitle : name;
        [catalog addObject:@{
            DKTopChannelFieldID: channelID,
            DKTopChannelFieldName: name,
            DKTopChannelFieldTitle: title,
            DKTopChannelFieldLocked: @(DKModelLocked(model)),
            DKTopChannelFieldPresent: @YES,
        }];
    }
    if (catalog.count == 0) return;

    for (NSDictionary *entry in old) {
        NSString *channelID = entry[DKTopChannelFieldID];
        if ([seen containsObject:channelID]) continue;
        [seen addObject:channelID];
        NSMutableDictionary *stale = [entry mutableCopy];
        stale[DKTopChannelFieldPresent] = @NO;
        [catalog addObject:stale];
    }
    DKTopChannelSave(catalog, old);
}

// 原方法执行后顶栏频道才有实际文案（同城显示为城市名），补记到目录。
static void DKTopChannelRecordTitles(AWEFeedChannelManager *manager) {
    if (![manager respondsToSelector:@selector(currentChannels)]) return;
    NSArray *channels = [manager currentChannels];
    if (![channels isKindOfClass:NSArray.class]) return;

    NSMutableDictionary<NSString *, NSString *> *titleByID = [NSMutableDictionary dictionary];
    for (id channel in channels) {
        if (![channel respondsToSelector:@selector(channelTitle)]) continue;
        NSString *channelID = DKModelChannelID(channel);
        id title = ((AWEFeedChannelObject *)channel).channelTitle;
        if (channelID && [title isKindOfClass:NSString.class] && [title length]) titleByID[channelID] = title;
    }
    if (titleByID.count == 0) return;

    NSArray<NSDictionary *> *old = DKTopChannelCatalog();
    NSMutableArray *catalog = [NSMutableArray arrayWithCapacity:old.count];
    for (NSDictionary *entry in old) {
        NSString *title = titleByID[entry[DKTopChannelFieldID]];
        if (!title || [title isEqual:entry[DKTopChannelFieldTitle]]) {
            [catalog addObject:entry];
            continue;
        }
        NSMutableDictionary *updated = [entry mutableCopy];
        updated[DKTopChannelFieldTitle] = title;
        [catalog addObject:updated];
    }
    DKTopChannelSave(catalog, old);
}

#pragma mark - 钩子

// 第 3 批合并段 3b-M4（顶栏频道移除，14 键整块）：原片段为整方法替换，因本文件已 hook 同方法，
// 改为把片段的 14 键映射表抽为静态函数接入现有过滤循环；现有选中频道重选与 keptIDs 逻辑原样复用。
static BOOL DKXSBatch3ChannelHidden(NSString *channelID) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([channelID isEqualToString:@"homepage_hot_container"]) {
        return [defaults boolForKey:@"DKXSHideHotContainer"];
    } else if ([channelID isEqualToString:@"homepage_follow"]) {
        return [defaults boolForKey:@"DKXSHideFollow"];
    } else if ([channelID isEqualToString:@"homepage_mall"]) {
        return [defaults boolForKey:@"DKXSHideMall"];
    } else if ([channelID isEqualToString:@"homepage_nearby"]) {
        return [defaults boolForKey:@"DKXSHideNearby"];
    } else if ([channelID isEqualToString:@"homepage_groupon"]) {
        return [defaults boolForKey:@"DKXSHideGroupon"];
    } else if ([channelID isEqualToString:@"homepage_tablive"]) {
        return [defaults boolForKey:@"DKXSHideTabLive"];
    } else if ([channelID isEqualToString:@"homepage_pad_hot"]) {
        return [defaults boolForKey:@"DKXSHidePadHot"];
    } else if ([channelID isEqualToString:@"homepage_hangout"]) {
        return [defaults boolForKey:@"DKXSHideHangout"];
    } else if ([channelID isEqualToString:@"homepage_familiar"]) {
        return [defaults boolForKey:@"DKXSHideFriend"];
    } else if ([channelID isEqualToString:@"homepage_playlet_stream"]) {
        return [defaults boolForKey:@"DKXSHidePlaylet"];
    } else if ([channelID isEqualToString:@"homepage_pad_cinema"]) {
        return [defaults boolForKey:@"DKXSHideCinema"];
    } else if ([channelID isEqualToString:@"homepage_pad_kids_v2"]) {
        return [defaults boolForKey:@"DKXSHideKidsV2"];
    } else if ([channelID isEqualToString:@"homepage_pad_game"]) {
        return [defaults boolForKey:@"DKXSHideGame"];
    } else if ([channelID isEqualToString:@"homepage_mediumvideo"]) {
        return [defaults boolForKey:@"DKXSHideMediumVideo"];
    }
    return NO;
}

%hook AWEFeedChannelManager

- (void)reloadChannelWithChannelModels:(id)models currentChannelIDList:(id)channelIDs
                            reloadType:(id)reloadType selectedChannelID:(id)selectedChannelID {
    if (![models isKindOfClass:NSArray.class] || ![channelIDs isKindOfClass:NSArray.class]) {
        %orig;
        return;
    }
    DKTopChannelRecord(models, channelIDs);

    NSMutableSet<NSString *> *hidden = [NSMutableSet set];
    NSMutableArray *keptModels = [NSMutableArray array];
    NSString *mainID = nil;
    for (id model in models) {
        NSString *channelID = DKModelChannelID(model);
        if (channelID && !DKModelLocked(model) && DKPrefBool(DKTopChannelHideKey(channelID))) {
            [hidden addObject:channelID];
            continue;
        }
        // 第 3 批 3b-M4 接入：上游 14 个频道移除键（见上方 DKXSBatch3ChannelHidden）。
        if (channelID && DKXSBatch3ChannelHidden(channelID)) {
            [hidden addObject:channelID];
            continue;
        }
        if (!mainID && channelID && DKModelIsMain(model)) mainID = channelID;
        [keptModels addObject:model];
    }

    NSMutableArray *keptIDs = [NSMutableArray array];
    for (id channelID in channelIDs) {
        if (![hidden containsObject:channelID]) [keptIDs addObject:channelID];
    }

    // 没有要移除的，或移除后顶栏为空：按原参数走。
    if (hidden.count == 0 || keptModels.count == 0 || keptIDs.count == 0) {
        %orig;
        DKTopChannelRecordTitles(self);
        return;
    }

    // 抖音选中失败时不会自行改选，被移除的选中频道换成主频道。
    id selected = selectedChannelID;
    if ([selected isKindOfClass:NSString.class] && [hidden containsObject:selected]) {
        selected = mainID && [keptIDs containsObject:mainID] ? mainID : keptIDs.firstObject;
    }
    %orig(keptModels, keptIDs, reloadType, selected);
    DKTopChannelRecordTitles(self);
}

%end
