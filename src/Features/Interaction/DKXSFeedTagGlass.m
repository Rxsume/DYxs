// 移植自 Si-yi/DYads- (fb78fd91)：改名一律 DYYY -> DKXS，设置键同步改名；逻辑原样。
#import "DKXSFeedTagGlass.h"
#import "DKXSFriendShareBadgeView.h"
#import "DKXSUtils.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <math.h>

static char kDKXSFeedTagGlassKey;
static char kDKXSFeedTagUpdateDepthKey;
static char kDKXSFeedTagRefreshKey;

@interface DKXSFeedTagGlassState : NSObject
@property (nonatomic, weak) UIView *host;
@property (nonatomic, strong) UIVisualEffectView *glass;
@property (nonatomic, strong) NSMapTable<UIView *, NSMutableDictionary *> *changes;
@property (nonatomic, assign) BOOL busy;
@end
@implementation DKXSFeedTagGlassState
@end

@implementation DKXSFeedTagGlass

+ (BOOL)isFeedTag:(UIView *)tag {
    if (!tag.window) return NO;
    for (UIView *parent = tag; parent; parent = parent.superview)
        if (parent.hidden || parent.alpha <= 0.01) return NO;
    Class interaction = NSClassFromString(@"AWEPlayInteractionViewController");
    UIViewController *controller = [DKXSUtils firstAvailableViewControllerFromView:tag];
    for (NSUInteger depth = 0; controller && depth < 12; depth++, controller = controller.parentViewController)
        if (interaction && [controller isKindOfClass:interaction]) return YES;
    return NO;
}

+ (UIView *)existingView:(NSString *)name inTag:(UIView *)tag {
    if (![tag respondsToSelector:NSSelectorFromString(name)]) return nil;
    @try {
        id view = [tag valueForKey:name];
        return [view isKindOfClass:UIView.class] && [view isDescendantOfView:tag] ? view : nil;
    } @catch (__unused NSException *exception) { return nil; }
}

+ (void)write:(id)value key:(NSString *)key view:(UIView *)view state:(DKXSFeedTagGlassState *)state {
    if (!view || !value) return;
    @try {
        id current = [view valueForKey:key] ?: NSNull.null;
        if (current == value || [current isEqual:value]) return;
        NSMutableDictionary *changes = [state.changes objectForKey:view];
        if (!changes) {
            changes = [NSMutableDictionary dictionary];
            [state.changes setObject:changes forKey:view];
        }
        NSDictionary *previous = changes[key];
        id original = previous && [current isEqual:previous[@"applied"]] ? previous[@"original"] : current;
        changes[key] = @{ @"original": original, @"applied": value };
        [view setValue:value forKey:key];
    } @catch (__unused NSException *exception) {}
}

+ (BOOL)needsLightText:(UIColor *)color {
    CGFloat r, g, b, a;
    return color && [color getRed:&r green:&g blue:&b alpha:&a] && a > 0.01 &&
        MAX(r, MAX(g, b)) < 0.8 && MAX(r, MAX(g, b)) - MIN(r, MIN(g, b)) < 0.12;
}

+ (BOOL)isRecommendationTag:(UIView *)tag {
    for (NSString *name in @[ @"AFDRecommendToFriendEntranceLabel", @"AFDFriendRecommendTagView" ]) {
        Class type = NSClassFromString(name);
        if (type && [tag isKindOfClass:type]) return YES;
    }
    return NO;
}

+ (BOOL)isNeutralText:(UIColor *)color {
    CGFloat r, g, b, a;
    return [color isKindOfClass:UIColor.class] && [color getRed:&r green:&g blue:&b alpha:&a] &&
        a > 0.01 && MAX(r, MAX(g, b)) - MIN(r, MIN(g, b)) < 0.12;
}

