// 移植自 Si-yi/DYads- 3819b4c（DYYYArticleChrome.m）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配：上游 DYYYChatChrome 的 glassBackgroundWithIdentifier:/placeGlassBackground:frame:inView:
// DYxs 不移植，改为本文件内同名语义的本地实现（PR #33 DKXSMessageListStyle.m 同款做法）。
#import "DKXSArticleChrome.h"
#import "DKXSArticleChromeMetrics.h"
#import "DKXSContentBarAdapter.h"
#import "DKXSChatEnhancementPolicy.h"
#import "DKXSUtils.h"
#import <objc/runtime.h>
#import <math.h>
#import "DKXSContentComments.h"
#import "DKXSContentMetadata.h"
#import "DKXSContentTopDrawingState.h"

static char kDKXSArticleChromeKey;
static char kDKXSArticleChromeMaterialKey;
static char kDKXSRichTopSurfaceKey;
@interface DKXSRichTopSurface : NSObject
@property (nonatomic, strong) id nativeColor;
@property (nonatomic, assign) BOOL writing;
@property (nonatomic, assign) BOOL suspended;
@end
@implementation DKXSRichTopSurface
@end

@interface DKXSArticleChromeState : NSObject
@property (nonatomic, assign) BOOL active;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, assign) BOOL rich;
@property (nonatomic, assign) NSInteger layoutFlags;
@property (nonatomic, weak) UIView *topBar;
@property (nonatomic, weak) UIView *bottomBar;
@property (nonatomic, weak) UIView *bottomActions;
@property (nonatomic, weak) UIScrollView *viewport;
@property (nonatomic, strong) NSMapTable<UIView *, NSMutableDictionary *> *topChanges;
@property (nonatomic, strong) DKXSContentTopDrawingState *moves;
@property (nonatomic, strong) NSMapTable<UIButton *, NSDictionary *> *followColors;
@property (nonatomic, strong) NSMapTable<UIView *, NSMutableDictionary *> *bottomChanges;
@property (nonatomic, strong) NSMapTable<UIView *, NSMutableDictionary *> *viewportChanges;
@property (nonatomic, strong) UIVisualEffectView *backGlass;
@property (nonatomic, strong) UIVisualEffectView *topActionsGlass;
@property (nonatomic, strong) UIVisualEffectView *centerGlass;
@property (nonatomic, strong) UIVisualEffectView *inputGlass;
@property (nonatomic, strong) UIVisualEffectView *bottomActionsGlass;
@end
@implementation DKXSArticleChromeState
@end

@implementation DKXSArticleChrome

// 顶栏/底栏玻璃本地实现（抄上游 DYYYChatChrome 的 glass:/placeGlass: 做法；DYxs 不移植 ChatChrome）。
+ (UIVisualEffectView *)dkxs_glassBackgroundWithIdentifier:(NSString *)identifier {
    UIVisualEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
    if (@available(iOS 26.0, *)) {
        UIGlassEffect *material = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular]; material.interactive = NO; effect = material;
    }
#endif
    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:effect];
    objc_setAssociatedObject(glass, &kDKXSArticleChromeMaterialKey, effect, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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
    if (!glass.effect) glass.effect = objc_getAssociatedObject(glass, &kDKXSArticleChromeMaterialKey);
    if (glass.hidden) glass.hidden = NO;
    if (glass.alpha != 1) glass.alpha = 1;
    if (!CGRectEqualToRect(glass.frame, frame)) glass.frame = frame;
    CGFloat radius = CGRectGetHeight(frame) / 2;
    if (glass.layer.cornerRadius != radius) glass.layer.cornerRadius = radius;
    if (glass.overrideUserInterfaceStyle != style) glass.overrideUserInterfaceStyle = style;
    if (glass.superview != carrier) [carrier insertSubview:glass atIndex:0];
}

+ (void)preparePreferences {
    // 两项均默认关闭，跟随第 8 批“全部默认关”的移植惯例（上游无显式默认值，同样关）。
    [NSUserDefaults.standardUserDefaults registerDefaults:@{@"DKXSEnableArticleTopGlass":@NO,@"DKXSEnableArticleBottomGlass":@NO}];
}

