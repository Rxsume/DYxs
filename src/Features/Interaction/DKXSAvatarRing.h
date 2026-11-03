// 移植自 Si-yi/DYads- (fb78fd91)：改名一律 DYYY -> DKXS，设置键同步改名；逻辑原样。
#import <UIKit/UIKit.h>

@interface DKXSAvatarRing : NSObject
+ (void)applyToRing:(UIView *)ring;
+ (void)restoreRing:(UIView *)ring;
+ (void)beginNativeUpdate:(UIView *)ring;
+ (void)endNativeUpdate:(UIView *)ring;
+ (void)refreshVisibleRings;
+ (NSDictionary *)diagnostics;
@end
