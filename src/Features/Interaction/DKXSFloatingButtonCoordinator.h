//
//  DKXSFloatingButtonCoordinator.h
//  DYxs 全量合并第 2 批 staging（尚未并入 DYxs 源码）
//  移植来源：Wtrwx/DYYY 的 DYYYFloatingButtonCoordinator.h；仅改名。
//
#import <Foundation/Foundation.h>

@class UIViewController;

typedef NS_OPTIONS(NSUInteger, DKXSFloatingButtonVisibility) {
    DKXSFloatingButtonVisibilityNone = 0,
    DKXSFloatingButtonVisibilitySpeed = 1 << 0,
    DKXSFloatingButtonVisibilityClear = 1 << 1,
};

// 页面事件只登记事实，两个按钮的 hidden 统一在协调器中更新。
@interface DKXSFloatingButtonCoordinator : NSObject
+ (void)registerInteractionController:(UIViewController *)controller;
+ (UIViewController *)currentInteractionController;
+ (BOOL)isControllerVisible:(UIViewController *)controller;
+ (void)commentController:(UIViewController *)controller visible:(BOOL)visible;
+ (void)pureModeController:(UIViewController *)controller visible:(BOOL)visible;
+ (void)setApplicationActive:(BOOL)active;
+ (void)reloadConfiguration;
+ (void)refresh;
+ (void)setNeedsRefresh;

+ (DKXSFloatingButtonVisibility)visibilityWithPlayback:(BOOL)playback
                                           appActive:(BOOL)appActive
                                             comment:(BOOL)comment
                                            pureMode:(BOOL)pureMode
                                           clearMode:(BOOL)clearMode
                                        speedEnabled:(BOOL)speedEnabled
                                        clearEnabled:(BOOL)clearEnabled
                                    hideSpeedOnClear:(BOOL)hideSpeedOnClear;
@end
