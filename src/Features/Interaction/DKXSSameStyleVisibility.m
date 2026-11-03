// 移植自 Si-yi/DYads- (fb78fd91)：改名一律 DYYY -> DKXS，设置键同步改名；逻辑原样。
#import "DKXSSameStyleVisibility.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

static char kDKXSSameStyleOriginalsKey;
static char kDKXSSameStyleDecorationLayersKey;
static char kDKXSSameStyleUpdateDepthKey;

@implementation DKXSSameStyleVisibility

+ (NSHashTable<UIView *> *)views {
    static NSHashTable *views;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ views = [NSHashTable weakObjectsHashTable]; });
    return views;
}

+ (BOOL)isRightMusicView:(UIView *)view {
    // 81ADA564：同一原生右栈还会使用独立的 StyleOne 类显示“玩同款”。
    if (![view isKindOfClass:NSClassFromString(@"AWEPlayInteractionSingleSongMusicStyleView")] &&
        ![view isKindOfClass:NSClassFromString(@"AWEPlayInteractionStyleOneMusicView")]) return NO;
    for (UIView *parent = view.superview; parent; parent = parent.superview) {
        if ([parent isKindOfClass:NSClassFromString(@"AWEElementStackView")] &&
            [parent.accessibilityLabel isEqualToString:@"right"]) return YES;
    }
    return NO;
}

+ (void)restoreView:(UIView *)view {
    NSMapTable<UILabel *, NSNumber *> *originals = objc_getAssociatedObject(view, &kDKXSSameStyleOriginalsKey);
    objc_setAssociatedObject(view, &kDKXSSameStyleOriginalsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (UILabel *label in originals.keyEnumerator.allObjects) {
        if (label.hidden) label.hidden = [[originals objectForKey:label] boolValue];
    }
    NSMapTable<CALayer *, NSMutableDictionary *> *layers = objc_getAssociatedObject(view, &kDKXSSameStyleDecorationLayersKey);
    objc_setAssociatedObject(view, &kDKXSSameStyleDecorationLayersKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    for (CALayer *layer in layers.keyEnumerator.allObjects) {
        NSDictionary *saved = [layers objectForKey:layer];
        if (layer.mask == saved[@"mask"]) layer.mask = saved[@"original"] == NSNull.null ? nil : saved[@"original"];
    }
    [CATransaction commit];
}

+ (void)applyToView:(UIView *)view {
    if (!NSThread.isMainThread || !view) return;
    if ([objc_getAssociatedObject(view, &kDKXSSameStyleUpdateDepthKey) unsignedIntegerValue]) return;
    [[self views] addObject:view];
    if (!view.window || ![[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSHideSameStyleButton"] || ![self isRightMusicView:view]) {
        [self restoreView:view];
        return;
    }
    // 导出确认：标题下面的 44pt 圆形容器内含黑色 60% 填充，文字隐藏后它仍会盖住封面。
    // 仅透明化原生标题装饰层的绘制，不改其 UIView 显隐/alpha/命中，不动音乐封面。
    NSMapTable<CALayer *, NSMutableDictionary *> *layers = objc_getAssociatedObject(view, &kDKXSSameStyleDecorationLayersKey);
    NSArray *keys = @[@"playInteractionCircleMaskView", @"playInteractionMaskView", @"playInteractionColorMaskView"];
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    for (CALayer *layer in layers.keyEnumerator.allObjects) {
        BOOL belongs = NO;
        for (CALayer *parent = layer; parent; parent = parent.superlayer)
            if (parent == view.layer) { belongs = YES; break; }
        if (belongs) continue;
        NSDictionary *saved = [layers objectForKey:layer];
        if (layer.mask == saved[@"mask"]) layer.mask = saved[@"original"] == NSNull.null ? nil : saved[@"original"];
        [layers removeObjectForKey:layer];
    }
    for (NSString *key in keys) {
        if (![view respondsToSelector:NSSelectorFromString(key)]) continue;
        UIView *decoration = nil;
        @try { decoration = [view valueForKey:key]; } @catch (__unused NSException *exception) { continue; }
        if (![decoration isKindOfClass:UIView.class] || decoration == view || ![decoration isDescendantOfView:view]) continue;
        BOOL insideCover = NO;
        for (UIView *parent = decoration; parent && parent != view; parent = parent.superview)
            if ([parent isKindOfClass:NSClassFromString(@"AWEMusicCoverButton")]) { insideCover = YES; break; }
        if (insideCover) continue;
        if (!layers) {
            layers = [NSMapTable weakToStrongObjectsMapTable];
            objc_setAssociatedObject(view, &kDKXSSameStyleDecorationLayersKey, layers, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        CALayer *layer = decoration.layer;
        NSMutableDictionary *saved = [layers objectForKey:layer];
        if (!saved) {
            CALayer *mask = [CALayer layer];
            mask.name = @"DKXS.MusicCaption.DecorationMask";
            mask.backgroundColor = UIColor.clearColor.CGColor;
            saved = [@{@"mask": mask, @"original": layer.mask ?: NSNull.null} mutableCopy];
            [layers setObject:saved forKey:layer];
        }
        CALayer *mask = saved[@"mask"];
        if (layer.mask != mask) {
            saved[@"original"] = layer.mask ?: NSNull.null;
            layer.mask = mask;
        }
        if (!CGRectEqualToRect(mask.frame, layer.bounds)) mask.frame = layer.bounds;
    }
    [CATransaction commit];
    NSMapTable<UILabel *, NSNumber *> *originals = objc_getAssociatedObject(view, &kDKXSSameStyleOriginalsKey);
    // 组件中的标题不再按文案匹配：拍同款、玩同款、听音乐等均只隐藏文字。
    // 两种已确认的原生音乐控件均使用直接子 UILabel；按钮/缩略图/点击遮罩及无障碍动作保留。
    for (UILabel *label in originals.keyEnumerator.allObjects) {
        if (label.superview == view) continue;
        if (label.hidden) label.hidden = [[originals objectForKey:label] boolValue];
        [originals removeObjectForKey:label];
    }
    for (UIView *child in view.subviews) {
        if (![child isKindOfClass:UILabel.class]) continue;
        UILabel *label = (UILabel *)child;
        if (!originals) {
            originals = [NSMapTable weakToStrongObjectsMapTable];
            objc_setAssociatedObject(view, &kDKXSSameStyleOriginalsKey, originals, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (![originals objectForKey:label] || !label.hidden) [originals setObject:@(label.hidden) forKey:label];
        if (!label.hidden) label.hidden = YES;
    }
}

+ (void)beginNativeUpdate:(UIView *)view {
    if (!NSThread.isMainThread || !view) return;
    NSUInteger depth = [objc_getAssociatedObject(view, &kDKXSSameStyleUpdateDepthKey) unsignedIntegerValue];
    objc_setAssociatedObject(view, &kDKXSSameStyleUpdateDepthKey, @(depth + 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!depth) [self restoreView:view];
}

+ (void)endNativeUpdate:(UIView *)view {
    if (!NSThread.isMainThread || !view) return;
    NSUInteger depth = [objc_getAssociatedObject(view, &kDKXSSameStyleUpdateDepthKey) unsignedIntegerValue];
    if (depth > 1) {
        objc_setAssociatedObject(view, &kDKXSSameStyleUpdateDepthKey, @(depth - 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        objc_setAssociatedObject(view, &kDKXSSameStyleUpdateDepthKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self applyToView:view];
    }
}

+ (void)refreshVisibleViews {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self refreshVisibleViews]; });
        return;
    }
    for (UIView *view in [self views].allObjects) [self applyToView:view];
}
@end
