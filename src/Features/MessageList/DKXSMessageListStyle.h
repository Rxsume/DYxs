// 移植自 Si-yi/DYads- f07ddb5（DYYYMessageListStyle.h）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
#import <UIKit/UIKit.h>
@interface DKXSMessageListStyle : NSObject
+ (void)preparePreferences;
+ (BOOL)cardsEnabled;
+ (BOOL)topEnabled;
+ (void)synchronizeController:(UIViewController *)controller;
+ (void)synchronizeCell:(UITableViewCell *)cell;
+ (void)resetCell:(UITableViewCell *)cell;
+ (void)prepareCellLayout:(UITableViewCell *)cell;
+ (void)synchronizeBar:(UIView *)bar;
+ (void)scheduleBarSynchronization:(UIView *)bar;
+ (UIColor *)nativeBackgroundColor:(UIColor *)color forBar:(UIView *)bar;
+ (BOOL)nativeOpaque:(BOOL)opaque forBar:(UIView *)bar;
+ (void)refresh;
+ (NSDictionary *)diagnostics;
@end
