//
//  DKXSFullscreenWiring.xm
//  DYxs（第 6 批 staging，尚未并入 DYxs 源码）
//
//  移植来源：Wtrwx/DYYY 的 DYYY.xm 中调用 DYYYFullscreenCoordinator 的各处
//  （只搬全屏接线；同块里的悬浮按钮、双击、倍速、毛玻璃驱动、隐藏按钮等
//  分属第 2、4、5 批或已在 DYxs 落地，本文件一律不搬）。
//  改名：DYYY* -> DKXS*；抖音类上的方法名保持上游原样。
//  与第 1、2、4 批及 DYxs 原有文件同类同方法处走 Logos %orig 链，
//  不直接改那些文件（见 REPORT.md 的链路表）。
//  本文件不 import DouyinHeaders、不 import 上游 AwemeHeaders；
//  抖音类只补最小接口声明（基类完整），传 self 给 UIViewController*/UIView*
//  参数时一律显式转型；用 objc_msgSend 的地方已 import <objc/message.h>。
//
#import <UIKit/UIKit.h>
#import "DKXSFullscreenCoordinator.h"
#import "DKXSUtils.h"
#import <objc/runtime.h>
#import <objc/message.h>

#define DKXSGetBool(key) [[NSUserDefaults standardUserDefaults] boolForKey:key]

// 最小接口声明（只含本文件用到的成员）。
@interface AWEPlayInteractionViewController : UIViewController
- (NSString *)referString;
@end
@interface AWEPlayVideoViewController : UIViewController
- (id)model;
@end
@interface AWECommentContainerViewController : UIViewController
@end
@interface AWEAwemeDetailTableViewController : UIViewController
@end
@interface AWENormalModeTabBar : UIView
@end
@interface AFDPureModePageContainerViewController : UIViewController
@end
@interface AFDPureModePageListViewController : UIViewController
@end
@interface AWEDPlayerFeedPlayerViewController : UIViewController
@end

// 上游 AWENormalModeTabBar 的 %new 方法 initializeOriginalTabBarHeight 的
// 等价实现：改成静态 C 函数，不往抖音类上加方法。
// UIView layoutSubviews 的全屏清底色分支依赖这个原始高度。
static CGFloat dkxsOriginalTabBarHeight = -1;
// 上游 DYYYUtils getActiveWindow 的等价实现（key window 优先）。
static UIWindow *dkxs_activeWindow(void) {
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        if (window.isKeyWindow) return window;
    }
    return [UIApplication sharedApplication].windows.firstObject;
}

static void DKXSInitOriginalTabBarHeight(UIView *tabBar) {
    if (dkxsOriginalTabBarHeight >= 0) return;
    UIWindow *targetWindow = tabBar.window ?: dkxs_activeWindow();
    if (tabBar.frame.size.height >= 30) {
        dkxsOriginalTabBarHeight = tabBar.frame.size.height;
    } else if (targetWindow) {
        dkxsOriginalTabBarHeight = 49 + targetWindow.safeAreaInsets.bottom;
    }
}

// 上游 DYYYUtils compareVersion 的等价实现（只用于私信播放页的
// 39.2.0 分支；40.8.0 下该分支恒为假，见 REPORT.md）。
static NSComparisonResult dkxs_compareVersion(NSString *a, NSString *b) {
    NSArray<NSString *> *pa = [a componentsSeparatedByString:@"."];
    NSArray<NSString *> *pb = [b componentsSeparatedByString:@"."];
    NSUInteger n = MAX(pa.count, pb.count);
    for (NSUInteger i = 0; i < n; i++) {
        NSInteger va = i < pa.count ? pa[i].integerValue : 0;
        NSInteger vb = i < pb.count ? pb[i].integerValue : 0;
        if (va < vb) return NSOrderedAscending;
        if (va > vb) return NSOrderedDescending;
    }
    return NSOrderedSame;
}

#pragma mark - UIView（只搬全屏部分；头像/清屏按钮/全局透明度不在本批）

%hook UIView

- (void)setBackgroundColor:(UIColor *)backgroundColor {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [(UIView *)self setBackgroundColor:backgroundColor];
        });
        return;
    }
    // 上游这里先判头像 chrome（第 3 批已另做），本批只保留底栏协调。
    backgroundColor = [DKXSFullscreenCoordinator backgroundForBottomView:(UIView *)self proposed:backgroundColor];
    if (DKXSGetBool(@"DKXSEnableFullScreen")) {
        UIViewController *vc = [DKXSUtils firstAvailableViewControllerFromView:(UIView *)self];
        if ([vc isKindOfClass:NSClassFromString(@"AWEAwemeDetailTableViewController")] ||
            [vc isKindOfClass:NSClassFromString(@"AWEAwemeDetailCellViewController")]) {
            %orig([UIColor clearColor]);
            return;
        }
    }
    %orig(backgroundColor);
}

