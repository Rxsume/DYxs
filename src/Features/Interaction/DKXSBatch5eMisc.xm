//
//  DKXSBatch5eMisc.xm
//  DYxs 全量合并第 5 批剩余部分（5e）staging，未并入 DYxs 源码。
//  移植来源：Wtrwx/DYYY 的 DYYY.xm（评论具体时间、关注/收藏二次确认、
//  隐藏系统顶栏），符号一律 DYYY* -> DKXS*。
//
//  与上游的差异（主 agent 复核必读）：
//  1. 二次确认弹窗：上游用自绘的 DYYYBottomAlertView（带头像），本文件改用
//     系统 UIAlertController（与优先小批的选择 UI 口径一致），头像不展示，
//     只显示昵称标题 + 个性签名正文；收藏确认沿用上游文案“是否确认/取消收藏？”。
//  2. 关注确认的两处入口（播放页头像元素、头像关注引导控制器）都搬了；
//     但引导控制器里的 onUnFollowViewClicked / followPromptViewClicked
//     只与 DKXSHideFollowPromptView（第 3 批）有关，本文件不重复搬。
//  3. 评论具体时间是三件套，必须一起上：AWEDateTimeFormatter 把相对时间
//     改写成“时间戳 + 空格”的原始串，AWERLVirtualLabel 再把它解析成
//     yyyy-MM-dd HH:mm:ss；只搬一半会满屏显示时间戳数字。
//     Swift 评论标签组（%group）按上游做法运行时取类再 %init，
//     40.8.0 若类改名则该组静默不装（其余两处仍生效）。
//  4. 隐藏系统顶栏共 6 个 VC（FeedRoot / LiveAudience / DetailTable /
//     HotSpot / FullPage / PureContainer），另带上游的清屏条件分支
//     （DKXSHideStatusBarOnClear 且清屏已隐藏元素时也隐藏）；
//     DYxs 现有代码未 hook 任何 prefersStatusBarHidden，无撞点。
//     注意 DKXSHideStatusbar 键已被第 2 批清屏文件读取（清屏时刷新状态栏
//     的守卫条件），本开关与清屏逻辑是同一键、同一语义，不冲突。
//
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL DKXSMisc5eGetBool(NSString *key) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

