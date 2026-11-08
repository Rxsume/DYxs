// 移植自 Si-yi/DYads- b97c05e（DYYYNoticeFilterGlass.m）：改名一律 DYYY -> DKXS，逻辑原样；
// 适配：上游 DYYYChatChrome 的 glassBackgroundWithIdentifier:/placeGlassBackground:frame:inView:
// DYxs 不移植，改为本文件内同名语义的本地实现（PR #33 DKXSMessageListStyle.m 同款做法）。
#import "DKXSNoticeFilterGlass.h"
#import "DKXSMessageListStyle.h"
#import "DKXSNoticeHeaderDrawingState.h"
#import "DKXSChatEnhancementPolicy.h"
#import "DKXSUtils.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>
#include <math.h>

static char kDKXSNoticeFilterGlassKey;
static char kDKXSNoticeFilterGlassMaterialKey;

// 最小接口声明：AWEIMFansAndInteractMergeViewControllerNaviBar 的 itemViews 在
// DKXSMessageListStyle.m 里已有同款本地声明；本文件直接调用，在此补充（不用 DouyinHeaders）。
@interface AWEIMFansAndInteractMergeViewControllerNaviBar : UIView
@property (nonatomic, strong, readonly) NSArray<UIView *> *itemViews;
@end

@class DKXSNoticeFilterGlassState;
@interface DKXSNoticeFilterGlass (Private)
+ (void)requested:(DKXSNoticeFilterGlassState *)state;
+ (void)optionChosen:(DKXSNoticeFilterGlassState *)state;
@end
@interface DKXSNoticeFilterGlassState : NSObject
@property (nonatomic, weak) UIView *item;
@property (nonatomic, weak) UIViewController *host;
@property (nonatomic, weak) UIView *panel;
@property (nonatomic, strong) UIVisualEffectView *glass;
@property (nonatomic, strong) NSHashTable<UIGestureRecognizer *> *gestures;
@property (nonatomic, strong) NSHashTable<UIGestureRecognizer *> *optionGestures;
@property (nonatomic, strong) NSHashTable<UIControl *> *optionControls;
@property (nonatomic) BOOL headerPending;
@property (nonatomic, strong) NSMapTable<UIView *, NSDictionary *> *fills;
@property (nonatomic) NSUInteger remaining;
@property (nonatomic) BOOL pending;
@property (nonatomic, copy) NSString *decision;
@property (nonatomic, copy) NSString *lastPanelClass;
@property (nonatomic) CGRect lastPanelFrame;
@property (nonatomic) NSUInteger appliedMenus;
- (void)tapped:(UIGestureRecognizer *)gesture;
- (void)optionTapped:(UIGestureRecognizer *)gesture;
- (void)optionSelected:(UIControl *)control;
@end
@implementation DKXSNoticeFilterGlassState
- (void)tapped:(UIGestureRecognizer *)gesture {if(gesture.state==UIGestureRecognizerStateEnded)[DKXSNoticeFilterGlass requested:self];}
- (void)optionTapped:(UIGestureRecognizer *)gesture {if(gesture.state==UIGestureRecognizerStateEnded)[DKXSNoticeFilterGlass optionChosen:self];}
- (void)optionSelected:(UIControl *)control {[DKXSNoticeFilterGlass optionChosen:self];}
@end

@implementation DKXSNoticeFilterGlass

// 过滤菜单玻璃本地实现（抄上游 DYYYChatChrome 的 glass:/placeGlass: 做法；DYxs 不移植 ChatChrome）。
+ (UIVisualEffectView *)dkxs_glassBackgroundWithIdentifier:(NSString *)identifier {
    UIVisualEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
    if (@available(iOS 26.0, *)) {
        UIGlassEffect *material = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular]; material.interactive = NO; effect = material;
    }
#endif
    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:effect];
    objc_setAssociatedObject(glass, &kDKXSNoticeFilterGlassMaterialKey, effect, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    glass.userInteractionEnabled = NO; glass.accessibilityElementsHidden = YES;
    glass.accessibilityIdentifier = identifier; glass.clipsToBounds = YES;
    glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.layer.borderWidth = 0.5; glass.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.18].CGColor;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
    if (@available(iOS 26.0, *)) glass.cornerConfiguration = [UICornerConfiguration capsuleConfiguration];
