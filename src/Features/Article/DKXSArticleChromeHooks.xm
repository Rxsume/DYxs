// 移植自 Si-yi/DYads- 3819b4c（DYYYArticleChromeHooks.xm）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
// 须先 import UIKit：下方的最小接口声明以 UIViewController/UIView 为父类，
// 未引入 UIKit 时编译器找不到父类接口（0.6.9.20 CI run #121 的教训，PR #32 已修）。
#import <UIKit/UIKit.h>
#import "DKXSArticleChrome.h"
#import "DKXSContentComments.h"
#import "DKXSChatEnhancementPolicy.h"


// 最小接口声明（沿用第 8 批写法，不 import 大头文件）：以下被 hook 的类
// 均不在 DKXSAwemeHeaders（39.5 导出）里；富内容占位类见 DKXSArticleChrome.h。
@interface AWESearchArticleContainerViewController : UIViewController
@property (nonatomic, strong, readonly) UIView *topBar;
@property (nonatomic, strong, readonly) UIView *bottomBar;
- (void)setupTopBar;
- (void)updateUIByStyle;
@end
@interface AWESearchArticleDetailTopBarView : UIView
@property (nonatomic, strong, readonly) UIView *containerView;
- (void)updateUIByStyle:(unsigned long long)style mainColor:(id)color;
@end
@interface AWESearchArticleDetailBottomInteractionView : UIView
@property (nonatomic, strong, readonly) UIView *itemStackView;
- (void)updateUIByStyle:(unsigned long long)style mainColor:(id)color;
@end
@interface AWESearchArticleDetailCommentInputView : UIView
- (void)updateUIByStyle:(unsigned long long)style;
@end

%group DKXSArticleHostChromeHooks
%hook AWESearchArticleContainerViewController
- (void)viewDidLoad { %orig; [DKXSArticleChrome beginAppearance:self]; }
- (void)viewWillAppear:(BOOL)animated {
    [DKXSArticleChrome beginAppearance:self]; %orig(animated);
    [UIView performWithoutAnimation:^{ [DKXSArticleChrome synchronize:self]; }];
}
- (void)viewWillLayoutSubviews {
    id token = [DKXSArticleChrome beginGeometryUpdate:self];
    @try { %orig; } @finally { [DKXSArticleChrome endNativeUpdate:token]; }
}
- (void)viewDidLayoutSubviews { %orig; [UIView performWithoutAnimation:^{ [DKXSArticleChrome synchronize:self]; }]; }
- (void)viewDidDisappear:(BOOL)animated { %orig(animated); [DKXSArticleChrome restore:self]; }
- (void)setupTopBar { %orig; [UIView performWithoutAnimation:^{ [DKXSArticleChrome synchronize:self]; }]; }
- (void)updateUIByStyle {
    id token = [DKXSArticleChrome beginNativeUpdate:self];
    @try { %orig; } @finally { [DKXSArticleChrome endNativeUpdate:token]; }
}
%end
%end

%group DKXSArticleTopChromeHooks
%hook AWESearchArticleDetailTopBarView
- (void)layoutSubviews {
    id token = [DKXSArticleChrome beginGeometryUpdate:self];
    @try { %orig; } @finally { [DKXSArticleChrome endNativeUpdate:token]; }
    [DKXSArticleChrome synchronizeForBar:self];
}
- (void)didMoveToWindow { %orig; [DKXSArticleChrome synchronizeForBar:self]; }
- (void)updateUIByStyle:(unsigned long long)style mainColor:(id)color {
    id token = [DKXSArticleChrome beginNativeUpdate:self];
    @try { %orig(style, color); } @finally { [DKXSArticleChrome endNativeUpdate:token]; }
}
%end
%end

%group DKXSArticleBottomChromeHooks
%hook AWESearchArticleDetailBottomInteractionView
- (void)layoutSubviews {
    id token = [DKXSArticleChrome beginGeometryUpdate:self];
    @try { %orig; } @finally { [DKXSArticleChrome endNativeUpdate:token]; }
    [DKXSArticleChrome synchronizeForBar:self];
}
- (void)didMoveToWindow { %orig; [DKXSArticleChrome synchronizeForBar:self]; }
- (void)updateUIByStyle:(unsigned long long)style mainColor:(id)color {
    id token = [DKXSArticleChrome beginNativeUpdate:self];
    @try { %orig(style, color); } @finally { [DKXSArticleChrome endNativeUpdate:token]; }
}
%end
%end

%group DKXSArticleInputChromeHooks
%hook AWESearchArticleDetailCommentInputView
- (void)layoutSubviews {
    id token = [DKXSArticleChrome beginGeometryUpdate:self];
    @try { %orig; } @finally { [DKXSArticleChrome endNativeUpdate:token]; }
    [DKXSArticleChrome synchronizeForBar:self];
}
- (void)updateUIByStyle:(unsigned long long)style {
    id token = [DKXSArticleChrome beginNativeUpdate:self];
    @try { %orig(style); } @finally { [DKXSArticleChrome endNativeUpdate:token]; }
}
%end
%end

