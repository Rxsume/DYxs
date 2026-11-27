//
//  DKInteractionCollapse.xm
//  功能：右侧互动区随底栏动态收缩 —— 底栏收成圆键时，右侧头像/点赞/评论/收藏/分享
//  一起收进底栏圆键（向圆键位置移动并淡出、不拦截点击），点底栏圆键全部展开。
//  一个键管全部：不再有右侧自建圆键，系统收缩圆键照常显示、照常点按展开，
//  展开时经 DKGlassTabBarPlatterDidShow 同步把右侧按钮带回来。
//
//  位移方式（0.6.9.76 起）：只动元素 center，绝不碰 transform。
//  旧版两代 transform 方案都出过事：63 版把某时刻的 transform 记成基准回写，
//  抖音出现动画的瞬态缩放被固化（元素变小错位）；75 版靠「上次写入值」浮点比对
//  叠加/撤销平移，比对在真机上总被外部改写打断，平移逐轮叠加、元素飞出屏幕缩没。
//  center 方案：收缩时把 center 移到目标位，记下原 center 与写入 center；
//  布局期发现 center 被抖音布局重置回原位就重新移动，发现被移到别处就以新位置
//  为原位重新移动；展开时 center 还是我们写的那份才还原，已被抖音接管就不碰。
//  抖音自己的布局每轮都会把元素放回自然位置，天然兜底，不存在叠加漂移。
//
//  性能：右侧栈判定按栈缓存（子视图签名变化才重查），center/alpha 只在值变化时写。
//

#import "DKInteractionCollapse.h"
#import "DKGlassTabBar.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"

#import <objc/runtime.h>

static BOOL gInteractionCollapsed = NO;
static NSHashTable<UIView *> *gInteractionStacks = nil;
static char kDKInteractionStoredCenterKey;
static char kDKInteractionWrittenCenterKey;
static char kDKInteractionModifiedKey;
static char kDKInteractionRightStackKey;
static char kDKInteractionStackSignatureKey;

static BOOL DKInteractionCollapseEnabled(void) {
    return DKPrefBool(DKKeyInteractionCollapse);
}

static UIViewController *DKInteractionViewControllerForView(UIView *view) {
    UIResponder *responder = view.nextResponder;
    while (responder && ![responder isKindOfClass:[UIViewController class]]) {
        responder = responder.nextResponder;
    }
    return (UIViewController *)responder;
}

static BOOL DKInteractionContainsClass(Class cls, UIView *container) {
    if (!cls || !container) return NO;
    if ([container isKindOfClass:cls]) return YES;
    for (UIView *subview in container.subviews) {
        if (DKInteractionContainsClass(cls, subview)) return YES;
    }
    return NO;
}

// 与 DKXSBatch5RestApplyElementScale 同款判据：右侧栈 = label "right" 或带头像元素，
// 且位于播放交互控制器内。
static BOOL DKInteractionIsRightStackUncached(UIView *stack) {
    UIViewController *viewController = DKInteractionViewControllerForView(stack);
    Class playVCClass = NSClassFromString(@"AWEPlayInteractionViewController");
    if (!viewController || !playVCClass || ![viewController isKindOfClass:playVCClass]) return NO;
    if ([stack.accessibilityLabel isEqualToString:@"right"]) return YES;
    if (DKInteractionContainsClass(NSClassFromString(@"AWEPlayInteractionUserAvatarView"), stack)) return YES;
    for (UIView *sub in stack.subviews) {
        if ([sub respondsToSelector:@selector(elementClassName)]) {
            NSString *name = [sub performSelector:@selector(elementClassName)];
            if ([name isEqualToString:@"AWEPlayInteractionUserAvatarOptElementElement"]) return YES;
        }
    }
    return NO;
}

static NSUInteger DKInteractionStackSignature(UIView *stack) {
    NSArray<UIView *> *subviews = stack.subviews;
    NSUInteger signature = subviews.count * 1315423911u;
    signature ^= (NSUInteger)(uintptr_t)subviews.firstObject;
    signature ^= ((NSUInteger)(uintptr_t)subviews.lastObject) << 1;
    return signature;
}

