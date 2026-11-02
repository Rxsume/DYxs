//
//  DKXSFloatingButtonCoordinator.m
//  DYxs 全量合并第 2 批 staging（尚未并入 DYxs 源码）
//  移植来源：Wtrwx/DYYY 的 DYYYFloatingButtonCoordinator.m；改名 + 全屏协调器改为动态查找（第 6 批才移植）。
//
#import "DKXSFloatingButtonCoordinator.h"
#import "DKXSFloatClearButton.h"
#import "DKXSFloatSpeedButton.h"
#import <UIKit/UIKit.h>
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>

@interface DKXSFloatingButtonCoordinator ()
@property(nonatomic, strong) NSHashTable<UIViewController *> *interactions;
@property(nonatomic, strong) NSHashTable<UIViewController *> *comments;
@property(nonatomic, strong) NSHashTable<UIViewController *> *pureControllers;
@property(nonatomic, assign) BOOL applicationActive;
@property(nonatomic, assign) BOOL refreshScheduled;
@property(nonatomic, assign) BOOL refreshing;
@property(nonatomic, assign) BOOL configurationDirty;
@end

@implementation DKXSFloatingButtonCoordinator

#pragma mark - 唯一显示规则

+ (DKXSFloatingButtonVisibility)visibilityWithPlayback:(BOOL)playback
                                           appActive:(BOOL)appActive
                                             comment:(BOOL)comment
                                            pureMode:(BOOL)pureMode
                                           clearMode:(BOOL)clearMode
                                        speedEnabled:(BOOL)speedEnabled
                                        clearEnabled:(BOOL)clearEnabled
                                    hideSpeedOnClear:(BOOL)hideSpeedOnClear {
    // 清屏状态不能越过页面和前后台限制，消息页始终不显示按钮。
    if (!appActive || !playback) return DKXSFloatingButtonVisibilityNone;
    DKXSFloatingButtonVisibility visibility = DKXSFloatingButtonVisibilityNone;
    if (speedEnabled && (clearMode ? !hideSpeedOnClear : !comment)) {
        visibility |= DKXSFloatingButtonVisibilitySpeed;
    }
    // 清屏时保留退出入口；普通状态下，评论和纯净模式隐藏清屏按钮。
    if (clearEnabled && (clearMode || (!comment && !pureMode))) {
        visibility |= DKXSFloatingButtonVisibilityClear;
    }
    return visibility;
}

#pragma mark - 页面事实

+ (instancetype)sharedCoordinator {
    static DKXSFloatingButtonCoordinator *coordinator;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        coordinator = [[self alloc] init];
        coordinator.interactions = [NSHashTable weakObjectsHashTable];
        coordinator.comments = [NSHashTable weakObjectsHashTable];
        coordinator.pureControllers = [NSHashTable weakObjectsHashTable];
        coordinator.configurationDirty = YES;
        coordinator.applicationActive = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
        [[NSNotificationCenter defaultCenter] addObserver:coordinator selector:@selector(defaultsDidChange:)
                                                    name:NSUserDefaultsDidChangeNotification object:nil];
    });
    return coordinator;
}

+ (BOOL)isControllerVisible:(UIViewController *)controller {
    UIView *view = controller.viewIfLoaded;
    UIWindow *window = view.window;
    if (!window || window.hidden || CGRectIsEmpty(view.bounds)) return NO;
    for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview) {
        if (ancestor.hidden || ancestor.alpha <= 0.01) return NO;
    }
    CGRect rect = [view convertRect:view.bounds toView:window];
    if (!CGRectIntersectsRect(rect, window.bounds)) return NO;

    // 缓存页面可能仍挂在窗口上，只承认当前选中的 Tab 和导航栈顶。
    for (UIViewController *child = controller; child; child = child.parentViewController) {
        UIViewController *parent = child.parentViewController;
        if ([parent isKindOfClass:UITabBarController.class] && ((UITabBarController *)parent).selectedViewController != child) return NO;
        if ([parent isKindOfClass:UINavigationController.class] && ((UINavigationController *)parent).topViewController != child) return NO;
        UIViewController *presented = child.presentedViewController;
        if (presented.viewIfLoaded.window && !presented.isBeingDismissed) return NO;
    }
    return YES;
}

