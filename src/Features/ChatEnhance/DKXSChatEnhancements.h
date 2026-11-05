// 移植自 Si-yi/DYads- 5e9a5c0（DYYYChatEnhancements.h）：改名一律 DYYY -> DKXS，设置键同步改名。
// 设置项不在本模块登记，见 DKXSBatch8Settings.xm（DYxs 用 DKSettingsRegister 登记）。
#import <UIKit/UIKit.h>

@interface DKXSChatEnhancements : NSObject
+ (BOOL)enabled:(NSString *)key;
+ (void)installHooks;
+ (void)cellChanged:(UIView *)cell;
+ (void)controllerAppeared:(UIViewController *)controller;
+ (void)recordCapability:(NSString *)name available:(BOOL)available;
+ (void)recordEvent:(NSString *)name;
+ (NSDictionary *)diagnostics;
@end
