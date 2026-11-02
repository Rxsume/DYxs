//
//  DKXSBatch3cAvatar.xm
//  DYxs — 第 3 批 staging（尚未并入 DYxs 源码）
//  移植自上游 Wtrwx/DYYY（head 49867e1，2026-10-25）DYYY.xm，类/函数前缀 DYYY -> DKXS，
//  设置键 DYYY* -> DKXS*。抖音类名、ivar 名、accessibilityLabel 文案保持原样。
//  本文件不 import 上游 AwemeHeaders.h；只用 UIKit + objc/runtime + 最小前置声明。
//  详见同目录 REPORT.md（冲突核查、删减说明、布局建议）。
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 最小接口声明：以下被 hook 的类在本文件内读写 UIView/NSObject 成员（hidden、alpha、superview、subviews、tag、window 等）或调用同文件 %new 方法，
// 原先只有 Logos 前置声明，编译器找不到这些成员；基类按视图身份声明为 UIView（模型类为 NSObject），不 import DouyinHeaders。
@interface AWEAdAvatarView : UIView
@end
@interface AWEHotSpotBlurView : UIView
@end
@interface AWEPlayInteractionElementMaskView : UIView
@end
@interface AWEPlayInteractionStaticFollowAnimationView : UIView
@end
@interface LOTAnimationView : UIView
@end

#define DKXSGetBool(key) [[NSUserDefaults standardUserDefaults] boolForKey:key]

