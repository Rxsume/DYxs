//
//  DKInteractionCollapse.xm
//  功能：右侧互动区随底栏动态收缩 —— 底栏收成圆键时，右侧点赞/评论/收藏/分享
//  一起滑出淡出且不拦截点击（点按落到视频上），头像保留；展开入口是画中画
//  悬浮窗（显示当前页图标，可拖动、拖到侧边吸附隐藏、大小可调），点它或系统
//  还原按钮展开底栏；底栏展开时右侧按钮回来、悬浮窗关闭。画中画不可用时
//  回退到贴右侧边缘的小圆键。
//  收缩位移叠加在元素缩放的 transform 之上，基准 transform 每轮布局重新记录。
//

#import "DKInteractionCollapse.h"
#import "DKGlassTabBar.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"

#import <AVKit/AVKit.h>
#import <objc/runtime.h>

static BOOL gInteractionCollapsed = NO;
static NSHashTable<UIView *> *gInteractionStacks = nil;
static char kDKInteractionBaseTransformKey;
static char kDKInteractionModifiedKey;
static char kDKInteractionKeyViewKey;

static const CGFloat kDKInteractionKeySide = 32.0;
static const CGFloat kDKInteractionKeyGap = 8.0;
// 小圆键贴右侧边缘：露出部分宽度，其余藏在边缘外。
static const CGFloat kDKInteractionKeyPeek = 22.0;
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

static CGAffineTransform DKInteractionBaseTransform(UIView *view) {
    NSValue *value = objc_getAssociatedObject(view, &kDKInteractionBaseTransformKey);
    return value ? value.CGAffineTransformValue : CGAffineTransformIdentity;
}

static void DKInteractionRecordBase(UIView *element) {
    if ([objc_getAssociatedObject(element, &kDKInteractionModifiedKey) boolValue]) return;
    objc_setAssociatedObject(element, &kDKInteractionBaseTransformKey,
        [NSValue valueWithCGAffineTransform:element.transform], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static CGAffineTransform DKInteractionElementTarget(UIView *element, UIView *stack) {
    CGAffineTransform base = DKInteractionBaseTransform(element);
    if (!gInteractionCollapsed) return base;
    CGFloat offset = CGRectGetWidth(stack.bounds) + 24.0;
    return CGAffineTransformConcat(base, CGAffineTransformMakeTranslation(offset, 0));
}

static void DKInteractionRestoreElement(UIView *element) {
    element.alpha = 1.0;
    element.transform = DKInteractionBaseTransform(element);
    element.userInteractionEnabled = YES;
    objc_setAssociatedObject(element, &kDKInteractionModifiedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - 头像下方圆键

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
    UIView *avatar = nil;
    for (UIView *element in stack.subviews) {
        if (DKInteractionIsAvatarElement(element)) { avatar = element; break; }
    }
    if (!avatar) {
        key.hidden = YES;
        return;
    }
    CGRect avatarFrame = [stack convertRect:avatar.frame toView:host];
    CGFloat side = kDKInteractionKeySide;
    // 贴右侧边缘：只露出 kDKInteractionKeyPeek，其余藏在边缘外，点露出部分展开。
    CGFloat x = CGRectGetWidth(host.bounds) - kDKInteractionKeyPeek;
    CGFloat y = CGRectGetMaxY(avatarFrame) + kDKInteractionKeyGap;
    CGRect frame = CGRectMake(x, y, side, side);
    if (!CGRectEqualToRect(key.frame, frame)) key.frame = frame;

    UIImageView *icon = (UIImageView *)[key viewWithTag:kDKInteractionKeyIconTag];
    if (icon) icon.frame = CGRectMake((side - 16.0) / 2.0, (side - 16.0) / 2.0, 16.0, 16.0);
    for (UIView *subview in ((UIVisualEffectView *)key).contentView.subviews) {
        if ([subview isKindOfClass:UIButton.class]) subview.frame = key.bounds;
    }
}

#pragma mark - 画中画悬浮窗

// 机制取自 Yoroin/GlobalRefresh-PiP 的 VideoCall 悬浮窗：透明的
// AVPictureInPictureVideoCallViewController 以 preferredContentSize 控制尺寸，
// 自定义 View 挂进 content view，AVPictureInPictureController(ContentSource)
// 启动；拖动、侧边吸附隐藏与缩放由系统负责。仅取悬浮窗本身，
// 不含其高刷请求与后台保活部分。

static BOOL gInteractionPiPActive = NO;

static CGFloat DKInteractionPiPSide(void) {
    NSInteger value = DKPrefInteger(DKKeyInteractionPiPSize);
    if (value <= 0) value = 48;
    return MIN(MAX((CGFloat)value, 24.0), 120.0);
}

static void DKInteractionShowFallbackKeys(void);

@interface DKInteractionPiPManager : NSObject <AVPictureInPictureControllerDelegate>
@property (nonatomic, strong) AVPictureInPictureController *pipController;
@property (nonatomic, strong) AVPictureInPictureVideoCallViewController *contentController;
@property (nonatomic, strong) UIView *sourceView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, assign) BOOL stoppingByUs;
+ (instancetype)sharedManager;
- (BOOL)startWithWindow:(UIWindow *)window;
- (void)stop;
- (void)applySize;
- (void)contentDidTap;
@end

@implementation DKInteractionPiPManager

+ (instancetype)sharedManager {
    static DKInteractionPiPManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ manager = [[DKInteractionPiPManager alloc] init]; });
    return manager;
}

