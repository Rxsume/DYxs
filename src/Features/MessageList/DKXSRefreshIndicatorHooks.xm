// 移植自 Si-yi/DYads- cbc2d5a（DYYYRefreshIndicatorHooks.xm）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
// 须先 import UIKit：下方的最小接口声明以 UIView 为父类，
// 未引入 UIKit 时编译器找不到父类接口（0.6.9.20 CI run #121 的教训）。
#import <UIKit/UIKit.h>
#import "DKXSRefreshIndicatorStyle.h"
#import "DKXSChatEnhancementPolicy.h"
// 最小接口声明：AWERefreshHeader 在 DKXSAwemeHeaders（39.5 导出）里没有，在此补充。
@interface AWERefreshHeader : UIView
@property (nonatomic, readonly) UIScrollView *scrollView;
@property (nonatomic, weak) UIView *loading;
@property (nonatomic, readonly, getter=isRefreshing) BOOL refreshing;
- (void)placeSubviews;
- (void)setState:(long long)state;
- (void)setPullingPercent:(double)percent;
- (void)scrollViewPanStateDidChange:(id)change;
@end
%group DKXSNoticeRefreshIndicatorHooks
%hook AWERefreshHeader
- (void)placeSubviews { %orig;[DKXSRefreshIndicatorStyle synchronizeHeader:(UIView *)self]; }
- (void)layoutSubviews { %orig;[DKXSRefreshIndicatorStyle synchronizeHeader:(UIView *)self]; }
- (void)didMoveToWindow { %orig;[DKXSRefreshIndicatorStyle synchronizeHeader:(UIView *)self]; }
- (void)setState:(long long)state { %orig(state);[DKXSRefreshIndicatorStyle synchronizeHeader:(UIView *)self]; }
- (void)setPullingPercent:(double)percent { %orig(percent);[DKXSRefreshIndicatorStyle synchronizeHeader:(UIView *)self]; }
- (void)setLoading:(UIView *)loading { %orig(loading);[DKXSRefreshIndicatorStyle synchronizeHeader:(UIView *)self]; }
- (void)scrollViewPanStateDidChange:(id)change { %orig(change);[DKXSRefreshIndicatorStyle synchronizeHeader:(UIView *)self]; }
%end
%end
@implementation DKXSRefreshIndicatorStyle (RuntimeHooks)
+ (void)installHooks {
    static BOOL installed;if(installed)return;
    @synchronized(self){if(installed)return;
    Class cls=NSClassFromString(@"AWERefreshHeader");
    if([cls isSubclassOfClass:UIView.class] && [DKXSChatEnhancementPolicy class:cls selector:@selector(scrollView) result:'@' arguments:@""] &&
       [DKXSChatEnhancementPolicy class:cls selector:@selector(loading) result:'@' arguments:@""] &&
       [DKXSChatEnhancementPolicy class:cls selector:@selector(isRefreshing) result:'B' arguments:@""] &&
       [DKXSChatEnhancementPolicy class:cls selector:@selector(setState:) result:'v' arguments:@"q"] &&
       [DKXSChatEnhancementPolicy class:cls selector:@selector(setPullingPercent:) result:'v' arguments:@"d"] &&
       [DKXSChatEnhancementPolicy class:cls selector:@selector(setLoading:) result:'v' arguments:@"@"] &&
       [DKXSChatEnhancementPolicy class:cls selector:@selector(scrollViewPanStateDidChange:) result:'v' arguments:@"@"]){%init(DKXSNoticeRefreshIndicatorHooks);installed=YES;}
    }
}
@end
%ctor { [DKXSRefreshIndicatorStyle installHooks]; }
