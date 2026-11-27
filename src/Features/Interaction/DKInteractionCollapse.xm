//
//  DKInteractionCollapse.xm
//  功能：右侧互动区随底栏动态收缩 —— 底栏收成圆键时，右侧头像/点赞/评论/收藏/分享
//  一起滑出淡出且不拦截点击（点按落到视频上）；收缩圆键在头像上方贴右边缘吸附
//  （自建玻璃圆键，只露一小条，点它展开底栏），底栏展开时右侧按钮回来、圆键消失。
//
//  transform 处理（0.6.9.75 重写，修右侧错位）：绝不把某一时刻捕获的 transform
//  当「基准」回写——抖音在 cell 出现动画中会给元素写瞬态缩放/位移，旧版把瞬态值
//  记成基准、展开时回写，元素就永久错位变小且每轮重录自 perpetuate。新版只在
//  元素当前 transform 上叠加/撤掉我们自己的平移量：写之前先按「上次写入值」
//  判断当前 transform 是否还是我们写的那份，是则先撤掉旧平移再叠新的；若已被
//  外部改写（抖音重置/动画），就以当前值为准重新叠加，展开时只撤自己的平移、
//  不碰外部写的值。
//
//  性能（0.6.9.75）：右侧栈判定与头像元素按栈缓存（子视图签名变化才重查），
//  布局期不再逐元素递归搜子树；transform/alpha 只在值变化时写。
//

#import "DKInteractionCollapse.h"
#import "DKGlassTabBar.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"

#import <objc/runtime.h>

static BOOL gInteractionCollapsed = NO;
static NSHashTable<UIView *> *gInteractionStacks = nil;
static char kDKInteractionAppliedOffsetKey;
static char kDKInteractionLastWrittenKey;
static char kDKInteractionModifiedKey;
static char kDKInteractionKeyViewKey;
static char kDKInteractionRightStackKey;
static char kDKInteractionStackSignatureKey;
static char kDKInteractionAvatarKey;

static const CGFloat kDKInteractionKeySide = 44.0;
static const CGFloat kDKInteractionKeyPeek = 22.0;
static const CGFloat kDKInteractionKeyGap = 8.0;
static const NSInteger kDKInteractionKeyIconTag = 7701;

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

// 头像元素：仅用于圆键定位（收缩时头像也一起收）。
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