- (void)layoutSubviews {
    %orig;
    if (DKXSGetBool(@"DKXSEnableFullScreen")) {
        if (self.frame.size.height == dkxsOriginalTabBarHeight && dkxsOriginalTabBarHeight > 0) {
            UIViewController *vc = [DKXSUtils firstAvailableViewControllerFromView:(UIView *)self];
            if ([vc isKindOfClass:NSClassFromString(@"AWEMixVideoPanelDetailTableViewController")] ||
                [vc isKindOfClass:NSClassFromString(@"AWECommentInputViewController")] ||
                [vc isKindOfClass:NSClassFromString(@"AWEAwemeDetailTableViewController")]) {
                self.backgroundColor = [UIColor clearColor];
            }
        }
    }
    if (DKXSGetBool(@"DKXSEnableFullScreen") || DKXSGetBool(@"DKXSEnableCommentBlur")) {
        UIViewController *vc = nil;
        for (UIView *subview in self.subviews) {
            if (subview.hidden || !subview.backgroundColor || !CGColorEqualToColor(subview.backgroundColor.CGColor, UIColor.blackColor.CGColor)) continue;
            if (!vc) vc = [DKXSUtils firstAvailableViewControllerFromView:(UIView *)self];
            if (![vc isKindOfClass:NSClassFromString(@"AWEPlayInteractionViewController")]) break;
            subview.hidden = YES;
        }
    }
}

// 只调整协调器注册的两个媒体承载视图，普通视图直接沿用传入值（上游原注释）。
- (void)setBounds:(CGRect)bounds {
    if (![NSThread isMainThread]) {
        __weak UIView *weakView = (UIView *)self;
        dispatch_async(dispatch_get_main_queue(), ^{ weakView.bounds = bounds; });
        return;
    }
    %orig([DKXSFullscreenCoordinator boundsForMediaHost:(UIView *)self proposed:bounds]);
}

- (void)setCenter:(CGPoint)center {
    if (![NSThread isMainThread]) {
        __weak UIView *weakView = (UIView *)self;
        dispatch_async(dispatch_get_main_queue(), ^{ weakView.center = center; });
        return;
    }
    %orig([DKXSFullscreenCoordinator centerForMediaHost:(UIView *)self proposed:center]);
}

- (void)setFrame:(CGRect)frame {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [(UIView *)self setFrame:frame];
        });
        return;
    }
    BOOL enableBlur = DKXSGetBool(@"DKXSEnableCommentBlur");
    BOOL enableFS = DKXSGetBool(@"DKXSEnableFullScreen");
    if (!enableFS && (!enableBlur || frame.origin.x == 0)) {
        %orig(frame);
        return;
    }
    frame = [DKXSFullscreenCoordinator frameForInteractionView:(UIView *)self proposed:frame];
    if (!enableBlur || frame.origin.x == 0) {
        %orig(frame);
        return;
    }
    UIViewController *vc = [DKXSUtils firstAvailableViewControllerFromView:(UIView *)self];
    static Class PlayVCClass1, PlayVCClass2, PlayVCClass3;
    static dispatch_once_t playClassesOnce;
    dispatch_once(&playClassesOnce, ^{
        PlayVCClass1 = NSClassFromString(@"AWEAwemePlayVideoViewController");
        PlayVCClass2 = NSClassFromString(@"AWEDPlayerFeedPlayerViewController");
        PlayVCClass3 = NSClassFromString(@"AWEDPlayerViewController_Merge");
    });
    BOOL isPlayVC = ((PlayVCClass1 && [vc isKindOfClass:PlayVCClass1]) ||
                     (PlayVCClass2 && [vc isKindOfClass:PlayVCClass2]) ||
                     (PlayVCClass3 && [vc isKindOfClass:PlayVCClass3]));
    if (isPlayVC) return;
    %orig(frame);
}

%end

#pragma mark - 播放互动页（只搬全屏布局；悬浮登记/双击/倍速属第 2、5 批）

%hook AWEPlayInteractionViewController