+ (UIViewController *)currentInteractionController {
    UIViewController *best = nil;
    CGFloat bestArea = 0;
    for (UIViewController *controller in [self sharedCoordinator].interactions) {
        if (![self isControllerVisible:controller]) continue;
        UIView *view = controller.viewIfLoaded;
        CGRect rect = [view convertRect:view.bounds toView:view.window];
        CGRect visible = CGRectIntersection(rect, view.window.bounds);
        CGFloat area = visible.size.width * visible.size.height;
        if (area > bestArea) {
            best = controller;
            bestArea = area;
        }
    }
    return best;
}

+ (void)registerInteractionController:(UIViewController *)controller {
    if (!controller || !NSThread.isMainThread) return;
    [[self sharedCoordinator].interactions addObject:controller];
    [self setNeedsRefresh];
}

+ (void)commentController:(UIViewController *)controller visible:(BOOL)visible {
    if (!controller || !NSThread.isMainThread) return;
    NSHashTable *controllers = [self sharedCoordinator].comments;
    if (visible) [controllers addObject:controller];
    else [controllers removeObject:controller];
    [self refresh];
}

+ (void)pureModeController:(UIViewController *)controller visible:(BOOL)visible {
    if (!controller || !NSThread.isMainThread) return;
    NSHashTable *controllers = [self sharedCoordinator].pureControllers;
    if (visible) [controllers addObject:controller];
    else [controllers removeObject:controller];
    [self refresh];
}

+ (void)setApplicationActive:(BOOL)active {
    [self sharedCoordinator].applicationActive = active;
    [self refresh];
}

#pragma mark - 配置与渲染

- (void)defaultsDidChange:(NSNotification *)notification {
    // 倍速索引、拖动位置等也会产生通知，同一轮主队列只合并刷新一次。
    dispatch_async(dispatch_get_main_queue(), ^{
        self.configurationDirty = YES;
        [DKXSFloatingButtonCoordinator setNeedsRefresh];
    });
}

+ (void)reloadConfiguration {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self reloadConfiguration]; });
        return;
    }
    [self sharedCoordinator].configurationDirty = YES;
    [self refresh];
}

+ (void)setNeedsRefresh {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self setNeedsRefresh]; });
        return;
    }
    DKXSFloatingButtonCoordinator *coordinator = [self sharedCoordinator];
    if (coordinator.refreshScheduled) return;
    coordinator.refreshScheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        coordinator.refreshScheduled = NO;
        [self refresh];
    });
}

- (BOOL)hasVisibleController:(NSHashTable<UIViewController *> *)controllers inWindow:(UIWindow *)window {
    for (UIViewController *controller in controllers) {
        if (controller.viewIfLoaded.window == window && [DKXSFloatingButtonCoordinator isControllerVisible:controller]) return YES;
    }
    return NO;
}