// 给原生小图标的绘制增加透明内边距，保持UIImageView尺寸、约束和命中区域不变。
+ (void)softenImageView:(UIView *)view scale:(CGFloat)scale alpha:(CGFloat)alpha state:(DKXSFeedTagGlassState *)state {
    if (![view isKindOfClass:UIImageView.class]) return;
    UIImageView *imageView = (id)view;
    CGSize size = imageView.bounds.size;
    if (!isfinite(size.width) || !isfinite(size.height) ||
        size.width < 4 || size.height < 4 || size.width > 40 || size.height > 40) return;
    [self write:@(alpha) key:@"alpha" view:imageView state:state];
    NSDictionary *previous = [state.changes objectForKey:imageView][@"image"];
    UIImage *current = imageView.image;
    BOOL ownsImage = current && current == previous[@"applied"];
    if (ownsImage) return;
    UIImage *source = current;
    if (![source isKindOfClass:UIImage.class] || source.images.count) return;
    // UIImage本身的逻辑尺寸也保留，避免改变UIImageView的intrinsicContentSize。
    CGSize canvas = source.size;
    if (!isfinite(canvas.width) || !isfinite(canvas.height) || canvas.width <= 0 || canvas.height <= 0 ||
        canvas.width > 256 || canvas.height > 256) return;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    format.scale = source.scale;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:canvas format:format];
    CGSize ink = CGSizeMake(canvas.width * scale, canvas.height * scale);
    UIImage *inset = [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
        [source drawInRect:CGRectMake((canvas.width - ink.width) * 0.5, (canvas.height - ink.height) * 0.5, ink.width, ink.height)];
    }];
    inset = [inset imageWithAlignmentRectInsets:source.alignmentRectInsets];
    [self write:[inset imageWithRenderingMode:source.renderingMode] key:@"image" view:imageView state:state];
}

+ (void)prepareLabels:(UIView *)host muted:(BOOL)muted state:(DKXSFeedTagGlassState *)state {
    UIColor *labelColor = [UIColor colorWithWhite:1 alpha:muted ? 0.9 : 1];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:host];
    Class yyLabel = NSClassFromString(@"YYLabel");
    for (NSUInteger index = 0; index < queue.count && index < 48; index++) {
        UIView *view = queue[index];
        if (view == state.glass || [view isKindOfClass:UIImageView.class]) continue;
        if ([view isKindOfClass:UILabel.class] || (yyLabel && [view isKindOfClass:yyLabel])) {
            @try {
                UIColor *color = [view valueForKey:@"textColor"];
                NSAttributedString *original = [view valueForKey:@"attributedText"];
                if (original.length) {
                    NSMutableAttributedString *text = [original mutableCopy];
                    __block BOOL changed = NO;
                    [original enumerateAttribute:NSForegroundColorAttributeName inRange:NSMakeRange(0, original.length) options:0 usingBlock:^(id value, NSRange range, BOOL *stop) {
                        UIColor *source = [value isKindOfClass:UIColor.class] ? value : color;
                        if (muted ? [self isNeutralText:source] : [self needsLightText:source]) {
                            if ([source isEqual:labelColor]) return;
                            [text addAttribute:NSForegroundColorAttributeName value:labelColor range:range];
                            changed = YES;
                        }
                    }];
                    if (changed) [self write:text key:@"attributedText" view:view state:state];
                } else if (muted ? [self isNeutralText:color] : [self needsLightText:color]) {
                    [self write:labelColor key:@"textColor" view:view state:state];
                }
            } @catch (__unused NSException *exception) {}
            continue;
        }
        [queue addObjectsFromArray:view.subviews];
    }
}

