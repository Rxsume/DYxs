// 移植自 Si-yi/DYads- b97c05e（DYYYNoticeFilterGlass.h）：改名一律 DYYY -> DKXS，逻辑原样。
#import <UIKit/UIKit.h>

@interface DKXSNoticeFilterGlass : NSObject
+ (void)bindPlate:(UIView *)plate;
+ (void)refresh;
+ (NSDictionary *)diagnostics;
@end
