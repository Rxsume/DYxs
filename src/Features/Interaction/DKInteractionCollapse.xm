//
//  DKInteractionCollapse.xm
//  功能：右侧互动区随底栏动态收缩 —— 底栏收成圆键时，右侧点赞/评论/收藏/分享
//  一起滑出淡出且不拦截点击（点按落到视频上），头像保留；展开用系统默认收缩
//  圆键（点它或下滑展开底栏），底栏展开时右侧按钮回来。
//  收缩位移只叠加/撤销自身的一段平移：应用时记下应用前与应用后的 transform，
//  展开时仅当当前 transform 仍是我们设的值才精确撤销；抖音已改动过则以抖音
//  当前值为准，不回写任何捕获的旧 transform，避免把瞬态缩放固化成错位。
//

#import "DKInteractionCollapse.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"

#import <objc/runtime.h>

static BOOL gInteractionCollapsed = NO;
static NSHashTable<UIView *> *gInteractionStacks = nil;
static NSUInteger gInteractionGeneration = 0;
static char kDKInteractionAppliedTransformKey;
static char kDKInteractionPreApplyTransformKey;
static char kDKInteractionModifiedKey;

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

// 头像元素：收缩时不隐藏，保留显示与点击。
static BOOL DKInteractionIsAvatarElement(UIView *element) {
    if ([element respondsToSelector:@selector(elementClassName)]) {
        NSString *name = [element performSelector:@selector(elementClassName)];
        if ([name isEqualToString:@"AWEPlayInteractionUserAvatarOptElementElement"]) return YES;
    }
    if (DKInteractionContainsClass(NSClassFromString(@"AWEPlayInteractionUserProfileContainerView"), element)) return YES;
    if (DKInteractionContainsClass(NSClassFromString(@"AWEPlayInteractionUserAvatarView"), element)) return YES;
    return NO;
}

