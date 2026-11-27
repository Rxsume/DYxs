//
//  DKInteractionCollapse.xm
//  功能：互动区随底栏动态收缩 —— 底栏收成圆键时，右侧头像/点赞/评论/收藏/分享、
//  左侧用户名/文案/标签、首页顶栏一起收进底栏圆键（向圆键位置移动并淡出/隐藏、
//  不拦截点击），点底栏圆键全部展开。一个键管全部：系统收缩圆键照常显示、
//  照常点按展开，展开时经 DKGlassTabBarPlatterDidShow 同步把各区带回来。
//
//  位移方式（0.6.9.76 起）：只动 center，绝不碰 transform。
//  旧版两代 transform 方案都出过事：63 版把某时刻的 transform 记成基准回写，
//  抖音出现动画的瞬态缩放被固化（元素变小错位）；75 版靠「上次写入值」浮点比对
//  叠加/撤销平移，比对在真机上总被外部改写打断，平移逐轮叠加、元素飞出屏幕缩没。
//  center 方案：收缩时把 center 移到目标位，记下原 center 与写入 center；
//  布局期发现 center 被抖音布局重置回原位就重新移动，发现被移到别处就以新位置
//  为原位重新移动；展开时 center 还是我们写的那份才还原，已被抖音接管就不碰。
//  抖音自己的布局每轮都会把元素放回自然位置，天然兜底，不存在叠加漂移。
//
//  顶栏注意：AWEFeedTopBarContainer 的 setAlpha: 被 DKXSBatch5dAppearance 强制接管
//  （恒回 1.0 或透明度设定值），alpha 淡出无效，顶栏改用 center 移到圆键 +
//  动画完成 hidden，展开时 unhide 并移回。
//
//  性能：栈判定按栈缓存（子视图签名变化才重查），center/alpha 只在值变化时写。
//

#import "DKInteractionCollapse.h"
#import "DKGlassTabBar.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"

#import <objc/runtime.h>

static BOOL gInteractionCollapsed = NO;
static NSHashTable<UIView *> *gInteractionStacks = nil;
static NSHashTable<UIView *> *gInteractionTopBars = nil;
static char kDKInteractionStoredCenterKey;
static char kDKInteractionWrittenCenterKey;
static char kDKInteractionModifiedKey;
static char kDKInteractionStackVerdictKey;
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

// 可收缩栈：播放交互控制器内的元素栈（左：用户名/文案/标签，右：头像/点赞等）。
static BOOL DKInteractionIsCollapsibleStackUncached(UIView *stack) {
    UIViewController *viewController = DKInteractionViewControllerForView(stack);
    Class playVCClass = NSClassFromString(@"AWEPlayInteractionViewController");
    return viewController && playVCClass && [viewController isKindOfClass:playVCClass];
}

static NSUInteger DKInteractionStackSignature(UIView *stack) {
    NSArray<UIView *> *subviews = stack.subviews;
    NSUInteger signature = subviews.count * 1315423911u;
    signature ^= (NSUInteger)(uintptr_t)subviews.firstObject;
    signature ^= ((NSUInteger)(uintptr_t)subviews.lastObject) << 1;
    return signature;
}