+ (void)refresh {
    if (!NSThread.isMainThread) {
        [self setNeedsRefresh];
        return;
    }
    DKXSFloatingButtonCoordinator *coordinator = [self sharedCoordinator];
    if (coordinator.refreshing) return;
    coordinator.refreshing = YES;
    @try {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        BOOL configurationChanged = coordinator.configurationDirty;
        if (coordinator.configurationDirty) {
            coordinator.configurationDirty = NO;
            DKXSInitTargetClassNames();
        }
        // 配置方法只在内容变化时更新外观，不随每次布局重设标题、位置和淡出计时器。
        if (configurationChanged) [DKXSFloatSpeedButton reloadConfiguration];
        // 倍速列表、默认倍速和索引也影响文案，仅配置通知时重算，普通布局不重算。
        if (configurationChanged) DKXSUpdateSpeedButtonUI();
        BOOL clearEnabled = [defaults boolForKey:@"DKXSEnableFloatClearButton"];
        BOOL purificationEnabled = [defaults boolForKey:@"DKXSEnablePure"];
        BOOL needsClearInstance = clearEnabled || purificationEnabled;
        UIViewController *current = [self currentInteractionController];
        UIWindow *window = current.viewIfLoaded.window;
        if (dkxsFloatSpeedButtonEnabled && window) [DKXSFloatSpeedButton attachToWindow:window interactionController:current];
        CGFloat configuredSize = [defaults floatForKey:@"DKXSEnableFloatClearButtonSize"];
        CGFloat clearSize = MIN(MAX(configuredSize > 0 ? configuredSize : 40.0, 20.0), 60.0);
        if (configurationChanged ||
            (needsClearInstance && window && (!dkxsHideButton || dkxsHideButton.window != window || fabs(dkxsHideButton.bounds.size.width - clearSize) > 0.01)) ||
            (!needsClearInstance && dkxsHideButton)) {
            DKXSReloadClearButtonConfiguration();
        }
        // 全屏协调器是第 6 批才移植；本批用动态查找，找不到时净化视为关。
        BOOL recommendedLayout = NO;
        Class fullscreenCoordinatorClass = NSClassFromString(@"DKXSFullscreenCoordinator");
        if (fullscreenCoordinatorClass && [fullscreenCoordinatorClass respondsToSelector:@selector(usesRecommendedLayoutForController:)]) {
            recommendedLayout = ((BOOL (*)(id, SEL, id))objc_msgSend)(fullscreenCoordinatorClass, @selector(usesRecommendedLayoutForController:), current);
        }
        dkxsHideButton.homePurificationActive = purificationEnabled && recommendedLayout;
        BOOL comment = window && [coordinator hasVisibleController:coordinator.comments inWindow:window];
        BOOL pureMode = window && [coordinator hasVisibleController:coordinator.pureControllers inWindow:window];
        DKXSFloatingButtonVisibility visibility = [self visibilityWithPlayback:current != nil
                                                                   appActive:coordinator.applicationActive
                                                                     comment:comment
                                                                    pureMode:pureMode
                                                                   clearMode:dkxsHideButton.isElementsHidden
                                                                speedEnabled:dkxsFloatSpeedButtonEnabled
                                                                clearEnabled:clearEnabled
                                                            hideSpeedOnClear:[defaults boolForKey:@"DKXSHideSpeed"]];
        BOOL speedHidden = !(visibility & DKXSFloatingButtonVisibilitySpeed);
        // 自动净化由设置开关控制；手动清屏入口在离开首页后恢复。
        BOOL clearHidden = dkxsHideButton.homePurificationActive || !(visibility & DKXSFloatingButtonVisibilityClear);
        if (dkxsSpeedButton && dkxsSpeedButton.hidden != speedHidden) {
            dkxsSpeedButton.hidden = speedHidden;
            if (!speedHidden) {
                [dkxsSpeedButton resetFadeTimer];
                [dkxsSpeedButton.superview bringSubviewToFront:dkxsSpeedButton];
            }
        }
        if (dkxsSpeedButton.edgeIndicatorView) dkxsSpeedButton.edgeIndicatorView.hidden = speedHidden || !dkxsSpeedButton.isEdgeHidden;
        if (dkxsHideButton && dkxsHideButton.hidden != clearHidden) {
            dkxsHideButton.hidden = clearHidden;
            if (!clearHidden) [dkxsHideButton.superview bringSubviewToFront:dkxsHideButton];
        }
        if (dkxsHideButton.edgeIndicatorView) {
            dkxsHideButton.edgeIndicatorView.hidden = clearHidden || !dkxsHideButton.isElementsHidden;
        }
    } @finally {
        coordinator.refreshing = NO;
    }
}
@end
