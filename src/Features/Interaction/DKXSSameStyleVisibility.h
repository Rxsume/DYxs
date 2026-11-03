// 移植自 Si-yi/DYads- (fb78fd91)：改名一律 DYYY -> DKXS，设置键同步改名；逻辑原样。
#import <UIKit/UIKit.h>

@interface DKXSSameStyleVisibility : NSObject
+ (void)applyToView:(UIView *)view;
+ (void)beginNativeUpdate:(UIView *)view;
+ (void)endNativeUpdate:(UIView *)view;
+ (void)refreshVisibleViews;
@end
