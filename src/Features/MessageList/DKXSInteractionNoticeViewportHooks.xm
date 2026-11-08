// 移植自 Si-yi/DYads- b97c05e（DYYYInteractionNoticeViewportHooks.xm）：改名一律 DYYY -> DKXS，逻辑原样。
// 须先 import UIKit：InteractionNoticeTabListContainerViewController 的最小接口声明
// 以 UIViewController 为父类，未引入 UIKit 时编译器找不到父类接口（0.6.9.20 CI run #121 的教训，PR #32 已修）。
#import <UIKit/UIKit.h>
#import "DKXSInteractionNoticeViewport.h"
#import "DKXSChatEnhancementPolicy.h"

%group DKXSNoticeNativeViewportHooks
%hook InteractionNoticeTabListContainerViewController
- (double)topSafeAreaForTabList {double native=%orig;return [DKXSInteractionNoticeViewport top:native controller:(UIViewController *)self];}
- (double)heightForHeaderView {double native=%orig;return [DKXSInteractionNoticeViewport header:native controller:(UIViewController *)self];}
- (void)viewWillAppear:(BOOL)animated {%orig(animated);[DKXSInteractionNoticeViewport beginAppearance:(UIViewController *)self];}
- (void)viewDidLoad {%orig;[DKXSInteractionNoticeViewport prepareController:(UIViewController *)self];}
- (void)viewDidLayoutSubviews {%orig;[DKXSInteractionNoticeViewport didLayoutController:(UIViewController *)self];}
%end
%end
@implementation DKXSInteractionNoticeViewport (RuntimeHooks)
+ (void)installHooks {
    static BOOL installed;if(installed)return;
    Class cls=NSClassFromString(@"InteractionNoticeTabListContainerViewController");
    if([cls isSubclassOfClass:UIViewController.class] && [DKXSChatEnhancementPolicy class:cls selector:@selector(topSafeAreaForTabList) result:'d' arguments:@""] && [DKXSChatEnhancementPolicy class:cls selector:@selector(heightForHeaderView) result:'d' arguments:@""] && [DKXSChatEnhancementPolicy class:cls selector:@selector(containerScrollView) result:'@' arguments:@""] && [DKXSChatEnhancementPolicy class:cls selector:@selector(currentHeaderViewController) result:'@' arguments:@""] && [DKXSChatEnhancementPolicy class:cls selector:@selector(updateHeaderViewLayout) result:'v' arguments:@""] && [DKXSChatEnhancementPolicy class:cls selector:@selector(layoutTabListSubviews) result:'v' arguments:@""] && [DKXSChatEnhancementPolicy class:cls selector:@selector(viewWillAppear:) result:'v' arguments:@"B"]){%init(DKXSNoticeNativeViewportHooks);installed=YES;}
}
@end
%ctor { [DKXSInteractionNoticeViewport installHooks]; }