- (void)viewDidLayoutSubviews {
    %orig;
    // 离屏和复用中的互动层保留原生尺寸，避免回退布局与原生回收布局反复改高。
    if (!self.viewIfLoaded.window) return;
    // 上游这里还调悬浮协调器 registerInteractionController；第 2 批已在
    // viewWillAppear 里登记，本批不再重复登记。
    UIViewController *directParentVC = self.parentViewController;
    for (UIViewController *parent = directParentVC; parent; parent = parent.parentViewController) {
        if ([parent isKindOfClass:NSClassFromString(@"AFDPlayRemoteFeedTableViewController")]) return;
    }
    if ([DKXSFullscreenCoordinator layoutNativeInteraction:(UIViewController *)self]) return;
    if ([DKXSFullscreenCoordinator usesRecommendedLayoutForController:(UIViewController *)self]) {
        [DKXSFullscreenCoordinator layoutInteraction:(UIViewController *)self];
        if (![DKXSFullscreenCoordinator isImageContentController:(UIViewController *)self]) return;
        if ([DKXSFullscreenCoordinator hasCommentInWindow:self.viewIfLoaded.window]) return;
    }
    if (!DKXSGetBool(@"DKXSEnableFullScreen")) return;
    if (!self.view.superview) return;
    CGRect frame = self.view.frame;
    UIView *container = self.view.superview;
    CGFloat superviewHeight = MAX(0, CGRectGetMaxY(container.bounds) - frame.origin.y);
    if (fabs(frame.size.width - container.bounds.size.width) > 1 || superviewHeight <= 0) return;
    NSString *currentReferString = self.referString;
    BOOL useFullHeight = [currentReferString isEqualToString:@"general_search"] || [currentReferString isEqualToString:@"search_result"] || [currentReferString isEqualToString:@"search_ecommerce"] ||
                         [currentReferString isEqualToString:@"close_friends_moment"] || [currentReferString isEqualToString:@"offline_mode"] || [currentReferString isEqualToString:@"challenge"] ||
                         [currentReferString isEqualToString:@"general_search_scan"] || currentReferString == nil;
    if (!useFullHeight && [currentReferString isEqualToString:@"co_play_watch"]) {
        Class richContentVCClass = NSClassFromString(@"AWEFriendsImpl.RichContentNewListViewController");
        for (UIViewController *parent = directParentVC; parent; parent = parent.parentViewController) {
            if (richContentVCClass && [parent isKindOfClass:richContentVCClass]) {
                useFullHeight = YES;
                break;
            }
        }
    }
    if (!useFullHeight && [currentReferString isEqualToString:@"chat"]) {
        // 上游在取不到版本号时回退到 AWEVersionUpdateManager；40.8.0 下
        // 版本号恒存在，该回退恒不触发，本批直接略过（见 REPORT.md）。
        // 39.2.0 及更早版本的私信播放页以完整高度布局信息区。
        NSString *currentVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        if (currentVersion.length > 0 && dkxs_compareVersion(currentVersion, @"39.2.0") != NSOrderedDescending) {
            useFullHeight = YES;
        }
    }
    if (useFullHeight) {
        frame.size.height = superviewHeight;
    } else {
        frame.size.height = MAX(0, superviewHeight - [DKXSFullscreenCoordinator bottomOccupiedHeightForView:self.view]);
    }
    if (fabs(frame.size.height - self.view.frame.size.height) > 0.5) {
        self.view.frame = frame;
    }
    [DKXSFullscreenCoordinator rememberInteractionGuide:(UIViewController *)self];
}

%end

#pragma mark - 评论容器（只搬全屏显隐转发；播放接管属第 1 批，悬浮属第 2 批，毛玻璃属第 4 批）

%hook AWECommentContainerViewController

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    [DKXSFullscreenCoordinator commentController:(UIViewController *)self visible:NO];
}

- (void)viewDidLayoutSubviews {
    %orig;
    [DKXSFullscreenCoordinator commentController:(UIViewController *)self visible:YES];
}

%end

#pragma mark - 底栏（只搬协调器注册；按钮隐藏属第 3 批）

%hook AWENormalModeTabBar

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        DKXSInitOriginalTabBarHeight((UIView *)self);
    }
    [DKXSFullscreenCoordinator registerTabBar:(UIView *)self];
}

- (void)layoutSubviews {
    %orig;
    [DKXSFullscreenCoordinator registerTabBar:(UIView *)self];
}

- (void)setHidden:(BOOL)hidden {
    %orig(hidden);
    [DKXSFullscreenCoordinator registerTabBar:(UIView *)self];
}

%end

#pragma mark - 详情页（只搬全屏分页；状态栏隐藏另见 REPORT.md 暂缓项）

%hook AWEAwemeDetailTableViewController