// 上游清屏分支的容错版：VC 上若有 hideButton 且其 isElementsHidden 为 YES，
// 且开了 DKXSHideStatusBarOnClear，也隐藏状态栏；取不到 hideButton 时不生效。
static BOOL DKXSStatusBarHiddenByClear(id vc) {
    if (!DKXSMisc5eGetBool(@"DKXSHideStatusBarOnClear")) return NO;
    id hideButton = nil;
    @try {
        hideButton = [vc valueForKey:@"hideButton"];
    } @catch (__unused NSException *exception) {
    }
    if (!hideButton || ![hideButton respondsToSelector:@selector(isElementsHidden)]) return NO;
    @try {
        return [hideButton isElementsHidden];
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

// ---- 评论具体时间 ----
%hook AWEDateTimeFormatter
+ (id)formattedDateForTimestamp:(double)timestamp {
    if (!DKXSMisc5eGetBool(@"DKXSCommentExactTime")) return %orig(timestamp);
    return [NSString stringWithFormat:@"%.0f ", timestamp];
}
%end

%hook AWERLVirtualLabel
- (void)setText:(NSString *)text {
    if (!DKXSMisc5eGetBool(@"DKXSCommentExactTime") || !text || text.length == 0) {
        %orig(text);
        return;
    }
    if ([text isEqualToString:@"回复"]) {
        %orig(@"");
        return;
    }
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^(\\d{10,13})([\\s\\S]*)" options:0 error:&error];
    NSTextCheckingResult *match = [regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (match) {
        NSString *rawTs = [text substringWithRange:[match rangeAtIndex:1]];
        NSString *suffix = [text substringWithRange:[match rangeAtIndex:2]];
        long long ts = [rawTs longLongValue];
        if (ts > 100000000000) {
            ts = ts / 1000;
        }
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:ts];
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        NSString *formattedDate = [formatter stringFromDate:date];
        NSString *newText = [NSString stringWithFormat:@"%@%@", formattedDate, suffix];
        %orig(newText);
    } else {
        %orig(text);
    }
}
%end

%group DKXSCommentExactTimeGroup
%hook AWECommentSwiftBizUI_CommentInteractionBaseLabel
- (void)setText:(NSString *)text {
    %orig(text);
    if (!DKXSMisc5eGetBool(@"DKXSCommentExactTime")) {
        return;
    }
    UILabel *label = (UILabel *)self;
    if (!text || text.length == 0) return;
    if ([text isEqualToString:@"翻译"] || [text isEqualToString:@"隐藏翻译"]) {
        CGRect currentFrame = label.frame;
        CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
        currentFrame.origin.x = screenWidth - 100.0 - currentFrame.size.width;
        label.frame = currentFrame;
        return;
    }
    UIFont *font = label.font;
    if (font) {
        CGFloat expectedWidth = ceilf([text sizeWithAttributes:@{NSFontAttributeName: font}].width);
        CGRect currentFrame = label.frame;
        if (currentFrame.size.width < expectedWidth && currentFrame.size.width > 0) {
            currentFrame.size.width = expectedWidth;
            label.frame = currentFrame;
            label.clipsToBounds = NO;
        }
    }
}
- (void)setFrame:(CGRect)frame {
    if (!DKXSMisc5eGetBool(@"DKXSCommentExactTime") || ![self respondsToSelector:@selector(text)]) {
        %orig(frame);
        return;
    }
    UILabel *label = (UILabel *)self;
    NSString *text = label.text;
    if (text && text.length > 0) {
        if ([text isEqualToString:@"翻译"] || [text isEqualToString:@"隐藏翻译"]) {
            CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
            frame.origin.x = screenWidth - 100.0 - frame.size.width;
        } else if ([self respondsToSelector:@selector(font)]) {
            UIFont *font = label.font;
            if (font) {
                CGFloat expectedWidth = ceilf([text sizeWithAttributes:@{NSFontAttributeName: font}].width);
                if (frame.size.width < expectedWidth && frame.size.width > 0) {
                    frame.size.width = expectedWidth;
                    label.clipsToBounds = NO;
                }
            }
        }
    }
    %orig(frame);
}
%end
%end

// ---- 关注二次确认 ----
static void DKXSShowFollowConfirm(UIViewController *host, NSString *nickname, NSString *signature, void (^confirm)(void)) {
    NSString *title = nickname.length > 0 ? nickname : @"关注确认";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:signature
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"关注" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if (confirm) confirm();
    }]];
    [host presentViewController:alert animated:YES completion:nil];
}

static void DKXSCollectFollowAuthorInfo(id model, NSString **nicknameOut, NSString **signatureOut) {
    NSString *nickname = @"";
    NSString *signature = @"";
    id author = nil;
    if ([model isKindOfClass:NSClassFromString(@"AWEAwemeModel")]) {
        @try {
            author = [model valueForKey:@"author"];
        } @catch (__unused NSException *exception) {
        }
    }
    if (author) {
        @try {
            nickname = [author valueForKey:@"nickname"] ?: @"";
            signature = [author valueForKey:@"signature"] ?: @"";
        } @catch (__unused NSException *exception) {
        }
    }
    if (nicknameOut) *nicknameOut = nickname;
    if (signatureOut) *signatureOut = signature;
}

%hook AWEPlayInteractionUserAvatarElement
- (void)onFollowViewClicked:(UITapGestureRecognizer *)gesture {
    if (DKXSMisc5eGetBool(@"DKXSFollowTips")) {
        NSString *nickname = @"";
        NSString *signature = @"";
        id model = nil;
        if ([self respondsToSelector:@selector(model)]) {
            model = [self model];
        }
        DKXSCollectFollowAuthorInfo(model, &nickname, &signature);
        NSMutableString *messageContent = [NSMutableString string];
        if (signature.length > 0) {
            [messageContent appendFormat:@"%@", signature];
        }
        UIViewController *host = nil;
        UIResponder *responder = self.nextResponder;
        while (responder && ![responder isKindOfClass:[UIViewController class]]) {
            responder = responder.nextResponder;
        }
        host = (UIViewController *)responder;
        if (host) {
            DKXSShowFollowConfirm(host, nickname, messageContent, ^{
                %orig(gesture);
            });
        } else {
            %orig;
        }
    } else {
        %orig;
    }
}
%end