static BOOL DKInteractionIsCollapsibleStack(UIView *stack) {
    NSUInteger signature = DKInteractionStackSignature(stack);
    NSNumber *cachedSignature = objc_getAssociatedObject(stack, &kDKInteractionStackSignatureKey);
    NSNumber *cached = objc_getAssociatedObject(stack, &kDKInteractionStackVerdictKey);
    if (cached && cachedSignature.unsignedIntegerValue == signature) return cached.boolValue;
    BOOL result = DKInteractionIsCollapsibleStackUncached(stack);
    objc_setAssociatedObject(stack, &kDKInteractionStackSignatureKey, @(signature), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(stack, &kDKInteractionStackVerdictKey, @(result), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return result;
}

#pragma mark - center 位移

static BOOL DKInteractionCenterClose(CGPoint a, CGPoint b) {
    return fabs(a.x - b.x) < 0.5 && fabs(a.y - b.y) < 0.5;
}

// 收缩目标位：底栏圆键中心（换算到该视图父视图坐标）；圆键不可用时退回向右滑出。
static CGPoint DKInteractionCollapseTarget(UIView *view, CGPoint stored) {
    UIView *platter = DKGlassTabBarCollapsePlatter();
    UIView *superview = view.superview;
    if (platter && platter.window && superview) {
        CGPoint centerInWindow = [platter convertPoint:CGPointMake(CGRectGetMidX(platter.bounds), CGRectGetMidY(platter.bounds)) toView:nil];
        return [superview convertPoint:centerInWindow fromView:nil];
    }
    return CGPointMake(stored.x + CGRectGetWidth(superview.bounds) + 24.0, stored.y);
}

// 收缩落定：确保 center 在目标位（布局期兜底，即时落定）。
static void DKInteractionSettleCollapsed(UIView *view) {
    NSValue *storedValue = objc_getAssociatedObject(view, &kDKInteractionStoredCenterKey);
    NSValue *writtenValue = objc_getAssociatedObject(view, &kDKInteractionWrittenCenterKey);
    CGPoint current = view.center;
    if (writtenValue && DKInteractionCenterClose(current, writtenValue.CGPointValue)) return;
    CGPoint stored;
    if (storedValue && DKInteractionCenterClose(current, storedValue.CGPointValue)) {
        stored = storedValue.CGPointValue;
    } else {
        // 抖音把视图放到了新位置（或首次收缩）：以当前为原位。
        stored = current;
    }
    CGPoint written = DKInteractionCollapseTarget(view, stored);
    objc_setAssociatedObject(view, &kDKInteractionStoredCenterKey,
        [NSValue valueWithCGPoint:stored], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kDKInteractionWrittenCenterKey,
        [NSValue valueWithCGPoint:written], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.center = written;
}

static void DKInteractionRestoreView(UIView *view) {
    NSValue *storedValue = objc_getAssociatedObject(view, &kDKInteractionStoredCenterKey);
    NSValue *writtenValue = objc_getAssociatedObject(view, &kDKInteractionWrittenCenterKey);
    if (storedValue && writtenValue && DKInteractionCenterClose(view.center, writtenValue.CGPointValue)) {
        view.center = storedValue.CGPointValue;
    }
    objc_setAssociatedObject(view, &kDKInteractionStoredCenterKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kDKInteractionWrittenCenterKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.alpha = 1.0;
    view.hidden = NO;
    view.userInteractionEnabled = YES;
    objc_setAssociatedObject(view, &kDKInteractionModifiedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DKInteractionRestoreStack(UIView *stack) {
    for (UIView *element in stack.subviews) {
        if ([objc_getAssociatedObject(element, &kDKInteractionModifiedKey) boolValue]) {
            DKInteractionRestoreView(element);
        }
    }
    objc_setAssociatedObject(stack, &kDKInteractionModifiedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DKInteractionRestoreTopBars(void) {
    for (UIView *topBar in gInteractionTopBars.allObjects) {
        if ([objc_getAssociatedObject(topBar, &kDKInteractionModifiedKey) boolValue]) {
            DKInteractionRestoreView(topBar);
        }
    }
}

void DKInteractionCollapseApplyStack(UIView *stack) {
    if (!stack) return;
    BOOL stackModified = [objc_getAssociatedObject(stack, &kDKInteractionModifiedKey) boolValue];
    if (!DKInteractionCollapseEnabled()) {
        if (stackModified) DKInteractionRestoreStack(stack);
        return;
    }
    if (!DKInteractionIsCollapsibleStack(stack)) return;
    if (!gInteractionStacks) gInteractionStacks = [NSHashTable weakObjectsHashTable];
    [gInteractionStacks addObject:stack];

    for (UIView *element in stack.subviews) {
        if (gInteractionCollapsed) {
            objc_setAssociatedObject(element, &kDKInteractionModifiedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(stack, &kDKInteractionModifiedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            element.userInteractionEnabled = NO;
            if (element.alpha != 0.0) element.alpha = 0.0;
            DKInteractionSettleCollapsed(element);
        } else if ([objc_getAssociatedObject(element, &kDKInteractionModifiedKey) boolValue]) {
            // 展开动画由 SetCollapsed 驱动；布局期只兜底：动画被打断且 center 还在写入位时还原。
            NSValue *writtenValue = objc_getAssociatedObject(element, &kDKInteractionWrittenCenterKey);
            if (!writtenValue || !DKInteractionCenterClose(element.center, writtenValue.CGPointValue)) {
                DKInteractionRestoreView(element);
            }
        }
    }
}

#pragma mark - 顶栏

static void DKInteractionApplyTopBar(UIView *topBar) {
    if (!topBar) return;
    BOOL modified = [objc_getAssociatedObject(topBar, &kDKInteractionModifiedKey) boolValue];
    if (!DKInteractionCollapseEnabled()) {
        if (modified) DKInteractionRestoreView(topBar);
        return;
    }
    if (!gInteractionTopBars) gInteractionTopBars = [NSHashTable weakObjectsHashTable];
    [gInteractionTopBars addObject:topBar];

    if (gInteractionCollapsed) {
        objc_setAssociatedObject(topBar, &kDKInteractionModifiedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        topBar.userInteractionEnabled = NO;
        NSValue *writtenValue = objc_getAssociatedObject(topBar, &kDKInteractionWrittenCenterKey);
        if (!writtenValue || !DKInteractionCenterClose(topBar.center, writtenValue.CGPointValue)) {
            // 抖音把顶栏放回了原位（或首次收缩）：落定到圆键位并隐藏。
            DKInteractionSettleCollapsed(topBar);
            topBar.hidden = YES;
        }
        // center 已在写入位：动画进行中或已落定，hidden 由动画完成回调负责，不插手。
    } else if (modified) {
        NSValue *writtenValue = objc_getAssociatedObject(topBar, &kDKInteractionWrittenCenterKey);
        if (!writtenValue || !DKInteractionCenterClose(topBar.center, writtenValue.CGPointValue)) {
            DKInteractionRestoreView(topBar);
        }
    }
}

%hook AWEFeedTopBarContainer
- (void)layoutSubviews {
    %orig;
    DKInteractionApplyTopBar(self);
}
%end

#pragma mark - 收缩/展开驱动

static void DKInteractionAnimateView(UIView *view, BOOL collapsed, BOOL useHidden) {
    CGPoint target;
    if (collapsed) {
        objc_setAssociatedObject(view, &kDKInteractionModifiedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        view.userInteractionEnabled = NO;
        NSValue *storedValue = objc_getAssociatedObject(view, &kDKInteractionStoredCenterKey);
        NSValue *writtenValue = objc_getAssociatedObject(view, &kDKInteractionWrittenCenterKey);
        CGPoint stored;
        if (writtenValue && DKInteractionCenterClose(view.center, writtenValue.CGPointValue) && storedValue) {
            stored = storedValue.CGPointValue;
        } else if (storedValue && DKInteractionCenterClose(view.center, storedValue.CGPointValue)) {
            stored = storedValue.CGPointValue;
        } else {
            stored = view.center;
        }
        target = DKInteractionCollapseTarget(view, stored);
        objc_setAssociatedObject(view, &kDKInteractionStoredCenterKey,
            [NSValue valueWithCGPoint:stored], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, &kDKInteractionWrittenCenterKey,
            [NSValue valueWithCGPoint:target], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        view.hidden = NO;
        NSValue *storedValue = objc_getAssociatedObject(view, &kDKInteractionStoredCenterKey);
        NSValue *writtenValue = objc_getAssociatedObject(view, &kDKInteractionWrittenCenterKey);
        if (storedValue && writtenValue && DKInteractionCenterClose(view.center, writtenValue.CGPointValue)) {
            target = storedValue.CGPointValue;
        } else {
            target = view.center;
        }
    }
    CGFloat alpha = collapsed ? 0.0 : 1.0;
    [UIView animateWithDuration:0.4 delay:0.0 usingSpringWithDamping:0.86 initialSpringVelocity:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
                         if (!useHidden) view.alpha = alpha;
                         view.center = target;
                     } completion:^(BOOL finished) {
                         if (collapsed) {
                             if (useHidden) view.hidden = YES;
                         } else {
                             view.userInteractionEnabled = YES;
                             objc_setAssociatedObject(view, &kDKInteractionModifiedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                             objc_setAssociatedObject(view, &kDKInteractionStoredCenterKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                             objc_setAssociatedObject(view, &kDKInteractionWrittenCenterKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                         }
                     }];
}

void DKInteractionCollapseSetCollapsed(BOOL collapsed) {
    gInteractionCollapsed = collapsed;
    if (!DKInteractionCollapseEnabled()) return;
    for (UIView *stack in gInteractionStacks.allObjects) {
        if (collapsed) {
            objc_setAssociatedObject(stack, &kDKInteractionModifiedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        for (UIView *element in stack.subviews) {
            DKInteractionAnimateView(element, collapsed, NO);
        }
        if (!collapsed) {
            objc_setAssociatedObject(stack, &kDKInteractionModifiedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    for (UIView *topBar in gInteractionTopBars.allObjects) {
        DKInteractionAnimateView(topBar, collapsed, YES);
    }
}

static void DKInteractionCollapseRefresh(void) {
    if (DKInteractionCollapseEnabled()) return;
    for (UIView *stack in gInteractionStacks.allObjects) {
        if ([objc_getAssociatedObject(stack, &kDKInteractionModifiedKey) boolValue]) {
            DKInteractionRestoreStack(stack);
        }
    }
    DKInteractionRestoreTopBars();
}

%ctor {
    DKSettingsRegister(DKKeyInteractionCollapse, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(DKKeyInteractionCollapse, @"右侧按钮随底栏收缩",
            @"开启后，底栏动态收缩时右侧按钮、左侧用户名文案和顶栏一起收进底栏圆键且不拦截点击；"
            @"点底栏圆键或下滑全部展开。需开启「悬浮玻璃底栏」与「动态收缩底栏」。");
        return DKSettingsOnChange(item, ^{ DKInteractionCollapseRefresh(); });
    });
}