- (void)contentDidTap {
    DKGlassTabBarSetCollapsed(NO);
}

- (void)updateIcon {
    UIView *platter = DKGlassTabBarCollapsePlatter();
    UIImageView *source = platter ? DKInteractionFindIcon(platter) : nil;
    self.iconView.image = source.image;
    self.iconView.tintColor = source.tintColor;
}

- (void)applySize {
    if (!self.contentController) return;
    CGFloat side = DKInteractionPiPSide();
    self.contentController.preferredContentSize = CGSizeMake(side, side);
}

- (BOOL)startWithWindow:(UIWindow *)window {
    if (!window) return NO;
    if (![AVPictureInPictureController isPictureInPictureSupported]) return NO;
    if (@available(iOS 15.0, *)) {
        CGFloat side = DKInteractionPiPSide();
        if (!self.sourceView) {
            self.sourceView = [[UIView alloc] init];
            self.sourceView.backgroundColor = UIColor.clearColor;
            self.sourceView.opaque = NO;
            self.sourceView.userInteractionEnabled = NO;
        }
        CGRect bounds = window.bounds;
        self.sourceView.frame = CGRectMake(CGRectGetWidth(bounds) - side - 8.0,
                                           CGRectGetHeight(bounds) * 0.66, side, side);
        if (self.sourceView.superview != window) [window addSubview:self.sourceView];

        if (!self.contentController) {
            self.contentController = [[AVPictureInPictureVideoCallViewController alloc] init];
            UIView *host = self.contentController.view;
            host.backgroundColor = UIColor.clearColor;
            host.opaque = NO;
            host.layer.backgroundColor = UIColor.clearColor.CGColor;
            host.layer.opaque = NO;
            host.clipsToBounds = YES;

            self.iconView = [[UIImageView alloc] init];
            self.iconView.contentMode = UIViewContentModeScaleAspectFit;
            self.iconView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [host addSubview:self.iconView];

            UIButton *hit = [UIButton buttonWithType:UIButtonTypeCustom];
            hit.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [hit addTarget:self action:@selector(contentDidTap) forControlEvents:UIControlEventTouchUpInside];
            [host addSubview:hit];
        }
        self.contentController.preferredContentSize = CGSizeMake(side, side);
        self.iconView.frame = CGRectInset(self.contentController.view.bounds, side * 0.22, side * 0.22);
        [self updateIcon];

        AVPictureInPictureControllerContentSource *source =
            [[AVPictureInPictureControllerContentSource alloc]
                initWithActiveVideoCallSourceView:self.sourceView
                            contentViewController:self.contentController];
        self.pipController = [[AVPictureInPictureController alloc] initWithContentSource:source];
        self.pipController.delegate = self;
        self.pipController.requiresLinearPlayback = YES;
        self.stoppingByUs = NO;
        gInteractionPiPActive = YES;
        [self.pipController startPictureInPicture];
        return YES;
    }
    return NO;
}

- (void)stop {
    if (self.pipController.isPictureInPictureActive) {
        self.stoppingByUs = YES;
        [self.pipController stopPictureInPicture];
    }
    gInteractionPiPActive = NO;
}

#pragma mark AVPictureInPictureControllerDelegate

