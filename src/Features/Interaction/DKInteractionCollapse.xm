//
//  DKInteractionCollapse.xm
//  功能：右侧互动区随底栏动态收缩 —— 底栏收成圆键时，右侧点赞/评论/收藏/分享栈
//  一起滑出淡出且不拦截点击（点按落到视频上），底栏展开时回来。
//  收缩位移叠加在元素缩放的 transform 之上，基准 transform 每轮布局重新记录。
//

#import "DKInteractionCollapse.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"

#import <objc/runtime.h>

static BOOL gInteractionCollapsed = NO;
static NSHashTable<UIView *> *gInteractionStacks = nil;
static char kDKInteractionBaseTransformKey;
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
    for (UIView *subview in container.subviews) {
        if ([subview isKindOfClass:cls]) return YES;
        if (DKInteractionContainsClass(cls, subview)) return YES;
    }
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

static CGAffineTransform DKInteractionBaseTransform(UIView *stack) {
    NSValue *value = objc_getAssociatedObject(stack, &kDKInteractionBaseTransformKey);
    return value ? value.CGAffineTransformValue : CGAffineTransformIdentity;
}

static CGAffineTransform DKInteractionTargetTransform(UIView *stack) {
    CGAffineTransform base = DKInteractionBaseTransform(stack);
    if (!gInteractionCollapsed) return base;
    CGFloat offset = CGRectGetWidth(stack.bounds) + 24.0;
    return CGAffineTransformConcat(base, CGAffineTransformMakeTranslation(offset, 0));
}

static void DKInteractionRestoreStack(UIView *stack) {
    stack.alpha = 1.0;
    stack.transform = DKInteractionBaseTransform(stack);
    stack.userInteractionEnabled = YES;
    objc_setAssociatedObject(stack, &kDKInteractionModifiedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void DKInteractionCollapseApplyStack(UIView *stack) {
    if (!stack) return;
    BOOL modified = [objc_getAssociatedObject(stack, &kDKInteractionModifiedKey) boolValue];
    if (!DKInteractionCollapseEnabled()) {
        if (modified) DKInteractionRestoreStack(stack);
        return;
    }
    if (!DKInteractionIsRightStack(stack)) return;
    if (!gInteractionStacks) gInteractionStacks = [NSHashTable weakObjectsHashTable];
    [gInteractionStacks addObject:stack];
    // 缩放已在本入口之前应用，当前 transform 即基准；收缩位移在其上叠加。
    objc_setAssociatedObject(stack, &kDKInteractionBaseTransformKey,
        [NSValue valueWithCGAffineTransform:stack.transform], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // 展开过程交给动画，布局期只强制落定收缩态，避免打断动画。
    if (gInteractionCollapsed) {
        objc_setAssociatedObject(stack, &kDKInteractionModifiedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        stack.userInteractionEnabled = NO;
        stack.alpha = 0.0;
        stack.transform = DKInteractionTargetTransform(stack);
    }
}

void DKInteractionCollapseSetCollapsed(BOOL collapsed) {
    gInteractionCollapsed = collapsed;
    if (!DKInteractionCollapseEnabled()) return;
    for (UIView *stack in gInteractionStacks.allObjects) {
        if (collapsed) {
            objc_setAssociatedObject(stack, &kDKInteractionModifiedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            stack.userInteractionEnabled = NO;
        }
        CGAffineTransform target = DKInteractionTargetTransform(stack);
        CGFloat alpha = collapsed ? 0.0 : 1.0;
        [UIView animateWithDuration:0.4 delay:0.0 usingSpringWithDamping:0.86 initialSpringVelocity:0.0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:^{
                             stack.alpha = alpha;
                             stack.transform = target;
                         } completion:^(BOOL finished) {
                             if (!collapsed) {
                                 stack.userInteractionEnabled = YES;
                                 objc_setAssociatedObject(stack, &kDKInteractionModifiedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                             }
                         }];
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
            @"开启后，底栏动态收缩时右侧点赞、评论、收藏、分享按钮一起滑出隐藏且不拦截点击，底栏展开时回来。"
            @"需开启「悬浮玻璃底栏」与「动态收缩底栏」。");
        return DKSettingsOnChange(item, ^{ DKInteractionCollapseRefresh(); });
    });
}
