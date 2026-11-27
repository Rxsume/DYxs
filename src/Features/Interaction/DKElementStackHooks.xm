//
//  DKElementStackHooks.xm
//  DYxs
//
//  播放交互层元素栈的统一布局入口：右侧互动区、左侧昵称文案、长按复制与播放页精简共用一处 layoutSubviews，
//  各自判定是不是自己的栈。新增作用于元素栈的功能在这里追加一行。
//  行内新增子视图时让所在栈重排一次，入口按行的新内容重新应用。
//

#import "DouyinHeaders.h"
#import "DKInfoAppearance.h"
#import "DKInfoLongPressCopy.h"
#import "DKInteractionAppearance.h"
#import "DKPlaybackClean.h"
#import "DKPublishInfo.h"
#import "DKRelatedBarBackground.h"
#import "DKRelatedBarOffset.h"
#import "DKInteractionCollapse.h"

#import <objc/runtime.h>

// 第 5b–5e 批合并段 DKXSElementScale（辅助函数段，粘到 import 区之后）：
// 上游 DYYYUtils firstAvailableViewControllerFromView / containsSubviewOfClass 的本地静态函数等价实现，不新增 import。
static UIViewController *DKXSBatch5RestViewControllerForView(UIView *view) {
    UIResponder *responder = view.nextResponder;
    while (responder && ![responder isKindOfClass:[UIViewController class]]) {
        responder = responder.nextResponder;
    }
    return (UIViewController *)responder;
}

static BOOL DKXSBatch5RestContainsSubviewOfClass(Class cls, UIView *container) {
    if (!cls || !container) return NO;
    for (UIView *subview in container.subviews) {
        if ([subview isKindOfClass:cls]) return YES;
        if (DKXSBatch5RestContainsSubviewOfClass(cls, subview)) return YES;
    }
    return NO;
}

// 上游 layoutSubviews 第二分支：只在 AWEPlayInteractionViewController 内生效。
// 0.6.9.75 性能：左右栈判定按栈缓存（子视图签名变化才重查，不再每次布局递归搜子树），
// 缩放值 1 秒缓存，transform 只在与当前值不同时写。
static char kDKXSElementScaleVerdictKey;
static char kDKXSElementScaleSignatureKey;

static NSUInteger DKXSBatch5RestStackSignature(UIView *stackView) {
    NSArray<UIView *> *subviews = stackView.subviews;
    NSUInteger signature = subviews.count * 1315423911u;
    signature ^= (NSUInteger)(uintptr_t)subviews.firstObject;
    signature ^= ((NSUInteger)(uintptr_t)subviews.lastObject) << 1;
    signature ^= stackView.accessibilityLabel.hash;
    return signature;
}

static CGFloat DKXSBatch5RestCachedScale(NSString *key) {
    static NSMutableDictionary<NSString *, NSNumber *> *cache = nil;
    static NSTimeInterval lastRead = 0;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (!cache) cache = [NSMutableDictionary dictionary];
    if (now - lastRead > 1.0) {
        [cache removeAllObjects];
        lastRead = now;
    }
    NSNumber *cached = cache[key];
    if (cached) return cached.doubleValue;
    NSString *value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    CGFloat scale = value.length > 0 ? [value floatValue] : 0;
    cache[key] = @(scale);
    return scale;
}

