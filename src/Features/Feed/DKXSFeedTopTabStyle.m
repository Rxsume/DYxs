// 移植自 Si-yi/DYads- b97c05e（DYYYFeedTopTabStyle.m）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配：上游默认开启 DYYYEnableFeedTopTabHighlight，DYxs 移植惯例全部默认关，不跟随。
// 接线不在上游 DYYY.xm（DYxs 不整并），改由 DKXSFeedTopTabHooks.xm 独立 hook 同类方法。
#import "DKXSFeedTopTabStyle.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <math.h>

// 最小接口声明：DKXSAwemeHeaders（39.5 导出）里的 AWEHPTopTabItemTextContentView 只声明了
// setContentText:；上游 AwemeHeaders.h 补的 titleLabel/selectedProgress/isLightTheme 在此补充。
@interface AWEHPTopTabItemTextContentView : UIView
@property (nonatomic, strong, readonly) UILabel *titleLabel;
@property (nonatomic, assign, readonly) double selectedProgress;
@property (nonatomic, assign, readonly) BOOL isLightTheme;
@end

static char kDKXSFeedTopTabPaintKey;

@implementation DKXSFeedTopTabStyle

+ (void)preparePreferences {
    // 默认关闭，跟随第 8 批“全部默认关”的移植惯例（上游默认开，不跟随）。
    [NSUserDefaults.standardUserDefaults registerDefaults:@{@"DKXSEnableFeedTopTabHighlight":@NO}];
}

+ (NSHashTable<UIView *> *)trackedTitles {
    static NSHashTable<UIView *> *titles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ titles = [NSHashTable weakObjectsHashTable]; });
    return titles;
}

+ (void)writeValue:(id)value key:(NSString *)key label:(UILabel *)label changes:(NSMutableDictionary *)changes {
    id current = [label valueForKeyPath:key] ?: NSNull.null;
    if ([current isEqual:value]) return;
    NSDictionary *previous = changes[key];
    id original = previous && [current isEqual:previous[@"applied"]] ? previous[@"original"] : current;
    changes[key] = @{ @"original": original, @"applied": value };
    [label setValue:value == NSNull.null ? nil : value forKeyPath:key];
}

+ (void)restoreLabel:(UILabel *)label {
    NSDictionary *changes = objc_getAssociatedObject(label, &kDKXSFeedTopTabPaintKey);
    for (NSString *key in changes) {
        NSDictionary *change = changes[key];
        id current = [label valueForKeyPath:key] ?: NSNull.null;
        if ([current isEqual:change[@"applied"]]) {
            id original = change[@"original"];
            [label setValue:original == NSNull.null ? nil : original forKeyPath:key];
        }
    }
    objc_setAssociatedObject(label, &kDKXSFeedTopTabPaintKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (void)applyToTextView:(UIView *)view {
    if (!NSThread.isMainThread) {
        __weak UIView *weakView = view;
        dispatch_async(dispatch_get_main_queue(), ^{ [self applyToTextView:weakView]; });
        return;
    }
    if (![view isKindOfClass:NSClassFromString(@"AWEHPTopTabItemTextContentView")]) return;
    AWEHPTopTabItemTextContentView *textView = (id)view;
    if (![textView respondsToSelector:@selector(titleLabel)] ||
        ![textView respondsToSelector:@selector(selectedProgress)] ||
        ![textView respondsToSelector:@selector(isLightTheme)]) return;
    UILabel *label = textView.titleLabel;
    if (![label isKindOfClass:UILabel.class] || ![label isDescendantOfView:view]) return;
    [[self trackedTitles] addObject:view];

    // 只处理视频首页原生频道栏，不接管搜索、消息或个人页的标签。
    BOOL inFeedTabs = NO;
    UIView *ancestor = view.superview;
    for (NSUInteger depth = 0; ancestor && depth < 8; depth++, ancestor = ancestor.superview) {
        if ([ancestor isKindOfClass:NSClassFromString(@"AWEFeedMultiTabSegmentedControl")]) {
            inFeedTabs = YES;
            break;
        }
    }
    double progress = textView.selectedProgress;
    if (!inFeedTabs || !isfinite(progress) || ![[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSEnableFeedTopTabHighlight"]) {
        [self restoreLabel:label];
        return;
    }
    // 跟随原生滑动进度渐变；字体、名称、字号与点击范围均沿用原生。
    progress = MIN(1.0, MAX(0.0, progress));
    BOOL lightTheme = textView.isLightTheme;
    UIColor *color = [UIColor colorWithWhite:lightTheme ? 0.08 : 1.0 alpha:0.66 + 0.34 * progress];
    NSMutableDictionary *changes = objc_getAssociatedObject(label, &kDKXSFeedTopTabPaintKey);
    if (!changes) {
        changes = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(label, &kDKXSFeedTopTabPaintKey, changes, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [self writeValue:color key:@"textColor" label:label changes:changes];
    [self writeValue:(__bridge id)UIColor.blackColor.CGColor key:@"layer.shadowColor" label:label changes:changes];
    [self writeValue:@(lightTheme ? 0.0 : 0.28) key:@"layer.shadowOpacity" label:label changes:changes];
    [self writeValue:@2.0 key:@"layer.shadowRadius" label:label changes:changes];
    [self writeValue:[NSValue valueWithCGSize:CGSizeMake(0, 1)] key:@"layer.shadowOffset" label:label changes:changes];
}

+ (void)refreshVisibleTitles {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self refreshVisibleTitles]; });
        return;
    }
    for (UIView *view in [self trackedTitles].allObjects) [self applyToTextView:view];
}

@end
