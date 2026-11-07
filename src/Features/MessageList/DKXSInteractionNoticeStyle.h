// 移植自 Si-yi/DYads- cbc2d5a（DYYYInteractionNoticeStyle.h）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
#import <UIKit/UIKit.h>
@interface DKXSInteractionNoticeStyle : NSObject
+ (id)beginUpdate:(UIView *)cell;
+ (void)endUpdate:(id)token;
+ (void)synchronizeCell:(UIView *)cell;
+ (void)resetCell:(UIView *)cell;
+ (void)synchronizeFansController:(UIViewController *)controller;
+ (void)prepareFansCell:(UIView *)cell table:(UITableView *)table indexPath:(NSIndexPath *)path controller:(UIViewController *)controller;
+ (void)clearFansBinding:(UIView *)cell;
+ (void)synchronizeMergedController:(UIViewController *)controller;
+ (void)refresh;
+ (NSDictionary *)diagnostics;
@end
@interface DKXSInteractionNoticeStyle (RuntimeHooks)
+ (void)installHooks;
+ (BOOL)installFansCellHooksForCell:(UIView *)cell;
+ (BOOL)installFansCellHooksForClass:(Class)cls;
+ (NSDictionary *)hookDiagnostics;
@end