+ (void)restoreTag:(UIView *)tag {
    if (!NSThread.isMainThread || !tag) return;
    objc_setAssociatedObject(tag, &kDKXSFeedTagRefreshKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DKXSFeedTagGlassState *state = objc_getAssociatedObject(tag, &kDKXSFeedTagGlassKey);
    if (!state || state.busy) return;
    state.busy = YES;
    [state.glass removeFromSuperview];
    for (UIView *view in state.changes.keyEnumerator.allObjects) {
        NSDictionary *changes = [state.changes objectForKey:view];
        for (NSString *key in changes) {
            @try {
                NSDictionary *change = changes[key];
                id current = [view valueForKey:key] ?: NSNull.null;
                if ([current isEqual:change[@"applied"]])
                    [view setValue:change[@"original"] == NSNull.null ? nil : change[@"original"] forKey:key];
            } @catch (__unused NSException *exception) {}
        }
    }
    objc_setAssociatedObject(tag, &kDKXSFeedTagGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (void)decorateTag:(UIView *)tag {
    if (!NSThread.isMainThread || !tag) return;
    [DKXSFriendShareBadgeView nativeTagUpdated:tag];
    if ([objc_getAssociatedObject(tag, &kDKXSFeedTagUpdateDepthKey) unsignedIntegerValue] > 0) return;
    DKXSFeedTagGlassState *state = objc_getAssociatedObject(tag, &kDKXSFeedTagGlassKey);
    if (state.busy) return;
    if (![self isFeedTag:tag]) { [self restoreTag:tag]; return; }
    UIView *host = [self existingView:@"containerView" inTag:tag] ?: tag;
    if (CGRectIsEmpty(host.bounds)) { [self restoreTag:tag]; return; }
    if (state && state.host != host) { [self restoreTag:tag]; state = nil; }
    if (!state) {
        state = [DKXSFeedTagGlassState new];
        state.host = host;
        state.changes = [NSMapTable weakToStrongObjectsMapTable];
        state.glass = [[UIVisualEffectView alloc] initWithEffect:nil];
        state.glass.userInteractionEnabled = NO;
        state.glass.isAccessibilityElement = NO;
        state.glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        objc_setAssociatedObject(tag, &kDKXSFeedTagGlassKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (state.busy) return;
    state.busy = YES;
    @try {
        [self write:UIColor.clearColor key:@"backgroundColor" view:tag state:state];
        [self write:UIColor.clearColor key:@"backgroundColor" view:host state:state];
        [self write:@NO key:@"opaque" view:tag state:state];
        [self write:@NO key:@"opaque" view:host state:state];
        // 仅替换已确认的背景槽，图标、头像、文字、按钮及原生布局均保留。
        for (NSString *name in @[ @"backgroundView", @"backgroundImageView" ]) {
            UIView *background = [self existingView:name inTag:tag];
            if (background && background != host) [self write:@YES key:@"hidden" view:background state:state];
        }
        if (!CGRectEqualToRect(state.glass.frame, host.bounds)) state.glass.frame = host.bounds;
        BOOL recommendation = [self isRecommendationTag:tag];
        state.glass.layer.cornerRadius = recommendation ? MIN(CGRectGetWidth(host.bounds), CGRectGetHeight(host.bounds)) * 0.5 :
            (host.layer.cornerRadius > 0 ? host.layer.cornerRadius : MIN(6, CGRectGetHeight(host.bounds) * 0.5));
        state.glass.layer.cornerCurve = recommendation ? kCACornerCurveContinuous : kCACornerCurveCircular;
        state.glass.clipsToBounds = YES;
        state.glass.layer.borderWidth = 0.5;
        state.glass.layer.borderColor = [UIColor colorWithWhite:1 alpha:recommendation ? 0.08 : 0.18].CGColor;
        state.glass.contentView.backgroundColor = [UIColor colorWithWhite:0 alpha:recommendation ? 0.56 : 0.06];
        // 推荐提示用轻量半透明底；其他标签保留原来的薄毛玻璃，不跟随面板透明度设置。
        state.glass.alpha = recommendation ? 1 : 0.9;
        if (host.subviews.firstObject != state.glass) [host insertSubview:state.glass atIndex:0];
        if (recommendation) {
            state.glass.effect = nil;
            [self softenImageView:[self existingView:@"iconView" inTag:tag] scale:0.875 alpha:0.9 state:state];
            [self softenImageView:[self existingView:@"rightArrow" inTag:tag] scale:0.75 alpha:0.55 state:state];
        } else if (!state.glass.effect) {
            state.glass.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
        }
        [self prepareLabels:host muted:recommendation state:state];
    } @finally { state.busy = NO; }
}

// 原生状态更新可能嵌套调用背景、文字及动画更新。最外层先还原，结束后接管，
// 避免把插件的文字/背景当作新模型的原生样式，也避免更新中途重复铺玻璃。
+ (void)beginNativeUpdate:(UIView *)tag {
    if (!NSThread.isMainThread || !tag) return;
    NSUInteger depth = [objc_getAssociatedObject(tag, &kDKXSFeedTagUpdateDepthKey) unsignedIntegerValue];
    objc_setAssociatedObject(tag, &kDKXSFeedTagUpdateDepthKey, @(depth + 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (depth == 0) [self restoreTag:tag];
}

+ (void)refreshAfterNativeUpdate:(UIView *)tag {
    if (!tag) return;
    if (!NSThread.isMainThread) {
        __weak UIView *weakTag = tag;
        dispatch_async(dispatch_get_main_queue(), ^{ [self refreshAfterNativeUpdate:weakTag]; });
        return;
    }
    [self decorateTag:tag];
    if (!tag.window || objc_getAssociatedObject(tag, &kDKXSFeedTagRefreshKey)) return;
    // 合并同一轮事件中的状态切换，在原生动画块/子视图替换提交后再同步一次。
    // 不轮询、不强制布局；离页或下一次模型更新会取消旧任务。
    NSObject *ticket = [NSObject new];
    objc_setAssociatedObject(tag, &kDKXSFeedTagRefreshKey, ticket, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *weakTag = tag;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *current = weakTag;
        if (!current || objc_getAssociatedObject(current, &kDKXSFeedTagRefreshKey) != ticket) return;
        objc_setAssociatedObject(current, &kDKXSFeedTagRefreshKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self decorateTag:current];
    });
}

+ (void)endNativeUpdate:(UIView *)tag {
    if (!tag) return;
    if (!NSThread.isMainThread) {
        [self refreshAfterNativeUpdate:tag];
        return;
    }
    NSUInteger depth = [objc_getAssociatedObject(tag, &kDKXSFeedTagUpdateDepthKey) unsignedIntegerValue];
    if (depth > 1) {
        objc_setAssociatedObject(tag, &kDKXSFeedTagUpdateDepthKey, @(depth - 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    objc_setAssociatedObject(tag, &kDKXSFeedTagUpdateDepthKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self refreshAfterNativeUpdate:tag];
}

+ (BOOL)isLabelView:(UIView *)view {
    for (NSString *name in @[ @"AFDRecommendToFriendEntranceLabel", @"AFDFriendRecommendTagView", @"AWEPlayInteractionGeneralTagView",
                             @"AWEPlayInteractionTagsContainerLabelView", @"AWEPlayDislikeTagView", @"AWEPlayDislikeWithDrawTagView",
                             @"AWEPlayInteractionWatchVideoLaterTagView", @"AWEFeedTagsView", @"AWEFeedMultiTagView", @"AFDRecommendToFriendTagView" ]) {
        Class type = NSClassFromString(name);
        if (type && [view isKindOfClass:type]) return YES;
    }
    return NO;
}

+ (void)decorateStack:(UIView *)stack {
    if (!NSThread.isMainThread || !stack) return;
    [DKXSFriendShareBadgeView nativeTagUpdated:stack];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:stack.subviews];
    for (NSUInteger index = 0; index < queue.count && index < 96; index++) {
        UIView *view = queue[index];
        if ([self isLabelView:view]) { [self decorateTag:view]; continue; }
        if (![view isKindOfClass:UIImageView.class] && ![view isKindOfClass:UILabel.class] && ![view isKindOfClass:UIVisualEffectView.class])
            [queue addObjectsFromArray:view.subviews];
    }
}

@end
