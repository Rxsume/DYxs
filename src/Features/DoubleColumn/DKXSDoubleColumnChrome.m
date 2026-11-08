// 移植自 Si-yi/DYads- b97c05e（DYYYDoubleColumnChrome.m）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
#import "DKXSDoubleColumnChrome.h"
#import "DKXSContentViewportMetrics.h"
#import "DKXSChatEnhancementPolicy.h"
#import <objc/runtime.h>
#import <string.h>

// 最小接口声明：AWEDCFeedListViewController 不在 DKXSAwemeHeaders（39.5 导出）里；
// updateLayoutWithTopAreaConfig 为本文件直接调用的唯一方法，其余角色视图走 valueForKey。
@interface AWEDCFeedListViewController : UIViewController
- (void)updateLayoutWithTopAreaConfig;
@end

static char kDKXSDoubleColumnChromeKey;
@interface DKXSDoubleColumnChromeState : NSObject
@property (nonatomic, assign) BOOL active;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, assign) BOOL hasFrame;
@property (nonatomic, assign) CGRect nativeFrame;
@property (nonatomic, assign) CGRect appliedFrame;
@property (nonatomic, weak) AWEDCFeedListViewController *feed;
@property (nonatomic, weak) UICollectionView *collection;
@property (nonatomic, strong) NSMapTable<UIView *, NSMutableDictionary *> *changes;
@end
@implementation DKXSDoubleColumnChromeState
@end