- (CGFloat)baseTableViewBottomInset {
    CGFloat inset = %orig;
    return [DKXSFullscreenCoordinator bottomInsetForDetail:inset controller:(UIViewController *)self];
}

- (void)viewDidLayoutSubviews {
    %orig;
    [DKXSFullscreenCoordinator reconcileDetailPaging:(UIViewController *)self];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [DKXSFullscreenCoordinator reconcileDetailPaging:(UIViewController *)self];
}

%end

#pragma mark - 纯净模式（容器帧 + 消失时刷新指南；悬浮显隐属第 2 批）

%hook AFDPureModePageContainerViewController

- (CGRect)getPureModeContainerFrame {
    CGRect frame = %orig;
    return [DKXSFullscreenCoordinator frameForPureModeContainer:(UIViewController *)self proposed:frame];
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    [DKXSFullscreenCoordinator invalidateGuides];
}

%end

%hook AFDPureModePageListViewController

- (void)viewWillLayoutSubviews {
    // 先提供完整视口，再由原生更新 cell 尺寸、分页偏移和进度条（上游原注释）。
    [DKXSFullscreenCoordinator layoutPlayerContainer:(UIViewController *)self];
    %orig;
}

%end

%hook AWEDPlayerFeedPlayerViewController

- (void)viewDidLayoutSubviews {
    %orig;
    [DKXSFullscreenCoordinator layoutPlayerContainer:(UIViewController *)self];
}

%end

#pragma mark - 播放器视图（帧/布局全程走协调器）

%hook TTPlayerView

- (void)setFrame:(CGRect)frame {
    if (![NSThread isMainThread]) {
        __weak UIView *weakView = (UIView *)self;
        dispatch_async(dispatch_get_main_queue(), ^{ weakView.frame = frame; });
        return;
    }
    %orig([DKXSFullscreenCoordinator frameForPlayer:(UIView *)self proposed:frame]);
}

- (void)layoutSubviews {
    [DKXSFullscreenCoordinator preparePlayer:(UIView *)self];
    %orig;
    UIView *parent = self.superview;
    if (parent) parent.backgroundColor = self.backgroundColor;
    [DKXSFullscreenCoordinator finishPlayer:(UIView *)self];
}

%end

// 三个 Metal 视图的 setCenter 上游原文完全相同（仅类名不同），本批照搬。
%hook TTMetalView

- (void)setCenter:(CGPoint)center {
    BOOL shouldAdjust = NO;
    UIView *view = (UIView *)self;
    if (DKXSGetBool(@"DKXSEnableFullScreen")) {
        CGFloat viewWidth = CGRectGetWidth(view.bounds);
        CGFloat containerWidth = view.superview.bounds.size.width;
        if (containerWidth > 0 && fabs(viewWidth - containerWidth) <= 1) {
            UIViewController *vc = [DKXSUtils firstAvailableViewControllerFromView:view];
            Class playClass = NSClassFromString(@"AWEPlayVideoViewController");
            if (playClass && [vc isKindOfClass:playClass] && [DKXSFullscreenCoordinator usesRecommendedLayoutForController:vc] && [DKXSFullscreenCoordinator isImageContentController:vc]) {
                AWEPlayVideoViewController *playVC = (AWEPlayVideoViewController *)vc;
                id model = playVC.model;
                if ([model respondsToSelector:@selector(isShowLandscapeEntryView)] &&
                    ((BOOL (*)(id, SEL))objc_msgSend)(model, @selector(isShowLandscapeEntryView))) {
                    shouldAdjust = YES;
                }
            }
        }
    }
    if (shouldAdjust) {
        CGFloat offset = [DKXSFullscreenCoordinator bottomOccupiedHeightForView:view];
        if (offset > 0) {
            center.y -= offset * 0.5;
        }
    }
    %orig(center);
}

%end

%hook TTMetalViewNew

- (void)setCenter:(CGPoint)center {
    BOOL shouldAdjust = NO;
    UIView *view = (UIView *)self;
    if (DKXSGetBool(@"DKXSEnableFullScreen")) {
        CGFloat viewWidth = CGRectGetWidth(view.bounds);
        CGFloat containerWidth = view.superview.bounds.size.width;
        if (containerWidth > 0 && fabs(viewWidth - containerWidth) <= 1) {
            UIViewController *vc = [DKXSUtils firstAvailableViewControllerFromView:view];
            Class playClass = NSClassFromString(@"AWEPlayVideoViewController");
            if (playClass && [vc isKindOfClass:playClass] && [DKXSFullscreenCoordinator usesRecommendedLayoutForController:vc] && [DKXSFullscreenCoordinator isImageContentController:vc]) {
                AWEPlayVideoViewController *playVC = (AWEPlayVideoViewController *)vc;
                id model = playVC.model;
                if ([model respondsToSelector:@selector(isShowLandscapeEntryView)] &&
                    ((BOOL (*)(id, SEL))objc_msgSend)(model, @selector(isShowLandscapeEntryView))) {
                    shouldAdjust = YES;
                }
            }
        }
    }
    if (shouldAdjust) {
        CGFloat offset = [DKXSFullscreenCoordinator bottomOccupiedHeightForView:view];
        if (offset > 0) {
            center.y -= offset * 0.5;
        }
    }
    %orig(center);
}

