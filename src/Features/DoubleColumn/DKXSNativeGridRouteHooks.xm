// 移植自 Si-yi/DYads- 7083bae（DYYYNativeGridRouteHooks.xm）：改名一律 DYYY -> DKXS，逻辑原样。
// UIKit 必须在 @interface 声明之前先 import（PR #32 教训）。
// 本地最小接口声明：39.5 头文件未声明 AWEDCFeedAlbumRouter；
// 安装时先经 DKXSChatEnhancementPolicy 核对方法签名，不存在时不安装、不调用。
// 开关 DKXSEnableNativeGridFullscreen 默认关（DYxs 移植惯例；上游默认开，不跟随）。
#import <UIKit/UIKit.h>
#import "DKXSNativeGridRoute.h"
#import "DKXSChatEnhancementPolicy.h"

@interface AWEDCFeedAlbumRouter : NSObject
- (void)enterVCWithRouterTargetModel:(id)target;
@end

%group DKXSNativeGridRouteHooks
%hook AWEDCFeedAlbumRouter
- (void)enterVCWithRouterTargetModel:(id)target {
    if (![DKXSNativeGridRoute routeTarget:target fromAlbum:self]) %orig(target);
}
%end
%end

@implementation DKXSNativeGridRoute (Hooks)
+ (void)installHooks {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self installHooks]; }); return; }
    static BOOL installed;
    Class router = NSClassFromString(@"AWEDCFeedAlbumRouter");
    if (!installed && [DKXSChatEnhancementPolicy class:router selector:@selector(enterVCWithRouterTargetModel:) result:'v' arguments:@"@"]) {
        %init(DKXSNativeGridRouteHooks);
        installed = YES;
        [DKXSNativeGridRoute setHookInstalled:YES];
    }
}
@end
%ctor {
    [NSUserDefaults.standardUserDefaults registerDefaults:@{ @"DKXSEnableNativeGridFullscreen":@NO }];
    [DKXSNativeGridRoute installHooks];
}