@implementation DKXSDoubleColumnChrome
+ (NSHashTable *)hosts {
    static NSHashTable *hosts; static dispatch_once_t once;
    dispatch_once(&once, ^{ hosts = [NSHashTable weakObjectsHashTable]; }); return hosts;
}
+ (BOOL)isHome:(UIViewController *)host {
    if (![host isKindOfClass:NSClassFromString(@"AWEFeedNewDoubleColumnViewController")]) return NO;
    UIViewController *parent = host;
    for (NSUInteger i = 0; parent && i < 16; i++, parent = parent.parentViewController)
        if ([parent isKindOfClass:NSClassFromString(@"AWEFeedRootViewController")]) return YES;
    return NO;
}
+ (DKXSDoubleColumnChromeState *)state:(UIViewController *)host {
    DKXSDoubleColumnChromeState *state = objc_getAssociatedObject(host, &kDKXSDoubleColumnChromeKey);
    if (!state) {
        state = [DKXSDoubleColumnChromeState new]; state.changes = [NSMapTable weakToStrongObjectsMapTable];
        objc_setAssociatedObject(host, &kDKXSDoubleColumnChromeKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [[self hosts] addObject:host];
    }
    return state;
}
+ (BOOL)supportsFrameDelegate:(Class)cls {
    Method method = class_getInstanceMethod(cls, @selector(dcFeed:frameForCollectionView:));
    if (!method) return NO;
    @try {
        NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
        return signature.numberOfArguments == 4 && signature.methodReturnLength == sizeof(CGRect) &&
            strcmp(signature.methodReturnType, @encode(CGRect)) == 0 &&
            strcmp([signature getArgumentTypeAtIndex:2], "@") == 0 && strcmp([signature getArgumentTypeAtIndex:3], "@") == 0;
    } @catch (__unused NSException *exception) { return NO; }
}
+ (NSDictionary *)rect:(CGRect)frame {
    return @{ @"x":@(frame.origin.x), @"y":@(frame.origin.y), @"width":@(frame.size.width), @"height":@(frame.size.height) };
}
+ (CGRect)frameForHost:(UIViewController *)host feed:(id)feed collection:(id)collection native:(CGRect)native {
    if (!NSThread.isMainThread || ![self isHome:host] || !host.isViewLoaded ||
        ![feed isKindOfClass:NSClassFromString(@"AWEDCFeedListViewController")] ||
        ![collection isKindOfClass:UICollectionView.class] || ![collection isDescendantOfView:[feed viewIfLoaded]] ||
        ![[feed viewIfLoaded] isDescendantOfView:host.viewIfLoaded]) return native;
    DKXSDoubleColumnChromeState *state = [self state:host];
    // 部分原生布局会读上次frame；只剥离确切属于本适配器的结果，不累加扩展。
    CGRect base = state.hasFrame && state.collection == collection && CGRectEqualToRect(native, state.appliedFrame) ? state.nativeFrame : native;
    NSDictionary *result = [DKXSContentViewportMetrics doubleColumn:[self rect:base]
        width:CGRectGetWidth(host.view.bounds) height:CGRectGetHeight(host.view.bounds)
        top:[NSUserDefaults.standardUserDefaults boolForKey:@"DKXSEnableArticleTopGlass"]
        bottom:[NSUserDefaults.standardUserDefaults boolForKey:@"DKXSEnableArticleBottomGlass"]];
    if (!result.count) { state.hasFrame = NO; return native; }
    CGRect frame = CGRectMake([result[@"x"] doubleValue], [result[@"y"] doubleValue], [result[@"width"] doubleValue], [result[@"height"] doubleValue]);
    state.feed = feed; state.collection = collection; state.nativeFrame = base; state.appliedFrame = frame; state.hasFrame = YES;
    return frame;
}
+ (void)write:(id)value key:(NSString *)key view:(UIView *)view state:(DKXSDoubleColumnChromeState *)state {
    if (!view) return;
    id current = [view valueForKey:key] ?: NSNull.null;
    if ([current isEqual:value]) return;
    NSMutableDictionary *record = [state.changes objectForKey:view];
    if (!record) { record = [NSMutableDictionary dictionary]; [state.changes setObject:record forKey:view]; }
    NSDictionary *previous = record[key];
    record[key] = @{ @"original":previous && [current isEqual:previous[@"applied"]] ? previous[@"original"] : current, @"applied":value };
    [view setValue:value forKey:key];
}
+ (void)restorePaint:(DKXSDoubleColumnChromeState *)state {
    for (UIView *view in state.changes.keyEnumerator.allObjects) {
        NSDictionary *record = [state.changes objectForKey:view];
        for (NSString *key in record) {
            NSDictionary *change = record[key];
            if ([([view valueForKey:key] ?: NSNull.null) isEqual:change[@"applied"]])
                [view setValue:change[@"original"] == NSNull.null ? nil : change[@"original"] forKey:key];
        }
    }
    [state.changes removeAllObjects];
}
+ (UIView *)existing:(NSString *)getter in:(UIViewController *)controller {
    if (![DKXSChatEnhancementPolicy class:controller.class selector:NSSelectorFromString(getter) result:'@' arguments:@""]) return nil;
    @try {
        id view = [controller valueForKey:getter];
        return [view isKindOfClass:UIView.class] && [view isDescendantOfView:controller.viewIfLoaded] ? view : nil;
    } @catch (__unused NSException *exception) { return nil; }
}
+ (void)beginAppearance:(UIViewController *)host {
    if (!NSThread.isMainThread || ![self isHome:host]) return;
    DKXSDoubleColumnChromeState *state = [self state:host]; state.active = YES;
    if (!state.feed) for (UIViewController *child in host.childViewControllers)
        if ([child isKindOfClass:NSClassFromString(@"AWEDCFeedListViewController")]) { state.feed = (id)child; break; }
    if ((state.hasFrame || [NSUserDefaults.standardUserDefaults boolForKey:@"DKXSEnableArticleTopGlass"] ||
         [NSUserDefaults.standardUserDefaults boolForKey:@"DKXSEnableArticleBottomGlass"]) &&
        [DKXSChatEnhancementPolicy class:state.feed.class selector:@selector(updateLayoutWithTopAreaConfig) result:'v' arguments:@""])
        [state.feed updateLayoutWithTopAreaConfig];
    [self synchronize:host];
}
+ (void)synchronize:(UIViewController *)host {
    if (!NSThread.isMainThread || ![self isHome:host]) return;
    DKXSDoubleColumnChromeState *state = objc_getAssociatedObject(host, &kDKXSDoubleColumnChromeKey);
    if (!state.active || state.busy) return;
    state.busy = YES;
    BOOL top = [NSUserDefaults.standardUserDefaults boolForKey:@"DKXSEnableArticleTopGlass"];
    if (top && state.hasFrame) {
        UIView *background = [self existing:@"topTabBackgroundView" in:host];
        [self write:UIColor.clearColor key:@"backgroundColor" view:background state:state];
        [self write:@NO key:@"opaque" view:background state:state];
        for (NSString *name in @[ @"topGradientView", @"topDividerView" ])
            [self write:@YES key:@"hidden" view:[self existing:name in:state.feed] state:state];
    } else [self restorePaint:state];
    state.busy = NO;
}
+ (void)restore:(UIViewController *)host {
    if (!NSThread.isMainThread) return;
    DKXSDoubleColumnChromeState *state = objc_getAssociatedObject(host, &kDKXSDoubleColumnChromeKey);
    state.active = NO; [self restorePaint:state];
    // 原生离页时仍可复用缓存frame，保留基线供下次委托识别；没有frame/inset/offset写入。
}
+ (void)refresh {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self refresh]; }); return; }
    for (UIViewController *host in [self hosts].allObjects) {
        DKXSDoubleColumnChromeState *state = objc_getAssociatedObject(host, &kDKXSDoubleColumnChromeKey);
        if (!state.active || state.busy) continue;
        if ([DKXSChatEnhancementPolicy class:state.feed.class selector:@selector(updateLayoutWithTopAreaConfig) result:'v' arguments:@""])
            [state.feed updateLayoutWithTopAreaConfig];
        [self synchronize:host];
    }
}
+ (NSDictionary *)diagnostics {
    if (!NSThread.isMainThread) return @{};
    NSMutableArray *items = [NSMutableArray array];
    for (UIViewController *host in [self hosts].allObjects) {
        DKXSDoubleColumnChromeState *state = objc_getAssociatedObject(host, &kDKXSDoubleColumnChromeKey);
        [items addObject:@{ @"active":@(state.active), @"layoutObserved":@(state.hasFrame),
            @"nativeViewport":NSStringFromCGRect(state.nativeFrame), @"requestedViewport":NSStringFromCGRect(state.appliedFrame),
            @"actualViewport":state.collection ? NSStringFromCGRect(state.collection.frame) : @"" }];
    }
    return @{ @"hosts":items };
}
@end