%hook AWEPlayInteractionUserAvatarFollowPromptController
- (void)onFollowViewClicked:(UITapGestureRecognizer *)gesture {
    if (DKXSMisc5eGetBool(@"DKXSHideFollowPromptView")) {
        return;
    }
    if (DKXSMisc5eGetBool(@"DKXSFollowTips")) {
        id context = nil;
        if ([self respondsToSelector:@selector(userAvatarContext)]) {
            context = [self valueForKey:@"userAvatarContext"];
        }
        id model = nil;
        @try {
            model = [context valueForKey:@"model"];
        } @catch (__unused NSException *exception) {
        }
        id author = nil;
        @try {
            author = [model valueForKey:@"author"];
        } @catch (__unused NSException *exception) {
        }
        NSString *nickname = @"";
        NSString *signature = @"";
        if (author) {
            @try {
                nickname = [author valueForKey:@"nickname"] ?: @"";
                signature = [author valueForKey:@"signature"] ?: @"";
            } @catch (__unused NSException *exception) {
            }
        }
        NSMutableString *messageContent = [NSMutableString string];
        if (signature.length > 0) {
            [messageContent appendFormat:@"%@", signature];
        }
        UIViewController *host = (UIViewController *)self;
        DKXSShowFollowConfirm(host, nickname, messageContent, ^{
            %orig(gesture);
        });
    } else {
        %orig;
    }
}
%end

// ---- 收藏二次确认 ----
%hook AWEFeedVideoButton
- (id)touchUpInsideBlock {
    id r = %orig;
    if (DKXSMisc5eGetBool(@"DKXSCollectTips") && [self.accessibilityLabel isEqualToString:@"收藏"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController *host = nil;
            UIResponder *responder = self.nextResponder;
            while (responder && ![responder isKindOfClass:[UIViewController class]]) {
                responder = responder.nextResponder;
            }
            host = (UIViewController *)responder;
            if (!host) return;
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"收藏确认"
                                                                           message:@"是否确认/取消收藏？"
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"确认" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                if (r && [r isKindOfClass:NSClassFromString(@"NSBlock")]) {
                    ((void (^)(void))r)();
                }
            }]];
            [host presentViewController:alert animated:YES completion:nil];
        });
        return nil;
    }
    return r;
}
%end

// ---- 隐藏系统顶栏（6 个 VC；hideButton 是上游清屏按钮的同名变量，
// 本文件用 valueForKey 容错取，取不到时只走 HideStatusbar 分支） ----
%hook AWEFeedRootViewController
- (BOOL)prefersStatusBarHidden {
    if (DKXSMisc5eGetBool(@"DKXSHideStatusbar") || DKXSStatusBarHiddenByClear(self)) return YES;
    return %orig;
}
%end

%hook IESLiveAudienceViewController
- (BOOL)prefersStatusBarHidden {
    if (DKXSMisc5eGetBool(@"DKXSHideStatusbar") || DKXSStatusBarHiddenByClear(self)) return YES;
    return %orig;
}
%end

%hook AWEAwemeDetailTableViewController
- (BOOL)prefersStatusBarHidden {
    if (DKXSMisc5eGetBool(@"DKXSHideStatusbar") || DKXSStatusBarHiddenByClear(self)) return YES;
    return %orig;
}
%end

%hook AWEAwemeHotSpotTableViewController
- (BOOL)prefersStatusBarHidden {
    if (DKXSMisc5eGetBool(@"DKXSHideStatusbar") || DKXSStatusBarHiddenByClear(self)) return YES;
    return %orig;
}
%end

%hook AWEFullPageFeedNewContainerViewController
- (BOOL)prefersStatusBarHidden {
    if (DKXSMisc5eGetBool(@"DKXSHideStatusbar") || DKXSStatusBarHiddenByClear(self)) return YES;
    return %orig;
}
%end

%hook AFDPureModePageContainerViewController
- (BOOL)prefersStatusBarHidden {
    if (DKXSMisc5eGetBool(@"DKXSHideStatusbar") || DKXSStatusBarHiddenByClear(self)) return YES;
    return %orig;
}
%end

%ctor {
    Class swiftLabelClass = NSClassFromString(@"AWECommentSwiftBizUI_CommentInteractionBaseLabel");
    if (swiftLabelClass) {
        %init(DKXSCommentExactTimeGroup, AWECommentSwiftBizUI_CommentInteractionBaseLabel = swiftLabelClass);
    }
}