%group DKXSRichHostChromeHooks
%hook DKXSRichContentHost
- (void)viewDidLoad { %orig; [DKXSArticleChrome beginAppearance:self]; }
- (void)viewWillAppear:(BOOL)animated {
    [DKXSArticleChrome beginAppearance:self]; %orig(animated);
    [UIView performWithoutAnimation:^{ [DKXSArticleChrome synchronize:self]; }];
}
- (void)viewWillLayoutSubviews {
    id token = [DKXSArticleChrome beginGeometryUpdate:self];
    @try { %orig; } @finally { [DKXSArticleChrome endNativeUpdate:token]; }
}
- (void)viewDidLayoutSubviews { %orig; [UIView performWithoutAnimation:^{ [DKXSArticleChrome synchronize:self]; }]; }
- (void)viewDidDisappear:(BOOL)animated { %orig(animated); [DKXSArticleChrome restore:self]; }
%end
%end

%group DKXSRichTopAreaHooks
%hook DKXSRichContentHost
- (double)topSafeAreaForTabList {
    double native = %orig;
    return [DKXSArticleChrome topAreaForHost:self native:native];
}
%end
%end

%group DKXSRichTopChromeHooks
%hook DKXSRichContentTopBar
- (void)setBackgroundColor:(UIColor *)color { %orig([DKXSArticleChrome backgroundForRichBar:self native:color]); }
- (void)didMoveToSuperview { %orig; [DKXSArticleChrome synchronizeForBar:self]; }
- (void)layoutSubviews {
    id token = [DKXSArticleChrome beginGeometryUpdate:self];
    @try { %orig; } @finally { [DKXSArticleChrome endNativeUpdate:token]; }
    [DKXSArticleChrome synchronizeForBar:self];
}
- (void)didMoveToWindow { %orig; [DKXSArticleChrome synchronizeForBar:self]; }
%end
%end

%group DKXSRichBottomChromeHooks
%hook DKXSRichContentBottomBar
- (void)layoutSubviews {
    id token = [DKXSArticleChrome beginGeometryUpdate:self];
    @try { %orig; } @finally { [DKXSArticleChrome endNativeUpdate:token]; }
    [DKXSArticleChrome synchronizeForBar:self];
}
- (void)didMoveToWindow { %orig; [DKXSArticleChrome synchronizeForBar:self]; }
%end
%end

%group DKXSRichRelationChromeHooks
%hook DKXSRichRelationButton
- (void)layoutSubviews { %orig; [DKXSArticleChrome synchronizeForBar:self]; }
%end
%end
%group DKXSRichCommentsChromeHooks
%hook DKXSRichContentList
- (void)viewDidLayoutSubviews { %orig; [DKXSContentComments synchronizeForList:self]; }
- (void)viewDidAppear:(BOOL)animated { %orig(animated); [DKXSContentComments synchronizeForList:self]; }
%end
%end