static BOOL DKInteractionIsRightStack(UIView *stack) {
    NSUInteger signature = DKInteractionStackSignature(stack);
    NSNumber *cachedSignature = objc_getAssociatedObject(stack, &kDKInteractionStackSignatureKey);
    NSNumber *cached = objc_getAssociatedObject(stack, &kDKInteractionRightStackKey);
    if (cached && cachedSignature.unsignedIntegerValue == signature) return cached.boolValue;
    BOOL result = DKInteractionIsRightStackUncached(stack);
    objc_setAssociatedObject(stack, &kDKInteractionStackSignatureKey, @(signature), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(stack, &kDKInteractionRightStackKey, @(result), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return result;
}

#pragma mark - center 位移

static BOOL DKInteractionCenterClose(CGPoint a, CGPoint b) {
    return fabs(a.x - b.x) < 0.5 && fabs(a.y - b.y) < 0.5;
}

// 收缩目标位：底栏圆键中心（换算到栈坐标）；圆键不可用时退回向右滑出。
static CGPoint DKInteractionCollapseTarget(UIView *stack, CGPoint stored) {
    UIView *platter = DKGlassTabBarCollapsePlatter();
    if (platter && platter.window) {
        CGPoint centerInWindow = [platter convertPoint:CGPointMake(CGRectGetMidX(platter.bounds), CGRectGetMidY(platter.bounds)) toView:nil];
        return [stack convertPoint:centerInWindow fromView:nil];
    }
    return CGPointMake(stored.x + CGRectGetWidth(stack.bounds) + 24.0, stored.y);
}

// 收缩落定：确保元素 center 在目标位（布局期兜底，即时落定）。
static void DKInteractionSettleCollapsed(UIView *element, UIView *stack) {
    NSValue *storedValue = objc_getAssociatedObject(element, &kDKInteractionStoredCenterKey);
    NSValue *writtenValue = objc_getAssociatedObject(element, &kDKInteractionWrittenCenterKey);
    CGPoint current = element.center;
    if (writtenValue && DKInteractionCenterClose(current, writtenValue.CGPointValue)) return;
    CGPoint stored;
    if (storedValue && DKInteractionCenterClose(current, storedValue.CGPointValue)) {
        stored = storedValue.CGPointValue;
    } else {
        // 抖音把元素放到了新位置（或首次收缩）：以当前为原位。
        stored = current;
    }
    CGPoint written = DKInteractionCollapseTarget(stack, stored);
    objc_setAssociatedObject(element, &kDKInteractionStoredCenterKey,
        [NSValue valueWithCGPoint:stored], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(element, &kDKInteractionWrittenCenterKey,
        [NSValue valueWithCGPoint:written], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    element.center = written;
}

static void DKInteractionRestoreElement(UIView *element) {
    NSValue *storedValue = objc_getAssociatedObject(element, &kDKInteractionStoredCenterKey);
    NSValue *writtenValue = objc_getAssociatedObject(element, &kDKInteractionWrittenCenterKey);
    if (storedValue && writtenValue && DKInteractionCenterClose(element.center, writtenValue.CGPointValue)) {
        element.center = storedValue.CGPointValue;
    }
    objc_setAssociatedObject(element, &kDKInteractionStoredCenterKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(element, &kDKInteractionWrittenCenterKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    element.alpha = 1.0;
    element.userInteractionEnabled = YES;
    objc_setAssociatedObject(element, &kDKInteractionModifiedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DKInteractionRestoreStack(UIView *stack) {
    for (UIView *element in stack.subviews) {
        if ([objc_getAssociatedObject(element, &kDKInteractionModifiedKey) boolValue]) {
            DKInteractionRestoreElement(element);
        }
    }
    objc_setAssociatedObject(stack, &kDKInteractionModifiedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void DKInteractionCollapseApplyStack(UIView *stack) {
    if (!stack) return;
    BOOL stackModified = [objc_getAssociatedObject(stack, &kDKInteractionModifiedKey) boolValue];
    if (!DKInteractionCollapseEnabled()) {
        if (stackModified) DKInteractionRestoreStack(stack);
        return;
    }
    if (!DKInteractionIsRightStack(stack)) return;
    if (!gInteractionStacks) gInteractionStacks = [NSHashTable weakObjectsHashTable];
    [gInteractionStacks addObject:stack];

    for (UIView *element in stack.subviews) {
        if (gInteractionCollapsed) {
            objc_setAssociatedObject(element, &kDKInteractionModifiedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(stack, &kDKInteractionModifiedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            element.userInteractionEnabled = NO;
            if (element.alpha != 0.0) element.alpha = 0.0;
            DKInteractionSettleCollapsed(element, stack);
        } else if ([objc_getAssociatedObject(element, &kDKInteractionModifiedKey) boolValue]) {
            // 展开动画由 SetCollapsed 驱动；布局期只兜底：动画被打断且 center 还在写入位时还原。
            NSValue *writtenValue = objc_getAssociatedObject(element, &kDKInteractionWrittenCenterKey);
            if (!writtenValue || !DKInteractionCenterClose(element.center, writtenValue.CGPointValue)) {
                DKInteractionRestoreElement(element);
            }
        }
    }
}

void DKInteractionCollapseSetCollapsed(BOOL collapsed) {
    gInteractionCollapsed = collapsed;
    if (!DKInteractionCollapseEnabled()) return;
    for (UIView *stack in gInteractionStacks.allObjects) {
        for (UIView *element in stack.subviews) {
            CGPoint target;
            if (collapsed) {
                objc_setAssociatedObject(element, &kDKInteractionModifiedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(stack, &kDKInteractionModifiedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                element.userInteractionEnabled = NO;
                NSValue *storedValue = objc_getAssociatedObject(element, &kDKInteractionStoredCenterKey);
                NSValue *writtenValue = objc_getAssociatedObject(element, &kDKInteractionWrittenCenterKey);
                CGPoint stored;
                if (writtenValue && DKInteractionCenterClose(element.center, writtenValue.CGPointValue) && storedValue) {
                    stored = storedValue.CGPointValue;
                } else if (storedValue && DKInteractionCenterClose(element.center, storedValue.CGPointValue)) {
                    stored = storedValue.CGPointValue;
                } else {
                    stored = element.center;
                }
                target = DKInteractionCollapseTarget(stack, stored);
                objc_setAssociatedObject(element, &kDKInteractionStoredCenterKey,
                    [NSValue valueWithCGPoint:stored], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(element, &kDKInteractionWrittenCenterKey,
                    [NSValue valueWithCGPoint:target], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            } else {
                NSValue *storedValue = objc_getAssociatedObject(element, &kDKInteractionStoredCenterKey);
                NSValue *writtenValue = objc_getAssociatedObject(element, &kDKInteractionWrittenCenterKey);
                if (storedValue && writtenValue && DKInteractionCenterClose(element.center, writtenValue.CGPointValue)) {
                    target = storedValue.CGPointValue;
                } else {
                    target = element.center;
                }
            }
            CGFloat alpha = collapsed ? 0.0 : 1.0;
            [UIView animateWithDuration:0.4 delay:0.0 usingSpringWithDamping:0.86 initialSpringVelocity:0.0
                                options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                             animations:^{
                                 element.alpha = alpha;
                                 element.center = target;
                             } completion:^(BOOL finished) {
                                 if (!collapsed) {
                                     element.userInteractionEnabled = YES;
                                     objc_setAssociatedObject(element, &kDKInteractionModifiedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                                     objc_setAssociatedObject(element, &kDKInteractionStoredCenterKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                                     objc_setAssociatedObject(element, &kDKInteractionWrittenCenterKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                                 }
                             }];
        }
        if (!collapsed) {
            objc_setAssociatedObject(stack, &kDKInteractionModifiedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

static void DKInteractionCollapseRefresh(void) {
    if (DKInteractionCollapseEnabled()) return;
    for (UIView *stack in gInteractionStacks.allObjects) {
        if ([objc_getAssociatedObject(stack, &kDKInteractionModifiedKey) boolValue]) {
            DKInteractionRestoreStack(stack);
        }
    }
}

%ctor {
    DKSettingsRegister(DKKeyInteractionCollapse, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(DKKeyInteractionCollapse, @"右侧按钮随底栏收缩",
            @"开启后，底栏动态收缩时右侧头像、点赞、评论、收藏、分享按钮一起收进底栏圆键且不拦截点击；"
            @"点底栏圆键或下滑全部展开。需开启「悬浮玻璃底栏」与「动态收缩底栏」。");
        return DKSettingsOnChange(item, ^{ DKInteractionCollapseRefresh(); });
    });
}
