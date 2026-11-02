//
//  DKXSFloatButtonWiring.xm
//  DYxs 全量合并第 2 批 staging（尚未并入 DYxs 源码）
//  新写（无上游对应文件）：把第 2 批的协调器与按钮接到抖音页面事件上。
//  上游把这些接线写在 DYYY.xm 里（第 5 批才移植的主文件）；不补这段，
//  协调器永远收不到页面，两个悬浮按钮不会出现，倍速点击也没有目标。
//  本文件只做第 2 批必需的最小接线，不搬 DYYY.xm 的其他逻辑。
//  抖音类只给最小 @interface 声明，不 import 上游 AwemeHeaders，
//  也不 import DYxs DouyinHeaders（避免与之重声明冲突，第 1 批同款做法）。
//

#import "DKXSFloatingButtonCoordinator.h"
#import "DKXSFloatSpeedButton.h"
#import "DKXSUtils.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

@interface AWEPlayInteractionViewController : UIViewController
- (id)controllerByProtocol:(Protocol *)protocol;
- (id)videoDelegate;
@end

@interface AWEAwemePlayVideoViewController : UIViewController
@end

@interface AWECommentContainerViewController : UIViewController
@end

@interface AFDPureModePageContainerViewController : UIViewController
@end

// 上游 DYYY.xm 里的 DYYYCurrentSpeedInteractionController 在此定义，
// 供 DKXSFloatSpeedButton.m 调用（头文件里已声明）。
id DKXSCurrentSpeedInteractionController(void) {
    return [DKXSFloatingButtonCoordinator currentInteractionController];
}

static BOOL DKXSSetPlaybackRateOnTarget(id target, double speed) {
    if (!target || ![target respondsToSelector:@selector(setVideoControllerPlaybackRate:)]) {
        return NO;
    }
    @try {
        ((void (*)(id, SEL, double))objc_msgSend)(target, @selector(setVideoControllerPlaybackRate:), speed);
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
}

// 上游 DYYY.xm 的 DYYYApplyPlaybackSpeed 的精简版：
// 优先走 AWEFastSpeedControllerProtocol / videoDelegate，
// 再在窗口层级里找当前可见的播放器控制器。
// 上游的按 aweme 模型匹配（DYYYAwemeModelsMatch / SpeedAwemeIdentifier）
// 属于第 5 批的速度管线，本批不用：当前可见的互动控制器即目标，
// 与第 1 批评论协调器的回退逻辑一致。
static BOOL DKXSApplyPlaybackSpeed(id preferredController, double speed) {
    id controller = preferredController;
    if (!controller || ![DKXSFloatingButtonCoordinator isControllerVisible:controller]) {
        controller = [DKXSFloatingButtonCoordinator currentInteractionController];
    }
    if (!controller) {
        return NO;
    }

    Protocol *speedControllerProtocol = NSProtocolFromString(@"AWEFastSpeedControllerProtocol");
    if (speedControllerProtocol && [controller respondsToSelector:@selector(controllerByProtocol:)]) {
        @try {
            id speedController = ((id (*)(id, SEL, Protocol *))objc_msgSend)(controller, @selector(controllerByProtocol:), speedControllerProtocol);
            if ([speedController respondsToSelector:@selector(playVideoViewController)]) {
                id playVideoViewController = ((id (*)(id, SEL))objc_msgSend)(speedController, @selector(playVideoViewController));
                if (DKXSSetPlaybackRateOnTarget(playVideoViewController, speed)) {
                    return YES;
                }
            }
        } @catch (NSException *exception) {
        }
    }

    if ([controller respondsToSelector:@selector(videoDelegate)]) {
        id videoDelegate = ((id (*)(id, SEL))objc_msgSend)(controller, @selector(videoDelegate));
        if (DKXSSetPlaybackRateOnTarget(videoDelegate, speed)) {
            return YES;
        }
    }

    UIViewController *topController = [DKXSUtils topView];
    UIWindow *window = topController.view.window;
    UIViewController *rootViewController = window.rootViewController;
    UIViewController *bestPlayerViewController = nil;
    CGFloat bestPlayerArea = -1.0;
    for (UIViewController *viewController in rootViewController ? DKXSFindViewControllersInHierarchy(rootViewController) : @[]) {
        if (![viewController isKindOfClass:NSClassFromString(@"AWEAwemePlayVideoViewController")] &&
            ![viewController isKindOfClass:NSClassFromString(@"AWEDPlayerFeedPlayerViewController")] &&
            ![viewController isKindOfClass:NSClassFromString(@"AWEDPlayerViewController_Merge")]) {
            continue;
        }
        if (![DKXSFloatingButtonCoordinator isControllerVisible:viewController]) {
            continue;
        }
        UIView *view = viewController.viewIfLoaded;
        CGRect rect = [view convertRect:view.bounds toView:view.window];
        CGRect visible = CGRectIntersection(rect, view.window.bounds);
        CGFloat area = visible.size.width * visible.size.height;
        if (area > bestPlayerArea) {
            bestPlayerArea = area;
            bestPlayerViewController = viewController;
        }
    }
    return DKXSSetPlaybackRateOnTarget(bestPlayerViewController, speed);
}

%hook AWEPlayInteractionViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    [DKXSFloatingButtonCoordinator registerInteractionController:self];
    // 上游 viewWillAppear 只做登记与倍速索引恢复；本批多做一步：
    // 切视频时把当前选中的倍速打到新控制器上，否则换视频后倍速会丢。
    // 上游的同款行为在 DYYY.xm 的 aweme 切换处理里（第 5 批），本批先用出现事件覆盖。
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSEnableFloatSpeedButton"]) {
        DKXSApplyPlaybackSpeed(self, DKXSGetCurrentSpeed());
    }
    [DKXSFloatingButtonCoordinator refresh];
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    [DKXSFloatingButtonCoordinator refresh];
}

