// 移植自 Si-yi/DYads- cbc2d5a（DYYYMessageListStyle.m）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
#import "DKXSMessageListStyle.h"
#import "DKXSMessageListCardView.h"
#import "DKXSMessageListMetrics.h"
#import "DKXSMessageListUpdateState.h"
#import "DKXSInteractionNoticeStyle.h"
#import "DKXSMessageListViewport.h"
#import "DKXSRefreshIndicatorStyle.h"
#import "DKXSMessageListStateStore.h"
#include <string.h>
#include <math.h>
#import "DKXSChatEnhancementPolicy.h"
#import "DKXSUtils.h"
#import "DKXSAwemeHeaders.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

// 最小接口声明：DKXSAwemeHeaders（39.5 导出）里的 AWEIMChatListViewController 是空接口、
// AWEIMChatListCommonCell 只有 renderWithHolder:；上游 DYads- 的 AwemeHeaders.h 则声明了
// tableView/chatList 与 AWEIMChatCellViewModel.chat。本文件直接调用的方法在此补充（不用 DouyinHeaders）。
// 另补本次新增调用：AWEIMChatCellRecommendChatLIView.lightInteractionBtn、
// AWEIMFansAndInteractMergeViewControllerNaviBar 的 itemViews/currentSelectedIndex/indicatorView、
// AWEIMFansAndInteractMergeViewController.fansViewController、UITableViewCellContentView。
@interface AWEIMChatModel : NSObject
@property (nonatomic, assign, readonly) BOOL stickOnTop;
@property (nonatomic, copy, readonly) NSString *name;
+ (BOOL)isNoticeChat:(id)chat;
@end
@interface AWEIMChatCellViewModel : NSObject
@property (nonatomic, strong, readonly) AWEIMChatModel *chat;
@end
@interface AWEIMChatListCommonCell (DKXSMessageList)
- (AWEIMChatCellViewModel *)cellViewModel;
@property (nonatomic, strong, readonly) UIView *avatarContainer;
@property (nonatomic, strong, readonly) UIView *horizontalLine;
@end
@interface AWEIMChatListViewController (DKXSMessageList)
@property (nonatomic, strong, readonly) UITableView *tableView;
@property (nonatomic, strong) NSArray *chatList;
@end
@interface AWEIMChatCellRecommendChatLIView : UIView
@property (nonatomic, strong, readonly) UIButton *lightInteractionBtn;
@end
@interface AWEIMFansAndInteractMergeViewControllerNaviBar : UIView
@property (nonatomic, strong, readonly) NSArray<UIView *> *itemViews;
@property (nonatomic, assign, readonly) long long currentSelectedIndex;
@property (nonatomic, strong, readonly) UIView *indicatorView;
- (void)setSelectedIndex:(long long)index;
@end
@interface AWEIMFansAndInteractMergeViewController : UIViewController
@property (nonatomic, strong, readonly) UIViewController *fansViewController;
@end
@interface UITableViewCellContentView : UIView
@end

@interface DKXSMessageCardState : NSObject
@property (nonatomic, strong) UIView *nativeBackground;
@property (nonatomic, strong) UIView *nativeSelected;
@property (nonatomic, strong) DKXSMessageListCardView *background;
@property (nonatomic, strong) DKXSMessageListCardView *selected;
@property (nonatomic, strong) NSMapTable<UIView *, id> *fills;
@property (nonatomic, strong) NSMapTable<UIView *, NSDictionary *> *masks;
@property (nonatomic, weak) UIView *line;
@property (nonatomic) BOOL lineHidden;
@property (nonatomic) BOOL busy;
@property (nonatomic, copy) NSString *kind;
@end
@implementation DKXSMessageCardState @end

@interface DKXSMessageContentState : NSObject
@property (nonatomic, weak) UIView *view;
@property (nonatomic, weak) UITableViewCell *cell;
@property (nonatomic, strong) DKXSMessageListUpdateState *updates;
@property (nonatomic) CGAffineTransform nativeTransform;
@property (nonatomic) CGAffineTransform appliedTransform;
@property (nonatomic) CGRect nativeFrame;
@property (nonatomic) CGRect displayedFrame;
@property (nonatomic) CGFloat scale;
@property (nonatomic) CGFloat topPadding;
@property (nonatomic) CGFloat bottomPadding;
@property (nonatomic) CGFloat verticalShift;
@property (nonatomic) BOOL active;
@property (nonatomic) BOOL applied;
@property (nonatomic) BOOL busy;
@property (nonatomic, copy) NSString *decision;
@end
@implementation DKXSMessageContentState @end
@interface DKXSMessageContentToken : NSObject
@property (nonatomic, strong) DKXSMessageContentState *state;
@property (nonatomic, weak) UIView *view;
@property (nonatomic) NSUInteger generation;
@end
@implementation DKXSMessageContentToken @end


@interface DKXSMessageLightState : NSObject
@property (nonatomic, weak) UIButton *button;
@property (nonatomic, strong) CALayer *nativeMask;
@property (nonatomic, strong) CAShapeLayer *mask;
@property (nonatomic) UIEdgeInsets nativeInsets;
@property (nonatomic) UIEdgeInsets appliedInsets;
@property (nonatomic) BOOL busy;
@end
@implementation DKXSMessageLightState @end

@interface DKXSMessageHeaderState : NSObject
@property (nonatomic, strong) UIVisualEffectView *left;
@property (nonatomic, strong) UIVisualEffectView *right;
@property (nonatomic, strong) UIVisualEffectView *actions;
@property (nonatomic, weak) UILabel *redundantTitle;
@property (nonatomic) BOOL titleHidden;
@property (nonatomic, strong) NSMapTable<UIView *, NSNumber *> *hiddenViews;
@property (nonatomic, weak) UIView *bar;
@property (nonatomic, weak) UIView *plate;
@property (nonatomic, weak) UIView *noticeActions;
@property (nonatomic) CGAffineTransform plateNativeTransform;
@property (nonatomic) CGAffineTransform plateAppliedTransform;
@property (nonatomic) BOOL plateApplied;
@property (nonatomic) BOOL auxiliary;
@property (nonatomic, strong) NSMapTable<UIView *, id> *fills;
@property (nonatomic, weak) UIView *line;
@property (nonatomic) BOOL notice;
@property (nonatomic) CGRect leftRect;
@property (nonatomic, weak) UIView *indicator;
@property (nonatomic) BOOL indicatorHidden;
@property (nonatomic, weak) UIView *leftAnchor;
@property (nonatomic, weak) UIView *rightAnchor;
@property (nonatomic, copy) NSArray<NSLayoutConstraint *> *constraints;
@property (nonatomic) BOOL lineHidden;
@property (nonatomic) BOOL nativeOpaque;
@property (nonatomic) BOOL pending;
@property (nonatomic) BOOL busy;
@end
@implementation DKXSMessageHeaderState @end

@implementation DKXSMessageListStyle
// 顶栏毛玻璃本地实现（抄上游 DYYYChatChrome 的 glass:/placeGlass: 做法；DYxs 不移植 ChatChrome，
// 其 glassBackgroundWithIdentifier:/placeGlassBackground:frame:inView: 在此同名语义复现）。
static char kDKXSMessageListMaterialKey;
+ (UIVisualEffectView *)dkxs_glassBackgroundWithIdentifier:(NSString *)identifier {
    UIVisualEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
    if (@available(iOS 26.0, *)) {
        UIGlassEffect *material = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular]; material.interactive = NO; effect = material;
    }
#endif
    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:effect];
    objc_setAssociatedObject(glass, &kDKXSMessageListMaterialKey, effect, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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
    if (!glass.effect) glass.effect = objc_getAssociatedObject(glass, &kDKXSMessageListMaterialKey);
    if (glass.hidden) glass.hidden = NO;
    if (glass.alpha != 1) glass.alpha = 1;
    if (!CGRectEqualToRect(glass.frame, frame)) glass.frame = frame;
    CGFloat radius = CGRectGetHeight(frame) / 2;
    if (glass.layer.cornerRadius != radius) glass.layer.cornerRadius = radius;
    if (glass.overrideUserInterfaceStyle != style) glass.overrideUserInterfaceStyle = style;
    if (glass.superview != carrier) [carrier insertSubview:glass atIndex:0];
}

