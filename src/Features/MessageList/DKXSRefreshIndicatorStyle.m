// 移植自 Si-yi/DYads- cbc2d5a（DYYYRefreshIndicatorStyle.m）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
#import "DKXSRefreshIndicatorStyle.h"
#import "DKXSMessageListStyle.h"
#import "DKXSMessageListMetrics.h"
#import "DKXSChatEnhancementPolicy.h"
#import "DKXSUtils.h"
#import "DKXSAwemeHeaders.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <math.h>

// 最小接口声明：AWERefreshHeader 与 AWEIMFansNewViewController.tableView 在上游 AwemeHeaders.h 有声明，
// DYxs 的 DKXSAwemeHeaders（39.5 导出）里没有，在此补充（不用 DouyinHeaders）。
@interface AWERefreshHeader : UIView
@property (nonatomic, readonly) UIScrollView *scrollView;
@property (nonatomic, weak) UIView *loading;
@property (nonatomic, readonly, getter=isRefreshing) BOOL refreshing;
- (void)placeSubviews;
- (void)setState:(long long)state;
- (void)setPullingPercent:(double)percent;
- (void)scrollViewPanStateDidChange:(id)change;
@end
@interface AWEIMFansNewViewController : UIViewController
@property (nonatomic, strong, readonly) UITableView *tableView;
@end

static char kDKXSRefreshIndicatorStateKey;
@interface DKXSRefreshIndicatorState : NSObject
@property (nonatomic, weak) UIView *loading;
@property (nonatomic, strong) CALayer *mask;
@property (nonatomic) BOOL suppressed;
@property (nonatomic) BOOL busy;
@end
@implementation DKXSRefreshIndicatorState @end

@implementation DKXSRefreshIndicatorStyle
+ (NSHashTable *)headers {static NSHashTable *headers;static dispatch_once_t once;dispatch_once(&once,^{headers=[NSHashTable weakObjectsHashTable];});return headers;}
+ (DKXSRefreshIndicatorState *)state:(UIView *)header {id state=objc_getAssociatedObject(header,&kDKXSRefreshIndicatorStateKey);return [state isKindOfClass:DKXSRefreshIndicatorState.class]?state:nil;}
+ (UIScrollView *)scrollViewForHeader:(UIView *)header {
    if(![header isKindOfClass:NSClassFromString(@"AWERefreshHeader")])return nil;
    UIView *view=header.superview;
    if(![view isKindOfClass:UIScrollView.class] || ((AWERefreshHeader *)header).scrollView!=view)return nil;
    UIViewController *owner=[DKXSUtils firstAvailableViewControllerFromView:header];
    BOOL fans=[owner isKindOfClass:NSClassFromString(@"AWEIMFansNewViewController")] && ((AWEIMFansNewViewController *)owner).tableView==view;
    BOOL notices=[owner isKindOfClass:NSClassFromString(@"AWENoticeSwiftImpl.InteractionNoticeListContainerViewController")];
    if(!fans && !notices)return nil;
    for(NSUInteger i=0;owner && i<12;i++,owner=owner.parentViewController)if([owner isKindOfClass:NSClassFromString(@"AWEIMFansAndInteractMergeViewController")])return (id)view;
    return nil;
}
+ (void)restore:(UIView *)header {
    DKXSRefreshIndicatorState *state=[self state:header];if(!state || state.busy)return;state.busy=YES;
    if(state.loading.layer.mask==state.mask)state.loading.layer.mask=nil;
    state.suppressed=NO;state.busy=NO;objc_setAssociatedObject(header,&kDKXSRefreshIndicatorStateKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
+ (void)synchronizeHeader:(UIView *)candidate {
    if(!NSThread.isMainThread)return;DKXSRefreshIndicatorState *state=[self state:candidate];if(state.busy)return;
    UIScrollView *scroll=[self scrollViewForHeader:candidate];
    if(scroll && candidate.window)[[self headers] addObject:candidate];
    if(!scroll || ![DKXSMessageListStyle topEnabled] || !candidate.window){[self restore:candidate];return;}
    AWERefreshHeader *header=(id)candidate;UIView *loading=header.loading;
    if(![loading isKindOfClass:NSClassFromString(@"AWEUILoadingView")] || ![loading isDescendantOfView:header] || !isfinite(scroll.contentOffset.y) || !isfinite(scroll.adjustedContentInset.top) || scroll.adjustedContentInset.top<0){[self restore:header];return;}
    BOOL show=[DKXSMessageListMetrics showRefreshIndicator:header.isRefreshing dragging:(scroll.dragging || scroll.tracking) offsetY:scroll.contentOffset.y insetTop:scroll.adjustedContentInset.top];
    if(state.loading!=loading){[self restore:header];state=nil;}
    if(show){[self restore:header];return;}
    CGRect bounds=loading.bounds;
    if(!isfinite(bounds.size.width) || !isfinite(bounds.size.height) || bounds.size.width<=0 || bounds.size.height<=0 || bounds.size.width>64 || bounds.size.height>64){[self restore:header];return;}
    if(!state){
        if(loading.layer.mask)return;
        state=[DKXSRefreshIndicatorState new];state.loading=loading;state.mask=[CALayer layer];state.mask.backgroundColor=UIColor.clearColor.CGColor;
        // 只遮住这一个32pt加载图，不改 refreshHeader.hidden/状态/回调，不能影响下拉触发。
        state.mask.frame=bounds;objc_setAssociatedObject(header,&kDKXSRefreshIndicatorStateKey,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    state.busy=YES;
    @try {
        if(loading.layer.mask && loading.layer.mask!=state.mask)return;
        [CATransaction begin];[CATransaction setDisableActions:YES];
        if(!CGRectEqualToRect(state.mask.frame,bounds))state.mask.frame=bounds;
        if(loading.layer.mask!=state.mask)loading.layer.mask=state.mask;
        [CATransaction commit];state.suppressed=loading.layer.mask==state.mask;
    } @finally {state.busy=NO;}
}
+ (void)refresh {if(NSThread.isMainThread)for(UIView *header in [self headers].allObjects)[self synchronizeHeader:header];}
+ (NSDictionary *)diagnostics {
    if(!NSThread.isMainThread)return @{};NSMutableArray *rows=[NSMutableArray array];
    for(UIView *view in [self headers].allObjects)if(view.window){
        AWERefreshHeader *header=(id)view;UIScrollView *scroll=[self scrollViewForHeader:header];DKXSRefreshIndicatorState *state=[self state:header];if(!scroll)continue;
        [rows addObject:@{@"refreshing":@(header.isRefreshing),@"dragging":@(scroll.dragging || scroll.tracking),@"idleSuppressed":@(state.suppressed && state.loading.layer.mask==state.mask),@"offsetY":@(scroll.contentOffset.y),@"insetTop":@(scroll.adjustedContentInset.top)}];
        if(rows.count>=4)break;
    }return @{@"headers":rows};
}
@end
