// 移植自 Si-yi/DYads- f07ddb5（DYYYMessageListStyle.m）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
#import "DKXSMessageListStyle.h"
#import "DKXSMessageListCardView.h"
#import "DKXSMessageListMetrics.h"
#import "DKXSChatEnhancementPolicy.h"
#import "DKXSUtils.h"
#import "DKXSAwemeHeaders.h"
#import <objc/runtime.h>

@interface DKXSMessageCardState : NSObject
@property (nonatomic, strong) UIView *nativeBackground;
@property (nonatomic, strong) UIView *nativeSelected;
@property (nonatomic, strong) DKXSMessageListCardView *background;
@property (nonatomic, strong) DKXSMessageListCardView *selected;
@property (nonatomic, strong) NSMapTable<UIView *, id> *fills;
@property (nonatomic, strong) NSMapTable<UIView *, NSDictionary *> *masks;
@property (nonatomic, strong) NSMapTable<UIView *, NSDictionary *> *translations;
@property (nonatomic, weak) UIView *line;
@property (nonatomic) BOOL lineHidden;
@property (nonatomic) BOOL busy;
@property (nonatomic, copy) NSString *kind;
@end
@implementation DKXSMessageCardState @end

@interface DKXSMessageHeaderState : NSObject
@property (nonatomic, strong) UIVisualEffectView *left;
@property (nonatomic, strong) UIVisualEffectView *right;
@property (nonatomic, strong) NSMapTable<UIView *, id> *fills;
@property (nonatomic, weak) UIView *line;
@property (nonatomic, weak) UIView *leftAnchor;
@property (nonatomic, weak) UIView *rightAnchor;
@property (nonatomic, copy) NSArray<NSLayoutConstraint *> *constraints;
@property (nonatomic) BOOL lineHidden;
@property (nonatomic) BOOL nativeOpaque;
@property (nonatomic) BOOL pending;
@property (nonatomic) BOOL busy;
@end
@implementation DKXSMessageHeaderState @end

