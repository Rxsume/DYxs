#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

/// DKXS 移植层的小工具：只保留自动消息 / ABTest 用到的三个方法，
/// 其余原版工具的下载、媒体、GIF 等能力不移植，避免把整套工具链拖进来。
@interface DKXSUtils : NSObject
+ (void)showToast:(NSString *)text;
+ (BOOL)isDarkMode;
+ (UIViewController *)firstAvailableViewControllerFromView:(UIView *)view;
/// 原 DYYYUtils topView 的 DKXS 版：取 key window 的 rootViewController，再沿 presentedViewController 走到最上层；无窗口时返回 nil。
+ (UIViewController *)topView;
@end