// 与 DKXSBatch5RestApplyElementScale 同款判据：右侧栈 = label "right" 或带头像元素，
// 且位于播放交互控制器内。
static BOOL DKInteractionIsRightStack(UIView *stack) {
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

static CGFloat DKInteractionOffsetForStack(UIView *stack) {
    return CGRectGetWidth(stack.bounds) + 24.0;
}

static BOOL DKInteractionElementModified(UIView *element) {
    return [objc_getAssociatedObject(element, &kDKInteractionModifiedKey) boolValue];
}

static void DKInteractionClearElementState(UIView *element) {
    objc_setAssociatedObject(element, &kDKInteractionModifiedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(element, &kDKInteractionAppliedTransformKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(element, &kDKInteractionPreApplyTransformKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// 给元素叠加收缩平移。已叠加且当前值仍是我们设的值时不重复叠加（栈宽变化时按新宽重算）。
static void DKInteractionApplyOffset(UIView *element, UIView *stack, BOOL animated) {
    CGFloat offset = DKInteractionOffsetForStack(stack);
    CGAffineTransform target;
    if (DKInteractionElementModified(element)) {
        NSValue *appliedValue = objc_getAssociatedObject(element, &kDKInteractionAppliedTransformKey);
        NSValue *preValue = objc_getAssociatedObject(element, &kDKInteractionPreApplyTransformKey);
        if (appliedValue && preValue &&
            CGAffineTransformEqualToTransform(element.transform, appliedValue.CGAffineTransformValue)) {
            target = CGAffineTransformConcat(preValue.CGAffineTransformValue,
                                             CGAffineTransformMakeTranslation(offset, 0));
            if (CGAffineTransformEqualToTransform(target, appliedValue.CGAffineTransformValue)) {
                return;
            }
            objc_setAssociatedObject(element, &kDKInteractionAppliedTransformKey,
                [NSValue valueWithCGAffineTransform:target], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else {
            // 抖音已改动 transform：以当前值为起点重新叠加。
            objc_setAssociatedObject(element, &kDKInteractionPreApplyTransformKey,
                [NSValue valueWithCGAffineTransform:element.transform], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            target = CGAffineTransformConcat(element.transform, CGAffineTransformMakeTranslation(offset, 0));
            objc_setAssociatedObject(element, &kDKInteractionAppliedTransformKey,
                [NSValue valueWithCGAffineTransform:target], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } else {
        objc_setAssociatedObject(element, &kDKInteractionPreApplyTransformKey,
            [NSValue valueWithCGAffineTransform:element.transform], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        target = CGAffineTransformConcat(element.transform, CGAffineTransformMakeTranslation(offset, 0));
        objc_setAssociatedObject(element, &kDKInteractionAppliedTransformKey,
            [NSValue valueWithCGAffineTransform:target], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(element, &kDKInteractionModifiedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(stack, &kDKInteractionModifiedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    element.userInteractionEnabled = NO;
    if (animated) {
        [UIView animateWithDuration:0.4 delay:0.0 usingSpringWithDamping:0.86 initialSpringVelocity:0.0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:^{
                             element.alpha = 0.0;
                             element.transform = target;
                         } completion:nil];
    } else {
        element.alpha = 0.0;
        element.transform = target;
    }
}

// 撤销收缩平移：仅当当前 transform 仍是我们设的值时回到应用前的值；
// 抖音已改动过则保留抖音当前值。绝不回写捕获的旧 transform。
static void DKInteractionRemoveOffset(UIView *element, BOOL animated) {
    if (!DKInteractionElementModified(element)) return;
    NSValue *appliedValue = objc_getAssociatedObject(element, &kDKInteractionAppliedTransformKey);
    NSValue *preValue = objc_getAssociatedObject(element, &kDKInteractionPreApplyTransformKey);
    CGAffineTransform target = element.transform;
    if (appliedValue && preValue &&
        CGAffineTransformEqualToTransform(element.transform, appliedValue.CGAffineTransformValue)) {
        target = preValue.CGAffineTransformValue;
    }
    NSUInteger generation = gInteractionGeneration;
    if (animated) {
        [UIView animateWithDuration:0.4 delay:0.0 usingSpringWithDamping:0.86 initialSpringVelocity:0.0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:^{
                             element.alpha = 1.0;
                             element.transform = target;
                         } completion:^(BOOL finished) {
                             if (generation != gInteractionGeneration) return;
                             element.userInteractionEnabled = YES;
                             DKInteractionClearElementState(element);
                         }];
    } else {
        element.alpha = 1.0;
        element.transform = target;
        element.userInteractionEnabled = YES;
        DKInteractionClearElementState(element);
    }
}

static void DKInteractionRestoreElement(UIView *element) {
    DKInteractionRemoveOffset(element, NO);
    element.alpha = 1.0;
    element.userInteractionEnabled = YES;
}

static void DKInteractionRestoreStack(UIView *stack) {
    for (UIView *element in stack.subviews) {
        if (DKInteractionElementModified(element)) {
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
        if (DKInteractionIsAvatarElement(element)) continue;
        if (gInteractionCollapsed) {
            // 布局期只强制落定收缩态（叠加平移、淡出、禁交互）。
            DKInteractionApplyOffset(element, stack, NO);
        } else if (DKInteractionElementModified(element)) {
            // 展开动画由 SetCollapsed 驱动；布局期仅清理残留状态，
            // 当前值已被动画改到目标时 RemoveOffset 不动 transform。
            DKInteractionRemoveOffset(element, NO);
        }
    }
}

void DKInteractionCollapseSetCollapsed(BOOL collapsed) {
    gInteractionCollapsed = collapsed;
    gInteractionGeneration++;
    if (!DKInteractionCollapseEnabled()) return;
    for (UIView *stack in gInteractionStacks.allObjects) {
        for (UIView *element in stack.subviews) {
            if (DKInteractionIsAvatarElement(element)) continue;
            if (collapsed) {
                DKInteractionApplyOffset(element, stack, YES);
            } else {
                DKInteractionRemoveOffset(element, YES);
            }
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
            @"开启后，底栏动态收缩时右侧点赞、评论、收藏、分享按钮一起滑出隐藏且不拦截点击，头像保留；"
            @"点系统圆键或下滑展开。需开启「悬浮玻璃底栏」与「动态收缩底栏」。");
        return DKSettingsOnChange(item, ^{ DKInteractionCollapseRefresh(); });
    });
}