+ (NSHashTable *)controllers { static NSHashTable *t; static dispatch_once_t once; dispatch_once(&once,^{t=[NSHashTable weakObjectsHashTable];}); return t; }
+ (NSHashTable *)cells { static NSHashTable *t; static dispatch_once_t once; dispatch_once(&once,^{t=[NSHashTable weakObjectsHashTable];}); return t; }
+ (NSHashTable *)bars { static NSHashTable *t; static dispatch_once_t once; dispatch_once(&once,^{t=[NSHashTable weakObjectsHashTable];}); return t; }
+ (void)preparePreferences {
    // DYxs 没有 DYYYEnableChatTopGlass 这一键（顶栏玻璃由 DYxsChatTopBlur 等键控制）；两项均默认关闭，跟随第 8 批“全部默认关”的移植惯例。
    [NSUserDefaults.standardUserDefaults registerDefaults:@{@"DKXSEnableMessageListCards":@NO,@"DKXSEnableMessageListTopGlass":@NO}];
}
+ (BOOL)cardsEnabled { return [NSUserDefaults.standardUserDefaults boolForKey:@"DKXSEnableMessageListCards"]; }
+ (BOOL)topEnabled { return [NSUserDefaults.standardUserDefaults boolForKey:@"DKXSEnableMessageListTopGlass"]; }
+ (BOOL)adapterReady {
    static BOOL ready;
    if(ready)return YES;
    Class cell=NSClassFromString(@"AWEIMChatListCommonCell"),vm=NSClassFromString(@"AWEIMChatCellViewModel"),chat=NSClassFromString(@"AWEIMChatModel");
    ready = [DKXSChatEnhancementPolicy class:cell selector:@selector(cellViewModel) result:'@' arguments:@""] &&
        [DKXSChatEnhancementPolicy class:vm selector:@selector(chat) result:'@' arguments:@""] &&
        [DKXSChatEnhancementPolicy class:chat selector:@selector(stickOnTop) result:'B' arguments:@""] &&
        [DKXSChatEnhancementPolicy class:chat selector:@selector(name) result:'@' arguments:@""] &&
        [DKXSChatEnhancementPolicy class:object_getClass(chat) selector:@selector(isNoticeChat:) result:'B' arguments:@"@"];
    return ready;
}
+ (UIViewController *)owner:(UIView *)view named:(NSString *)name {
    UIViewController *controller=[DKXSUtils firstAvailableViewControllerFromView:view];
    Class cls=NSClassFromString(name);
    for(NSUInteger i=0;controller && i<12;i++,controller=controller.parentViewController)
        if(cls && [controller isKindOfClass:cls])return controller;
    return nil;
}
+ (NSString *)kindForChat:(AWEIMChatModel *)chat {
    if(![chat isKindOfClass:NSClassFromString(@"AWEIMChatModel")])return nil;
    BOOL notice=[NSClassFromString(@"AWEIMChatModel") isNoticeChat:chat] && [chat.name isKindOfClass:NSString.class] &&
        [@[@"互动消息",@"互动通知"] containsObject:chat.name];
    return [DKXSMessageListMetrics kindForNotice:notice pinned:chat.stickOnTop];
}
+ (NSMapTable *)rowPlans:(UITableView *)table create:(BOOL)create {
    NSMapTable *plans=objc_getAssociatedObject(table,@selector(rowHeight:controller:table:indexPath:));
    if(!plans && create){plans=[NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory|NSPointerFunctionsObjectPointerPersonality valueOptions:NSPointerFunctionsStrongMemory];objc_setAssociatedObject(table,@selector(rowHeight:controller:table:indexPath:),plans,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    return plans;
}
+ (CGFloat)rowHeight:(CGFloat)native controller:(UIViewController *)candidate table:(UITableView *)table indexPath:(NSIndexPath *)path {
    if(!NSThread.isMainThread || ![self cardsEnabled] || ![self adapterReady] || ![self contentAdapterReady] || ![candidate isKindOfClass:NSClassFromString(@"AWEIMChatListViewController")] || path.section!=0)return native;
    AWEIMChatListViewController *owner=(id)candidate;NSArray *chats=owner.chatList;
    if(table!=owner.tableView || ![chats isKindOfClass:NSArray.class] || path.row>=chats.count)return native;
    NSString *kind=[self kindForChat:chats[path.row]],*previous=path.row?[self kindForChat:chats[path.row-1]]:nil,*next=path.row+1<chats.count?[self kindForChat:chats[path.row+1]]:nil;
    NSDictionary *plan=[DKXSMessageListMetrics paddingForKind:kind previous:previous next:next nativeHeight:native];
    if(!plan.count)return native;
    [[self rowPlans:table create:YES] setObject:plan forKey:chats[path.row]];
    return [plan[@"height"] doubleValue];
}
+ (NSDictionary *)paddingForCell:(UITableViewCell *)cell {
    AWEIMChatListViewController *owner=(id)[self owner:cell named:@"AWEIMChatListViewController"];
    if(!owner || ![cell isKindOfClass:NSClassFromString(@"AWEIMChatListCommonCell")])return nil;
    id chat=((AWEIMChatListCommonCell *)cell).cellViewModel.chat;
    NSDictionary *plan=chat?[[self rowPlans:owner.tableView create:NO] objectForKey:chat]:nil;
    return plan && fabs(cell.bounds.size.height-[plan[@"height"] doubleValue])<0.5?plan:nil;
}
+ (UIView *)avatarInContent:(UIView *)content {
    if(content.subviews.count>64)return nil;
    for(UIView *view in content.subviews){
        if(view.subviews.count>8)continue;
        for(UIView *leaf in view.subviews)if([leaf isKindOfClass:NSClassFromString(@"AWEIMChatCellAvatarView")])return leaf;
    }
    return nil;
}
+ (NSHashTable *)lightViews { static NSHashTable *t;static dispatch_once_t once;dispatch_once(&once,^{t=[NSHashTable weakObjectsHashTable];});return t; }
+ (void)resetLightInteraction:(UIView *)view {
    if(!NSThread.isMainThread)return;
    DKXSMessageLightState *state=objc_getAssociatedObject(view,@selector(synchronizeLightInteraction:));
    if(!state || state.busy)return;state.busy=YES;
    UIButton *button=state.button;
    if(button.layer.mask==state.mask)button.layer.mask=state.nativeMask;
    if(UIEdgeInsetsEqualToEdgeInsets(button.imageEdgeInsets,state.appliedInsets))button.imageEdgeInsets=state.nativeInsets;
    objc_setAssociatedObject(view,@selector(synchronizeLightInteraction:),nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);[[self lightViews] removeObject:view];
}
+ (void)synchronizeLightInteraction:(UIView *)candidate {
    if(!NSThread.isMainThread || ![candidate isKindOfClass:NSClassFromString(@"AWEIMChatCellRecommendChatLIView")])return;
    DKXSMessageLightState *state=objc_getAssociatedObject(candidate,@selector(synchronizeLightInteraction:));if(state.busy)return;
    if(![self cardsEnabled] || !candidate.window || ![self owner:candidate named:@"AWEIMChatListViewController"]){[self resetLightInteraction:candidate];return;}
    if(![candidate respondsToSelector:@selector(lightInteractionBtn)])return;
    UIButton *button=((AWEIMChatCellRecommendChatLIView *)candidate).lightInteractionBtn;
    if(![button isKindOfClass:UIButton.class] || button.bounds.size.width<30 || button.bounds.size.width>60 || button.bounds.size.height<30 || button.bounds.size.height>60)return;
    if(state && state.button!=button){[self resetLightInteraction:candidate];state=nil;}
    if(!state){
        if(button.layer.mask)return;
        state=[DKXSMessageLightState new];state.button=button;state.nativeMask=button.layer.mask;state.nativeInsets=button.imageEdgeInsets;state.mask=[CAShapeLayer layer];state.mask.fillColor=UIColor.blackColor.CGColor;
        state.appliedInsets=state.nativeInsets;
        objc_setAssociatedObject(candidate,@selector(synchronizeLightInteraction:),state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);[[self lightViews] addObject:candidate];
    }
    state.busy=YES;
    @try {
        if(!UIEdgeInsetsEqualToEdgeInsets(button.imageEdgeInsets,state.appliedInsets))state.nativeInsets=button.imageEdgeInsets;
        state.appliedInsets=UIEdgeInsetsMake(state.nativeInsets.top+3,state.nativeInsets.left+3,state.nativeInsets.bottom+3,state.nativeInsets.right+3);
        CGFloat diameter=MIN(button.bounds.size.width,button.bounds.size.height)*0.75;
        CGRect circle=CGRectMake((button.bounds.size.width-diameter)/2,(button.bounds.size.height-diameter)/2,diameter,diameter);
        [CATransaction begin];[CATransaction setDisableActions:YES];if(!CGRectEqualToRect(state.mask.frame,button.bounds))state.mask.frame=button.bounds;
        CGPathRef path=[UIBezierPath bezierPathWithOvalInRect:circle].CGPath;
        if(!state.mask.path || !CGPathEqualToPath(state.mask.path,path))state.mask.path=path;
        if(button.layer.mask!=state.mask)button.layer.mask=state.mask;[CATransaction commit];
        if(!UIEdgeInsetsEqualToEdgeInsets(button.imageEdgeInsets,state.appliedInsets))button.imageEdgeInsets=state.appliedInsets;
    } @finally {state.busy=NO;}
}
+ (void)clearFill:(UIView *)view state:(DKXSMessageCardState *)state {
    if(!view)return;
    UIColor *color=view.backgroundColor;
    if(![state.fills objectForKey:view] || (color && CGColorGetAlpha(color.CGColor)>0)) [state.fills setObject:color ?: NSNull.null forKey:view];
    if(color && CGColorGetAlpha(color.CGColor)>0)view.backgroundColor=UIColor.clearColor;
}
+ (void)restoreMasks:(DKXSMessageCardState *)state {
    for(UIView *view in state.masks.keyEnumerator.allObjects){
        NSDictionary *saved=[state.masks objectForKey:view];
        if(view.layer.mask==saved[@"applied"])view.layer.mask=saved[@"native"]==NSNull.null?nil:saved[@"native"];
    }
    [state.masks removeAllObjects];
}
+ (NSHashTable *)contentViews { static NSHashTable *t;static dispatch_once_t once;dispatch_once(&once,^{t=[NSHashTable weakObjectsHashTable];});return t; }
+ (BOOL)contentAdapterReady {
    static BOOL ready;if(ready)return YES;
    Class cls=NSClassFromString(@"UITableViewCellContentView");
    if(![cls isSubclassOfClass:UIView.class])return NO;
    NSDictionary *types=@{NSStringFromSelector(@selector(setFrame:)):[NSString stringWithUTF8String:@encode(CGRect)],NSStringFromSelector(@selector(setBounds:)):[NSString stringWithUTF8String:@encode(CGRect)],NSStringFromSelector(@selector(setCenter:)):[NSString stringWithUTF8String:@encode(CGPoint)],NSStringFromSelector(@selector(setTransform:)):[NSString stringWithUTF8String:@encode(CGAffineTransform)]};
    for(NSString *name in types){
        NSMethodSignature *signature=[cls instanceMethodSignatureForSelector:NSSelectorFromString(name)];
        if(!signature || signature.numberOfArguments!=3 || strcmp(signature.methodReturnType,@encode(void)) || strcmp([signature getArgumentTypeAtIndex:2],[types[name] UTF8String]))return NO;
    }
    ready=YES;return YES;
}
+ (DKXSMessageContentState *)contentState:(UIView *)view {
    if(!NSThread.isMainThread)return nil;
    DKXSMessageContentState *state=objc_getAssociatedObject(view,@selector(beginContentGeometry:));
    return state.active && state.cell.contentView==view?state:nil;
}
+ (NSDictionary *)valuesForFrame:(CGRect)frame {
    return @{@"x":@(frame.origin.x),@"y":@(frame.origin.y),@"width":@(frame.size.width),@"height":@(frame.size.height)};
}
+ (CGRect)nativeContentFrame:(CGRect)frame forView:(UIView *)view {
    DKXSMessageContentState *state=[self contentState:view];
    if(!state || state.busy || state.updates.depth || !state.applied)return frame;
    NSDictionary *native=[DKXSMessageListMetrics nativeFrameForRequest:[self valuesForFrame:frame] previousNative:[self valuesForFrame:state.nativeFrame] previousDisplayed:[self valuesForFrame:state.displayedFrame]];
    return CGRectMake([native[@"x"] doubleValue],[native[@"y"] doubleValue],[native[@"width"] doubleValue],[native[@"height"] doubleValue]);
}
+ (void)applyContent:(DKXSMessageContentState *)state {
    UIView *view=state.view;
    if(!view || !state.active || state.busy || state.updates.depth)return;
    NSDictionary *plan=[DKXSMessageListMetrics contentTransformForX:0 y:0 width:view.bounds.size.width height:view.bounds.size.height rowWidth:view.bounds.size.width rowHeight:view.bounds.size.height];
    if(!plan.count){state.decision=@"unready_bounds";return;}
    state.scale=[plan[@"scale"] doubleValue];
    state.nativeFrame=view.frame;
    state.nativeTransform=view.transform;
    state.appliedTransform=CGAffineTransformScale(state.nativeTransform,state.scale,state.scale);
    state.verticalShift=0;
    state.busy=YES;
    @try {[UIView performWithoutAnimation:^{
        view.transform=state.appliedTransform;
        if(state.topPadding || state.bottomPadding){
            UIView *avatar=[self avatarInContent:view];
            if(avatar){
                CGRect rect=[avatar convertRect:avatar.bounds toView:state.cell];
                CGFloat desired=(state.topPadding+state.cell.bounds.size.height-state.bottomPadding)/2;
                state.verticalShift=desired-CGRectGetMidY(rect);
                CGAffineTransform shifted=state.appliedTransform;shifted.ty+=state.verticalShift;
                state.appliedTransform=shifted;view.transform=shifted;
            }
        }
    }];}
    @finally {state.busy=NO;}
    state.displayedFrame=view.frame;state.applied=YES;state.decision=@"container_applied";
}
+ (id)beginContentGeometry:(UIView *)view {
    DKXSMessageContentState *state=[self contentState:view];
    if(!state || state.busy)return nil;
    BOOL outer=state.updates.depth==0;
    NSUInteger generation=[state.updates beginUpdate];
    if(outer && state.applied){
        state.busy=YES;
        @try {if(CGAffineTransformEqualToTransform(view.transform,state.appliedTransform))[UIView performWithoutAnimation:^{view.transform=state.nativeTransform;}];}
        @finally {state.busy=NO;}
        state.applied=NO;
    }
    DKXSMessageContentToken *token=[DKXSMessageContentToken new];token.state=state;token.view=view;token.generation=generation;
    return token;
}
+ (void)endContentGeometry:(id)candidate {
    if(!NSThread.isMainThread || ![candidate isKindOfClass:DKXSMessageContentToken.class])return;
    DKXSMessageContentToken *token=candidate;
    if([self contentState:token.view]!=token.state)return;
    if([token.state.updates endUpdate:token.generation])[self applyContent:token.state];
}
+ (CGAffineTransform)nativeContentTransform:(CGAffineTransform)transform forView:(UIView *)view {
    DKXSMessageContentState *state=[self contentState:view];
    if(!state || state.busy)return transform;
    if(state.applied && !state.updates.depth && CGAffineTransformEqualToTransform(transform,state.appliedTransform))return transform;
    state.nativeTransform=transform;
    if(state.updates.depth || !state.applied)return transform;
    CGAffineTransform applied=CGAffineTransformScale(transform,state.scale,state.scale);
    applied.ty+=state.verticalShift;state.appliedTransform=applied;
    return state.appliedTransform;
}
+ (void)didSetContentTransform:(UIView *)view {
    DKXSMessageContentState *state=[self contentState:view];
    if(!state || state.busy || state.updates.depth || !state.applied || state.scale<=0)return;
    state.displayedFrame=view.frame;
    // 原生变换与均匀缩放共用中心；反算只用于识别之后由显示 frame 派生的原生移动。
    CGRect rect=view.frame;rect.origin.y-=state.verticalShift;CGFloat xInset=rect.size.width*(1/state.scale-1)/2,yInset=rect.size.height*(1/state.scale-1)/2;
    state.nativeFrame=CGRectInset(rect,-xInset,-yInset);
}
+ (void)resetContentView:(UIView *)view {
    DKXSMessageContentState *state=objc_getAssociatedObject(view,@selector(beginContentGeometry:));
    if(!state || state.busy)return;
    [state.updates invalidate];state.active=NO;state.busy=YES;
    @try {if(state.applied && CGAffineTransformEqualToTransform(view.transform,state.appliedTransform))[UIView performWithoutAnimation:^{view.transform=state.nativeTransform;}];}
    @finally {state.busy=NO;}
    objc_setAssociatedObject(view,@selector(beginContentGeometry:),nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [[self contentViews] removeObject:view];
}
+ (void)synchronizeContent:(UITableViewCell *)cell {
    UIView *view=cell.contentView;
    if(![self contentAdapterReady] || ![view isKindOfClass:NSClassFromString(@"UITableViewCellContentView")])return;
    DKXSMessageContentState *state=[self contentState:view];
    NSDictionary *padding=[self paddingForCell:cell];
    CGFloat top=[padding[@"top"] doubleValue],bottom=[padding[@"bottom"] doubleValue];
    BOOL changed=state && (state.topPadding!=top || state.bottomPadding!=bottom);
    if(state && changed){
        id token=[self beginContentGeometry:view];state.topPadding=top;state.bottomPadding=bottom;[self endContentGeometry:token];
    }
    if(state){
        if(state.busy || state.updates.depth)return;
        if(state.applied && CGAffineTransformEqualToTransform(view.transform,state.appliedTransform)){[self didSetContentTransform:view];return;}
    } else {
        state=[DKXSMessageContentState new];state.view=view;state.cell=cell;state.active=YES;state.topPadding=top;state.bottomPadding=bottom;state.updates=[DKXSMessageListUpdateState new];
        objc_setAssociatedObject(view,@selector(beginContentGeometry:),state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);[[self contentViews] addObject:view];
    }
    [self applyContent:state];
}
+ (void)maskBackground:(UIView *)view state:(DKXSMessageCardState *)state {
    NSDictionary *saved=[state.masks objectForKey:view];
    if(saved && view.layer.mask!=saved[@"applied"]){[state.masks removeObjectForKey:view];saved=nil;}
    CALayer *mask=saved[@"applied"];
    if(!mask){
        if(view.layer.mask)return;
        // 原生满行底板可能在异步渲染后重写颜色。仅遮住已核对的空背景视图，不钩全局 setter。
        mask=[CALayer layer];mask.backgroundColor=UIColor.clearColor.CGColor;
        [state.masks setObject:@{@"native":NSNull.null,@"applied":mask,@"background":@YES} forKey:view];
        [CATransaction begin];[CATransaction setDisableActions:YES];view.layer.mask=mask;[CATransaction commit];
    }
    CGRect rect=view.bounds;
    if(!CGRectEqualToRect(mask.frame,rect)){[CATransaction begin];[CATransaction setDisableActions:YES];mask.frame=rect;[CATransaction commit];}
}
+ (void)resetCard:(UITableViewCell *)cell {
    if(!NSThread.isMainThread)return;
    DKXSMessageCardState *state=objc_getAssociatedObject(cell,@selector(synchronizeCell:));
    if(!state || state.busy)return;
    state.busy=YES;
    if(cell.backgroundView==state.background)cell.backgroundView=state.nativeBackground;
    if(cell.selectedBackgroundView==state.selected)cell.selectedBackgroundView=state.nativeSelected;
    for(UIView *view in state.fills.keyEnumerator.allObjects)if(!view.backgroundColor || CGColorGetAlpha(view.backgroundColor.CGColor)==0){
        id color=[state.fills objectForKey:view];view.backgroundColor=color==NSNull.null?nil:color;
    }
    if(state.line.hidden)state.line.hidden=state.lineHidden;
    objc_setAssociatedObject(cell,@selector(synchronizeCell:),nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [[self cells] removeObject:cell];
}
+ (void)resetCell:(UITableViewCell *)cell {
    if(!NSThread.isMainThread)return;
    [self resetContentView:cell.contentView];[self resetCard:cell];
}
+ (void)synchronizeCell:(UITableViewCell *)base {
    if(!NSThread.isMainThread || ![base isKindOfClass:NSClassFromString(@"AWEIMChatListCommonCell")])return;
    AWEIMChatListCommonCell *cell=(id)base;
    DKXSMessageCardState *state=objc_getAssociatedObject(cell,@selector(synchronizeCell:));
    if(state.busy)return;
    AWEIMChatListViewController *owner=(id)[self owner:cell named:@"AWEIMChatListViewController"];
    if(![self cardsEnabled] || !owner || !cell.window || ![self adapterReady]){[self resetCell:cell];return;}
    [self synchronizeContent:cell];
    for(UIView *view in cell.contentView.subviews)if([view isKindOfClass:NSClassFromString(@"AWEIMChatCellRecommendChatLIView")])[self synchronizeLightInteraction:view];
    UITableView *table=owner.tableView;
    NSIndexPath *index=[table indexPathForCell:cell];
    NSArray *chats=owner.chatList;
    if(![table isKindOfClass:UITableView.class] || ![chats isKindOfClass:NSArray.class] || !index || index.row>=chats.count ||
        [table numberOfRowsInSection:index.section]!=chats.count || table.hasUncommittedUpdates)return;
    AWEIMChatModel *chat=cell.cellViewModel.chat;
    if(chats[index.row]!=chat){[self resetCard:cell];return;}
    NSString *kind=[self kindForChat:chat],*previous=index.row?[self kindForChat:chats[index.row-1]]:nil;
    NSString *next=index.row+1<chats.count?[self kindForChat:chats[index.row+1]]:nil;
    NSDictionary *segment=[DKXSMessageListMetrics segmentForKind:kind previous:previous next:next width:cell.bounds.size.width height:cell.bounds.size.height];
    if(!segment.count){[self resetCard:cell];return;}
    if(!state){
        state=[DKXSMessageCardState new];state.nativeBackground=cell.backgroundView;state.nativeSelected=cell.selectedBackgroundView;
        state.fills=[NSMapTable weakToStrongObjectsMapTable];state.masks=[NSMapTable weakToStrongObjectsMapTable];state.background=[[DKXSMessageListCardView alloc] initWithFrame:cell.bounds];state.selected=[[DKXSMessageListCardView alloc] initWithFrame:cell.bounds];
        state.background.accessibilityIdentifier=@"DYxs.MessageGroupBackground";state.selected.accessibilityIdentifier=@"DYxs.MessageGroupSelection";
        objc_setAssociatedObject(cell,@selector(synchronizeCell:),state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);[[self cells] addObject:cell];
    }
    state.busy=YES;
    @try {
        state.kind=kind;
        BOOL dark=[DKXSUtils isDarkMode] || cell.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;
        CGFloat surfaceWhite=0.125;
        state.background.fillColor=dark?[UIColor colorWithWhite:surfaceWhite alpha:1]:UIColor.secondarySystemGroupedBackgroundColor;
        state.selected.fillColor=dark?[UIColor colorWithWhite:0.21 alpha:1]:UIColor.tertiarySystemFillColor;
        state.background.segment=segment;state.selected.segment=segment;
        if(!CGRectEqualToRect(state.background.frame,cell.bounds))state.background.frame=cell.bounds;
        if(!CGRectEqualToRect(state.selected.frame,cell.bounds))state.selected.frame=cell.bounds;
        if(cell.backgroundView!=state.background)cell.backgroundView=state.background;
        if(cell.selectedBackgroundView!=state.selected)cell.selectedBackgroundView=state.selected;
        [self clearFill:cell state:state];[self clearFill:cell.contentView state:state];
        CGFloat nativeHeight=[[self paddingForCell:cell][@"nativeHeight"] doubleValue];
        for(UIView *view in cell.contentView.subviews)
            if(view.class==UIView.class && !view.subviews.count && !view.layer.contents && !view.layer.sublayers.count && (CGRectEqualToRect(view.frame,cell.contentView.bounds) || (nativeHeight>0 && view.frame.origin.x==0 && view.frame.origin.y==0 && view.frame.size.width==cell.contentView.bounds.size.width && fabs(view.frame.size.height-nativeHeight)<0.5)))
                [self maskBackground:view state:state];
        UIView *line=cell.horizontalLine;
        if(line!=state.line){state.line=line;state.lineHidden=line.hidden;}
        if(!line.hidden)line.hidden=YES;
    } @finally {state.busy=NO;}
}
+ (void)synchronizeController:(UIViewController *)controller {
    if(!NSThread.isMainThread || ![controller isKindOfClass:NSClassFromString(@"AWEIMChatListViewController")] || !controller.isViewLoaded)return;
    [[self controllers] addObject:controller];
    UITableView *table=((AWEIMChatListViewController *)controller).tableView;
    if(![table isKindOfClass:UITableView.class])return;
    NSNumber *separator=[DKXSMessageListStateStore separatorForObject:table];
    if([self cardsEnabled] && [self adapterReady]){
        if(!separator)[DKXSMessageListStateStore setSeparator:@(table.separatorStyle) forObject:table];
        if(table.separatorStyle!=UITableViewCellSeparatorStyleNone)table.separatorStyle=UITableViewCellSeparatorStyleNone;
    } else if(separator){
        if(table.separatorStyle==UITableViewCellSeparatorStyleNone)table.separatorStyle=separator.integerValue;
        [DKXSMessageListStateStore setSeparator:nil forObject:table];
    }
    [DKXSMessageListViewport synchronizeController:controller];
    for(UITableViewCell *cell in table.visibleCells)[self synchronizeCell:cell];
}
// 顶栏颜色与玻璃分别保存；原生后续换肤仍通过专用导航栏 setter 记录原值。
+ (DKXSMessageHeaderState *)headerState:(UIView *)bar create:(BOOL)create {
    DKXSMessageHeaderState *state=objc_getAssociatedObject(bar,@selector(synchronizeBar:));
    if(!state && create){
        state=[DKXSMessageHeaderState new];state.bar=bar;state.hiddenViews=[NSMapTable weakToStrongObjectsMapTable];state.fills=[NSMapTable weakToStrongObjectsMapTable];state.nativeOpaque=bar.opaque;
        state.left=[self dkxs_glassBackgroundWithIdentifier:@"DYxs.MessageListLeftGlass"];
        state.right=[self dkxs_glassBackgroundWithIdentifier:@"DYxs.MessageListRightGlass"];
        state.actions=[self dkxs_glassBackgroundWithIdentifier:@"DYxs.NoticeActionsGlass"];
        objc_setAssociatedObject(bar,@selector(synchronizeBar:),state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);[[self bars] addObject:bar];
    }
    return state;
}
+ (void)restoreHeader:(UIView *)bar state:(DKXSMessageHeaderState *)state {
    if(!state || state.busy)return;
    state.busy=YES;
    [self restoreNoticePlate:state];
    for(UIView *view in state.hiddenViews.keyEnumerator.allObjects)if(view.hidden)view.hidden=[[state.hiddenViews objectForKey:view] boolValue];
    [NSLayoutConstraint deactivateConstraints:state.constraints];
    [state.left removeFromSuperview];[state.right removeFromSuperview];[state.actions removeFromSuperview];
    if(state.redundantTitle.hidden)state.redundantTitle.hidden=state.titleHidden;
    for(UIView *view in state.fills.keyEnumerator.allObjects)if(!view.backgroundColor || CGColorGetAlpha(view.backgroundColor.CGColor)==0){
        id saved=[state.fills objectForKey:view];view.backgroundColor=saved==NSNull.null?nil:saved;
    }
    if(!bar.opaque)bar.opaque=state.nativeOpaque;
    if(state.line.hidden)state.line.hidden=state.lineHidden;
    if(state.indicator.hidden)state.indicator.hidden=state.indicatorHidden;
    objc_setAssociatedObject(bar,@selector(synchronizeBar:),nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [[self bars] removeObject:bar];
    state.busy=NO;
}
+ (BOOL)hasTopOwner:(UIView *)bar {
    return [self owner:bar named:@"AWEIMMessageTabViewController"] || [self owner:bar named:@"AWEIMFansAndInteractMergeViewController"];
}
+ (UIColor *)nativeBackgroundColor:(UIColor *)color forBar:(UIView *)bar {
    if(!NSThread.isMainThread || ![self topEnabled] || ![self hasTopOwner:bar])return color;
    DKXSMessageHeaderState *state=[self headerState:bar create:YES];
    if(state.busy)return color;
    [state.fills setObject:color?:NSNull.null forKey:bar];
    return UIColor.clearColor;
}
+ (BOOL)nativeOpaque:(BOOL)opaque forBar:(UIView *)bar {
    if(!NSThread.isMainThread || ![self topEnabled] || ![self hasTopOwner:bar])return opaque;
    DKXSMessageHeaderState *state=[self headerState:bar create:YES];
    if(state.busy)return opaque;
    state.nativeOpaque=opaque;
    return NO;
}
+ (void)clearHeaderFill:(UIView *)view state:(DKXSMessageHeaderState *)state {
    if(!view)return;
    UIColor *color=view.backgroundColor;
    if(![state.fills objectForKey:view] || (color && CGColorGetAlpha(color.CGColor)>0))[state.fills setObject:color?:NSNull.null forKey:view];
    if(color && CGColorGetAlpha(color.CGColor)>0)view.backgroundColor=UIColor.clearColor;
}
+ (CGRect)noticeBackFrame:(UIView *)left carrier:(UIView *)carrier {
    CGRect ink=CGRectNull;NSMutableArray *pending=[NSMutableArray arrayWithObject:left];NSUInteger visited=0;
    while(pending.count && visited++<64){
        UIView *view=pending.lastObject;[pending removeLastObject];if(view.hidden || view.alpha<=0.01)continue;
        if(([view isKindOfClass:UILabel.class] || [view isKindOfClass:UIImageView.class]) && view.bounds.size.width>0 && view.bounds.size.height>0){
            CGRect frame=[view convertRect:view.bounds toView:carrier];ink=CGRectIsNull(ink)?frame:CGRectUnion(ink,frame);
        }
        if(pending.count+view.subviews.count<=64)[pending addObjectsFromArray:view.subviews];
    }
    if(CGRectIsNull(ink))ink=left.frame;
    CGFloat width=MIN(76,MAX(44,ink.size.width+16));
    return CGRectMake(MAX(8,CGRectGetMidX(ink)-width/2),(carrier.bounds.size.height-40)/2,width,40);
}
+ (UIView *)selectedNoticeItem:(UIView *)plate {
    Class cls=NSClassFromString(@"AWEIMFansAndInteractMergeViewControllerNaviBar");
    if(![DKXSChatEnhancementPolicy class:cls selector:@selector(itemViews) result:'@' arguments:@""] || ![DKXSChatEnhancementPolicy class:cls selector:@selector(currentSelectedIndex) result:'q' arguments:@""])return nil;
    AWEIMFansAndInteractMergeViewControllerNaviBar *tabs=(id)plate;NSArray *items=tabs.itemViews;long long index=tabs.currentSelectedIndex;
    if(![items isKindOfClass:NSArray.class] || index<0 || (NSUInteger)index>=items.count)return nil;
    UIView *item=items[(NSUInteger)index];return [item isKindOfClass:UIView.class] && [item isDescendantOfView:plate]?item:nil;
}
+ (void)hideHeaderView:(UIView *)view state:(DKXSMessageHeaderState *)state {
    if(!view)return;if(![state.hiddenViews objectForKey:view])[state.hiddenViews setObject:@(view.hidden) forKey:view];if(!view.hidden)view.hidden=YES;
}
+ (AWENavigationBar *)outerNoticeBarForFansBar:(UIView *)bar {
    if(![self owner:bar named:@"AWEIMFansContainerViewController"])return nil;
    UIViewController *merge=[self owner:bar named:@"AWEIMFansAndInteractMergeViewController"];
    for(UIView *view in merge.viewIfLoaded.subviews)if(view!=bar && [view isKindOfClass:NSClassFromString(@"AWENavigationBar")]){
        for(UIView *item in ((AWENavigationBar *)view).contentView.subviews)if([item isKindOfClass:NSClassFromString(@"AWEIMFansAndInteractMergeViewControllerNaviBar")])return (id)view;
    }return nil;
}
+ (UIView *)fansActionsForOuterBar:(UIView *)bar {
    UIViewController *owner=[self owner:bar named:@"AWEIMFansAndInteractMergeViewController"];
    if(![DKXSChatEnhancementPolicy class:owner.class selector:@selector(fansViewController) result:'@' arguments:@""])return nil;
    // 直接读取原生关注页。不能让互动页的深层控制器耗尽遍历预算而漏掉同级关注页。
    UIViewController *fans=((AWEIMFansAndInteractMergeViewController *)owner).fansViewController;
    if(![fans isKindOfClass:NSClassFromString(@"AWEIMFansContainerViewController")] || !fans.isViewLoaded)return nil;
    for(UIView *view in fans.viewIfLoaded.subviews)if([view isKindOfClass:NSClassFromString(@"AWENavigationBar")]){
        UIView *actions=((AWENavigationBar *)view).rightBtnsContainerView;
        if(actions.window==bar.window && !actions.hidden && actions.bounds.size.width>0 && actions.bounds.size.width<=120)return actions;
    }return nil;
}
+ (void)synchronizeFansBar:(AWENavigationBar *)bar outer:(AWENavigationBar *)outer {
    DKXSMessageHeaderState *state=[self headerState:bar create:NO];if(state.busy)return;
    UIView *carrier=bar.contentView,*actions=bar.rightBtnsContainerView;
    if(![self topEnabled] || !outer.window || !bar.window || actions.superview!=carrier || actions.bounds.size.width<=0 || actions.bounds.size.width>120){[self restoreHeader:bar state:state];return;}
    state=[self headerState:bar create:YES];state.busy=YES;state.auxiliary=YES;state.notice=YES;
    @try {
        [self clearHeaderFill:bar state:state];[self clearHeaderFill:carrier state:state];[self clearHeaderFill:actions state:state];if(bar.opaque)bar.opaque=NO;
        // 关注子页另有 titleView/默认 titleLabel 和返回。只保留外层双标签与返回。
        for(UIView *view in carrier.subviews)if([view isKindOfClass:UILabel.class] || [view isKindOfClass:NSClassFromString(@"AWEIMNavigationUnreadView")])[self hideHeaderView:view state:state];
        UIView *title=bar.titleView;if([title isKindOfClass:UILabel.class] && title!=carrier && [title isDescendantOfView:carrier])[self hideHeaderView:title state:state];
        [self hideHeaderView:bar.bottomLineView state:state];
        CGRect rect=[actions convertRect:actions.bounds toView:carrier];rect.origin.y=(carrier.bounds.size.height-40)/2;rect.size.height=40;
        [self dkxs_placeGlassBackground:state.actions frame:rect inView:carrier];
        state.rightAnchor=actions;
    } @finally {state.busy=NO;}
    [self synchronizeBar:outer];[self scheduleBarSynchronization:outer];
}
+ (void)restoreNoticePlate:(DKXSMessageHeaderState *)state {
    if(state.plateApplied && CGAffineTransformEqualToTransform(state.plate.transform,state.plateAppliedTransform))state.plate.transform=state.plateNativeTransform;
    if(objc_getAssociatedObject(state.plate,@selector(beginNoticePlateFrame:))==state)objc_setAssociatedObject(state.plate,@selector(beginNoticePlateFrame:),nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    state.plateApplied=NO;state.plate=nil;state.noticeActions=nil;
}
+ (id)beginNoticePlateFrame:(UIView *)plate {
    if(!NSThread.isMainThread)return nil;DKXSMessageHeaderState *state=objc_getAssociatedObject(plate,@selector(beginNoticePlateFrame:));if(!state || state.busy)return nil;
    state.busy=YES;if(state.plateApplied && CGAffineTransformEqualToTransform(plate.transform,state.plateAppliedTransform))plate.transform=state.plateNativeTransform;state.plateApplied=NO;return state;
}
+ (void)endNoticePlateFrame:(id)token {
    if(![token isKindOfClass:DKXSMessageHeaderState.class])return;DKXSMessageHeaderState *state=token;state.busy=NO;
    if([self headerState:state.bar create:NO]==state)[self synchronizeBar:state.bar];
}
+ (CGFloat)noticeTitleLeft:(UIView *)plate carrier:(UIView *)carrier {
    NSArray *items=((AWEIMFansAndInteractMergeViewControllerNaviBar *)plate).itemViews;UIView *first=items.firstObject;
    if(![first isKindOfClass:UIView.class])return NAN;
    NSMutableArray *pending=[NSMutableArray arrayWithObject:first];NSUInteger visited=0;CGFloat left=CGFLOAT_MAX;
    while(pending.count && visited++<48){UIView *view=pending.lastObject;[pending removeLastObject];if(view.hidden || view.alpha<=0.01)continue;
        if([view isKindOfClass:UILabel.class] && view.bounds.size.width>20)left=MIN(left,CGRectGetMinX([view convertRect:view.bounds toView:carrier]));
        if(pending.count+view.subviews.count<=48)[pending addObjectsFromArray:view.subviews];
    }return left==CGFLOAT_MAX?NAN:left;
}
+ (void)positionNoticePlate:(UIView *)plate carrier:(UIView *)carrier leftRect:(CGRect)leftRect state:(DKXSMessageHeaderState *)state {
    if(state.plate!=plate){[self restoreNoticePlate:state];state.plate=plate;state.plateNativeTransform=plate.transform;}
    else if(!state.plateApplied || !CGAffineTransformEqualToTransform(plate.transform,state.plateAppliedTransform))state.plateNativeTransform=plate.transform;
    AWEIMFansAndInteractMergeViewControllerNaviBar *tabs=(id)plate;
    UIView *actions=tabs.currentSelectedIndex==1?[self fansActionsForOuterBar:state.bar]:nil;
    CGFloat oldShift=state.plateApplied?state.plateAppliedTransform.tx-state.plateNativeTransform.tx:0;
    UIView *selected=[self selectedNoticeItem:plate];CGRect selectedRect=[selected convertRect:selected.bounds toView:carrier];
    CGFloat actionsLeft=carrier.bounds.size.width;
    if(actions){
        // 同宽原生子导航栏的最终栏位不随分页转场的中间 contentOffset 摆动。
        BOOL sameCarrier=fabs(actions.superview.bounds.size.width-carrier.bounds.size.width)<0.5 && CGAffineTransformIsIdentity(actions.transform);
        actionsLeft=sameCarrier?CGRectGetMinX(actions.frame):CGRectGetMinX([actions convertRect:actions.bounds toView:carrier]);
    }
    NSDictionary *plan=[DKXSMessageListMetrics noticeHeaderShiftForBackRight:CGRectGetMaxX(leftRect) titleLeft:[self noticeTitleLeft:plate carrier:carrier]-oldShift selectedCenter:CGRectGetMidX(selectedRect)-oldShift glassWidth:116 actionsLeft:actionsLeft width:carrier.bounds.size.width];
    CGFloat shift=actions?[plan[@"translationX"] doubleValue]:0;
    CGAffineTransform applied=state.plateNativeTransform;applied.tx+=shift;
    state.plateAppliedTransform=applied;state.plateApplied=YES;state.noticeActions=actions;
    objc_setAssociatedObject(plate,@selector(beginNoticePlateFrame:),state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [UIView performWithoutAnimation:^{if(!CGAffineTransformEqualToTransform(plate.transform,applied))plate.transform=applied;}];
}
+ (NSUInteger)actualHiddenHeaderViews:(DKXSMessageHeaderState *)state {
    NSUInteger count=0;for(UIView *view in state.hiddenViews.keyEnumerator.allObjects)if(view.hidden)count++;return count;
}
+ (BOOL)passThroughNoticeActions:(CGPoint)point bar:(UIView *)bar {
    if(!NSThread.isMainThread)return NO;DKXSMessageHeaderState *state=[self headerState:bar create:NO];UIView *actions=state.noticeActions;
    return state.notice && !state.auxiliary && actions.window==bar.window && actions.window && !actions.hidden && actions.userInteractionEnabled && CGRectContainsPoint(actions.bounds,[bar convertPoint:point toView:actions]);
}
+ (void)synchronizeBar:(UIView *)candidate {
    if(!NSThread.isMainThread || ![candidate isKindOfClass:NSClassFromString(@"AWENavigationBar")])return;
    AWENavigationBar *bar=(id)candidate;
    DKXSMessageHeaderState *state=[self headerState:bar create:NO];
    if(state.busy)return;
    if(![self topEnabled] || ![self hasTopOwner:bar] || !bar.window){[self restoreHeader:bar state:state];return;}
    AWENavigationBar *outer=[self outerNoticeBarForFansBar:bar];
    if(outer){[self synchronizeFansBar:bar outer:outer];return;}
    BOOL notice=[self owner:bar named:@"AWEIMFansAndInteractMergeViewController"]!=nil;
    UIView *carrier=bar.contentView,*left=nil,*right=notice?nil:bar.rightBtnsContainerView;
    if(!carrier || carrier.bounds.size.height<32 || carrier.bounds.size.height>64){[self restoreHeader:bar state:state];return;}
    for(UIView *view in carrier.subviews){
        if([view isKindOfClass:NSClassFromString(notice?@"AWEIMNavigationUnreadView":@"AWEIMMessageTabExpandedHitContainerView")])left=view;
        if(notice && [view isKindOfClass:NSClassFromString(@"AWEIMFansAndInteractMergeViewControllerNaviBar")])right=view;
    }
    NSUInteger buttons=0;
    for(UIView *child in right.subviews)if([child isKindOfClass:UIControl.class]&&!child.hidden)buttons++;
    if(!left || right.superview!=carrier || (!notice && buttons<2) || left.hidden || right.hidden || left.alpha<=0.01 || right.alpha<=0.01){[self restoreHeader:bar state:state];return;}
    state=[self headerState:bar create:YES];state.busy=YES;
    @try {
        [self clearHeaderFill:bar state:state];[self clearHeaderFill:carrier state:state];
        [self clearHeaderFill:left state:state];[self clearHeaderFill:right state:state];
        if(bar.opaque)bar.opaque=NO;
        UIView *line=bar.bottomLineView;
        if(line!=state.line){state.line=line;state.lineHidden=line.hidden;}
        if(!line.hidden)line.hidden=YES;
        // 玻璃的约束依赖原生按钮容器的实际边界；不会把布局中途的零宽当作最终尺寸。
        // 背景留在外层，不进入原生按钮数组/子视图，避免参与原生按钮宽度测量。
        CGFloat height=MIN(44,carrier.bounds.size.height);
        CGRect leftRect=notice?[self noticeBackFrame:left carrier:carrier]:CGRectMake(left.frame.origin.x,(carrier.bounds.size.height-height)/2,height,height);
        if(notice)[self positionNoticePlate:right carrier:carrier leftRect:leftRect state:state];
        UIView *selected=notice?[self selectedNoticeItem:right]:nil;UIView *rightAnchor=selected?:right;
        CGRect rightRect=CGRectMake(right.frame.origin.x,(carrier.bounds.size.height-height)/2,right.bounds.size.width,height);
        if(selected){CGRect item=[selected convertRect:selected.bounds toView:carrier];CGFloat width=MIN(116,MAX(0,item.size.width-16));rightRect=CGRectMake(CGRectGetMidX(item)-width/2,(carrier.bounds.size.height-36)/2,width,36);}
        BOOL rebind=state.notice!=notice || state.leftAnchor!=left || state.rightAnchor!=rightAnchor || state.left.superview!=carrier || state.right.superview!=carrier || !CGSizeEqualToSize(state.leftRect.size,leftRect.size) || (notice && !CGRectEqualToRect(state.leftRect,leftRect));
        if(rebind)[NSLayoutConstraint deactivateConstraints:state.constraints];
        [UIView performWithoutAnimation:^{
            [self dkxs_placeGlassBackground:state.left frame:leftRect inView:carrier];
            [self dkxs_placeGlassBackground:state.right frame:rightRect inView:carrier];
            state.left.alpha=notice?0.82:1;state.right.alpha=notice?0.72:1;
            state.left.layer.borderColor=[UIColor colorWithWhite:1 alpha:(notice?0.12:0.18)].CGColor;
            state.right.layer.borderColor=[UIColor colorWithWhite:1 alpha:(notice?0.10:0.18)].CGColor;
        }];
        if(!selected && state.indicator){if(state.indicator.hidden)state.indicator.hidden=state.indicatorHidden;state.indicator=nil;}
        if(selected && [right respondsToSelector:@selector(indicatorView)]){
            UIView *indicator=((AWEIMFansAndInteractMergeViewControllerNaviBar *)right).indicatorView;
            if(![indicator isKindOfClass:UIView.class])indicator=nil;
            if(indicator!=state.indicator){if(state.indicator.hidden)state.indicator.hidden=state.indicatorHidden;state.indicator=indicator;state.indicatorHidden=indicator.hidden;}
            if(!indicator.hidden)indicator.hidden=YES;
        }
        if(notice){
            // 自定义双标签已承载标题；原生导航栏在关注页另写的默认标题必须让位。
            UILabel *title=bar.titleLabel;
            if(![title isKindOfClass:UILabel.class] || ![title isDescendantOfView:carrier] || [title isDescendantOfView:right])title=nil;
            if(title!=state.redundantTitle){if(state.redundantTitle.hidden)state.redundantTitle.hidden=state.titleHidden;state.redundantTitle=title;state.titleHidden=title.hidden;}
            if(title && !title.hidden)title.hidden=YES;
            // 装饰层按原生完成后的坐标放置，不能用约束牵动嵌套原生标签布局。
            [NSLayoutConstraint deactivateConstraints:state.constraints];state.constraints=nil;
            state.left.translatesAutoresizingMaskIntoConstraints=YES;state.right.translatesAutoresizingMaskIntoConstraints=YES;
            UIView *actions=bar.rightBtnsContainerView;
            if(actions!=right && actions.superview==carrier && !actions.hidden && actions.bounds.size.width>0 && actions.bounds.size.width<=120 && actions.frame.origin.x>carrier.bounds.size.width/2){
                CGRect rect=[actions convertRect:actions.bounds toView:carrier];rect.origin.y=(carrier.bounds.size.height-40)/2;rect.size.height=40;
                [self dkxs_placeGlassBackground:state.actions frame:rect inView:carrier];
            }else [state.actions removeFromSuperview];
            state.leftAnchor=left;state.rightAnchor=rightAnchor;state.notice=YES;state.leftRect=leftRect;
        }else if(rebind){
            state.left.translatesAutoresizingMaskIntoConstraints=NO;state.right.translatesAutoresizingMaskIntoConstraints=NO;
            NSMutableArray *constraints=[NSMutableArray arrayWithArray:@[
                [state.left.leadingAnchor constraintEqualToAnchor:left.leadingAnchor],
                [state.left.centerYAnchor constraintEqualToAnchor:carrier.centerYAnchor],
                [state.left.widthAnchor constraintEqualToConstant:leftRect.size.width],
                [state.left.heightAnchor constraintEqualToConstant:leftRect.size.height],
                [state.right.centerYAnchor constraintEqualToAnchor:carrier.centerYAnchor],
                [state.right.heightAnchor constraintEqualToConstant:rightRect.size.height]]];
            [constraints addObjectsFromArray:@[[state.right.leadingAnchor constraintEqualToAnchor:right.leadingAnchor],[state.right.trailingAnchor constraintEqualToAnchor:right.trailingAnchor]]];
            state.constraints=constraints;[NSLayoutConstraint activateConstraints:constraints];
            state.leftAnchor=left;state.rightAnchor=rightAnchor;state.notice=notice;state.leftRect=leftRect;
        }
    } @finally {state.busy=NO;}
}
+ (void)synchronizeHeaderForView:(UIView *)view {
    if(!NSThread.isMainThread)return;
    for(NSUInteger i=0;view && i<8;i++,view=view.superview)if([view isKindOfClass:NSClassFromString(@"AWENavigationBar")]){[self synchronizeBar:view];[self scheduleBarSynchronization:view];break;}
}
+ (void)scheduleBarSynchronization:(UIView *)bar {
    if(!NSThread.isMainThread)return;
    DKXSMessageHeaderState *state=[self headerState:bar create:NO];
    if(!state || state.pending || state.busy || !bar.window)return;
    state.pending=YES;
    __weak UIView *weakBar=bar;
    dispatch_async(dispatch_get_main_queue(),^{
        UIView *strongBar=weakBar;
        if(!strongBar || [self headerState:strongBar create:NO]!=state)return;
        state.pending=NO;
        [self synchronizeBar:strongBar];
        [DKXSMessageListViewport refresh];
    });
}
+ (void)refresh {
    if(!NSThread.isMainThread)return;
    if(![self cardsEnabled]){
        for(UIView *view in [self lightViews].allObjects)[self resetLightInteraction:view];
        for(UIView *view in [self contentViews].allObjects)[self resetContentView:view];
        for(UITableViewCell *cell in [self cells].allObjects)[self resetCell:cell];
    }
    for(UIViewController *controller in [self controllers].allObjects){
        UITableView *table=((AWEIMChatListViewController *)controller).tableView;
        if([self rowPlans:table create:NO] && !table.hasUncommittedUpdates && !table.dragging && !table.decelerating)[table reloadData];
        [self synchronizeController:controller];
    }
    for(UIView *bar in [self bars].allObjects)[self synchronizeBar:bar];
    [DKXSInteractionNoticeStyle refresh];
    [DKXSRefreshIndicatorStyle refresh];
    [DKXSMessageListViewport refresh];
}
+ (NSDictionary *)diagnostics {
    if(!NSThread.isMainThread)return @{};
    NSMutableDictionary *groups=[NSMutableDictionary dictionary];
    NSMutableDictionary *decisions=[NSMutableDictionary dictionary];
    NSUInteger insets=0,backgroundMasks=0;
    for(UITableViewCell *cell in [self cells].allObjects)if(cell.window){
        DKXSMessageCardState *s=objc_getAssociatedObject(cell,@selector(synchronizeCell:));
        if(s.kind)groups[s.kind]=@([groups[s.kind] unsignedIntegerValue]+1);
        for(UIView *view in s.masks.keyEnumerator.allObjects){NSDictionary *mask=[s.masks objectForKey:view];if([mask[@"background"] boolValue] && view.layer.mask==mask[@"applied"])backgroundMasks++;}
    }
    NSMutableArray *content=[NSMutableArray array];
    for(UIView *view in [self contentViews].allObjects)if(view.window){
        DKXSMessageContentState *state=[self contentState:view];if(!state)continue;
        BOOL matches=state.applied && !state.updates.depth && CGAffineTransformEqualToTransform(view.transform,state.appliedTransform);
        if(matches)insets++;
        NSString *decision=matches?@"container_matches":state.decision?:@"matrix_changed";
        if(state.applied && !matches)decision=@"matrix_changed";
        decisions[decision]=@([decisions[decision] unsignedIntegerValue]+1);
        if(content.count>=3)continue;
        NSMutableDictionary *sample=[@{@"scaleX":@(hypot(view.transform.a,view.transform.b)),@"visualFrame":[self valuesForFrame:[view convertRect:view.bounds toView:state.cell]],@"matrixMatches":@(matches),@"updateDepth":@(state.updates.depth),@"paddingTop":@(state.topPadding),@"paddingBottom":@(state.bottomPadding)} mutableCopy];
        for(UIView *child in view.subviews){
            if([child isKindOfClass:NSClassFromString(@"IESIMAsyncDrawableView")] && !sample[@"textFrame"] && !child.hidden)
                sample[@"textFrame"]=[self valuesForFrame:[child convertRect:child.bounds toView:state.cell]];
            if(child.subviews.count>8)continue;
            for(UIView *leaf in child.subviews)if([leaf isKindOfClass:NSClassFromString(@"AWEIMChatCellAvatarView")])
                sample[@"avatarFrame"]=[self valuesForFrame:[leaf convertRect:leaf.bounds toView:state.cell]];
        }
        CALayer *presentation=view.layer.presentationLayer;
        if(presentation){CGAffineTransform transform=presentation.affineTransform;sample[@"presentationScaleX"]=@(hypot(transform.a,transform.b));}
        [content addObject:sample];
    }
    NSMutableArray *headers=[NSMutableArray array];
    for(UIView *bar in [self bars].allObjects)if(bar.window && headers.count<4){
        DKXSMessageHeaderState *s=[self headerState:bar create:NO];
        [headers addObject:@{@"transparent":@(!bar.backgroundColor || CGColorGetAlpha(bar.backgroundColor.CGColor)==0),@"leftGlassWidth":@(s.left.bounds.size.width),@"rightGlassWidth":@(s.auxiliary?s.actions.bounds.size.width:s.right.bounds.size.width),@"rightMounted":@(s.auxiliary?s.actions.superview!=nil:s.right.superview!=nil),@"auxiliaryFansBar":@(s.auxiliary),@"hiddenNativeHeaderViews":@([self actualHiddenHeaderViews:s]),@"tabTranslationX":@(s.plateApplied && CGAffineTransformEqualToTransform(s.plate.transform,s.plateAppliedTransform)?s.plateAppliedTransform.tx-s.plateNativeTransform.tx:0),@"selectedTabOnly":@(s.notice)}];
    }
    return @{@"viewport":[DKXSMessageListViewport diagnostics],@"cardsEnabled":@([self cardsEnabled]),@"topEnabled":@([self topEnabled]),@"adapterReady":@([self adapterReady]),@"visibleRowsByGroup":groups,@"insetRows":@(insets),@"contentScale":@0.92,@"contentDecisions":decisions,@"contentContainers":content,@"contentAdapterReady":@([self contentAdapterReady]),@"backgroundMasks":@(backgroundMasks),@"compactLightInteractionViews":@([self lightViews].allObjects.count),@"headers":headers,@"nativeRowGeometry":@YES,@"unreadMutation":@NO};
}
@end
