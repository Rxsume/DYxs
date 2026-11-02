// 移植来源：Wtrwx/DYYY 的 DYYYCommentPlaybackHooks.xm + 上游 DYYY.xm 中
// AWECommentContainerViewController 的评论显隐转发（原名见 REPORT.md）。
// 转发 hook 是本批必需的：没有它，协调器永远收不到评论控制器，
// pauseIfNeeded 会直接返回，接管逻辑等于没接。转发只调协调器，不调
// 上游的 FloatingButton/Fullscreen/Blur 协调器（均不在本批）。
// 注意：DYxs 的 DKCommentBottomBar/DKCommentGlass/DKCommentMediaCleaner
// 已 hook 同类的 viewWillAppear/viewDidDisappear，Logos 会按 %orig 链式调用。
#import <UIKit/UIKit.h>
#import "DKXSCommentPlaybackCoordinator.h"

%hook AWECommentMediaFeedParams

- (BOOL (^)(void))panelVideoHasPausedByComment {
    BOOL (^originalBlock)(void) = %orig;
    if (![DKXSCommentPlaybackCoordinator ownsPlayback]) return originalBlock;
    return ^BOOL {
        return [DKXSCommentPlaybackCoordinator ownsPlayback] || (originalBlock ? originalBlock() : NO);
    };
}

- (BOOL (^)(void))fullPanelShouldPreventPlay {
    BOOL (^originalBlock)(void) = %orig;
    if (![DKXSCommentPlaybackCoordinator ownsPlayback]) return originalBlock;
    return ^BOOL {
        return [DKXSCommentPlaybackCoordinator ownsPlayback] || (originalBlock ? originalBlock() : NO);
    };
}

%end

%hook _TtC33AWECommentPanelContainerSwiftImpl30CommentContainerInnerViewModel

- (instancetype)init {
    id viewModel = %orig;
    [DKXSCommentPlaybackCoordinator registerViewModel:viewModel];
    return viewModel;
}

- (void)setTabManager:(id)tabManager {
    %orig(tabManager);
    [DKXSCommentPlaybackCoordinator registerViewModel:self];
}

%end

%hook AWECommentContainerViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig(animated);
    // 本文件不 import DouyinHeaders，Logos 只给本类前置声明，编译器不知道它是
    // UIViewController 的子类，直接传 self 会报 cannot initialize（build #45）。
    // 上游与 DouyinHeaders 均声明本类为 UIViewController 子类，故显式转型。
    [DKXSCommentPlaybackCoordinator commentController:(UIViewController *)self visible:YES];
}

- (void)viewDidDisappear:(BOOL)animated {
    BOOL skipsLifecycle = [DKXSCommentPlaybackCoordinator shouldSkipLifecycle:(UIViewController *)self];
    %orig(animated);
    if (skipsLifecycle) return;
    [DKXSCommentPlaybackCoordinator commentController:(UIViewController *)self visible:NO];
}

%end

%ctor {
    %init;
}