#endif
    return glass;
}
+ (void)dkxs_placeGlassBackground:(UIVisualEffectView *)glass frame:(CGRect)frame inView:(UIView *)carrier {
    UIUserInterfaceStyle style = [DKXSUtils isDarkMode] || carrier.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
    if (!glass.effect) glass.effect = objc_getAssociatedObject(glass, &kDKXSNoticeFilterGlassMaterialKey);
    if (glass.hidden) glass.hidden = NO;
    if (glass.alpha != 1) glass.alpha = 1;
    if (!CGRectEqualToRect(glass.frame, frame)) glass.frame = frame;
    CGFloat radius = CGRectGetHeight(frame) / 2;
    if (glass.layer.cornerRadius != radius) glass.layer.cornerRadius = radius;
    if (glass.overrideUserInterfaceStyle != style) glass.overrideUserInterfaceStyle = style;
    if (glass.superview != carrier) [carrier insertSubview:glass atIndex:0];
}

+ (NSHashTable<UIView *> *)items {static NSHashTable *items;static dispatch_once_t once;dispatch_once(&once,^{items=[NSHashTable weakObjectsHashTable];});return items;}
+ (UIViewController *)hostForView:(UIView *)view {
    UIViewController *owner=[DKXSUtils firstAvailableViewControllerFromView:view];
    for(NSUInteger i=0;owner && i<12;i++,owner=owner.parentViewController)if([owner isKindOfClass:NSClassFromString(@"AWEIMFansAndInteractMergeViewController")])return owner;
    return nil;
}
+ (BOOL)valid:(DKXSNoticeFilterGlassState *)state {
    return [DKXSMessageListStyle topEnabled] && state.item.window && state.host.viewIfLoaded.window && state.host.navigationController.topViewController==state.host && objc_getAssociatedObject(state.item,&kDKXSNoticeFilterGlassKey)==state;
}
+ (void)restoreMenu:(DKXSNoticeFilterGlassState *)state {
    for(UIGestureRecognizer *gesture in state.optionGestures.allObjects)[gesture removeTarget:state action:@selector(optionTapped:)];
    for(UIControl *control in state.optionControls.allObjects)[control removeTarget:state action:@selector(optionSelected:) forControlEvents:UIControlEventAllEvents];
    [state.optionGestures removeAllObjects];[state.optionControls removeAllObjects];
    [state.glass removeFromSuperview];
    for(UIView *view in state.fills.keyEnumerator.allObjects){
        NSDictionary *saved=[state.fills objectForKey:view];
        if(!view.backgroundColor || CGColorGetAlpha(view.backgroundColor.CGColor)==0)view.backgroundColor=saved[@"color"]==NSNull.null?nil:saved[@"color"];
        if(!view.opaque)view.opaque=[saved[@"opaque"] boolValue];
    }
    [state.fills removeAllObjects];state.panel=nil;
}
+ (void)restoreItem:(UIView *)item {
    DKXSNoticeFilterGlassState *state=objc_getAssociatedObject(item,&kDKXSNoticeFilterGlassKey);if(!state)return;
    for(UIGestureRecognizer *gesture in state.gestures.allObjects)[gesture removeTarget:state action:@selector(tapped:)];
    [self restoreMenu:state];state.remaining=0;
    objc_setAssociatedObject(item,&kDKXSNoticeFilterGlassKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);[[self items] removeObject:item];
}
+ (NSSet<NSString *> *)titles {return [NSSet setWithArray:@[@"全部消息",@"赞与收藏",@"提及",@"收到的评论",@"发出的评论",@"收到的弹幕",@"发出的弹幕"]];}
+ (NSArray<UILabel *> *)menuLabels:(DKXSNoticeFilterGlassState *)state {
    NSMutableDictionary<NSString *,UILabel *> *found=[NSMutableDictionary dictionary];NSSet *titles=[self titles];
    NSArray *windows=state.item.window.windowScene.windows?:@[state.item.window];NSUInteger visited=0;
    for(UIWindow *window in windows.reverseObjectEnumerator){
        if(window.hidden || window.alpha<=0.01 || fabs(window.bounds.size.width-state.item.window.bounds.size.width)>0.5)continue;
        NSMutableArray<UIView *> *pending=[NSMutableArray arrayWithObject:window];
        while(pending.count && visited++<512){
            UIView *view=pending.lastObject;[pending removeLastObject];
            if(view.hidden || view.alpha<=0.01 || [view isKindOfClass:NSClassFromString(@"AWENoticeSwiftBizUI.InteractionNoticeContainerCell")])continue;
            if([view isKindOfClass:UILabel.class]){
                NSString *text=[((UILabel *)view).text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                if(text.length && [titles containsObject:text])found[text]=(id)view;
                if(found.count==titles.count)return found.allValues;
            }
            if(pending.count+view.subviews.count<=512)[pending addObjectsFromArray:view.subviews];
        }
        [found removeAllObjects];
    }return nil;
}
+ (UIView *)panelForLabels:(NSArray<UILabel *> *)labels {
    if(labels.count!=7)return nil;
    UIView *panel=labels.firstObject.superview;BOOL common=NO;
    for(NSUInteger i=0;panel && i<12;i++,panel=panel.superview){BOOL all=YES;for(UIView *label in labels)if(![label isDescendantOfView:panel]){all=NO;break;}if(all){common=YES;break;}}
    if(!common || !panel || [panel isKindOfClass:UIWindow.class] || !panel.window || !isfinite(panel.bounds.size.width) || !isfinite(panel.bounds.size.height) || panel.bounds.size.width>panel.window.bounds.size.width+0.5 || panel.bounds.size.width<200 || panel.bounds.size.height<200 || panel.bounds.size.height>panel.window.bounds.size.height*0.75)return nil;
    // 合并同尺寸的原生黑底包装；不处理外层全屏遮暗和点击关闭区域。
    for(NSUInteger i=0;i<4;i++){
        UIView *parent=panel.superview;
        if(!parent || [parent isKindOfClass:UIWindow.class] || fabs(parent.bounds.size.width-panel.bounds.size.width)>0.5 || fabs(parent.bounds.size.height-panel.bounds.size.height)>0.5)break;
        CGRect relative=[panel convertRect:panel.bounds toView:parent];
        if(fabs(relative.origin.x-parent.bounds.origin.x)>0.5 || fabs(relative.origin.y-parent.bounds.origin.y)>0.5)break;
        panel=parent;
    }return panel;
}
+ (void)clearFill:(UIView *)view state:(DKXSNoticeFilterGlassState *)state {
    if(!view || [view isKindOfClass:UIVisualEffectView.class])return;
    UIColor *color=view.backgroundColor;
    if(![state.fills objectForKey:view] || (color && CGColorGetAlpha(color.CGColor)>0))[state.fills setObject:@{@"color":color?:NSNull.null,@"opaque":@(view.opaque)} forKey:view];
    if(color && CGColorGetAlpha(color.CGColor)>0)view.backgroundColor=UIColor.clearColor;
    if(view.opaque)view.opaque=NO;
}
+ (void)applyPanel:(UIView *)panel labels:(NSArray<UILabel *> *)labels state:(DKXSNoticeFilterGlassState *)state {
    if(!panel.superview || [panel isKindOfClass:UIVisualEffectView.class] || ([panel isKindOfClass:UIScrollView.class] && ((UIScrollView *)panel).contentSize.height>panel.bounds.size.height+0.5)){state.decision=@"unknown_panel";return;}
    if(state.panel!=panel)[self restoreMenu:state];state.panel=panel;
    for(UIView *label in labels)for(UIView *view=label.superview;view;view=view.superview){
        [self clearFill:view state:state];
        for(UIGestureRecognizer *gesture in view.gestureRecognizers)if([gesture isKindOfClass:UITapGestureRecognizer.class] && ![state.optionGestures containsObject:gesture]){[gesture addTarget:state action:@selector(optionTapped:)];[state.optionGestures addObject:gesture];}
        NSMutableArray<UIView *> *controls=[NSMutableArray arrayWithObject:view];if(view.subviews.count<=16)[controls addObjectsFromArray:view.subviews];
        for(UIView *candidate in controls)if([candidate isKindOfClass:UIControl.class] && ![state.optionControls containsObject:(id)candidate]){[(UIControl *)candidate addTarget:state action:@selector(optionSelected:) forControlEvents:UIControlEventTouchUpInside|UIControlEventPrimaryActionTriggered];[state.optionControls addObject:(id)candidate];}
        // 原生有时把纯色背景放在同尺寸空包装里，保留其点击行为，仅清掉填充。
        for(UIView *fill in view.subviews)if(fill.subviews.count==0 && ![fill isKindOfClass:UILabel.class] && ![fill isKindOfClass:UIImageView.class] && ![fill isKindOfClass:UIVisualEffectView.class] && CGRectEqualToRect(fill.frame,view.bounds) && fill.backgroundColor && CGColorGetAlpha(fill.backgroundColor.CGColor)>0)[self clearFill:fill state:state];
        if([view isKindOfClass:UITableViewCell.class])[self clearFill:((UITableViewCell *)view).backgroundView state:state];
        if([view isKindOfClass:UICollectionViewCell.class])[self clearFill:((UICollectionViewCell *)view).backgroundView state:state];
        if(view==panel)break;
    }
    if(!state.glass)state.glass=[self dkxs_glassBackgroundWithIdentifier:@"DYxs.NoticeFilterMenuGlass"];
    CGRect frame=CGRectInset(panel.bounds,8,0);
    [self dkxs_placeGlassBackground:state.glass frame:frame inView:panel];
    state.glass.layer.cornerRadius=20;state.glass.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    // 原生重建/重排选项时，subviews顺序可能变化；绘制层级必须始终低于原选项。
    [panel sendSubviewToBack:state.glass];
    if(![DKXSNoticeHeaderDrawingState pinBackgroundLayer:state.glass.layer inLayer:panel.layer reorder:^{if(panel.subviews.firstObject!=state.glass)[panel sendSubviewToBack:state.glass];}]){[self restoreMenu:state];state.decision=@"unknown_native_layers";return;}
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
    if(@available(iOS 26.0,*))state.glass.cornerConfiguration=[UICornerConfiguration configurationWithUniformRadius:[UICornerRadius fixedRadius:20]];
#endif
    if(state.glass.superview==panel){state.decision=@"applied";state.lastPanelClass=NSStringFromClass(panel.class);state.lastPanelFrame=panel.frame;state.appliedMenus++;}
}
+ (void)schedule:(DKXSNoticeFilterGlassState *)state {
    if(state.pending || !state.remaining)return;state.pending=YES;
    __weak DKXSNoticeFilterGlassState *weakState=state;
    dispatch_async(dispatch_get_main_queue(),^{
        DKXSNoticeFilterGlassState *current=weakState;if(!current)return;current.pending=NO;
        if(![self valid:current]){[self restoreItem:current.item];return;}
        if(!current.remaining)return;current.remaining--;
        NSArray *labels=[self menuLabels:current];UIView *panel=[self panelForLabels:labels];
        if(panel){[self applyPanel:panel labels:labels state:current];current.remaining=0;}
        else {if(!current.panel.window)[self restoreMenu:current];current.decision=@"menu_not_visible";}
    });
}
+ (void)optionChosen:(DKXSNoticeFilterGlassState *)state {
    if(!NSThread.isMainThread || state.headerPending || ![self valid:state])return;
    state.headerPending=YES;__weak DKXSNoticeFilterGlassState *weakState=state;
    dispatch_async(dispatch_get_main_queue(),^{
        DKXSNoticeFilterGlassState *current=weakState;if(!current)return;current.headerPending=NO;
        if([self valid:current])[DKXSMessageListStyle synchronizeHeaderForView:current.item];
    });
}
+ (void)requested:(DKXSNoticeFilterGlassState *)state {
    if(!NSThread.isMainThread || ![self valid:state])return;
    state.remaining=2;[self schedule:state];
}
+ (void)bindPlate:(UIView *)plate {
    if(!NSThread.isMainThread || ![plate isKindOfClass:NSClassFromString(@"AWEIMFansAndInteractMergeViewControllerNaviBar")] || ![DKXSChatEnhancementPolicy class:plate.class selector:@selector(itemViews) result:'@' arguments:@""])return;
    NSArray *items=((AWEIMFansAndInteractMergeViewControllerNaviBar *)plate).itemViews;
    UIView *item=[items isKindOfClass:NSArray.class] && items.count?[items firstObject]:nil;if(![item isKindOfClass:UIView.class])return;
    UIViewController *host=[self hostForView:item];
    if(![DKXSMessageListStyle topEnabled] || !host || !item.window){[self restoreItem:item];return;}
    NSMutableArray *pending=[NSMutableArray arrayWithObject:item];UIView *filter=nil;NSUInteger visited=0;
    while(pending.count && visited++<32){UIView *view=pending.lastObject;[pending removeLastObject];if([view isKindOfClass:NSClassFromString(@"AWENoticeSwiftBizUI.InteractionNoticeGroupFilterView")]){filter=view;break;}if(pending.count+view.subviews.count<=32)[pending addObjectsFromArray:view.subviews];}
    if(!filter){[self restoreItem:item];return;}
    DKXSNoticeFilterGlassState *state=objc_getAssociatedObject(item,&kDKXSNoticeFilterGlassKey);
    if(!state){state=[DKXSNoticeFilterGlassState new];state.item=item;state.host=host;state.gestures=[NSHashTable weakObjectsHashTable];state.optionGestures=[NSHashTable weakObjectsHashTable];state.optionControls=[NSHashTable weakObjectsHashTable];state.fills=[NSMapTable weakToStrongObjectsMapTable];state.decision=@"waiting_for_open";objc_setAssociatedObject(item,&kDKXSNoticeFilterGlassKey,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);[[self items] addObject:item];}
    for(UIView *view=filter;view;view=view.superview){for(UIGestureRecognizer *gesture in view.gestureRecognizers)if([gesture isKindOfClass:UITapGestureRecognizer.class] && ![state.gestures containsObject:gesture]){[gesture addTarget:state action:@selector(tapped:)];[state.gestures addObject:gesture];}if(view==item)break;}
    // 只在原生栏确实布局时补一次检查；任务自身不重排、不循环或轮询。
    if(state.remaining)[self schedule:state];
    if(state.panel && !state.panel.window)[self restoreMenu:state];
    else if(state.panel.window && state.glass.superview==state.panel)[DKXSNoticeHeaderDrawingState pinBackgroundLayer:state.glass.layer inLayer:state.panel.layer reorder:^{if(state.panel.subviews.firstObject!=state.glass)[state.panel sendSubviewToBack:state.glass];}];
}
+ (void)refresh {
    if(!NSThread.isMainThread)return;
    for(UIView *item in [self items].allObjects)if(![DKXSMessageListStyle topEnabled] || !item.window)[self restoreItem:item];
}
+ (NSDictionary *)diagnostics {
    if(!NSThread.isMainThread)return @{};NSMutableArray *rows=[NSMutableArray array];
    for(UIView *item in [self items].allObjects){DKXSNoticeFilterGlassState *state=objc_getAssociatedObject(item,&kDKXSNoticeFilterGlassKey);if(item.window && rows.count<2)[rows addObject:@{@"gestureTargets":@(state.gestures.allObjects.count),@"glassMounted":@(state.glass.superview!=nil && state.panel.window!=nil),@"decision":state.decision?:@"",@"appliedMenus":@(state.appliedMenus),@"backgroundZ":@(state.glass.layer.zPosition),@"optionCallbacks":@(state.optionGestures.allObjects.count+state.optionControls.allObjects.count),@"lastPanelClass":state.lastPanelClass?:@"",@"lastPanelFrame":NSStringFromCGRect(state.lastPanelFrame)}];}
    return @{@"menus":rows};
}
@end
