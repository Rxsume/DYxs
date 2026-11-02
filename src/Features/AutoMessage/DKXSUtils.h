#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

/// DKXS 移植层的小工具：只保留自动消息 / ABTest 用到的三个方法，
/// 其余原版工具的下载、媒体、GIF 等能力不移植，避免把整套工具链拖进来。
@interface DKXSUtils : NSObject
+ (void)showToast:(NSString *)text;
+ (BOOL)isDarkMode;
+ (UIViewController *)firstAvailableViewControllerFromView:(UIView *)view;
@end