static UIView *DKInteractionAvatarElement(UIView *stack) {
    NSValue *cached = objc_getAssociatedObject(stack, &kDKInteractionAvatarKey);
    UIView *avatar = cached.nonretainedObjectValue;
    if (avatar && avatar.superview == stack) return avatar;
    avatar = nil;
    for (UIView *element in stack.subviews) {
        if (DKInteractionIsAvatarElement(element)) { avatar = element; break; }
    }
    objc_setAssociatedObject(stack, &kDKInteractionAvatarKey,
        avatar ? [NSValue valueWithNonretainedObject:avatar] : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return avatar;
}

#pragma mark - transform 平移叠加/撤销

static CGFloat DKInteractionAppliedOffset(UIView *element) {
    return [objc_getAssociatedObject(element, &kDKInteractionAppliedOffsetKey) doubleValue];
}

static BOOL DKInteractionOffsetIntact(UIView *element) {
    NSValue *lastWritten = objc_getAssociatedObject(element, &kDKInteractionLastWrittenKey);
    if (!lastWritten) return NO;
    return CGAffineTransformEqualToTransform(element.transform, lastWritten.CGAffineTransformValue);
}

// 当前 transform 去掉我们自己的平移后的「干净」值；若已被外部改写，
// 说明我们的平移已不在其中，直接以当前值为准并清掉记账。
static CGAffineTransform DKInteractionCleanTransform(UIView *element) {
    CGFloat applied = DKInteractionAppliedOffset(element);
    if (applied == 0) return element.transform;
    if (!DKInteractionOffsetIntact(element)) {
        objc_setAssociatedObject(element, &kDKInteractionAppliedOffsetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(element, &kDKInteractionLastWrittenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return element.transform;
    }
    return CGAffineTransformConcat(element.transform, CGAffineTransformMakeTranslation(-applied, 0));
}

static void DKInteractionWriteTransform(UIView *element, CGAffineTransform transform, CGFloat appliedOffset) {
    element.transform = transform;
    objc_setAssociatedObject(element, &kDKInteractionAppliedOffsetKey, @(appliedOffset), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(element, &kDKInteractionLastWrittenKey,
        [NSValue valueWithCGAffineTransform:transform], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static CGAffineTransform DKInteractionTargetTransform(UIView *element, CGFloat offset) {
    CGAffineTransform clean = DKInteractionCleanTransform(element);
    if (offset == 0) return clean;
    return CGAffineTransformConcat(clean, CGAffineTransformMakeTranslation(offset, 0));
}

static void DKInteractionRestoreElement(UIView *element) {
    if (DKInteractionAppliedOffset(element) != 0) {
        CGAffineTransform clean = DKInteractionCleanTransform(element);
        if (!CGAffineTransformEqualToTransform(element.transform, clean)) {
            DKInteractionWriteTransform(element, clean, 0);
        } else {
            objc_setAssociatedObject(element, &kDKInteractionAppliedOffsetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(element, &kDKInteractionLastWrittenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    element.alpha = 1.0;
    element.userInteractionEnabled = YES;
    objc_setAssociatedObject(element, &kDKInteractionModifiedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - 头像上方圆键

@interface DKInteractionKeyTarget : NSObject
- (void)keyDidTap;
@end

@implementation DKInteractionKeyTarget
- (void)keyDidTap {
    DKGlassTabBarSetCollapsed(NO);
}
@end

static DKInteractionKeyTarget *gKeyTarget = nil;

static UIView *DKInteractionMakeKey(UIView *stack) API_AVAILABLE(ios(26.0)) {
    UIVisualEffectView *key = [[UIVisualEffectView alloc]
        initWithEffect:DKGlassTabBarMakeEffect(stack.traitCollection.userInterfaceStyle, YES)];
    key.cornerConfiguration = [UICornerConfiguration capsuleConfiguration];

    UIImageView *icon = [[UIImageView alloc] init];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.tag = kDKInteractionKeyIconTag;
    [key.contentView addSubview:icon];

    if (!gKeyTarget) gKeyTarget = [[DKInteractionKeyTarget alloc] init];
    UIButton *hit = [UIButton buttonWithType:UIButtonTypeCustom];
    [hit addTarget:gKeyTarget action:@selector(keyDidTap) forControlEvents:UIControlEventTouchUpInside];
    [key.contentView addSubview:hit];

    key.hidden = YES;
    key.alpha = 0.0;
    return key;
}

static UIImageView *DKInteractionFindIcon(UIView *root) {
    for (UIView *subview in root.subviews) {
        if ([subview isKindOfClass:UIImageView.class] && ((UIImageView *)subview).image) {
            return (UIImageView *)subview;
        }
        UIImageView *found = DKInteractionFindIcon(subview);
        if (found) return found;
    }
    return nil;
}

// 圆键图标跟系统收缩圆键一致：从收缩底板里取当前页图标。
static void DKInteractionUpdateKeyIcon(UIView *key) {
    UIView *platter = DKGlassTabBarCollapsePlatter();
    UIImageView *source = platter ? DKInteractionFindIcon(platter) : nil;
    UIImageView *icon = (UIImageView *)[key viewWithTag:kDKInteractionKeyIconTag];
    if (!icon) return;
    icon.image = source.image;
    icon.tintColor = source.tintColor;
}

static void DKInteractionLayoutKey(UIView *stack) {
    UIView *key = objc_getAssociatedObject(stack, &kDKInteractionKeyViewKey);
    UIView *host = stack.superview;
    if (!key || !host) return;
    UIView *avatar = DKInteractionAvatarElement(stack);
    if (!avatar) {
        key.hidden = YES;
        return;
    }
    // 用 center/bounds 算头像原位（不受 transform 影响，头像收缩后圆键位置不变）。
    CGPoint avatarCenter = [stack convertPoint:avatar.center toView:host];
    CGFloat avatarMinY = avatarCenter.y - CGRectGetHeight(avatar.bounds) / 2.0;
    CGFloat side = kDKInteractionKeySide;
    // 圆键贴右边缘吸附：只露出一小条，其余藏到边缘外，点露出部分展开。
    CGFloat x = CGRectGetWidth(host.bounds) - kDKInteractionKeyPeek;
    CGFloat y = avatarMinY - kDKInteractionKeyGap - side;
    CGRect frame = CGRectMake(x, y, side, side);
    if (!CGRectEqualToRect(key.frame, frame)) key.frame = frame;

    UIImageView *icon = (UIImageView *)[key viewWithTag:kDKInteractionKeyIconTag];
    CGRect iconFrame = CGRectMake((kDKInteractionKeyPeek - 20.0) / 2.0, (side - 20.0) / 2.0, 20.0, 20.0);
    if (icon && !CGRectEqualToRect(icon.frame, iconFrame)) icon.frame = iconFrame;
    for (UIView *subview in ((UIVisualEffectView *)key).contentView.subviews) {
        if ([subview isKindOfClass:UIButton.class] && !CGRectEqualToRect(subview.frame, key.bounds)) {
            subview.frame = key.bounds;
        }
    }
}

static void DKInteractionRestoreStack(UIView *stack) {
    for (UIView *element in stack.subviews) {
        if ([objc_getAssociatedObject(element, &kDKInteractionModifiedKey) boolValue]) {
            DKInteractionRestoreElement(element);
        }
    }
    UIView *key = objc_getAssociatedObject(stack, &kDKInteractionKeyViewKey);
    if (key) {
        key.hidden = YES;
        key.alpha = 0.0;
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

    if (@available(iOS 26.0, *)) {
        UIView *key = objc_getAssociatedObject(stack, &kDKInteractionKeyViewKey);
        if (!key && stack.superview) {
            key = DKInteractionMakeKey(stack);
            [stack.superview addSubview:key];
            objc_setAssociatedObject(stack, &kDKInteractionKeyViewKey, key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (key) {
            if (key.superview != stack.superview && stack.superview) [stack.superview addSubview:key];
            DKInteractionLayoutKey(stack);
            if (gInteractionCollapsed) {
                key.hidden = NO;
                key.alpha = 1.0;
            }
        }
    }

    CGFloat offset = CGRectGetWidth(stack.bounds) + 24.0;
    for (UIView *element in stack.subviews) {
        if (gInteractionCollapsed) {
            // 已落定（当前值就是我们写的那份且平移量对）就不再写，避免打断动画与无谓布局。
            if (DKInteractionAppliedOffset(element) == offset && DKInteractionOffsetIntact(element)) {
                if (element.alpha != 0.0) element.alpha = 0.0;
                continue;
            }
            objc_setAssociatedObject(element, &kDKInteractionModifiedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(stack, &kDKInteractionModifiedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            element.userInteractionEnabled = NO;
            element.alpha = 0.0;
            DKInteractionWriteTransform(element, DKInteractionTargetTransform(element, offset), offset);
        } else if ([objc_getAssociatedObject(element, &kDKInteractionModifiedKey) boolValue]) {
            // 展开动画由 SetCollapsed 驱动；布局期只兜底撤销残留平移（动画被打断/外部改写时）。
            if (!DKInteractionOffsetIntact(element)) {
                DKInteractionRestoreElement(element);
            }
        }
    }
}

void DKInteractionCollapseSetCollapsed(BOOL collapsed) {
    gInteractionCollapsed = collapsed;
    if (!DKInteractionCollapseEnabled()) return;
    for (UIView *stack in gInteractionStacks.allObjects) {
        UIView *key = objc_getAssociatedObject(stack, &kDKInteractionKeyViewKey);
        if (key) {
            if (collapsed) {
                DKInteractionUpdateKeyIcon(key);
                key.hidden = NO;
            }
            [UIView animateWithDuration:0.4 delay:0.0 usingSpringWithDamping:0.86 initialSpringVelocity:0.0
                                options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                             animations:^{ key.alpha = collapsed ? 1.0 : 0.0; }
                             completion:^(BOOL finished) { if (!collapsed) key.hidden = YES; }];
        }
        CGFloat offset = CGRectGetWidth(stack.bounds) + 24.0;
        for (UIView *element in stack.subviews) {
            if (collapsed) {
                objc_setAssociatedObject(element, &kDKInteractionModifiedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(stack, &kDKInteractionModifiedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                element.userInteractionEnabled = NO;
            }
            CGAffineTransform target = DKInteractionTargetTransform(element, collapsed ? offset : 0);
            // 先记账再动画：模型值立即变成 target，布局期靠记账判断是否已落定。
            objc_setAssociatedObject(element, &kDKInteractionAppliedOffsetKey,
                @(collapsed ? offset : 0), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(element, &kDKInteractionLastWrittenKey,
                [NSValue valueWithCGAffineTransform:target], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            CGFloat alpha = collapsed ? 0.0 : 1.0;
            [UIView animateWithDuration:0.4 delay:0.0 usingSpringWithDamping:0.86 initialSpringVelocity:0.0
                                options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                             animations:^{
                                 element.alpha = alpha;
                                 element.transform = target;
                             } completion:^(BOOL finished) {
                                 if (!collapsed) {
                                     element.userInteractionEnabled = YES;
                                     objc_setAssociatedObject(element, &kDKInteractionModifiedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                                     objc_setAssociatedObject(element, &kDKInteractionAppliedOffsetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                                     objc_setAssociatedObject(element, &kDKInteractionLastWrittenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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
            @"开启后，底栏动态收缩时右侧头像、点赞、评论、收藏、分享按钮一起滑出隐藏且不拦截点击；"
            @"收缩圆键在头像上方贴右边缘吸附，只露出一小条，点露出部分或下滑展开。需开启「悬浮玻璃底栏」与「动态收缩底栏」。");
        return DKSettingsOnChange(item, ^{ DKInteractionCollapseRefresh(); });
    });
}