+ (NSHashTable<UIViewController *> *)hosts {
    static NSHashTable *hosts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ hosts = [NSHashTable weakObjectsHashTable]; });
    return hosts;
}
+ (BOOL)isArticle:(UIViewController *)controller {
    Class cls = NSClassFromString(@"AWESearchArticleContainerViewController");
    return (cls && [controller isKindOfClass:cls]) || [DKXSContentBarAdapter isRichHost:controller];
}
+ (id)object:(id)object getter:(NSString *)name {
    SEL getter = NSSelectorFromString(name);
    if (!object || ![DKXSChatEnhancementPolicy class:[object class] selector:getter result:'@' arguments:@""]) return nil;
    @try { return [object valueForKey:name]; } @catch (__unused NSException *exception) { return nil; }
}
+ (UIView *)view:(NSString *)name in:(UIView *)root {
    id value = [self object:root getter:name];
    return [value isKindOfClass:UIView.class] && [value isDescendantOfView:root] ? value : nil;
}
+ (NSDictionary *)frame:(UIView *)view in:(UIView *)root {
    if (!view || !root || ![DKXSContentBarAdapter isVisible:view in:root]) return @{};
    CGRect rect = [view convertRect:view.bounds toView:root];
    return @{ @"x":@(rect.origin.x), @"y":@(rect.origin.y), @"width":@(rect.size.width), @"height":@(rect.size.height) };
}
+ (CGRect)rect:(NSDictionary *)frame {
    return CGRectMake([frame[@"x"] doubleValue], [frame[@"y"] doubleValue],
        [frame[@"width"] doubleValue], [frame[@"height"] doubleValue]);
}
+ (void)write:(id)value key:(NSString *)key view:(UIView *)view changes:(NSMapTable *)changes {
    if (!view || !value) return;
    @try {
        id current = [view valueForKeyPath:key] ?: NSNull.null;
        if ([current isEqual:value]) return;
        NSMutableDictionary *record = [changes objectForKey:view];
        if (!record) { record = [NSMutableDictionary dictionary]; [changes setObject:record forKey:view]; }
        NSDictionary *previous = record[key];
        id original = previous && [current isEqual:previous[@"applied"]] ? previous[@"original"] : current;
        record[key] = @{ @"original":original, @"applied":value };
        DKXSRichTopSurface *surface = objc_getAssociatedObject(view, &kDKXSRichTopSurfaceKey);
        surface.writing = YES;
        @try { [view setValue:value == NSNull.null ? nil : value forKeyPath:key]; }
        @finally { surface.writing = NO; }
    } @catch (__unused NSException *exception) {}
}
+ (void)clear:(UIView *)view changes:(NSMapTable *)changes {
    [self write:UIColor.clearColor key:@"backgroundColor" view:view changes:changes];
    [self write:@NO key:@"opaque" view:view changes:changes];
}
+ (void)restoreChanges:(NSMapTable *)changes {
    for (UIView *view in changes.keyEnumerator.allObjects) {
        NSDictionary *record = [changes objectForKey:view];
        for (NSString *key in record) {
            @try {
                id current = [view valueForKeyPath:key] ?: NSNull.null;
                NSDictionary *change = record[key];
                if ([current isEqual:change[@"applied"]]) {
                    id original = change[@"original"];
                    DKXSRichTopSurface *surface = objc_getAssociatedObject(view, &kDKXSRichTopSurfaceKey);
                    surface.writing = YES;
                    @try { [view setValue:original == NSNull.null ? nil : original forKeyPath:key]; }
                    @finally { surface.writing = NO; }
                }
            } @catch (__unused NSException *exception) {}
        }
    }
    [changes removeAllObjects];
}
+ (DKXSRichTopSurface *)surface:(UIView *)bar {
    DKXSRichTopSurface *surface = objc_getAssociatedObject(bar, &kDKXSRichTopSurfaceKey);
    if (!surface) { surface = [DKXSRichTopSurface new]; objc_setAssociatedObject(bar, &kDKXSRichTopSurfaceKey, surface, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    return surface;
}
+ (UIColor *)backgroundForRichBar:(UIView *)bar native:(UIColor *)color {
    if (!NSThread.isMainThread) return color;
    DKXSRichTopSurface *surface = [self surface:bar];
    if (surface.writing) return color;
    if (surface.suspended || ![NSUserDefaults.standardUserDefaults boolForKey:@"DKXSEnableArticleTopGlass"]) {
        surface.nativeColor = color ?: NSNull.null; return color;
    }
    // 原生初始化/主题赋色发生在首帧前；保存请求值但不短暂显示实底。
    surface.nativeColor = color ?: NSNull.null;
    return UIColor.clearColor;
}
+ (void)resumeSurface:(UIView *)bar {
    if (![bar isKindOfClass:NSClassFromString(@"AWEKnowledgeRichContentImpl.FullPageFeedTopBarView")]) return;
    DKXSRichTopSurface *surface = [self surface:bar]; surface.suspended = NO;
    if (!surface.nativeColor) surface.nativeColor = bar.backgroundColor ?: NSNull.null;
}
+ (void)restoreSurface:(UIView *)bar {
    DKXSRichTopSurface *surface = objc_getAssociatedObject(bar, &kDKXSRichTopSurfaceKey);
    if (!surface.nativeColor) return;
    surface.writing = YES;
    @try { bar.backgroundColor = surface.nativeColor == NSNull.null ? nil : surface.nativeColor; }
    @finally { surface.writing = NO; }
}
+ (void)restoreMoves:(DKXSArticleChromeState *)state { [state.moves restore]; }
+ (CGAffineTransform)nativeTransform:(UIView *)view state:(DKXSArticleChromeState *)state {
    return [state.moves nativeTransform:view.layer];
}
+ (CGRect)nativeRect:(UIView *)view in:(UIView *)container state:(DKXSArticleChromeState *)state {
    if (![DKXSContentBarAdapter isVisible:view in:container]) return CGRectZero;
    CGRect centered = CGRectOffset(view.bounds, -CGRectGetMidX(view.bounds), -CGRectGetMidY(view.bounds));
    CGRect rect = CGRectApplyAffineTransform(centered, [self nativeTransform:view state:state]);
    rect.origin.x += view.center.x; rect.origin.y += view.center.y;
    return [view.superview convertRect:rect toView:container];
}
+ (NSDictionary *)topFrame:(UIView *)view in:(UIView *)container state:(DKXSArticleChromeState *)state ink:(BOOL)ink {
    CGRect rect = [self nativeRect:view in:container state:state];
    if (CGRectIsEmpty(rect)) return @{};
    if (ink && [view isKindOfClass:UILabel.class]) {
        UILabel *label = (id)view; CGFloat width = MIN(rect.size.width, ceil([label sizeThatFits:label.bounds.size].width));
        if (label.textAlignment == NSTextAlignmentCenter) rect.origin.x += (rect.size.width - width) / 2;
        else if (label.textAlignment == NSTextAlignmentRight) rect.origin.x += rect.size.width - width;
        rect.size.width = width;
    }
    return @{ @"x":@(rect.origin.x), @"y":@(rect.origin.y), @"width":@(rect.size.width), @"height":@(rect.size.height) };
}
+ (void)move:(UIView *)view shift:(CGFloat)shift scale:(CGFloat)scale state:(DKXSArticleChromeState *)state {
    if (view) [state.moves applyShift:shift scale:scale toLayer:view.layer];
}
+ (void)whiteFollow:(UIView *)view state:(DKXSArticleChromeState *)state {
    if (![view isKindOfClass:UIButton.class]) return;
    UIButton *button = (id)view;
    id color = [button titleColorForState:UIControlStateNormal] ?: NSNull.null;
    NSDictionary *record = [state.followColors objectForKey:button];
    if (![color isEqual:UIColor.whiteColor]) {
        id original = record && [color isEqual:record[@"applied"]] ? record[@"original"] : color;
        [state.followColors setObject:@{ @"original":original, @"applied":UIColor.whiteColor } forKey:button];
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    }
}
+ (void)restoreFollowColors:(DKXSArticleChromeState *)state {
    for (UIButton *button in state.followColors.keyEnumerator.allObjects) {
        NSDictionary *record = [state.followColors objectForKey:button];
        if ([[button titleColorForState:UIControlStateNormal] isEqual:record[@"applied"]])
            [button setTitleColor:record[@"original"] == NSNull.null ? nil : record[@"original"] forState:UIControlStateNormal];
    }
    [state.followColors removeAllObjects];
}
+ (void)dropTop:(DKXSArticleChromeState *)state {
    [state.backGlass removeFromSuperview]; [state.topActionsGlass removeFromSuperview]; [state.centerGlass removeFromSuperview];
    [self restoreMoves:state];
    [self restoreFollowColors:state];
    [self restoreChanges:state.topChanges];
    [self restoreSurface:state.topBar];
}
+ (void)dropBottom:(DKXSArticleChromeState *)state {
    [state.moves restoreLayer:state.bottomActions.layer]; state.bottomActions = nil;
    [state.inputGlass removeFromSuperview]; [state.bottomActionsGlass removeFromSuperview];
    [self restoreChanges:state.bottomChanges];
    if (!state.rich) { [self restoreChanges:state.viewportChanges]; state.viewport = nil; }
}
// 原生Swift栏没有可用的ObjC角色getter，适配器只识别已导出的现成子视图。
+ (NSDictionary *)rolesForTop:(UIView *)bar {
    NSDictionary *rich = [DKXSContentBarAdapter topRoles:bar];
    if (rich.count) return rich;
    NSMutableDictionary *roles = [NSMutableDictionary dictionary];
    NSDictionary *keys = @{ @"container":@"containerView", @"back":@"backImageView", @"avatar":@"avatarImageView",
        @"name":@"nameLabel", @"follow":@"followButton", @"search":@"searchImageView" };
    for (NSString *key in keys) { UIView *view = [self view:keys[key] in:bar]; if (view) roles[key] = view; }
    return roles;
}
+ (void)hideSeparators:(UIView *)bar changes:(NSMapTable *)changes {
    // 两份实际导出均为直属、全宽、至多1pt的分隔线；不向文字、头像和内容内部搜索。
    for (UIView *view in bar.subviews)
        if (CGRectGetHeight(view.bounds) > 0 && CGRectGetHeight(view.bounds) <= 1 &&
            CGRectGetWidth(view.bounds) >= CGRectGetWidth(bar.bounds) - 1)
            [self write:@YES key:@"hidden" view:view changes:changes];
}
+ (void)applyTop:(UIView *)bar state:(DKXSArticleChromeState *)state {
    NSDictionary *roles = [self rolesForTop:bar];
    UIView *container = roles[@"container"];
    if (!container) {
        [state.backGlass removeFromSuperview]; [state.topActionsGlass removeFromSuperview]; [state.centerGlass removeFromSuperview];
        [self restoreMoves:state];
        [self clear:bar changes:state.topChanges]; [self hideSeparators:bar changes:state.topChanges]; return;
    }
    NSDictionary *layout = [DKXSArticleChromeMetrics topForWidth:CGRectGetWidth(container.bounds) height:CGRectGetHeight(container.bounds)
        back:[self topFrame:roles[@"back"] in:container state:state ink:NO] avatar:[self topFrame:roles[@"avatar"] in:container state:state ink:NO]
        name:[self topFrame:roles[@"name"] in:container state:state ink:YES]
        follow:[self topFrame:roles[@"follow"] in:container state:state ink:NO] search:[self topFrame:roles[@"search"] in:container state:state ink:NO]];
    if (!layout.count) {
        [state.backGlass removeFromSuperview]; [state.topActionsGlass removeFromSuperview]; [state.centerGlass removeFromSuperview];
        [self restoreMoves:state];
        // 未完成原生几何时只清实底，不把首帧恢复成原版。
        [self clear:bar changes:state.topChanges]; [self clear:container changes:state.topChanges];
        [self hideSeparators:bar changes:state.topChanges]; return;
    }
    CGFloat shift = [layout[@"authorShift"] doubleValue];
    [self move:roles[@"avatar"] shift:shift scale:1 state:state];
    [self move:roles[@"name"] shift:shift scale:1 state:state];
    [self move:roles[@"back"] shift:0 scale:1.10 state:state];
    [self move:roles[@"search"] shift:[layout[@"searchShift"] doubleValue] scale:1 state:state];
    [self move:roles[@"follow"] shift:[layout[@"followShift"] doubleValue] scale:1 state:state];
    [self whiteFollow:roles[@"follow"] state:state];
    [self write:@0 key:@"layer.borderWidth" view:roles[@"follow"] changes:state.topChanges];
    if (!state.backGlass) state.backGlass = [self dkxs_glassBackgroundWithIdentifier:@"DYxs.Article.BackGlass"];
    if (!state.topActionsGlass) state.topActionsGlass = [self dkxs_glassBackgroundWithIdentifier:@"DYxs.Article.TopActionsGlass"];
    [self clear:bar changes:state.topChanges];
    [self clear:container changes:state.topChanges];
    [self clear:[self view:@"animatedBackground" in:bar] changes:state.topChanges];
    [self write:@YES key:@"hidden" view:[self view:@"separatorLineView" in:bar] changes:state.topChanges];
    [self write:@YES key:@"hidden" view:[self view:@"gradientView" in:bar] changes:state.topChanges];
    [self hideSeparators:bar changes:state.topChanges];
    UIView *center = roles[@"center"];
    CGRect centerRect = center ? [center convertRect:center.bounds toView:container] : CGRectZero;
    centerRect = CGRectInset(centerRect, -6, 0);
    if (center && ![DKXSContentBarAdapter isVisible:roles[@"avatar"] in:bar] &&
        ![DKXSContentBarAdapter isVisible:roles[@"name"] in:bar] &&
        !CGRectIntersectsRect(centerRect, [self rect:layout[@"back"]]) &&
        !CGRectIntersectsRect(centerRect, [self rect:layout[@"actions"]])) {
        if (!state.centerGlass) state.centerGlass = [self dkxs_glassBackgroundWithIdentifier:@"DYxs.Content.CenterGlass"];
        [self dkxs_placeGlassBackground:state.centerGlass frame:[container convertRect:centerRect toView:bar] inView:bar];
    } else [state.centerGlass removeFromSuperview];
    [self dkxs_placeGlassBackground:state.backGlass frame:[container convertRect:[self rect:layout[@"back"]] toView:bar] inView:bar];
    [self dkxs_placeGlassBackground:state.topActionsGlass frame:[container convertRect:[self rect:layout[@"actions"]] toView:bar] inView:bar];
}
+ (BOOL)applyBottom:(UIView *)bar state:(DKXSArticleChromeState *)state {
    NSDictionary *roles = [DKXSContentBarAdapter bottomRoles:bar];
    UIView *container = roles[@"container"] ?: [self view:@"containerView" in:bar];
    UIView *input = roles[@"input"] ?: [self view:@"inputView" in:bar];
    UIView *actions = roles[@"actions"] ?: [self view:@"itemStackView" in:bar];
    if (!container || !input || !actions) { [self dropBottom:state]; return NO; }
    NSDictionary *layout = [DKXSArticleChromeMetrics bottomForWidth:CGRectGetWidth(bar.bounds) height:CGRectGetHeight(bar.bounds)
        input:[self topFrame:input in:bar state:state ink:NO] actions:[self topFrame:actions in:bar state:state ink:NO]];
    if (!layout.count) { [self dropBottom:state]; return NO; }
    if (state.bottomActions != actions) [state.moves restoreLayer:state.bottomActions.layer];
    state.bottomActions = actions;
    [self move:actions shift:0 scale:0.92 state:state];
    if (!state.inputGlass) state.inputGlass = [self dkxs_glassBackgroundWithIdentifier:@"DYxs.Article.CommentInputGlass"];
    if (!state.bottomActionsGlass) state.bottomActionsGlass = [self dkxs_glassBackgroundWithIdentifier:@"DYxs.Article.BottomActionsGlass"];
    for (UIView *view in @[ bar, container ?: bar, input ?: bar, actions ?: bar ]) [self clear:view changes:state.bottomChanges];
    [self write:@YES key:@"hidden" view:[self view:@"separatorLine" in:bar] changes:state.bottomChanges];
    [self hideSeparators:bar changes:state.bottomChanges];
    [self dkxs_placeGlassBackground:state.inputGlass frame:[self rect:layout[@"input"]] inView:bar];
    [self dkxs_placeGlassBackground:state.bottomActionsGlass frame:[self rect:layout[@"actions"]] inView:bar];
    return YES;
}
+ (void)revealBottomForHost:(UIViewController *)controller bar:(UIView *)bar state:(DKXSArticleChromeState *)state {
    if ([DKXSContentBarAdapter isRichHost:controller]) {
        UIScrollView *viewport = [DKXSContentBarAdapter viewportInHost:controller];
        // CA9C05EE外层本来已到屏幕底部；仅放开顶端裁切，不改滚动几何和内层评论裁切。
        if (viewport && CGRectGetWidth(viewport.bounds) == CGRectGetWidth(controller.view.bounds)) {
            if (state.viewport != viewport) [self restoreChanges:state.viewportChanges];
            state.viewport = viewport;
            [self write:@NO key:@"clipsToBounds" view:viewport changes:state.viewportChanges];
        }
        return;
    }
    id tabs = [self object:controller getter:@"tabListVC"];
    id viewport = [self object:tabs getter:@"containerScrollView"];
    UIView *root = controller.viewIfLoaded;
    if (![tabs isKindOfClass:UIViewController.class] || ![viewport isKindOfClass:UIScrollView.class] ||
        ![[tabs viewIfLoaded] isDescendantOfView:root] || ![viewport isDescendantOfView:[tabs viewIfLoaded]] ||
        ![DKXSArticleChromeMetrics canRevealViewport:[self frame:viewport in:root] bottom:[self frame:bar in:root]
            rootWidth:CGRectGetWidth(root.bounds) rootHeight:CGRectGetHeight(root.bounds)]) {
        [self restoreChanges:state.viewportChanges]; state.viewport = nil; return;
    }
    state.viewport = viewport;
    // 保留原生873pt视口与滚动边界，只让正文绘制透过外层裁切。评论列表的内层裁切保留。
    [self write:@NO key:@"clipsToBounds" view:viewport changes:state.viewportChanges];
    [self write:@NO key:@"clipsToBounds" view:[tabs viewIfLoaded] changes:state.viewportChanges];
}
+ (void)beginAppearance:(UIViewController *)controller {
    if (!NSThread.isMainThread || ![self isArticle:controller]) return;
    DKXSArticleChromeState *state = objc_getAssociatedObject(controller, &kDKXSArticleChromeKey);
    if (!state) {
        state = [DKXSArticleChromeState new];
        state.topChanges = [NSMapTable weakToStrongObjectsMapTable];
        state.moves = [DKXSContentTopDrawingState new];
        state.followColors = [NSMapTable weakToStrongObjectsMapTable];
        state.bottomChanges = [NSMapTable weakToStrongObjectsMapTable];
        state.viewportChanges = [NSMapTable weakToStrongObjectsMapTable];
        objc_setAssociatedObject(controller, &kDKXSArticleChromeKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    state.rich = [DKXSContentBarAdapter isRichHost:controller];
    if (!state.active) state.layoutFlags = -1;
    state.active = YES;
    [self resumeSurface:[DKXSContentBarAdapter topBarInHost:controller]];
    [[self hosts] addObject:controller];
    [UIView performWithoutAnimation:^{ [self synchronize:controller]; }];
}
+ (void)synchronize:(UIViewController *)controller {
    if (!NSThread.isMainThread || ![self isArticle:controller] || !controller.isViewLoaded) return;
    DKXSArticleChromeState *state = objc_getAssociatedObject(controller, &kDKXSArticleChromeKey);
    if (!state.active || state.busy) return;
    state.busy = YES;
    @try {
        BOOL rich = [DKXSContentBarAdapter isRichHost:controller];
        UIView *top = rich ? [DKXSContentBarAdapter topBarInHost:controller] : [self object:controller getter:@"topBar"];
        UIView *bottom = rich ? [DKXSContentBarAdapter bottomBarInHost:controller] : [self object:controller getter:@"bottomBar"];
        if (state.topBar != top) { [self dropTop:state]; state.topBar = top; [self resumeSurface:top]; }
        if (state.bottomBar != bottom) { [self dropBottom:state]; state.bottomBar = bottom; }
        BOOL topEnabled = [NSUserDefaults.standardUserDefaults boolForKey:@"DKXSEnableArticleTopGlass"];
        BOOL bottomEnabled = [NSUserDefaults.standardUserDefaults boolForKey:@"DKXSEnableArticleBottomGlass"];
        NSInteger flags = (topEnabled ? 1 : 0) | (bottomEnabled ? 2 : 0);
        if (rich && CGRectGetWidth(controller.view.bounds) >= 280 && CGRectGetHeight(controller.view.bounds) > CGRectGetWidth(controller.view.bounds) && state.layoutFlags != flags) {
            BOOL relayout = state.layoutFlags > 0 || flags > 0;
            state.layoutFlags = flags;
            if (relayout && [DKXSChatEnhancementPolicy class:controller.class selector:@selector(layoutTabListSubviews) result:'v' arguments:@""])
                [(DKXSRichContentHost *)controller layoutTabListSubviews];
        }
        BOOL validTop = rich ? top != nil : [top isKindOfClass:NSClassFromString(@"AWESearchArticleDetailTopBarView")] && [top isDescendantOfView:controller.view];
        BOOL validBottom = rich ? bottom != nil : [bottom isKindOfClass:NSClassFromString(@"AWESearchArticleDetailBottomInteractionView")] && [bottom isDescendantOfView:controller.view];
        if (topEnabled && validTop) [self applyTop:top state:state]; else [self dropTop:state];
        if (bottomEnabled && validBottom && [self applyBottom:bottom state:state]) [self revealBottomForHost:controller bar:bottom state:state];
        else [self dropBottom:state];
        if (rich) {
            if ((topEnabled && validTop) || (bottomEnabled && validBottom)) [self revealBottomForHost:controller bar:bottom state:state];
            else { [self restoreChanges:state.viewportChanges]; state.viewport = nil; }
        }
    } @finally { state.busy = NO; }
    [DKXSContentComments synchronize:controller];
    [DKXSContentMetadata synchronizeInHost:controller];
}
+ (UIViewController *)hostForOrigin:(id)origin {
    if ([self isArticle:origin]) return origin;
    if (![origin isKindOfClass:UIView.class]) return nil;
    UIResponder *responder = [origin nextResponder];
    for (NSUInteger depth = 0; responder && depth < 12; depth++, responder = responder.nextResponder) {
        if ([responder isKindOfClass:UIViewController.class] && [self isArticle:(id)responder]) return (id)responder;
    }
    return nil;
}
+ (void)synchronizeForBar:(UIView *)bar {
    if (NSThread.isMainThread) [UIView performWithoutAnimation:^{ [self synchronize:[self hostForOrigin:bar]]; }];
}
+ (id)beginGeometryUpdate:(id)origin {
    if (!NSThread.isMainThread) return nil;
    UIViewController *host = [self hostForOrigin:origin];
    DKXSArticleChromeState *state = objc_getAssociatedObject(host, &kDKXSArticleChromeKey);
    if (!state.active || state.busy) return nil;
    state.busy = YES; [self restoreMoves:state]; return host;
}
+ (id)beginNativeUpdate:(id)origin {
    if (!NSThread.isMainThread) return nil;
    UIViewController *host = [self hostForOrigin:origin];
    DKXSArticleChromeState *state = objc_getAssociatedObject(host, &kDKXSArticleChromeKey);
    if (!state.active || state.busy) return nil;
    state.busy = YES; [self restoreMoves:state]; [self restoreFollowColors:state];
    // 先还原接管值，再让原生重算主题，避免把自有clear当作下一次原生底色。
    [self restoreChanges:state.topChanges]; [self restoreChanges:state.bottomChanges];
    return host;
}
+ (void)endNativeUpdate:(id)token {
    if (!NSThread.isMainThread || !token) return;
    DKXSArticleChromeState *state = objc_getAssociatedObject(token, &kDKXSArticleChromeKey);
    state.busy = NO;
    if (state && !state.active) { [self restore:token]; return; }
    [UIView performWithoutAnimation:^{ [self synchronize:token]; }];
}
+ (void)restore:(UIViewController *)controller {
    if (!NSThread.isMainThread) return;
    DKXSArticleChromeState *state = objc_getAssociatedObject(controller, &kDKXSArticleChromeKey);
    if (!state) return;
    if (state.busy) { state.active = NO; return; }
    state.active = NO; state.busy = YES;
    DKXSRichTopSurface *surface = objc_getAssociatedObject(state.topBar, &kDKXSRichTopSurfaceKey); surface.suspended = YES;
    [DKXSContentComments restore:controller];
    [self dropTop:state]; [self dropBottom:state];
    [self restoreChanges:state.viewportChanges];
    objc_setAssociatedObject(controller, &kDKXSArticleChromeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [[self hosts] removeObject:controller];
}
+ (double)topAreaForHost:(UIViewController *)host native:(double)native {
    if (!NSThread.isMainThread || ![DKXSContentBarAdapter isRichHost:host] || !isfinite(native) || native < 0 || native > 180 ||
        ![NSUserDefaults.standardUserDefaults boolForKey:@"DKXSEnableArticleTopGlass"]) return native;
    // 首次查询可能发生在viewDidLoad之前，不能先给122再给0，也不能为读尺寸触发loadView。
    UIView *root = host.viewIfLoaded;
    if (root && CGRectGetWidth(root.bounds) > 0 && CGRectGetHeight(root.bounds) > 0 &&
        (CGRectGetWidth(root.bounds) < 280 || CGRectGetHeight(root.bounds) <= CGRectGetWidth(root.bounds))) return native;
    return 0;
}
+ (void)refresh {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self refresh]; }); return; }
    for (UIViewController *host in [self hosts].allObjects) [UIView performWithoutAnimation:^{ [self synchronize:host]; }];
}
+ (NSDictionary *)diagnostics {
    if (!NSThread.isMainThread) return @{};
    NSMutableArray *items = [NSMutableArray array];
    for (UIViewController *host in [self hosts].allObjects) {
        DKXSArticleChromeState *state = objc_getAssociatedObject(host, &kDKXSArticleChromeKey);
        if (!state) continue;
        [items addObject:@{ @"active":@(state.active), @"hostClass":NSStringFromClass(host.class),
            @"nativeTopAreaAvailable":@([DKXSChatEnhancementPolicy class:host.class selector:@selector(topSafeAreaForTabList) result:'d' arguments:@""]),
            @"topMounted":@(state.backGlass.superview == state.topBar && state.topBar != nil),
            @"bottomMounted":@(state.inputGlass.superview == state.bottomBar && state.bottomBar != nil),
            @"backGlass":state.backGlass ? NSStringFromCGRect(state.backGlass.frame) : @"",
            @"topActionsGlass":state.topActionsGlass ? NSStringFromCGRect(state.topActionsGlass.frame) : @"",
            @"inputGlass":state.inputGlass ? NSStringFromCGRect(state.inputGlass.frame) : @"",
            @"bottomActionsGlass":state.bottomActionsGlass ? NSStringFromCGRect(state.bottomActionsGlass.frame) : @"",
            @"viewportFrame":state.viewport ? NSStringFromCGRect(state.viewport.frame) : @"",
            @"viewportUnclipped":@(state.viewport && !state.viewport.clipsToBounds) }];
    }
    return @{ @"topEnabled":@([NSUserDefaults.standardUserDefaults boolForKey:@"DKXSEnableArticleTopGlass"]),
              @"bottomEnabled":@([NSUserDefaults.standardUserDefaults boolForKey:@"DKXSEnableArticleBottomGlass"]), @"hosts":items };
}
@end
