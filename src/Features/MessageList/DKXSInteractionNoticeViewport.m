// 移植自 Si-yi/DYads- b97c05e（DYYYInteractionNoticeViewport.m）：改名一律 DYYY -> DKXS，逻辑原样。
#import "DKXSInteractionNoticeViewport.h"
#import "DKXSNoticeViewportPolicy.h"
#import "DKXSMessageListStyle.h"
#import <objc/runtime.h>
#import <math.h>
static char kDKXSNoticeViewportPolicyKey;
static char kDKXSNoticeViewportLayoutAttemptKey;
static char kDKXSNoticeViewportLayoutBusyKey;
@implementation DKXSInteractionNoticeViewport
+ (NSHashTable *)controllers {static NSHashTable *t;static dispatch_once_t once;dispatch_once(&once,^{t=[NSHashTable weakObjectsHashTable];});return t;}
+ (DKXSNoticeViewportPolicy *)policy:(UIViewController *)controller {
    DKXSNoticeViewportPolicy *policy=objc_getAssociatedObject(controller,&kDKXSNoticeViewportPolicyKey);
    if(!policy && controller){policy=[DKXSNoticeViewportPolicy new];objc_setAssociatedObject(controller,&kDKXSNoticeViewportPolicyKey,policy,OBJC_ASSOCIATION_RETAIN_NONATOMIC);[[self controllers] addObject:controller];}
    return policy;
}
+ (BOOL)eligible:(UIViewController *)controller {
    if(!NSThread.isMainThread || ![DKXSMessageListStyle topEnabled] || ![controller isKindOfClass:NSClassFromString(@"InteractionNoticeTabListContainerViewController")] || !controller.isViewLoaded)return NO;
    CGRect bounds=controller.viewIfLoaded.bounds;
    if(!isfinite(bounds.size.width) || !isfinite(bounds.size.height) || bounds.size.width<160 || bounds.size.height<=bounds.size.width)return NO;
    for(NSUInteger i=0;i<12 && controller;i++,controller=controller.parentViewController)if([controller isKindOfClass:NSClassFromString(@"AWEIMFansAndInteractMergeViewController")])return YES;
    return NO;
}
+ (double)top:(double)native controller:(UIViewController *)controller {
    if(!NSThread.isMainThread)return native;
    return [[self policy:controller] topForNative:native enabled:[self eligible:controller]];
}
+ (double)header:(double)native controller:(UIViewController *)controller {
    if(!NSThread.isMainThread)return native;
    return [[self policy:controller] headerForNative:native enabled:[self eligible:controller]];
}
+ (NSArray<NSNumber *> *)geometryForNotice:(InteractionNoticeTabListContainerViewController *)notice {
    UIScrollView *scroll=notice.containerScrollView;
    UIView *header=notice.currentHeaderViewController.viewIfLoaded,*page=nil;
    for(UIView *view in scroll.subviews)if([view isKindOfClass:NSClassFromString(@"AWETabListTabContainerScrollView")]){page=view;break;}
    return @[@(scroll.frame.origin.y),@(header.superview==scroll?header.frame.size.height:NAN),@(page?page.frame.origin.y:NAN)];
}
+ (NSArray *)signatureForPolicy:(DKXSNoticeViewportPolicy *)policy controller:(UIViewController *)controller {
    return @[@(policy.active),@(policy.nativeTop),@(policy.nativeHeader),@(controller.viewIfLoaded.bounds.size.width),@(controller.viewIfLoaded.bounds.size.height)];
}
+ (void)prepareController:(UIViewController *)controller {
    if(!NSThread.isMainThread || ![controller isKindOfClass:NSClassFromString(@"InteractionNoticeTabListContainerViewController")] || !controller.isViewLoaded || [objc_getAssociatedObject(controller,&kDKXSNoticeViewportLayoutBusyKey) boolValue])return;
    InteractionNoticeTabListContainerViewController *notice=(id)controller;
    (void)notice.topSafeAreaForTabList;(void)notice.heightForHeaderView;
    DKXSNoticeViewportPolicy *policy=[self policy:controller];
    id previous=objc_getAssociatedObject(controller,&kDKXSNoticeViewportLayoutAttemptKey);
    UIScrollView *scroll=notice.containerScrollView;
    if((!policy.active && !previous) || !isfinite(policy.nativeTop) || !isfinite(policy.nativeHeader) || ![scroll isKindOfClass:NSClassFromString(@"AWETabListContainerScrollView")] || scroll.dragging || scroll.tracking || scroll.decelerating)return;
    NSArray *signature=[self signatureForPolicy:policy controller:controller],*actual=[self geometryForNotice:notice];
    CGFloat offsetBefore=scroll.contentOffset.y;
    BOOL attempted=[previous isEqual:signature];
    if(attempted){
        if(!policy.active || [policy reservationMatchesContainerTop:[actual[0] doubleValue] headerHeight:[actual[1] doubleValue] pageTop:[actual[2] doubleValue]])return;
        // 同一配置曾请求过，却仍是导出中的0高Header/0起点：直接回原生，不重复争抢布局。
        [policy validateContainerTop:[actual[0] doubleValue] headerHeight:[actual[1] doubleValue] pageTop:[actual[2] doubleValue]];
    }
    objc_setAssociatedObject(controller,&kDKXSNoticeViewportLayoutAttemptKey,signature,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(controller,&kDKXSNoticeViewportLayoutBusyKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        if(!attempted){
            // 外层布局并不更新实际Header；必须调用原生自己的Header更新入口。
            [notice updateHeaderViewLayout];[notice layoutTabListSubviews];
            if(policy.active){
                actual=[self geometryForNotice:notice];
                // 原生更新若同步把offset加106，仍会把首行留在状态栏后；也必须撤回。
                double reservedTop=[actual[2] doubleValue]-scroll.contentOffset.y+offsetBefore;
                [policy validateContainerTop:[actual[0] doubleValue] headerHeight:[actual[1] doubleValue] pageTop:reservedTop];
            }
        }
        if(policy.reservationRejected){
            // 顶部留白未被原生采用时恢复两个布局返回值，保证首次内容仍位于导航栏下方。
            (void)notice.topSafeAreaForTabList;(void)notice.heightForHeaderView;
            [notice updateHeaderViewLayout];[notice layoutTabListSubviews];
        }
    } @catch(__unused NSException *exception) {
        [policy validateContainerTop:NAN headerHeight:NAN pageTop:NAN];
        (void)notice.topSafeAreaForTabList;(void)notice.heightForHeaderView;
        [controller.viewIfLoaded setNeedsLayout];
    } @finally {
        objc_setAssociatedObject(controller,&kDKXSNoticeViewportLayoutAttemptKey,[self signatureForPolicy:policy controller:controller],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(controller,&kDKXSNoticeViewportLayoutBusyKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
+ (void)beginAppearance:(UIViewController *)controller {
    if(!NSThread.isMainThread)return;
    [[self policy:controller] beginAppearance];
    objc_setAssociatedObject(controller,&kDKXSNoticeViewportLayoutAttemptKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);[self prepareController:controller];
}
+ (void)didLayoutController:(UIViewController *)controller {[self prepareController:controller];}
+ (void)refresh {
    if(!NSThread.isMainThread)return;
    for(UIViewController *controller in [self controllers].allObjects)if(controller.isViewLoaded){[self prepareController:controller];[controller.viewIfLoaded setNeedsLayout];}
}
+ (NSDictionary *)diagnostics {
    if(!NSThread.isMainThread)return @{};NSMutableArray *rows=[NSMutableArray array];
    for(UIViewController *controller in [self controllers].allObjects)if(controller.viewIfLoaded.window){
        DKXSNoticeViewportPolicy *policy=objc_getAssociatedObject(controller,&kDKXSNoticeViewportPolicyKey);
        UIScrollView *scroll=((InteractionNoticeTabListContainerViewController *)controller).containerScrollView;
        if(![scroll isKindOfClass:NSClassFromString(@"AWETabListContainerScrollView")])continue;
        NSArray *actual=[self geometryForNotice:(id)controller];
        BOOL matched=[policy reservationMatchesContainerTop:[actual[0] doubleValue] headerHeight:[actual[1] doubleValue] pageTop:[actual[2] doubleValue]];
        [rows addObject:@{@"active":@(policy.active),@"nativeLayoutRequested":@(objc_getAssociatedObject(controller,&kDKXSNoticeViewportLayoutAttemptKey)!=nil),@"nativeTop":isfinite(policy.nativeTop)?@(policy.nativeTop):NSNull.null,@"nativeHeader":isfinite(policy.nativeHeader)?@(policy.nativeHeader):NSNull.null,@"reservedHeader":isfinite(policy.requestedHeader)?@(policy.requestedHeader):NSNull.null,@"actualHeaderHeight":isfinite([actual[1] doubleValue])?actual[1]:NSNull.null,@"actualPageTop":isfinite([actual[2] doubleValue])?actual[2]:NSNull.null,@"reservationApplied":@(matched),@"fallbackToNative":@(policy.reservationRejected),@"containerFrame":NSStringFromCGRect(scroll.frame),@"offset":NSStringFromCGPoint(scroll.contentOffset),@"fullViewport":@(matched && fabs(scroll.frame.size.height-controller.viewIfLoaded.bounds.size.height)<1)}];
    }return @{@"nativeLayout":@YES,@"controllers":rows};
}
@end
