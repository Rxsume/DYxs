// 移植自 Si-yi/DYads- 7083bae（DYYYNativeGridRoute.h）：改名一律 DYYY -> DKXS，逻辑原样。
#import <UIKit/UIKit.h>

@interface DKXSNativeGridRoute : NSObject
+ (BOOL)routeTarget:(id)target fromAlbum:(id)album;
+ (NSDictionary *)diagnostics;
+ (void)resetFailure;
+ (void)setHookInstalled:(BOOL)installed;
@end
@interface DKXSNativeGridRoute (Hooks)
+ (void)installHooks;
@end