static id DKXSAvatarObjectForSelector(id object, SEL selector) {
    if (!object || !selector || ![object respondsToSelector:selector]) {
        return nil;
    }
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (signature.numberOfArguments != 2 || signature.methodReturnType[0] != '@') {
        return nil;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    @try {
        return [object performSelector:selector];
    } @catch (__unused NSException *exception) {
        // 私有 getter 在旧版或初始化阶段不可用时，跳过当前附加视图。
        return nil;
    }
#pragma clang diagnostic pop
}

static UIView *DKXSAvatarViewForSelector(id object, SEL selector) {
    id value = DKXSAvatarObjectForSelector(object, selector);
    return [value isKindOfClass:[UIView class]] ? value : nil;
}

static char kDKXSAvatarFollowApplyingKey;
static char kDKXSAvatarFollowDeferredApplyKey;
static char kDKXSAvatarFollowScopeViewKey;
static char kDKXSAvatarActionHiddenViewKey;
static char kDKXSAvatarActionRemovedViewKey;
static char kDKXSAvatarActionChromeViewKey;
static char kDKXSAvatarActionHiddenLayerKey;
static char kDKXSAvatarActionChromeLayerKey;
static char kDKXSAvatarSurroundingHiddenViewKey;

static BOOL DKXSAvatarFollowOptionsEnabled(void) {
    return DKXSGetBool(@"DKXSHideLOTAnimationView") || DKXSGetBool(@"DKXSHideFollowPromptView");
}

static BOOL DKXSShouldForceHideAvatarActionLayer(CALayer *layer) {
    return layer && objc_getAssociatedObject(layer, &kDKXSAvatarActionHiddenLayerKey) && DKXSAvatarFollowOptionsEnabled();
}

static BOOL DKXSShouldClearAvatarActionLayer(CALayer *layer) {
    if (!layer || (!objc_getAssociatedObject(layer, &kDKXSAvatarActionChromeLayerKey) &&
                   !objc_getAssociatedObject(layer, &kDKXSAvatarActionHiddenLayerKey))) {
        return NO;
    }
    return DKXSAvatarFollowOptionsEnabled();
}

static void DKXSMarkAvatarActionLayerHidden(CALayer *layer) {
    if (!layer) {
        return;
    }

    objc_setAssociatedObject(layer, &kDKXSAvatarActionHiddenLayerKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    layer.hidden = YES;
    for (CALayer *sublayer in [layer.sublayers copy]) {
        DKXSMarkAvatarActionLayerHidden(sublayer);
    }
}

static void DKXSMarkAvatarActionLayerChrome(CALayer *layer) {
    if (!layer) {
        return;
    }

    objc_setAssociatedObject(layer, &kDKXSAvatarActionChromeLayerKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    layer.contents = nil;
    layer.opaque = NO;
    layer.backgroundColor = UIColor.clearColor.CGColor;
    layer.borderWidth = 0.0;
    layer.borderColor = UIColor.clearColor.CGColor;
    layer.shadowOpacity = 0.0;
    layer.shadowColor = UIColor.clearColor.CGColor;
    if ([layer isKindOfClass:[CAShapeLayer class]]) {
        CAShapeLayer *shapeLayer = (CAShapeLayer *)layer;
        shapeLayer.fillColor = UIColor.clearColor.CGColor;
        shapeLayer.strokeColor = UIColor.clearColor.CGColor;
    }

    for (CALayer *sublayer in [layer.sublayers copy]) {
        DKXSMarkAvatarActionLayerHidden(sublayer);
    }
}

static void DKXSPrepareAvatarActionSublayer(CALayer *parentLayer, CALayer *sublayer) {
    if (!parentLayer || !sublayer) {
        return;
    }

    BOOL isSuppressedTree = objc_getAssociatedObject(parentLayer, &kDKXSAvatarActionChromeLayerKey) ||
                            objc_getAssociatedObject(parentLayer, &kDKXSAvatarActionHiddenLayerKey);
    if (isSuppressedTree && DKXSAvatarFollowOptionsEnabled()) {
        DKXSMarkAvatarActionLayerHidden(sublayer);
    }
}

static void DKXSMarkAvatarActionViewHidden(UIView *view) {
    if (!view) {
        return;
    }

    objc_setAssociatedObject(view, &kDKXSAvatarActionHiddenViewKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!view.hidden) view.hidden = YES;
}

static BOOL DKXSShouldForceAvatarActionViewHidden(UIView *view) {
    if (!view) {
        return NO;
    }

    BOOL hideVisual = objc_getAssociatedObject(view, &kDKXSAvatarActionHiddenViewKey) != nil;
    BOOL removeView = objc_getAssociatedObject(view, &kDKXSAvatarActionRemovedViewKey) != nil;
    if (!hideVisual && !removeView) {
        return NO;
    }
    return (hideVisual && DKXSAvatarFollowOptionsEnabled()) || (removeView && DKXSGetBool(@"DKXSHideFollowPromptView"));
}

static BOOL DKXSShouldClearAvatarActionViewChrome(UIView *view) {
    return view && objc_getAssociatedObject(view, &kDKXSAvatarActionChromeViewKey) && DKXSGetBool(@"DKXSHideLOTAnimationView");
}

static void DKXSHideAvatarVisualForSelector(id object, SEL selector) {
    UIView *view = DKXSAvatarViewForSelector(object, selector);
    if (view) {
        view.hidden = YES;
    }
}

static void DKXSMarkAvatarSurroundingViewHidden(UIView *view) {
    if (!view) {
        return;
    }

    objc_setAssociatedObject(view, &kDKXSAvatarSurroundingHiddenViewKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!view.hidden) view.hidden = YES;
    if (view.userInteractionEnabled) view.userInteractionEnabled = NO;
}

static BOOL DKXSShouldForceAvatarSurroundingViewHidden(UIView *view) {
    return view && objc_getAssociatedObject(view, &kDKXSAvatarSurroundingHiddenViewKey) && DKXSGetBool(@"DKXSHideAvatarButton");
}

static void DKXSHideAvatarSurroundingVisualForSelector(id object, SEL selector) {
    UIView *view = DKXSAvatarViewForSelector(object, selector);
    DKXSMarkAvatarSurroundingViewHidden(view);
}

static void DKXSApplyAvatarSurroundingSettingsForOwner(id owner) {
    if (!owner || !DKXSGetBool(@"DKXSHideAvatarButton")) {
        return;
    }

    for (NSString *selectorName in @[
             @"colorRingView",
             @"storyRingView",
             @"story25RingView",
             @"decorationView",
             @"avatarDecorationView",
             @"avatarPendantView",
             @"avatarLiveMarkView",
             @"liveMarkView",
             @"avatarLiveTagView",
             @"liveTagView",
         ]) {
        DKXSHideAvatarSurroundingVisualForSelector(owner, NSSelectorFromString(selectorName));
    }
}

static void DKXSRemoveAvatarView(UIView *view) {
    if (!view) {
        return;
    }
    objc_setAssociatedObject(view, &kDKXSAvatarActionRemovedViewKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!view.hidden) view.hidden = YES;
    if (view.userInteractionEnabled) view.userInteractionEnabled = NO;
}

static void DKXSRemoveAvatarViewForSelector(id object, SEL selector) {
    UIView *view = DKXSAvatarViewForSelector(object, selector);
    DKXSRemoveAvatarView(view);
}

static void DKXSHideAvatarFollowLayerContents(UIView *view) {
    if (!view) {
        return;
    }
    objc_setAssociatedObject(view, &kDKXSAvatarActionChromeViewKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.backgroundColor = UIColor.clearColor;
    view.opaque = NO;
    DKXSMarkAvatarActionLayerChrome(view.layer);
}

static void DKXSClearAvatarActionLayerChrome(CALayer *layer) {
    DKXSMarkAvatarActionLayerChrome(layer);
}

static void DKXSClearAvatarActionSubviewChrome(UIView *view) {
    if (!view) {
        return;
    }

    objc_setAssociatedObject(view, &kDKXSAvatarActionChromeViewKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.backgroundColor = UIColor.clearColor;
    view.opaque = NO;
    DKXSClearAvatarActionLayerChrome(view.layer);

    for (UIView *subview in [view.subviews copy]) {
        DKXSClearAvatarActionSubviewChrome(subview);
    }
}

static void DKXSClearAvatarActionViewChrome(UIView *view) {
    if (!view) {
        return;
    }

    objc_setAssociatedObject(view, &kDKXSAvatarActionChromeViewKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.backgroundColor = UIColor.clearColor;
    view.opaque = NO;
    DKXSClearAvatarActionLayerChrome(view.layer);

    for (UIView *subview in [view.subviews copy]) {
        DKXSClearAvatarActionSubviewChrome(subview);
    }
}

static BOOL DKXSIsLegacyAvatarFollowAnimationView(UIView *view) {
    Class promptClass = NSClassFromString(@"AWEPlayInteractionFollowPromptView");
    UIView *ancestor = view.superview;
    for (NSInteger depth = 0; ancestor && depth < 6; depth++, ancestor = ancestor.superview) {
        if (promptClass && [ancestor isKindOfClass:promptClass]) {
            return YES;
        }
    }
    return NO;
}

static BOOL DKXSHideAvatarFollowIconInView(UIView *view) {
    if (!view) {
        return NO;
    }

    NSString *className = NSStringFromClass(view.class);
    if ([className isEqualToString:@"LOTAnimationView"]) {
        DKXSHideAvatarFollowLayerContents(view);
        return YES;
    }

    if ([className isEqualToString:@"AWEPlayInteractionStaticFollowAnimationView"]) {
        BOOL foundIcon = NO;
        for (NSString *selectorName in @[ @"plusImageView", @"tickImageView" ]) {
            UIView *iconView = DKXSAvatarViewForSelector(view, NSSelectorFromString(selectorName));
            if (iconView) {
                DKXSMarkAvatarActionViewHidden(iconView);
                foundIcon = YES;
            }
        }
        if (!foundIcon) {
            DKXSHideAvatarFollowLayerContents(view);
        }
        return YES;
    }

    BOOL foundIcon = NO;
    for (UIView *subview in view.subviews) {
        foundIcon = DKXSHideAvatarFollowIconInView(subview) || foundIcon;
    }
    return foundIcon;
}

static BOOL DKXSIsAvatarFollowContainerView(UIView *view) {
    NSString *className = NSStringFromClass(view.class);
    return [className containsString:@"Follow"] || [className containsString:@"follow"] ||
           [className containsString:@"Prompt"] || [className containsString:@"Add"] ||
           [className containsString:@"SendMessage"] || [className containsString:@"sendMessage"] ||
           [className containsString:@"SendMsg"] || [className containsString:@"sendMsg"] ||
           [className containsString:@"EnterStore"] || [className containsString:@"enterStore"] ||
           [className containsString:@"LinkIcon"] || [className containsString:@"linkIcon"];
}

static BOOL DKXSIsSmallAvatarFollowBadgeView(UIView *view) {
    CGFloat width = CGRectGetWidth(view.bounds);
    CGFloat height = CGRectGetHeight(view.bounds);
    return width > 0.0 && height > 0.0 && width <= 52.0 && height <= 52.0;
}

static UIView *DKXSAvatarFollowRemovalTargetForView(UIView *view, UIView *rootView) {
    UIView *target = view;
    UIView *ancestor = view.superview;
    while (ancestor && ancestor != rootView) {
        if (DKXSIsAvatarFollowContainerView(ancestor) || DKXSIsSmallAvatarFollowBadgeView(ancestor)) {
            target = ancestor;
            ancestor = ancestor.superview;
            continue;
        }
        break;
    }
    return target;
}

static BOOL DKXSHideAvatarAuxiliaryActionVisualsInView(UIView *view) {
    if (!view) {
        return NO;
    }

    NSString *className = NSStringFromClass(view.class);
    BOOL isActionVisual = [view isKindOfClass:[UIImageView class]] ||
                          [className containsString:@"GuideAnimation"] ||
                          [className containsString:@"SendMessageImage"] ||
                          [className containsString:@"SendMsgImage"] ||
                          [className containsString:@"EnterStoreImage"] ||
                          [className containsString:@"LinkIcon"];
    if (isActionVisual) {
        DKXSMarkAvatarActionViewHidden(view);
        return YES;
    }

    BOOL foundVisual = NO;
    for (UIView *subview in [view.subviews copy]) {
        foundVisual = DKXSHideAvatarAuxiliaryActionVisualsInView(subview) || foundVisual;
    }
    return foundVisual;
}

static NSArray<NSArray<NSString *> *> *DKXSAvatarAuxiliaryActionSelectorGroups(void) {
    return @[
        @[ @"sendMessageView", @"avatarSendMessageImageView", @"sendMessageGuideView" ],
        @[ @"enterStoreView", @"avatarEnterStoreImageView", @"enterStoreGuideView" ],
        @[ @"linkIconContainerView", @"userAvatarLinkIcon" ],
    ];
}

static BOOL DKXSApplyAvatarAuxiliaryActionSettingsForOwner(id owner) {
    BOOL hidePlus = DKXSGetBool(@"DKXSHideLOTAnimationView");
    BOOL removePlus = DKXSGetBool(@"DKXSHideFollowPromptView");
    if (!hidePlus && !removePlus) {
        return NO;
    }

    BOOL handled = NO;
    for (NSArray<NSString *> *selectorGroup in DKXSAvatarAuxiliaryActionSelectorGroups()) {
        UIView *containerView = DKXSAvatarViewForSelector(owner, NSSelectorFromString(selectorGroup.firstObject));
        NSMutableArray<UIView *> *visualViews = [NSMutableArray array];
        for (NSUInteger index = 1; index < selectorGroup.count; index++) {
            UIView *visualView = DKXSAvatarViewForSelector(owner, NSSelectorFromString(selectorGroup[index]));
            if (visualView) {
                [visualViews addObject:visualView];
            }
        }

        if (removePlus) {
            UIView *fallbackVisual = visualViews.firstObject;
            UIView *removalTarget = containerView ?: DKXSAvatarFollowRemovalTargetForView(fallbackVisual, nil);
            DKXSRemoveAvatarView(removalTarget);
            for (UIView *visualView in visualViews) {
                DKXSRemoveAvatarView(visualView);
            }
            handled = (removalTarget || visualViews.count > 0) || handled;
            continue;
        }

        for (UIView *visualView in visualViews) {
            visualView.hidden = YES;
            handled = YES;
        }
        if (containerView) {
            DKXSClearAvatarActionViewChrome(containerView);
            BOOL foundVisual = DKXSHideAvatarAuxiliaryActionVisualsInView(containerView);
            if (!foundVisual && visualViews.count == 0) {
                DKXSHideAvatarFollowLayerContents(containerView);
            }
            handled = YES;
        }
    }
    return handled;
}

static BOOL DKXSApplyAvatarFollowSettingsInView(UIView *view, UIView *rootView) {
    if (!view) {
        return NO;
    }

    BOOL hidePlus = DKXSGetBool(@"DKXSHideLOTAnimationView");
    BOOL removePlus = DKXSGetBool(@"DKXSHideFollowPromptView");
    if (!hidePlus && !removePlus) {
        return NO;
    }

    // 记录已识别的头像操作树，便于异步追加子视图时立即再识别。
    objc_setAssociatedObject(view, &kDKXSAvatarFollowScopeViewKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSString *className = NSStringFromClass(view.class);
    BOOL isAvatarView = [className isEqualToString:@"AWEPlayInteractionUserAvatarView"];
    BOOL isStaticFollowView = [className isEqualToString:@"AWEPlayInteractionStaticFollowAnimationView"];
    BOOL isLegacyFollowAnimation = [className isEqualToString:@"LOTAnimationView"] && DKXSIsLegacyAvatarFollowAnimationView(view);
    BOOL isLegacyPromptContainer = [className isEqualToString:@"AWEPlayInteractionFollowPromptView"];
    BOOL handled = NO;

    if (isAvatarView) {
        handled = DKXSApplyAvatarAuxiliaryActionSettingsForOwner(view) || handled;
    }

    if (isStaticFollowView || isLegacyFollowAnimation) {
        if (removePlus) {
            DKXSRemoveAvatarView(DKXSAvatarFollowRemovalTargetForView(view, rootView));
        } else {
            DKXSHideAvatarFollowIconInView(view);
        }
        handled = YES;
    } else if (removePlus && isLegacyPromptContainer) {
        view.hidden = YES;
        view.userInteractionEnabled = NO;
        handled = YES;
    }

    for (UIView *subview in [view.subviews copy]) {
        handled = DKXSApplyAvatarFollowSettingsInView(subview, rootView) || handled;
    }
    return handled;
}

static void DKXSApplyAvatarFollowSettingsForContext(id context) {
    UIView *elementView = DKXSAvatarViewForSelector(context, NSSelectorFromString(@"elementView"));
    if (elementView) {
        DKXSApplyAvatarFollowSettingsInView(elementView, elementView);
    }
}

static void DKXSApplyAvatarFollowPromptSettings(id owner) {
    BOOL hidePlus = DKXSGetBool(@"DKXSHideLOTAnimationView");
    BOOL removePlus = DKXSGetBool(@"DKXSHideFollowPromptView");
    if (!owner || (!hidePlus && !removePlus) || objc_getAssociatedObject(owner, &kDKXSAvatarFollowApplyingKey)) {
        return;
    }

    // 必须先建立屏障：旧版头像 getter 会同步触发配置回调，再进入本方法。
    objc_setAssociatedObject(owner, &kDKXSAvatarFollowApplyingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        for (NSString *selectorName in @[ @"followAnimationView", @"unfollowAnimationView", @"staticFollowAnimationView" ]) {
            UIView *animationView = DKXSAvatarViewForSelector(owner, NSSelectorFromString(selectorName));
            if (!animationView) {
                continue;
            }
            if (removePlus) {
                DKXSRemoveAvatarView(DKXSAvatarFollowRemovalTargetForView(animationView, nil));
            } else {
                DKXSHideAvatarFollowIconInView(animationView);
            }
        }

        UIView *followAddView = DKXSAvatarViewForSelector(owner, NSSelectorFromString(@"followAddView"));
        if (removePlus) {
            DKXSRemoveAvatarView(followAddView);
        } else {
            BOOL foundIcon = DKXSHideAvatarFollowIconInView(followAddView);
            if (hidePlus && followAddView) {
                DKXSClearAvatarActionViewChrome(followAddView);
                if (!foundIcon) {
                    DKXSHideAvatarFollowLayerContents(followAddView);
                }
            }
        }

        UIView *followPromptView = DKXSAvatarViewForSelector(owner, NSSelectorFromString(@"followPromptView"));
        if (removePlus) {
            DKXSRemoveAvatarView(followPromptView);
        } else {
            DKXSApplyAvatarFollowSettingsInView(followPromptView, followPromptView);
        }

        DKXSApplyAvatarAuxiliaryActionSettingsForOwner(owner);

        if ([owner isKindOfClass:[UIView class]]) {
            DKXSApplyAvatarFollowSettingsInView((UIView *)owner, (UIView *)owner);
        } else if ([owner isKindOfClass:[UIViewController class]]) {
            DKXSApplyAvatarFollowSettingsInView(((UIViewController *)owner).viewIfLoaded, ((UIViewController *)owner).viewIfLoaded);
        }
        DKXSApplyAvatarFollowSettingsForContext(DKXSAvatarObjectForSelector(owner, NSSelectorFromString(@"userAvatarContext")));
    } @finally {
        objc_setAssociatedObject(owner, &kDKXSAvatarFollowApplyingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void DKXSApplyAvatarFollowPromptSettingsWithRetry(id owner) {
    if (!owner || !DKXSAvatarFollowOptionsEnabled()) return;
    if (!NSThread.isMainThread) {
        __weak id weakOwner = owner;
        dispatch_async(dispatch_get_main_queue(), ^{ DKXSApplyAvatarFollowPromptSettingsWithRetry(weakOwner); });
        return;
    }
    // 重入回调连延迟任务也不能再登记，避免原生 getter 反复初始化头像。
    if (objc_getAssociatedObject(owner, &kDKXSAvatarFollowApplyingKey)) return;
    DKXSApplyAvatarFollowPromptSettings(owner);
    if (objc_getAssociatedObject(owner, &kDKXSAvatarFollowDeferredApplyKey)) return;

    objc_setAssociatedObject(owner, &kDKXSAvatarFollowDeferredApplyKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak id weakOwner = owner;
    dispatch_async(dispatch_get_main_queue(), ^{
        id target = weakOwner;
        if (!target) return;
        DKXSApplyAvatarFollowPromptSettings(target);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            id currentOwner = weakOwner;
            if (!currentOwner) return;
            DKXSApplyAvatarFollowPromptSettings(currentOwner);
            objc_setAssociatedObject(currentOwner, &kDKXSAvatarFollowDeferredApplyKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        });
    });
}

// 隐藏头像加号和透明

%hook AWEFeedLiveMarkView
- (void)setHidden:(BOOL)hidden {
    if (DKXSGetBool(@"DKXSHideAvatarLive") || DKXSGetBool(@"DKXSHideAvatarButton")) {
        hidden = YES;
    }

    %orig(hidden);
}
%end

%hook AWEAdAvatarView
- (void)layoutSubviews {
    %orig;

    // 检查是否需要隐藏头像
    if (DKXSGetBool(@"DKXSHideAvatarButton")) {
        self.hidden = YES;
        return;
    }
}
%end

%hook LOTAnimationView
- (void)layoutSubviews {
    %orig;
    // 旧版加号动画可能被额外容器包裹，沿父视图向上识别关注提示视图。
    if (DKXSIsLegacyAvatarFollowAnimationView(self)) {
        // 检查是否需要隐藏加号
        if (DKXSAvatarFollowOptionsEnabled()) {
            if (DKXSGetBool(@"DKXSHideFollowPromptView")) {
                DKXSRemoveAvatarView(DKXSAvatarFollowRemovalTargetForView(self, nil));
            } else {
                DKXSHideAvatarFollowLayerContents(self);
            }
            DKXSApplyAvatarFollowPromptSettingsWithRetry(self.superview ?: self);
            return;
        }
    }
}
%end

%hook AWEPlayInteractionStaticFollowAnimationView
- (void)layoutSubviews {
    %orig;
    if (DKXSAvatarFollowOptionsEnabled()) {
        DKXSApplyAvatarFollowSettingsInView((UIView *)self, nil);
        DKXSApplyAvatarFollowPromptSettingsWithRetry(self.superview ?: self);
    }
}
%end

%hook AWEPlayInteractionFollowPromptView

- (void)layoutSubviews {
    %orig;

    if (DKXSAvatarFollowOptionsEnabled()) {
        DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
        if (DKXSGetBool(@"DKXSHideFollowPromptView")) {
            return;
        }
    }
}

- (void)didMoveToWindow {
    %orig;

    if (DKXSAvatarFollowOptionsEnabled()) {
        DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
    }
}

- (void)didMoveToSuperview {
    %orig;

    if (DKXSAvatarFollowOptionsEnabled()) {
        DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
        return;
    }
}

%end

%hook AWEPlayInteractionUserAvatarView
- (void)layoutSubviews {
    %orig;

    if (DKXSGetBool(@"DKXSHideAvatarButton")) {
        DKXSHideAvatarVisualForSelector(self, NSSelectorFromString(@"userAvatarView"));
        DKXSApplyAvatarSurroundingSettingsForOwner(self);
    }

    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)didMoveToWindow {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)didMoveToSuperview {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)updateRightContainerElement {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)p_resetFollowAnimation {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)playFollowAnimation:(id)completion {
    %orig(completion);
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)playUnFollowAnimation {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)changeSendMessageViewWithFlag:(BOOL)flag {
    %orig(flag);
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}
%end

%hook AWEPlayInteractionUserAvatarFollowPromptController
- (void)onFollowViewClicked:(UITapGestureRecognizer *)gesture {
    if (DKXSGetBool(@"DKXSHideFollowPromptView")) {
        return;
    }

    %orig(gesture);
}

- (void)onUnFollowViewClicked:(id)arg1 {
    if (DKXSGetBool(@"DKXSHideFollowPromptView")) {
        return;
    }
    %orig(arg1);
}

- (void)followPromptViewClicked:(id)arg1 {
    if (DKXSGetBool(@"DKXSHideFollowPromptView")) {
        return;
    }
    %orig(arg1);
}

- (void)layoutElementView {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (BOOL)shouldShowFollowAddWithModel:(id)arg1 {
    if (DKXSGetBool(@"DKXSHideFollowPromptView")) {
        return NO;
    }
    return %orig(arg1);
}

- (BOOL)shouldShowSpecialFollowWithModel:(id)arg1 {
    if (DKXSGetBool(@"DKXSHideFollowPromptView")) {
        return NO;
    }
    return %orig(arg1);
}

- (void)showFollowAddView:(BOOL)show {
    %orig(show);
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)viewController_willDisplay {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)viewController_viewDidAppear {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)updateFollowStatus {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)followStatusChanged:(id)arg1 {
    %orig(arg1);
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)playFollowAnimation {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)playFollowAnimation:(id)completion {
    %orig(completion);
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)playUnFollowAnimation {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)_ensureStaticFollowAnimationView {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}
%end

%hook AWEPlayInteractionUserAvatarMainBusinessController
- (void)layoutElementView {
    %orig;
    if (DKXSGetBool(@"DKXSHideAvatarButton")) {
        DKXSHideAvatarVisualForSelector(self, NSSelectorFromString(@"avatarPicView"));
        id context = DKXSAvatarObjectForSelector(self, NSSelectorFromString(@"userAvatarContext"));
        DKXSHideAvatarVisualForSelector(context, NSSelectorFromString(@"avatarPicView"));
        DKXSApplyAvatarSurroundingSettingsForOwner(self);
    }
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}
%end

%hook AWEPlayInteractionUserAvatarOptElementElement
- (void)layoutElementView {
    %orig;
    if (DKXSGetBool(@"DKXSHideAvatarButton")) {
        id context = DKXSAvatarObjectForSelector(self, NSSelectorFromString(@"userAvatarContext"));
        DKXSHideAvatarVisualForSelector(context, NSSelectorFromString(@"avatarPicView"));
        DKXSApplyAvatarSurroundingSettingsForOwner(self);
    }
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)viewController_willDisplay {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)viewController_viewDidAppear {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)setAppear:(BOOL)appear {
    %orig(appear);
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}
%end

%hook AWEPlayInteractionUserAvatarStoryController
- (void)layoutElementView {
    %orig;
    DKXSApplyAvatarSurroundingSettingsForOwner(self);
}

- (void)showStory25RingView {
    %orig;
    DKXSApplyAvatarSurroundingSettingsForOwner(self);
}
%end

%hook AWEPlayInteractionUserAvatarDecorationController
- (void)layoutElementView {
    %orig;
    DKXSApplyAvatarSurroundingSettingsForOwner(self);
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)viewController_willDisplay {
    %orig;
    DKXSApplyAvatarSurroundingSettingsForOwner(self);
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)setDecorationStyle:(long long)style {
    %orig(style);
    DKXSApplyAvatarSurroundingSettingsForOwner(self);
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}
%end

%hook AWEPlayInteractionUserAvatarSendMessageController
- (void)controllerViewDidLayout {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)controllerStartConfigAvatarView:(id)view {
    %orig(view);
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
    DKXSApplyAvatarFollowPromptSettingsWithRetry(view);
}

- (void)controllerWillDisplay {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)controllerPlay {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)controllerReset {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)updateSendMessageView:(BOOL)show {
    %orig(show);
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)p_updateSendMessageView:(BOOL)show {
    %orig(show);
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)p_showSendMessageView:(id)view shouldShowSendMessageView:(BOOL)show animated:(BOOL)animated completion:(id)completion {
    %orig(view, show, animated, completion);
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
    DKXSApplyAvatarFollowPromptSettingsWithRetry(view);
}

- (BOOL)shouldShowSendMessageView {
    if (DKXSGetBool(@"DKXSHideFollowPromptView")) {
        return NO;
    }
    return %orig;
}

- (BOOL)shouldShowSendMessageGuideAnimation {
    if (DKXSAvatarFollowOptionsEnabled()) {
        return NO;
    }
    return %orig;
}

- (void)playSendMessageGuideAnimationIfNeeded {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)onSendMessageViewClicked:(id)arg1 {
    if (DKXSGetBool(@"DKXSHideFollowPromptView")) {
        return;
    }
    %orig(arg1);
}
%end

%hook AWEPlayInteractionUserAvatarSendMsgController
- (void)layoutElementView {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)viewController_willDisplay {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)viewController_viewDidDisappear {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)play {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)reset {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)changeSendMessageViewWithFlag:(BOOL)flag {
    %orig(flag);
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)showSendMessageView:(id)view show:(BOOL)show animated:(BOOL)animated completion:(id)completion {
    %orig(view, show, animated, completion);
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
    DKXSApplyAvatarFollowPromptSettingsWithRetry(view);
}

- (void)showSendMessageViewWithAnimation:(BOOL)animated {
    %orig(animated);
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (BOOL)shouldShowSendMessageView:(id)arg1 {
    if (DKXSGetBool(@"DKXSHideFollowPromptView")) {
        return NO;
    }
    return %orig(arg1);
}

- (BOOL)shouldShowSendMessageGuideAnimation {
    if (DKXSAvatarFollowOptionsEnabled()) {
        return NO;
    }
    return %orig;
}

- (void)updateSendMsgWithFollowShow:(BOOL)show animation:(BOOL)animated {
    %orig(show, animated);
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)handleAvatarFollowStatusChange:(id)arg1 {
    %orig(arg1);
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)playSendMessageGuideAnimationIfNeeded {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)onSendMessageViewClicked:(id)arg1 {
    if (DKXSGetBool(@"DKXSHideFollowPromptView")) {
        return;
    }
    %orig(arg1);
}
%end

%hook AWEPlayInteractionUserAvatarEnterStoreController
- (void)layoutElementView {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)viewController_willDisplay {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)viewController_viewDidAppear {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)play {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)reset {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)showEnterStore {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)hideEnterStore {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (BOOL)shouldShowEnterStoreView {
    if (DKXSGetBool(@"DKXSHideFollowPromptView")) {
        return NO;
    }
    return %orig;
}

- (BOOL)shouldShowEnterStoreGuideAnimation {
    if (DKXSAvatarFollowOptionsEnabled()) {
        return NO;
    }
    return %orig;
}

- (void)playEnterStoreGuideAnimationIfNeeded {
    if (DKXSAvatarFollowOptionsEnabled()) {
        DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
        return;
    }
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)handleAvatarFollowStatusChange:(id)arg1 {
    %orig(arg1);
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)onEnterStoreViewClicked:(id)arg1 {
    if (DKXSGetBool(@"DKXSHideFollowPromptView")) {
        return;
    }
    %orig(arg1);
}
%end

%hook AWEPlayInteractionUserAvatarAdLinkController
- (void)layoutElementView {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)reset {
    %orig;
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)updateCommerceHotSplashLinkIconImageIfNeeded:(id)arg1 {
    %orig(arg1);
    DKXSApplyAvatarFollowPromptSettingsWithRetry(self);
}

- (void)onLinkIconContainerViewClicked:(id)arg1 {
    if (DKXSGetBool(@"DKXSHideFollowPromptView")) {
        return;
    }
    %orig(arg1);
}
%end

%hook AWEUserModel

- (NSNumber *)roomID {
	BOOL DKXSHideAvatarLive = DKXSGetBool(@"DKXSHideAvatarLive") || DKXSGetBool(@"DKXSHideAvatarButton");
	if (DKXSHideAvatarLive) {
		return @(0);
	}
	return %orig;
}

%end

%hook AWEUserModel

- (id)storyRing {
	BOOL DKXSHideAvatarButton = DKXSGetBool(@"DKXSHideAvatarButton");
	if (DKXSHideAvatarButton) {
		return nil;
	}
	return %orig;
}

- (void)setStoryRing:(id)ring {
	BOOL DKXSHideAvatarButton = DKXSGetBool(@"DKXSHideAvatarButton");
	if (DKXSHideAvatarButton) {
		%orig(nil);
		return;
	}
	%orig;
}

%end

%hook AWECodeGenStoryRingInfoModel

- (NSArray *)storyRingsModelArray {
	BOOL DKXSHideAvatarButton = DKXSGetBool(@"DKXSHideAvatarButton");
	if (DKXSHideAvatarButton) {
		return @[];
	}
	return %orig;
}

- (void)setStoryRingsModelArray:(NSArray *)array {
	BOOL DKXSHideAvatarButton = DKXSGetBool(@"DKXSHideAvatarButton");
	if (DKXSHideAvatarButton) {
		%orig(@[]);
		return;
	}
	%orig;
}

%end

%hook AWEPlayInteractionElementMaskView
- (void)layoutSubviews {
    if (DKXSGetBool(@"DKXSHideGradient")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook AWEHotSpotBlurView
- (void)layoutSubviews {
    if (DKXSGetBool(@"DKXSHideGradient")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end


%ctor {
    %init;
}
