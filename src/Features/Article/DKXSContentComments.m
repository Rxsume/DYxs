// 移植自 Si-yi/DYads- 3819b4c（DYYYContentComments.m）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
#import "DKXSContentComments.h"
#import "DKXSContentBarAdapter.h"
#import "DKXSCommentBlurCoordinator.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

static char kDKXSContentCommentsKey;
@interface DKXSContentCommentsState : NSObject
@property (nonatomic, assign) BOOL active;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, weak) UICollectionView *collection;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) NSMapTable<UIView *, NSMutableDictionary *> *changes;
@end
@implementation DKXSContentCommentsState
@end

@implementation DKXSContentComments

+ (CGFloat)commentBlurTransparency {
    // 与 DKXSCommentBlurCoordinator 同款取值：DKXSCommentBlurTransparent 为 0-1 小数，越界缺省 0.9。
    CGFloat transparency = [[[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSCommentBlurTransparent"] floatValue];
    return (transparency > 0 && transparency <= 1) ? transparency : 0.9;
}
+ (NSHashTable *)hosts {
    static NSHashTable *hosts; static dispatch_once_t once;
    dispatch_once(&once, ^{ hosts = [NSHashTable weakObjectsHashTable]; }); return hosts;
}
+ (UICollectionView *)collectionInHost:(UIViewController *)host {
    UIScrollView *outer = [DKXSContentBarAdapter viewportInHost:host];
    // F020EC6B：分页外壳 -> 评论控制器root -> UICollectionView，不进入媒体播放器树。
    for (UIView *pager in outer.subviews) {
        if (![pager isKindOfClass:NSClassFromString(@"AWETabListTabContainerScrollView")]) continue;
        for (UIView *root in pager.subviews) for (UIView *view in root.subviews)
            if ([view isKindOfClass:UICollectionView.class] && CGRectGetWidth(view.bounds) >= 280 &&
                [DKXSContentBarAdapter isVisible:view in:outer]) return (id)view;
    }
    return nil;
}
+ (void)write:(id)value key:(NSString *)key view:(UIView *)view state:(DKXSContentCommentsState *)state {
    if (!view) return;
    id current = [view valueForKey:key] ?: NSNull.null;
    if ([current isEqual:value]) return;
    NSMutableDictionary *record = [state.changes objectForKey:view];
    if (!record) { record = [NSMutableDictionary dictionary]; [state.changes setObject:record forKey:view]; }
    NSDictionary *previous = record[key];
    record[key] = @{ @"original":previous && [current isEqual:previous[@"applied"]] ? previous[@"original"] : current, @"applied":value };
    [view setValue:value == NSNull.null ? nil : value forKey:key];
}
+ (void)clear:(UIView *)view state:(DKXSContentCommentsState *)state {
    [self write:UIColor.clearColor key:@"backgroundColor" view:view state:state];
    [self write:@NO key:@"opaque" view:view state:state];
}
+ (void)drop:(DKXSContentCommentsState *)state {
    for (UIView *view in state.changes.keyEnumerator.allObjects) {
        NSDictionary *record = [state.changes objectForKey:view];
        for (NSString *key in record) {
            NSDictionary *change = record[key];
            if ([([view valueForKey:key] ?: NSNull.null) isEqual:change[@"applied"]])
                [view setValue:change[@"original"] == NSNull.null ? nil : change[@"original"] forKey:key];
        }
    }
    [state.changes removeAllObjects]; state.collection = nil;
    [state.panel removeFromSuperview];
}
+ (void)synchronize:(UIViewController *)host {
    if (!NSThread.isMainThread || ![DKXSContentBarAdapter isRichHost:host] || !host.isViewLoaded) return;
    DKXSContentCommentsState *state = objc_getAssociatedObject(host, &kDKXSContentCommentsKey);
    if (!state) {
        state = [DKXSContentCommentsState new]; state.changes = [NSMapTable weakToStrongObjectsMapTable];
        objc_setAssociatedObject(host, &kDKXSContentCommentsKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [[self hosts] addObject:host];
    }
    if (state.busy) return;
    state.active = YES; state.busy = YES;
    @try {
        UICollectionView *collection = [self collectionInHost:host];
        if (![NSUserDefaults.standardUserDefaults boolForKey:@"DKXSEnableCommentBlur"] || !collection) { [self drop:state]; return; }
        if (state.collection != collection) { [self drop:state]; state.collection = collection; }
        if (!state.panel) {
            state.panel = [UIView new]; state.panel.userInteractionEnabled = NO;
            state.panel.accessibilityIdentifier = @"DYxs.Content.Comments.Material";
            state.panel.layer.cornerRadius = 24; state.panel.layer.cornerCurve = kCACornerCurveContinuous; state.panel.clipsToBounds = YES;

        }
        state.panel.frame = collection.bounds;
        [DKXSCommentBlurCoordinator applyBlurEffectToView:state.panel transparency:[self commentBlurTransparency] blurViewTag:999];
        for (UIView *view in state.panel.subviews) view.userInteractionEnabled = NO;
        [self write:state.panel key:@"backgroundView" view:collection state:state];
        [self clear:collection state:state]; [self clear:collection.superview state:state];
        // 只去除已确认的中性分区底板，评论文字、头像、选中高亮和点击控件均不递归处理。
        for (UIView *view in collection.subviews) {
            NSString *name = NSStringFromClass(view.class);
            if ([name isEqual:@"AWEBaseListSectionBackgroundView"] ||
                [name isEqual:@"AWEKnowledgeRichContentImpl.FullPageFeedCommentInputCell"]) [self clear:view state:state];
        }
    } @finally { state.busy = NO; }
}
+ (void)synchronizeForList:(UIViewController *)list {
    if (!NSThread.isMainThread) return;
    UIViewController *parent = list;
    for (NSUInteger i = 0; parent && i < 8; i++, parent = parent.parentViewController) {
        if (![DKXSContentBarAdapter isRichHost:parent]) continue;
        DKXSContentCommentsState *state = objc_getAssociatedObject(parent, &kDKXSContentCommentsKey);
        if (state.active) [self synchronize:parent];
        return;
    }
}
+ (void)restore:(UIViewController *)host {
    if (!NSThread.isMainThread) return;
    DKXSContentCommentsState *state = objc_getAssociatedObject(host, &kDKXSContentCommentsKey);
    state.active = NO; [self drop:state];
}
+ (void)refresh {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self refresh]; }); return; }
    for (UIViewController *host in [self hosts].allObjects) {
        DKXSContentCommentsState *state = objc_getAssociatedObject(host, &kDKXSContentCommentsKey);
        if (state.active) [self synchronize:host];
    }
}
+ (NSDictionary *)diagnostics {
    if (!NSThread.isMainThread) return @{};
    NSMutableArray *items = [NSMutableArray array];
    for (UIViewController *host in [self hosts].allObjects) {
        DKXSContentCommentsState *state = objc_getAssociatedObject(host, &kDKXSContentCommentsKey);
        if (!state.active) continue;
        [items addObject:@{ @"mounted":@(state.collection && state.collection.backgroundView == state.panel),
            @"backgroundMode":@"nativeBlur", @"panelFrame":NSStringFromCGRect(state.panel.frame) }];
    }
    return @{ @"enabled":@([NSUserDefaults.standardUserDefaults boolForKey:@"DKXSEnableCommentBlur"]),
        @"opacity":@([self commentBlurTransparency]), @"hosts":items };
}
@end