%end

%hook TTMetalViewVP

- (void)setCenter:(CGPoint)center {
    BOOL shouldAdjust = NO;
    UIView *view = (UIView *)self;
    if (DKXSGetBool(@"DKXSEnableFullScreen")) {
        CGFloat viewWidth = CGRectGetWidth(view.bounds);
        CGFloat containerWidth = view.superview.bounds.size.width;
        if (containerWidth > 0 && fabs(viewWidth - containerWidth) <= 1) {
            UIViewController *vc = [DKXSUtils firstAvailableViewControllerFromView:view];
            Class playClass = NSClassFromString(@"AWEPlayVideoViewController");
            if (playClass && [vc isKindOfClass:playClass] && [DKXSFullscreenCoordinator usesRecommendedLayoutForController:vc] && [DKXSFullscreenCoordinator isImageContentController:vc]) {
                AWEPlayVideoViewController *playVC = (AWEPlayVideoViewController *)vc;
                id model = playVC.model;
                if ([model respondsToSelector:@selector(isShowLandscapeEntryView)] &&
                    ((BOOL (*)(id, SEL))objc_msgSend)(model, @selector(isShowLandscapeEntryView))) {
                    shouldAdjust = YES;
                }
            }
        }
    }
    if (shouldAdjust) {
        CGFloat offset = [DKXSFullscreenCoordinator bottomOccupiedHeightForView:view];
        if (offset > 0) {
            center.y -= offset * 0.5;
        }
    }
    %orig(center);
}

%end

#pragma mark - 文案标签（只搬全屏信息区跟随；缩放/位移属第 5d 批）

%hook AWEPlayInteractionDescriptionLabel

- (void)layoutSubviews {
    %orig;
    [DKXSFullscreenCoordinator layoutInformationLabel:(UIView *)self];
}

%end

%hook AWEUserNameLabel

- (void)layoutSubviews {
    %orig;
    [DKXSFullscreenCoordinator layoutInformationLabel:(UIView *)self];
}

%end

#pragma mark - 评论打开前冻结关闭态（动画开始早于 viewDidLayoutSubviews，上游原注释）

@interface AWEPlayInteractionCommentPanelController : UIViewController
@end
@interface CommentInputContainerView : UIView
@end
@interface BDMultiContentContainer_ImageContentView : UIView
@end
@interface AWEIMFeedVideoQuickReplayInputViewController : UIViewController
@end

%hook AWEPlayInteractionViewController

- (void)performCommentAction {
    [DKXSFullscreenCoordinator beginCommentInWindow:self.viewIfLoaded.window];
    %orig;
}

%end

%hook AWEPlayInteractionCommentPanelController

- (void)performCommentAction {
    [DKXSFullscreenCoordinator beginCommentInWindow:dkxs_activeWindow()];
    %orig;
}

%end

%hook CommentInputContainerView

- (void)layoutSubviews {
    %orig;
    UIViewController *parentVC = nil;
    if ([self respondsToSelector:@selector(viewController)]) {
        id viewController = [self performSelector:@selector(viewController)];
        if ([viewController respondsToSelector:@selector(parentViewController)]) {
            parentVC = [viewController parentViewController];
        }
    }
    [DKXSFullscreenCoordinator layoutBottomInput:(UIView *)self controller:parentVC];
}

%end

%hook BDMultiContentContainer_ImageContentView

- (void)setTransform:(CGAffineTransform)transform {
    %orig([DKXSFullscreenCoordinator transformForImageView:(UIView *)self proposed:transform]);
}

- (void)layoutSubviews {
    %orig;
    [DKXSFullscreenCoordinator layoutImageView:(UIView *)self];
}

%end

%hook AWEIMFeedVideoQuickReplayInputViewController

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat height = %orig;
    return [DKXSFullscreenCoordinator heightForDetailRow:height table:tableView controller:(UIViewController *)self];
}

%end

%ctor {
    %init;
}
