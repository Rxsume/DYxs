// 移植自 Si-yi/DYads- cbc2d5a（DYYYRefreshIndicatorStyle.h）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
#import <UIKit/UIKit.h>
@interface DKXSRefreshIndicatorStyle : NSObject
+ (void)synchronizeHeader:(UIView *)header;
+ (void)refresh;
+ (NSDictionary *)diagnostics;
@end
@interface DKXSRefreshIndicatorStyle (RuntimeHooks)
+ (void)installHooks;
@end
