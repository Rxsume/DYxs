// 移植自 Si-yi/DYads- (fb78fd91)：改名一律 DYYY -> DKXS，设置键同步改名；逻辑原样。
#import <UIKit/UIKit.h>

@interface DKXSCommentVideoLayout : NSObject
+ (BOOL)enabled;
+ (BOOL)freezeController:(UIViewController *)controller;
+ (void)synchronizeController:(UIViewController *)controller;
+ (void)didMagnifyController:(UIViewController *)controller;
+ (void)refreshVisiblePlayers;
+ (NSDictionary *)diagnostics;
@end
@interface DKXSCommentVideoLayout (Hooks)
+ (void)installHooks;
@end