static void DKXSBatch5RestApplyElementScale(UIView *stackView) {
    NSUInteger signature = DKXSBatch5RestStackSignature(stackView);
    NSNumber *cachedSignature = objc_getAssociatedObject(stackView, &kDKXSElementScaleSignatureKey);
    NSNumber *cachedVerdict = objc_getAssociatedObject(stackView, &kDKXSElementScaleVerdictKey);
    BOOL isRightStack = NO;
    BOOL isLeftStack = NO;
    if (cachedVerdict && cachedSignature.unsignedIntegerValue == signature) {
        isRightStack = (cachedVerdict.integerValue & 1) != 0;
        isLeftStack = (cachedVerdict.integerValue & 2) != 0;
    } else {
        UIViewController *viewController = DKXSBatch5RestViewControllerForView(stackView);
        Class playVCClass = NSClassFromString(@"AWEPlayInteractionViewController");
        if (!viewController || !playVCClass || ![viewController isKindOfClass:playVCClass]) {
            objc_setAssociatedObject(stackView, &kDKXSElementScaleSignatureKey, @(signature), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(stackView, &kDKXSElementScaleVerdictKey, @0, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return;
        }

        NSString *label = stackView.accessibilityLabel ?: @"";
        BOOL hasAnchor = DKXSBatch5RestContainsSubviewOfClass(NSClassFromString(@"AWEFeedAnchorContainerView"), stackView);
        BOOL hasAvatar = DKXSBatch5RestContainsSubviewOfClass(NSClassFromString(@"AWEPlayInteractionUserAvatarView"), stackView);
        isRightStack = ([label isEqualToString:@"right"] || hasAvatar);
        if (!isRightStack) {
            NSArray *subviews = [stackView.subviews copy];
            for (NSInteger i = (NSInteger)subviews.count - 1; i >= 0; i--) {
                UIView *sub = subviews[i];
                if ([sub respondsToSelector:@selector(elementClassName)]) {
                    NSString *elementClassName = [sub performSelector:@selector(elementClassName)];
                    if ([elementClassName isEqualToString:@"AWEPlayInteractionUserAvatarOptElementElement"]) {
                        isRightStack = YES;
                        break;
                    }
                }
            }
        }
        isLeftStack = ([label isEqualToString:@"left"] || hasAnchor);
        if (!isLeftStack) {
            NSArray *subviews = [stackView.subviews copy];
            for (NSInteger i = (NSInteger)subviews.count - 1; i >= 0; i--) {
                UIView *sub = subviews[i];
                if ([sub respondsToSelector:@selector(elementClassName)]) {
                    NSString *elementClassName = [sub performSelector:@selector(elementClassName)];
                    if ([elementClassName isEqualToString:@"AWEPlayInteractionDescriptionElement"]) {
                        isLeftStack = YES;
                        break;
                    }
                }
            }
        }
        objc_setAssociatedObject(stackView, &kDKXSElementScaleSignatureKey, @(signature), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(stackView, &kDKXSElementScaleVerdictKey,
            @((isRightStack ? 1 : 0) | (isLeftStack ? 2 : 0)), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (isRightStack) {
        CGFloat scale = DKXSBatch5RestCachedScale(@"DKXSElementScale");
        CGAffineTransform desired = CGAffineTransformIdentity;
        if (scale > 0 && scale != 1.0) {
            NSArray *subviews = [stackView.subviews copy];
            CGFloat ty = 0;
            for (UIView *view in subviews) {
                CGFloat viewHeight = view.frame.size.height;
                ty += (viewHeight - viewHeight * scale) / 2;
            }
            CGFloat frameWidth = stackView.frame.size.width;
            CGFloat right_tx = (frameWidth - frameWidth * scale) / 2;
            desired = CGAffineTransformMake(scale, 0, 0, scale, right_tx, ty);
        }
        if (!CGAffineTransformEqualToTransform(stackView.transform, desired)) {
            stackView.transform = desired;
        }
    } else if (isLeftStack) {
        CGFloat scale = DKXSBatch5RestCachedScale(@"DKXSNicknameScale");
        if (scale > 0) {
            CGAffineTransform desired = CGAffineTransformIdentity;
            if (scale != 1.0) {
                NSArray *subviews = [stackView.subviews copy];
                CGFloat ty = 0;
                for (UIView *view in subviews) {
                    CGFloat viewHeight = view.frame.size.height;
                    ty += (viewHeight - viewHeight * scale) / 2;
                }
                CGFloat frameWidth = stackView.frame.size.width;
                CGFloat left_tx = (frameWidth - frameWidth * scale) / 2 - frameWidth * (1 - scale);
                desired = CGAffineTransformMakeScale(scale, scale);
                desired = CGAffineTransformTranslate(desired, left_tx / scale, ty / scale);
            }
            if (!CGAffineTransformEqualToTransform(stackView.transform, desired)) {
                stackView.transform = desired;
            }
        }
    }
}

%hook AWEElementStackView

- (void)layoutSubviews {
    // 行的显隐在布局前落定，栈按最终的可见行排布一次。
    DKPlaybackCleanApplyStack(self);
    %orig;
    DKInteractionAppearanceApplyStack(self);
    DKInfoAppearanceApplyStack(self);
    DKInfoLongPressCopyApplyStack(self);
    DKPublishInfoApplyStack(self);
    DKRelatedBarOffsetApplyStack(self);
    DKRelatedBarBackgroundApplyStack(self);
    DKXSBatch5RestApplyElementScale(self);
    DKInteractionCollapseApplyStack(self);
}

- (NSArray<__kindof UIView *> *)arrangedSubviews {
    NSArray *originalSubviews = %orig;
    UIViewController *viewController = DKXSBatch5RestViewControllerForView(self);
    Class playVCClass = NSClassFromString(@"AWEPlayInteractionViewController");
    if (viewController && playVCClass && [viewController isKindOfClass:playVCClass]) {
        if ([self.accessibilityLabel isEqualToString:@"left"] ||
            DKXSBatch5RestContainsSubviewOfClass(NSClassFromString(@"AWEFeedAnchorContainerView"), self)) {
            NSString *scaleValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSNicknameScale"];
            if (scaleValue.length > 0) {
                CGFloat scale = [scaleValue floatValue];
                self.transform = CGAffineTransformIdentity;
                if (scale > 0 && scale != 1.0) {
                    NSArray *subviews = [self.subviews copy];
                    CGFloat ty = 0;
                    for (UIView *view in subviews) {
                        CGFloat viewHeight = view.frame.size.height;
                        ty += (viewHeight - viewHeight * scale) / 2;
                    }
                    CGFloat frameWidth = self.frame.size.width;
                    CGFloat left_tx = (frameWidth - frameWidth * scale) / 2 - frameWidth * (1 - scale);
                    CGAffineTransform newTransform = CGAffineTransformMakeScale(scale, scale);
                    newTransform = CGAffineTransformTranslate(newTransform, left_tx / scale, ty / scale);
                    self.transform = newTransform;
                }
            }
        }
    }
    return originalSubviews;
}

%end

%hook AWEBaseElementView

// 元素在已有行内换内容时（如解除静音后「取消静音」换成音乐组件）行尺寸不变，抖音不重排栈。
- (void)didAddSubview:(UIView *)subview {
    %orig;
    UIView *stack = self.superview;
    if ([stack isKindOfClass:%c(AWEElementStackView)]) [stack setNeedsLayout];
}

%end
