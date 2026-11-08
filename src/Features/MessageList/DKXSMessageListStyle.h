// 移植自 Si-yi/DYads- cbc2d5a（DYYYMessageListStyle.h）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
#import <UIKit/UIKit.h>
@interface DKXSMessageListStyle : NSObject
+ (void)preparePreferences;
+ (BOOL)cardsEnabled;
+ (BOOL)topEnabled;
+ (CGFloat)rowHeight:(CGFloat)native controller:(UIViewController *)controller table:(UITableView *)table indexPath:(NSIndexPath *)path;
+ (void)synchronizeLightInteraction:(UIView *)view;
+ (void)resetLightInteraction:(UIView *)view;
+ (void)synchronizeController:(UIViewController *)controller;
+ (void)synchronizeCell:(UITableViewCell *)cell;
+ (void)resetCell:(UITableViewCell *)cell;
+ (BOOL)contentAdapterReady;
+ (CGRect)nativeContentFrame:(CGRect)frame forView:(UIView *)view;
+ (id)beginContentGeometry:(UIView *)view;
+ (void)endContentGeometry:(id)token;
+ (CGAffineTransform)nativeContentTransform:(CGAffineTransform)transform forView:(UIView *)view;
+ (void)didSetContentTransform:(UIView *)view;
+ (BOOL)passThroughNoticeActions:(CGPoint)point bar:(UIView *)bar;
+ (void)synchronizeBar:(UIView *)bar;
+ (void)synchronizeHeaderForView:(UIView *)view;
+ (void)scheduleBarSynchronization:(UIView *)bar;
+ (UIColor *)nativeBackgroundColor:(UIColor *)color forBar:(UIView *)bar;
+ (BOOL)nativeOpaque:(BOOL)opaque forBar:(UIView *)bar;
+ (void)refresh;
+ (NSDictionary *)diagnostics;
@end
