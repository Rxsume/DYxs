// 移植自 Si-yi/DYads- b97c05e（DYYYDoubleColumnChromeHooks.xm）：改名一律 DYYY -> DKXS，逻辑原样。
// 须先 import UIKit：下方的最小接口声明以 UIViewController 为父类，
// 未引入 UIKit 时编译器找不到父类接口（0.6.9.20 CI run #121 的教训，PR #32 已修）。
#import <UIKit/UIKit.h>
#import "DKXSDoubleColumnChrome.h"
#import "DKXSChatEnhancementPolicy.h"

// 最小接口声明（沿用第 8 批写法，不 import 大头文件）：AWEFeedNewDoubleColumnViewController
// 不在 DKXSAwemeHeaders（39.5 导出）里；dcFeed:frameForCollectionView: 为本文件 hook 的委托方法。
@interface AWEFeedNewDoubleColumnViewController : UIViewController
- (CGRect)dcFeed:(id)feed frameForCollectionView:(id)collection;
@end

%group DKXSDoubleColumnChromeHooks
%hook AWEFeedNewDoubleColumnViewController
- (CGRect)dcFeed:(id)feed frameForCollectionView:(id)collection {
    CGRect native = %orig(feed, collection);
    return [DKXSDoubleColumnChrome frameForHost:self feed:feed collection:collection native:native];
}
- (void)viewWillAppear:(BOOL)animated { %orig(animated); [DKXSDoubleColumnChrome beginAppearance:self]; }
- (void)viewDidLayoutSubviews { %orig; [DKXSDoubleColumnChrome synchronize:self]; }
- (void)viewDidDisappear:(BOOL)animated { %orig(animated); [DKXSDoubleColumnChrome restore:self]; }
%end
%end

@implementation DKXSDoubleColumnChrome (Hooks)
+ (void)installHooks {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self installHooks]; }); return; }
    static BOOL installed;
    Class host = NSClassFromString(@"AWEFeedNewDoubleColumnViewController");
    if (!installed && [host isSubclassOfClass:UIViewController.class] && [self supportsFrameDelegate:host] &&
        [DKXSChatEnhancementPolicy class:host selector:@selector(viewWillAppear:) result:'v' arguments:@"B"] &&
        [DKXSChatEnhancementPolicy class:host selector:@selector(viewDidLayoutSubviews) result:'v' arguments:@""] &&
        [DKXSChatEnhancementPolicy class:host selector:@selector(viewDidDisappear:) result:'v' arguments:@"B"]) {
        %init(DKXSDoubleColumnChromeHooks); installed = YES;
    }
}
@end
%ctor { [DKXSDoubleColumnChrome installHooks]; }