- (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController
    failedToStartPictureInPictureWithError:(NSError *)error {
    gInteractionPiPActive = NO;
    DKInteractionShowFallbackKeys();
}

- (void)pictureInPictureControllerDidStopPictureInPicture:(AVPictureInPictureController *)pictureInPictureController {
    BOOL byUs = self.stoppingByUs;
    self.stoppingByUs = NO;
    gInteractionPiPActive = NO;
    // 用户手动关掉悬浮窗时把底栏展开，避免无入口。
    if (!byUs && gInteractionCollapsed) DKGlassTabBarSetCollapsed(NO);
}

- (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler:(void (^)(BOOL restored))completionHandler {
    DKGlassTabBarSetCollapsed(NO);
    completionHandler(YES);
}

@end

// 画中画启动失败时回退：显示贴边小圆键。
static void DKInteractionShowFallbackKeys(void) {
    if (!gInteractionCollapsed) return;
    for (UIView *stack in gInteractionStacks.allObjects) {
        UIView *key = objc_getAssociatedObject(stack, &kDKInteractionKeyViewKey);
        if (!key) continue;
        DKInteractionUpdateKeyIcon(key);
        key.hidden = NO;
        key.alpha = 1.0;
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
            // 画中画悬浮窗在运行时不显示回退小圆键。
            if (gInteractionCollapsed && !gInteractionPiPActive) {
                key.hidden = NO;
                key.alpha = 1.0;
            }
        }
    }

    for (UIView *element in stack.subviews) {
        if (DKInteractionIsAvatarElement(element)) continue;
        // 缩放已在本入口之前应用，当前 transform 即基准；收缩位移在其上叠加。
        DKInteractionRecordBase(element);
        // 展开过程交给动画，布局期只强制落定收缩态，避免打断动画。
        if (gInteractionCollapsed) {
            objc_setAssociatedObject(element, &kDKInteractionModifiedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(stack, &kDKInteractionModifiedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            element.userInteractionEnabled = NO;
            element.alpha = 0.0;
            element.transform = DKInteractionElementTarget(element, stack);
        }
    }
}

void DKInteractionCollapseSetCollapsed(BOOL collapsed) {
    gInteractionCollapsed = collapsed;
    if (!DKInteractionCollapseEnabled()) return;
    BOOL pipStarted = NO;
    if (collapsed) {
        UIWindow *window = nil;
        for (UIView *stack in gInteractionStacks.allObjects) {
            if (stack.window) { window = stack.window; break; }
        }
        if (!window) window = [UIApplication sharedApplication].windows.firstObject;
        pipStarted = [[DKInteractionPiPManager sharedManager] startWithWindow:window];
    } else {
        [[DKInteractionPiPManager sharedManager] stop];
    }
    for (UIView *stack in gInteractionStacks.allObjects) {
        UIView *key = objc_getAssociatedObject(stack, &kDKInteractionKeyViewKey);
        if (key && pipStarted) {
            key.hidden = YES;
            key.alpha = 0.0;
        } else if (key) {
            if (collapsed) {
                DKInteractionUpdateKeyIcon(key);
                key.hidden = NO;
                // 从右侧边缘外侧入到露出位置。
                key.transform = CGAffineTransformMakeTranslation(kDKInteractionKeySide, 0);
            }
            [UIView animateWithDuration:0.4 delay:0.0 usingSpringWithDamping:0.86 initialSpringVelocity:0.0
                                options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                             animations:^{
                                 key.alpha = collapsed ? 1.0 : 0.0;
                                 key.transform = collapsed ? CGAffineTransformIdentity
                                                           : CGAffineTransformMakeTranslation(kDKInteractionKeySide, 0);
                             }
                             completion:^(BOOL finished) {
                                 if (!collapsed) {
                                     key.hidden = YES;
                                     key.transform = CGAffineTransformIdentity;
                                 }
                             }];
        }
        for (UIView *element in stack.subviews) {
            if (DKInteractionIsAvatarElement(element)) continue;
            DKInteractionRecordBase(element);
            if (collapsed) {
                objc_setAssociatedObject(element, &kDKInteractionModifiedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(stack, &kDKInteractionModifiedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                element.userInteractionEnabled = NO;
            }
            CGAffineTransform target = DKInteractionElementTarget(element, stack);
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
            @"开启后，底栏动态收缩时右侧点赞、评论、收藏、分享按钮一起滑出隐藏且不拦截点击，头像保留；"
            @"展开入口是画中画悬浮窗（显示当前页图标，可拖动、拖到侧边吸附隐藏），点它或下滑展开。"
            @"需开启「悬浮玻璃底栏」与「动态收缩底栏」。");
        return DKSettingsOnChange(item, ^{ DKInteractionCollapseRefresh(); });
    });
    DKSettingsRegister(DKKeyInteractionPiPSize, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeTextInput(DKKeyInteractionPiPSize, @"悬浮窗大小", @"48", 60);
        return DKSettingsOnChange(item, ^{ [[DKInteractionPiPManager sharedManager] applySize]; });
    });
}