%new
- (void)speedButtonTapped:(UIButton *)sender {
    [(DKXSFloatSpeedButton *)sender resetFadeTimer];
    NSArray *speeds = DKXSGetSpeedOptions();
    if (speeds.count == 0) {
        return;
    }
    NSInteger currentIndex = DKXSGetCurrentSpeedIndex();
    NSInteger newIndex = (currentIndex + 1) % speeds.count;
    DKXSSetCurrentSpeedIndex(newIndex);
    float newSpeed = [speeds[newIndex] floatValue];
    DKXSUpdateSpeedButtonUI();
    // 上游这里还清长按倍速状态（DYYYClearLongPressSpeedState）；
    // 长按倍速是第 5 批，本批没有该状态，故不调用，第 5 批移植时补上。

    [UIView animateWithDuration:0.1
                          delay:0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
                       sender.transform = CGAffineTransformMakeScale(1.1, 1.1);
                     }
                     completion:^(BOOL finished) {
                       [UIView animateWithDuration:0.1
                                             delay:0
                                           options:UIViewAnimationOptionCurveEaseIn
                                        animations:^{
                                          sender.transform = CGAffineTransformIdentity;
                                        }
                                        completion:nil];
                     }];

    id currentController = DKXSCurrentSpeedInteractionController();
    if (currentController) {
        dkxsSpeedButton.interactionController = currentController;
    }
    if (!DKXSApplyPlaybackSpeed(currentController, newSpeed)) {
        [DKXSUtils showToast:@"无法找到视频控制器"];
    }
}

%end

%hook AWECommentContainerViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    [DKXSFloatingButtonCoordinator commentController:self visible:YES];
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    [DKXSFloatingButtonCoordinator commentController:self visible:NO];
}

%end

%hook AFDPureModePageContainerViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [DKXSFloatingButtonCoordinator pureModeController:self visible:YES];
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    [DKXSFloatingButtonCoordinator pureModeController:self visible:NO];
    // 上游这里还调全屏协调器的 invalidateGuides（第 6 批），本批没有该协调器，不调用。
}

%end

%ctor {
    // 上游在 AppDelegate hook 里做前后台切换；本批改用通知，不 hook AppDelegate，
    // 避免与 DYxs 现有 AppDelegate hook 冲突。
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *notification) {
                                                    [DKXSFloatingButtonCoordinator setApplicationActive:YES];
                                                    [DKXSFloatingButtonCoordinator reloadConfiguration];
                                                  }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *notification) {
                                                    [DKXSFloatingButtonCoordinator setApplicationActive:NO];
                                                  }];
    [DKXSFloatingButtonCoordinator reloadConfiguration];
    %init;
}
