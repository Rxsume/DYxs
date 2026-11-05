// 移植自 Si-yi/DYads- (fb78fd91)：改名一律 DYYY -> DKXS，设置键同步改名；逻辑原样。
#import <UIKit/UIKit.h>

@interface DKXSFeedTagGlass : NSObject
+ (void)installHooks;
+ (void)decorateTag:(UIView *)tag;
+ (BOOL)isLabelView:(UIView *)view;
+ (void)decorateStack:(UIView *)stack;
+ (void)restoreTag:(UIView *)tag;
+ (void)beginNativeUpdate:(UIView *)tag;
+ (void)endNativeUpdate:(UIView *)tag;
@end
