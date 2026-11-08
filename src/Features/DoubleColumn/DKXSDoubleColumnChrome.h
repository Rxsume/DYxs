// 移植自 Si-yi/DYads- b97c05e（DYYYDoubleColumnChrome.h）：改名一律 DYYY -> DKXS，逻辑原样。
#import <UIKit/UIKit.h>

@interface DKXSDoubleColumnChrome : NSObject
+ (void)beginAppearance:(UIViewController *)host;
+ (void)synchronize:(UIViewController *)host;
+ (void)restore:(UIViewController *)host;
+ (void)refresh;
+ (CGRect)frameForHost:(UIViewController *)host feed:(id)feed collection:(id)collection native:(CGRect)native;
+ (BOOL)supportsFrameDelegate:(Class)cls;
+ (NSDictionary *)diagnostics;
@end
@interface DKXSDoubleColumnChrome (Hooks)
+ (void)installHooks;
@end