@implementation DKXSArticleChrome (Hooks)
+ (void)installHooks {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self installHooks]; }); return; }
    static BOOL hostInstalled, topInstalled, bottomInstalled, inputInstalled;
    static BOOL richHostInstalled, richTopInstalled, richBottomInstalled, richAreaInstalled, relationInstalled, commentsInstalled;
    Class relation = NSClassFromString(@"AWEKnowledgeRichContentImpl.FullPageFeedRelationButton");
    if (!relationInstalled && [relation isSubclassOfClass:UIButton.class] &&
        [DKXSChatEnhancementPolicy class:relation selector:@selector(layoutSubviews) result:'v' arguments:@""]) {
        %init(DKXSRichRelationChromeHooks, DKXSRichRelationButton = relation); relationInstalled = YES;
    }
    Class comments = NSClassFromString(@"AWEKnowledgeRichContentImpl.FullPageFeedListViewController");
    if (!commentsInstalled && [comments isSubclassOfClass:UIViewController.class] &&
        [DKXSChatEnhancementPolicy class:comments selector:@selector(viewDidLayoutSubviews) result:'v' arguments:@""] &&
        [DKXSChatEnhancementPolicy class:comments selector:@selector(viewDidAppear:) result:'v' arguments:@"B"]) {
        %init(DKXSRichCommentsChromeHooks, DKXSRichContentList = comments); commentsInstalled = YES;
    }
    Class rich = NSClassFromString(@"AWEKnowledgeRichContentImpl.FullPageFeedTabListViewController");
    if (!richHostInstalled && [rich isSubclassOfClass:UIViewController.class] &&
        [DKXSChatEnhancementPolicy class:rich selector:@selector(viewDidLoad) result:'v' arguments:@""] &&
        [DKXSChatEnhancementPolicy class:rich selector:@selector(viewWillLayoutSubviews) result:'v' arguments:@""] &&
        [DKXSChatEnhancementPolicy class:rich selector:@selector(viewWillAppear:) result:'v' arguments:@"B"] &&
        [DKXSChatEnhancementPolicy class:rich selector:@selector(viewDidLayoutSubviews) result:'v' arguments:@""] &&
        [DKXSChatEnhancementPolicy class:rich selector:@selector(viewDidDisappear:) result:'v' arguments:@"B"]) {
        %init(DKXSRichHostChromeHooks, DKXSRichContentHost = rich); richHostInstalled = YES;
    }
    // 只有客户端确实提供原生double布局入口时才接入；缺失不替换播放器或视口frame。
    if (!richAreaInstalled && [rich isSubclassOfClass:UIViewController.class] &&
        [DKXSChatEnhancementPolicy class:rich selector:@selector(topSafeAreaForTabList) result:'d' arguments:@""] &&
        [DKXSChatEnhancementPolicy class:rich selector:@selector(layoutTabListSubviews) result:'v' arguments:@""]) {
        %init(DKXSRichTopAreaHooks, DKXSRichContentHost = rich); richAreaInstalled = YES;
    }
    Class richTop = NSClassFromString(@"AWEKnowledgeRichContentImpl.FullPageFeedTopBarView");
    if (!richTopInstalled && [richTop isSubclassOfClass:UIView.class] &&
        [DKXSChatEnhancementPolicy class:richTop selector:@selector(setBackgroundColor:) result:'v' arguments:@"@"] &&
        [DKXSChatEnhancementPolicy class:richTop selector:@selector(didMoveToSuperview) result:'v' arguments:@""] &&
        [DKXSChatEnhancementPolicy class:richTop selector:@selector(layoutSubviews) result:'v' arguments:@""] &&
        [DKXSChatEnhancementPolicy class:richTop selector:@selector(didMoveToWindow) result:'v' arguments:@""]) {
        %init(DKXSRichTopChromeHooks, DKXSRichContentTopBar = richTop); richTopInstalled = YES;
    }
    Class richBottom = NSClassFromString(@"AWEKnowledgeRichContentImpl.FullPageFeedBottomBarView");
    if (!richBottomInstalled && [richBottom isSubclassOfClass:UIView.class] &&
        [DKXSChatEnhancementPolicy class:richBottom selector:@selector(layoutSubviews) result:'v' arguments:@""] &&
        [DKXSChatEnhancementPolicy class:richBottom selector:@selector(didMoveToWindow) result:'v' arguments:@""]) {
        %init(DKXSRichBottomChromeHooks, DKXSRichContentBottomBar = richBottom); richBottomInstalled = YES;
    }
    Class host = NSClassFromString(@"AWESearchArticleContainerViewController");
    if (!hostInstalled && [host isSubclassOfClass:UIViewController.class] &&
        [DKXSChatEnhancementPolicy class:host selector:@selector(viewDidLoad) result:'v' arguments:@""] &&
        [DKXSChatEnhancementPolicy class:host selector:@selector(viewWillLayoutSubviews) result:'v' arguments:@""] &&
        [DKXSChatEnhancementPolicy class:host selector:@selector(setupTopBar) result:'v' arguments:@""] &&
        [DKXSChatEnhancementPolicy class:host selector:@selector(updateUIByStyle) result:'v' arguments:@""] &&
        [DKXSChatEnhancementPolicy class:host selector:@selector(topBar) result:'@' arguments:@""] &&
        [DKXSChatEnhancementPolicy class:host selector:@selector(bottomBar) result:'@' arguments:@""]) {
        %init(DKXSArticleHostChromeHooks); hostInstalled = YES;
    }
    Class top = NSClassFromString(@"AWESearchArticleDetailTopBarView");
    if (!topInstalled && [top isSubclassOfClass:UIView.class] &&
        [DKXSChatEnhancementPolicy class:top selector:@selector(containerView) result:'@' arguments:@""] &&
        [DKXSChatEnhancementPolicy class:top selector:@selector(updateUIByStyle:mainColor:) result:'v' arguments:@"Q@"]) {
        %init(DKXSArticleTopChromeHooks); topInstalled = YES;
    }
    Class bottom = NSClassFromString(@"AWESearchArticleDetailBottomInteractionView");
    if (!bottomInstalled && [bottom isSubclassOfClass:UIView.class] &&
        [DKXSChatEnhancementPolicy class:bottom selector:@selector(itemStackView) result:'@' arguments:@""] &&
        [DKXSChatEnhancementPolicy class:bottom selector:@selector(updateUIByStyle:mainColor:) result:'v' arguments:@"Q@"]) {
        %init(DKXSArticleBottomChromeHooks); bottomInstalled = YES;
    }
    Class input = NSClassFromString(@"AWESearchArticleDetailCommentInputView");
    if (!inputInstalled && [input isSubclassOfClass:UIView.class] &&
        [DKXSChatEnhancementPolicy class:input selector:@selector(updateUIByStyle:) result:'v' arguments:@"Q"]) {
        %init(DKXSArticleInputChromeHooks); inputInstalled = YES;
    }
}
@end

%ctor { [DKXSArticleChrome preparePreferences]; [DKXSArticleChrome installHooks]; }
