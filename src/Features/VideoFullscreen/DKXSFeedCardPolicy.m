// 移植自 Si-yi/DYads- 5e9a5c0（DYYYFeedCardPolicy.m）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样。
#import "DKXSFeedCardPolicy.h"
#import <objc/runtime.h>
#import <math.h>

static char kDKXSFeedCardScopeKey;
@interface DKXSFeedCardScope : NSObject
@property (atomic, weak) id feed;
@property (atomic, assign) BOOL home;
@property (atomic, assign) BOOL enabled;
@end
@implementation DKXSFeedCardScope
@end
@implementation DKXSFeedCardPolicy
+ (BOOL)isPromotionalCard:(id)model {
    Class cls = NSClassFromString(@"AWEAwemeModel");
    if (!cls || ![model isKindOfClass:cls]) return NO;
    // dCardModel 是 POI 动态卡；普通作品的 poiInfo、位置锚点不参与判断。
    for (NSString *key in @[@"hotSpotLynxCardModel", @"dCardModel"]) {
        if (![model respondsToSelector:NSSelectorFromString(key)]) continue;
        @try {
            id value = [model valueForKey:key];
            if (value && value != NSNull.null) return YES;
        } @catch (__unused NSException *e) {}
    }
    return NO;
}
+ (BOOL)bindFeed:(id)feed controller:(id)controller {
    if (!NSThread.isMainThread || !controller || !feed) return NO;
    BOOL home = NO;
    Class root = NSClassFromString(@"AWEFeedRootViewController");
    id parent = feed;
    for (NSUInteger i = 0; parent && i < 24; i++) {
        if (root && [parent isKindOfClass:root]) { home = YES; break; }
        if (![parent respondsToSelector:NSSelectorFromString(@"parentViewController")]) break;
        @try { parent = [parent valueForKey:@"parentViewController"]; } @catch (__unused NSException *e) { break; }
    }
    Class hotList = NSClassFromString(@"AWEHotListDataController");
    home = home && hotList && [controller isKindOfClass:hotList];
    DKXSFeedCardScope *scope = objc_getAssociatedObject(controller, &kDKXSFeedCardScopeKey);
    BOOL enabled = [NSUserDefaults.standardUserDefaults boolForKey:@"DKXSSkipHotSpot"];
    BOOL changed = !scope || scope.feed != feed || scope.home != home || scope.enabled != enabled;
    BOOL recalculate = changed && ((home && enabled) || (scope.home && scope.enabled));
    if (!scope) { scope = [DKXSFeedCardScope new]; objc_setAssociatedObject(controller, &kDKXSFeedCardScopeKey, scope, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    scope.feed = feed; scope.home = home; scope.enabled = enabled;
    return recalculate;
}
+ (BOOL)isEnabledForController:(id)controller {
    DKXSFeedCardScope *scope = objc_getAssociatedObject(controller, &kDKXSFeedCardScopeKey);
    return scope.home && scope.enabled && scope.feed != nil;
}
+ (NSArray *)filterArray:(id)array controller:(id)controller {
    if (![self isEnabledForController:controller] || ![array isKindOfClass:NSArray.class]) return array;
    NSMutableArray *filtered = nil;
    NSUInteger index = 0;
    for (id model in array) {
        if ([self isPromotionalCard:model]) {
            if (!filtered) filtered = [[array subarrayWithRange:NSMakeRange(0, index)] mutableCopy];
        } else if (filtered) [filtered addObject:model];
        index++;
    }
    return filtered ? ([array isKindOfClass:NSMutableArray.class] ? filtered : filtered.copy) : array;
}
+ (double)bottomConstant:(double)native inset:(double)inset reversed:(BOOL)reversed {
    if (!isfinite(native) || !isfinite(inset) || inset < 0) return native;
    return native + (reversed ? inset : -inset);
}
@end