// 最小接口声明：DKXSAwemeHeaders（39.5 导出）里的 AWEIMChatListViewController 是空接口、
// AWEIMChatListCommonCell 只有 renderWithHolder:；上游 DYads- 的 AwemeHeaders.h 则声明了
// tableView/chatList 与 AWEIMChatCellViewModel.chat。本文件直接调用的方法在此补充（不用 DouyinHeaders）。
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
        [DKXSChatEnhancementPolicy class:cell selector:@selector(avatarContainer) result:'@' arguments:@""] &&
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
+ (void)restoreInsets:(DKXSMessageCardState *)state {
    for(UIView *view in state.translations.keyEnumerator.allObjects){
        NSDictionary *saved=[state.translations objectForKey:view];
        if(CGAffineTransformEqualToTransform(view.transform,[saved[@"applied"] CGAffineTransformValue]))view.transform=[saved[@"native"] CGAffineTransformValue];
    }
    [state.translations removeAllObjects];
    for(UIView *view in state.masks.keyEnumerator.allObjects){
        NSDictionary *saved=[state.masks objectForKey:view];
        if([saved[@"background"] boolValue])continue;
        if(view.layer.mask==saved[@"applied"])view.layer.mask=saved[@"native"]==NSNull.null?nil:saved[@"native"];
        [state.masks removeObjectForKey:view];
    }
}
+ (void)maskView:(UIView *)view visibleWidth:(CGFloat)width background:(BOOL)background state:(DKXSMessageCardState *)state {
    NSDictionary *saved=[state.masks objectForKey:view];
    if(saved && view.layer.mask!=saved[@"applied"]){[state.masks removeObjectForKey:view];saved=nil;}
    CALayer *mask=saved[@"applied"];
    if(!mask){
        if(view.layer.mask)return;
        // 原生满行底板可能在异步渲染后重写颜色。仅遮住已核对的空背景视图，不钩全局 setter。
        mask=[CALayer layer];mask.backgroundColor=background?UIColor.clearColor.CGColor:UIColor.blackColor.CGColor;
        [state.masks setObject:@{@"native":NSNull.null,@"applied":mask,@"background":@(background)} forKey:view];
        [CATransaction begin];[CATransaction setDisableActions:YES];view.layer.mask=mask;[CATransaction commit];
    }
    CGRect rect=background?view.bounds:CGRectMake(0,0,width,view.bounds.size.height);
    if(!CGRectEqualToRect(mask.frame,rect)){[CATransaction begin];[CATransaction setDisableActions:YES];mask.frame=rect;[CATransaction commit];}
}
+ (void)prepareCellLayout:(UITableViewCell *)cell {
    if(!NSThread.isMainThread)return;
    DKXSMessageCardState *state=objc_getAssociatedObject(cell,@selector(synchronizeCell:));
    if(!state || state.busy)return;
    state.busy=YES;
    [self restoreInsets:state];
    [self restoreMasks:state];
    state.busy=NO;
}
+ (void)insetContent:(AWEIMChatListCommonCell *)cell state:(DKXSMessageCardState *)state {
    // 39.5 异步平铺布局：只平移已确认的原生组件，保留头像比例、正文绘制、按钮和原生命中。
    UIView *avatar=[cell respondsToSelector:@selector(avatarContainer)]?cell.avatarContainer:nil;
    if(avatar.superview!=cell.contentView){[self restoreInsets:state];return;}
    NSMutableArray *components=[NSMutableArray array];
    for(UIView *view in cell.contentView.subviews){
        if(view==state.line || view.hidden)continue;
        if(view.class==UIView.class && !view.subviews.count && !view.layer.contents && CGRectEqualToRect(view.frame,cell.contentView.bounds))continue;
        BOOL supported=view==avatar || [view isKindOfClass:NSClassFromString(@"IESIMAsyncDrawableView")] ||
            [view isKindOfClass:NSClassFromString(@"AWEIMConsecutiveChatDaysWrapper")] ||
            [view isKindOfClass:NSClassFromString(@"AWEIMChatCellRecommendChatLIView")] || view.class==UIImageView.class;
        NSDictionary *old=[state.translations objectForKey:view];
        BOOL owns=old && CGAffineTransformEqualToTransform(view.transform,[old[@"applied"] CGAffineTransformValue]);
        CGAffineTransform native=owns?[old[@"native"] CGAffineTransformValue]:view.transform;
        if(!supported || !CGAffineTransformIsIdentity(native)){[self restoreInsets:state];return;}
        [components addObject:view];
    }
    NSMutableArray *placements=[NSMutableArray array];
    for(UIView *view in components){
        NSDictionary *old=[state.translations objectForKey:view];
        if(old && !CGAffineTransformEqualToTransform(view.transform,[old[@"applied"] CGAffineTransformValue])){[state.translations removeObjectForKey:view];old=nil;}
        // UIView 的 center/bounds 不随 transform 平移；由这两者取得原生矩形，不能再次扣 tx。
        CGRect rect=CGRectMake(view.center.x-view.bounds.size.width/2,view.center.y-view.bounds.size.height/2,view.bounds.size.width,view.bounds.size.height);
        BOOL trailing=view!=avatar && ![view isKindOfClass:NSClassFromString(@"AWEIMConsecutiveChatDaysWrapper")] && rect.origin.x>=cell.bounds.size.width*0.6;
        CGFloat rightLimit=cell.bounds.size.width-16;
        if(!trailing)for(UIView *other in components){
            if(other==view || other==avatar || [other isKindOfClass:NSClassFromString(@"AWEIMConsecutiveChatDaysWrapper")])continue;
            CGRect tail=CGRectMake(other.center.x-other.bounds.size.width/2,other.center.y-other.bounds.size.height/2,other.bounds.size.width,other.bounds.size.height);
            if(tail.origin.x<cell.bounds.size.width*0.6 || CGRectGetMaxY(tail)<=CGRectGetMinY(rect) || CGRectGetMinY(tail)>=CGRectGetMaxY(rect))continue;
            CGFloat gap=MAX(0,MIN(12,tail.origin.x-CGRectGetMaxX(rect)));
            rightLimit=MIN(rightLimit,tail.origin.x-gap);
        }
        NSDictionary *plan=[DKXSMessageListMetrics contentPlacementForX:rect.origin.x width:rect.size.width rowWidth:cell.bounds.size.width trailing:trailing nativeRightLimit:rightLimit];
        if(!plan.count || (!trailing && [plan[@"visibleWidth"] doubleValue]<rect.size.width && ![view isKindOfClass:NSClassFromString(@"IESIMAsyncDrawableView")])){[self restoreInsets:state];return;}
        [placements addObject:@{@"view":view,@"plan":plan}];
    }
    for(NSDictionary *placement in placements){
        UIView *view=placement[@"view"];NSDictionary *plan=placement[@"plan"];
        NSDictionary *old=[state.translations objectForKey:view];
        CGAffineTransform native=old?[old[@"native"] CGAffineTransformValue]:view.transform;
        CGAffineTransform applied=CGAffineTransformTranslate(native,[plan[@"translation"] doubleValue],0);
        if(!CGAffineTransformEqualToTransform(view.transform,applied))view.transform=applied;
        [state.translations setObject:@{@"native":[NSValue valueWithCGAffineTransform:native],@"applied":[NSValue valueWithCGAffineTransform:applied]} forKey:view];
        if([plan[@"visibleWidth"] doubleValue]<view.bounds.size.width && [view isKindOfClass:NSClassFromString(@"IESIMAsyncDrawableView")])
            [self maskView:view visibleWidth:[plan[@"visibleWidth"] doubleValue] background:NO state:state];
    }
}
+ (void)resetCell:(UITableViewCell *)cell {
    if(!NSThread.isMainThread)return;
    DKXSMessageCardState *state=objc_getAssociatedObject(cell,@selector(synchronizeCell:));
    if(!state || state.busy)return;
    [self prepareCellLayout:cell];
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
+ (void)synchronizeCell:(UITableViewCell *)base {
    if(!NSThread.isMainThread || ![base isKindOfClass:NSClassFromString(@"AWEIMChatListCommonCell")])return;
    AWEIMChatListCommonCell *cell=(id)base;
    DKXSMessageCardState *state=objc_getAssociatedObject(cell,@selector(synchronizeCell:));
    if(state.busy)return;
    AWEIMChatListViewController *owner=(id)[self owner:cell named:@"AWEIMChatListViewController"];
    if(![self cardsEnabled] || !owner || !cell.window || ![self adapterReady]){[self resetCell:cell];return;}
    UITableView *table=owner.tableView;
    NSIndexPath *index=[table indexPathForCell:cell];
    NSArray *chats=owner.chatList;
    if(![table isKindOfClass:UITableView.class] || ![chats isKindOfClass:NSArray.class] || !index || index.row>=chats.count ||
        [table numberOfRowsInSection:index.section]!=chats.count || table.hasUncommittedUpdates)return;
    AWEIMChatModel *chat=cell.cellViewModel.chat;
    if(chats[index.row]!=chat){[self resetCell:cell];return;}
    NSString *kind=[self kindForChat:chat],*previous=index.row?[self kindForChat:chats[index.row-1]]:nil;
    NSString *next=index.row+1<chats.count?[self kindForChat:chats[index.row+1]]:nil;
    NSDictionary *segment=[DKXSMessageListMetrics segmentForKind:kind previous:previous next:next width:cell.bounds.size.width height:cell.bounds.size.height];
    if(!segment.count){[self resetCell:cell];return;}
    if(!state){
        state=[DKXSMessageCardState new];state.nativeBackground=cell.backgroundView;state.nativeSelected=cell.selectedBackgroundView;
        state.fills=[NSMapTable weakToStrongObjectsMapTable];state.masks=[NSMapTable weakToStrongObjectsMapTable];state.translations=[NSMapTable weakToStrongObjectsMapTable];state.background=[[DKXSMessageListCardView alloc] initWithFrame:cell.bounds];state.selected=[[DKXSMessageListCardView alloc] initWithFrame:cell.bounds];
        state.background.accessibilityIdentifier=@"DYxs.MessageGroupBackground";state.selected.accessibilityIdentifier=@"DYxs.MessageGroupSelection";
        objc_setAssociatedObject(cell,@selector(synchronizeCell:),state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);[[self cells] addObject:cell];
    }
    state.busy=YES;
    @try {
        state.kind=kind;
        BOOL dark=[DKXSUtils isDarkMode] || cell.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;
        state.background.fillColor=dark?[UIColor colorWithWhite:0.14 alpha:1]:UIColor.secondarySystemGroupedBackgroundColor;
        state.selected.fillColor=dark?[UIColor colorWithWhite:0.21 alpha:1]:UIColor.tertiarySystemFillColor;
        state.background.segment=segment;state.selected.segment=segment;
        if(!CGRectEqualToRect(state.background.frame,cell.bounds))state.background.frame=cell.bounds;
        if(!CGRectEqualToRect(state.selected.frame,cell.bounds))state.selected.frame=cell.bounds;
        if(cell.backgroundView!=state.background)cell.backgroundView=state.background;
        if(cell.selectedBackgroundView!=state.selected)cell.selectedBackgroundView=state.selected;
        [self clearFill:cell state:state];[self clearFill:cell.contentView state:state];
        for(UIView *view in cell.contentView.subviews)
            if(view.class==UIView.class && !view.subviews.count && !view.layer.contents && !view.layer.sublayers.count && CGRectEqualToRect(view.frame,cell.contentView.bounds))
                [self maskView:view visibleWidth:0 background:YES state:state];
        UIView *line=cell.horizontalLine;
        if(line!=state.line){state.line=line;state.lineHidden=line.hidden;}
        if(!line.hidden)line.hidden=YES;
        [self insetContent:cell state:state];
    } @finally {state.busy=NO;}
}
+ (void)synchronizeController:(UIViewController *)controller {
    if(!NSThread.isMainThread || ![controller isKindOfClass:NSClassFromString(@"AWEIMChatListViewController")] || !controller.isViewLoaded)return;
    [[self controllers] addObject:controller];
    UITableView *table=((AWEIMChatListViewController *)controller).tableView;
    if(![table isKindOfClass:UITableView.class])return;
    NSNumber *separator=objc_getAssociatedObject(table,@selector(synchronizeController:));
    if([self cardsEnabled] && [self adapterReady]){
        if(!separator)objc_setAssociatedObject(table,@selector(synchronizeController:),@(table.separatorStyle),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if(table.separatorStyle!=UITableViewCellSeparatorStyleNone)table.separatorStyle=UITableViewCellSeparatorStyleNone;
    } else if(separator){
        if(table.separatorStyle==UITableViewCellSeparatorStyleNone)table.separatorStyle=separator.integerValue;
        objc_setAssociatedObject(table,@selector(synchronizeController:),nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for(UITableViewCell *cell in table.visibleCells)[self synchronizeCell:cell];
}
// 顶栏颜色与玻璃分别保存；原生后续换肤仍通过专用导航栏 setter 记录原值。
+ (DKXSMessageHeaderState *)headerState:(UIView *)bar create:(BOOL)create {
    DKXSMessageHeaderState *state=objc_getAssociatedObject(bar,@selector(synchronizeBar:));
    if(!state && create){
        state=[DKXSMessageHeaderState new];state.fills=[NSMapTable weakToStrongObjectsMapTable];state.nativeOpaque=bar.opaque;
        state.left=[self dkxs_glassBackgroundWithIdentifier:@"DYxs.MessageListLeftGlass"];
        state.right=[self dkxs_glassBackgroundWithIdentifier:@"DYxs.MessageListRightGlass"];
        objc_setAssociatedObject(bar,@selector(synchronizeBar:),state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);[[self bars] addObject:bar];
    }
    return state;
}
+ (void)restoreHeader:(UIView *)bar state:(DKXSMessageHeaderState *)state {
    if(!state || state.busy)return;
    state.busy=YES;
    [NSLayoutConstraint deactivateConstraints:state.constraints];
    [state.left removeFromSuperview];[state.right removeFromSuperview];
    for(UIView *view in state.fills.keyEnumerator.allObjects)if(!view.backgroundColor || CGColorGetAlpha(view.backgroundColor.CGColor)==0){
        id saved=[state.fills objectForKey:view];view.backgroundColor=saved==NSNull.null?nil:saved;
    }
    if(!bar.opaque)bar.opaque=state.nativeOpaque;
    if(state.line.hidden)state.line.hidden=state.lineHidden;
    objc_setAssociatedObject(bar,@selector(synchronizeBar:),nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [[self bars] removeObject:bar];
    state.busy=NO;
}
+ (UIColor *)nativeBackgroundColor:(UIColor *)color forBar:(UIView *)bar {
    if(!NSThread.isMainThread || ![self topEnabled] || ![self owner:bar named:@"AWEIMMessageTabViewController"])return color;
    DKXSMessageHeaderState *state=[self headerState:bar create:YES];
    if(state.busy)return color;
    [state.fills setObject:color?:NSNull.null forKey:bar];
    return UIColor.clearColor;
}
+ (BOOL)nativeOpaque:(BOOL)opaque forBar:(UIView *)bar {
    if(!NSThread.isMainThread || ![self topEnabled] || ![self owner:bar named:@"AWEIMMessageTabViewController"])return opaque;
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
+ (void)synchronizeBar:(UIView *)candidate {
    if(!NSThread.isMainThread || ![candidate isKindOfClass:NSClassFromString(@"AWENavigationBar")])return;
    AWENavigationBar *bar=(id)candidate;
    DKXSMessageHeaderState *state=[self headerState:bar create:NO];
    if(state.busy)return;
    if(![self topEnabled] || ![self owner:bar named:@"AWEIMMessageTabViewController"] || !bar.window){[self restoreHeader:bar state:state];return;}
    UIView *carrier=bar.contentView,*left=nil,*right=bar.rightBtnsContainerView;
    if(!carrier || carrier.bounds.size.height<32 || carrier.bounds.size.height>64){[self restoreHeader:bar state:state];return;}
    for(UIView *view in carrier.subviews)
        if([view isKindOfClass:NSClassFromString(@"AWEIMMessageTabExpandedHitContainerView")])left=view;
    NSUInteger buttons=0;
    for(UIView *child in right.subviews)if([child isKindOfClass:UIControl.class]&&!child.hidden)buttons++;
    if(!left || right.superview!=carrier || buttons<2 || left.hidden || right.hidden || left.alpha<=0.01 || right.alpha<=0.01){[self restoreHeader:bar state:state];return;}
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
        CGRect leftRect=CGRectMake(left.frame.origin.x,(carrier.bounds.size.height-height)/2,height,height);
        CGRect rightRect=CGRectMake(right.frame.origin.x,(carrier.bounds.size.height-height)/2,right.bounds.size.width,height);
        BOOL rebind=state.leftAnchor!=left || state.rightAnchor!=right || state.left.superview!=carrier || state.right.superview!=carrier;
        if(rebind)[NSLayoutConstraint deactivateConstraints:state.constraints];
        [self dkxs_placeGlassBackground:state.left frame:leftRect inView:carrier];
        [self dkxs_placeGlassBackground:state.right frame:rightRect inView:carrier];
        if(rebind){
            state.left.translatesAutoresizingMaskIntoConstraints=NO;state.right.translatesAutoresizingMaskIntoConstraints=NO;
            state.constraints=@[
                [state.left.leadingAnchor constraintEqualToAnchor:left.leadingAnchor],
                [state.left.centerYAnchor constraintEqualToAnchor:carrier.centerYAnchor],
                [state.left.widthAnchor constraintEqualToConstant:44],
                [state.left.heightAnchor constraintEqualToConstant:44],
                [state.right.leadingAnchor constraintEqualToAnchor:right.leadingAnchor],
                [state.right.trailingAnchor constraintEqualToAnchor:right.trailingAnchor],
                [state.right.centerYAnchor constraintEqualToAnchor:carrier.centerYAnchor],
                [state.right.heightAnchor constraintEqualToConstant:44]];
            [NSLayoutConstraint activateConstraints:state.constraints];state.leftAnchor=left;state.rightAnchor=right;
        }
    } @finally {state.busy=NO;}
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
    });
}
+ (void)refresh {
    if(!NSThread.isMainThread)return;
    if(![self cardsEnabled])for(UITableViewCell *cell in [self cells].allObjects)[self resetCell:cell];
    for(UIViewController *controller in [self controllers].allObjects)[self synchronizeController:controller];
    for(UIView *bar in [self bars].allObjects)[self synchronizeBar:bar];
}
+ (NSDictionary *)diagnostics {
    if(!NSThread.isMainThread)return @{};
    NSMutableDictionary *groups=[NSMutableDictionary dictionary];
    NSUInteger insets=0,backgroundMasks=0;
    for(UITableViewCell *cell in [self cells].allObjects)if(cell.window){
        DKXSMessageCardState *s=objc_getAssociatedObject(cell,@selector(synchronizeCell:));
        if(s.kind)groups[s.kind]=@([groups[s.kind] unsignedIntegerValue]+1);
        if(s.translations.count)insets++;
        for(UIView *view in s.masks.keyEnumerator.allObjects){NSDictionary *mask=[s.masks objectForKey:view];if([mask[@"background"] boolValue] && view.layer.mask==mask[@"applied"])backgroundMasks++;}
    }
    NSMutableArray *headers=[NSMutableArray array];
    for(UIView *bar in [self bars].allObjects)if(bar.window && headers.count<4){
        DKXSMessageHeaderState *s=[self headerState:bar create:NO];
        [headers addObject:@{@"transparent":@(!bar.backgroundColor || CGColorGetAlpha(bar.backgroundColor.CGColor)==0),@"leftGlassWidth":@(s.left.bounds.size.width),@"rightGlassWidth":@(s.right.bounds.size.width),@"rightMounted":@(s.right.superview!=nil)}];
    }
    return @{@"cardsEnabled":@([self cardsEnabled]),@"topEnabled":@([self topEnabled]),@"adapterReady":@([self adapterReady]),@"visibleRowsByGroup":groups,@"insetRows":@(insets),@"backgroundMasks":@(backgroundMasks),@"headers":headers,@"nativeRowGeometry":@YES,@"unreadMutation":@NO};
}
@end
