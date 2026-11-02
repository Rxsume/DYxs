//
//  DKXSBatch5dAppearance.xm
//  DYxs 全量合并第 5 批剩余部分（5d）staging，未并入 DYxs 源码。
//  移植来源：Wtrwx/DYYY 的 DYYY.xm（顶栏透明、头像透明、通知毛玻璃与圆角、
//  视频背景颜色、全局透明），符号一律 DYYY* -> DKXS*。
//
//  撞点与分工（主 agent 复核必读）：
//  - AWEFeedTopBarContainer：DYxs 的 DKTopBarAlpha.xm 只 hook 了
//    layoutSubviews / didMoveToWindow，本文件 hook didMoveToSuperview /
//    setAlpha:，方法不重叠，走 %orig 链共存；但两者都会改顶栏 alpha，
//    真机须确认 DKXSEnableTopBarFade（若开）与本透明度不互盖。
//  - AWEInnerNotificationWindow：DYxs 的 DKInnerNotificationGlass.xm hook 的
//    是 AWEInnerNotificationContainerView（容器内），本文件 hook 的是 Window，
//    类不重叠；但两者都是毛玻璃，叠加后可能更糊，真机二选一验证。
//  - 通知毛玻璃的 alpha 沿用上游做法：读第 4 批的 DKXSCommentBlurTransparent
//    （0–1 小数，非法时 0.5），不是本批新键，不要重复登记。
//  - 全局透明的 KVO：上游把 KVO 装在 AppDelegate hook 里；本文件改在 %ctor
//    里用一个常驻单例直接监听 defaults 的 DKXSGlobalTransparency 键，
//    变化时发 DKXSGlobalTransparencyDidChangeNotification，效果等价，
//    避免再动 AppDelegate。AWEElementStackView 的 setAlpha: 乘上全局系数。
//  - AWEAdAvatarView：DYxs 现有代码未 hook，无撞点。
//  - MTKView / AWEAwemeModel 的背景色方法：DYxs 未 hook，无撞点；
//    注意 AWEAwemeModel 本批 5c 文件也 hook，但方法不同（init/setVideo
//    与 awe_smartBackgroundColor/awe_playerBackgroundViewShowType 不重叠）。
//
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSString *const DKXSGlobalTransparencyKey = @"DKXSGlobalTransparency";
static NSString *const DKXSGlobalTransparencyDidChangeNotification = @"DKXSGlobalTransparencyDidChangeNotification";
static char kDKXSGlobalTransparencyBaseAlphaKey;
static char kDKXSGlobalTransparencyApplyingKey;
static const NSInteger DKXSIgnoreGlobalAlphaTag = 999999;

// 上游 DYYYUtils colorFromSchemeHexString 的最小版：只解析 #RGB / #RRGGBB /
// #AARRGGBB（八位忽略透明度）；"random" / "random_gradient" 这类 scheme 词
// 在本文件返回 nil（调用方 fallback 白色或原色），与 5a 的 helper 口径一致。
static UIColor *DKXSAppearanceColorFromHex(NSString *hex) {
    if (!hex || hex.length == 0) return nil;
    NSString *s = [hex stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([s hasPrefix:@"#"]) s = [s substringFromIndex:1];
    if (s.length == 3) {
        unichar r = [s characterAtIndex:0], g = [s characterAtIndex:1], b = [s characterAtIndex:2];
        s = [NSString stringWithFormat:@"%C%C%C%C%C%C", r, r, g, g, b, b];
    } else if (s.length == 8) {
        s = [s substringFromIndex:2];
    }
    if (s.length != 6) return nil;
    unsigned int rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:s];
    if (![scanner scanHexInt:&rgb] || !scanner.isAtEnd) return nil;
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0 alpha:1.0];
}

// 顶栏透明：0–1 小数；小于 0.011 时按上游钳到 0.011（避免顶栏彻底点不到）。
%hook AWEFeedTopBarContainer
- (void)didMoveToSuperview {
    %orig;
    [self setAlpha:self.alpha];
}
- (void)setAlpha:(CGFloat)alpha {
    NSString *transparentValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSTopBarTransparent"];
    if (transparentValue && transparentValue.length > 0) {
        CGFloat alphaValue = [transparentValue floatValue];
        if (alphaValue >= 0.0 && alphaValue <= 1.0) {
            CGFloat finalAlpha = (alphaValue < 0.011) ? 0.011 : alphaValue;
            %orig(finalAlpha);
        } else {
            %orig(1.0);
        }
    } else {
        %orig(1.0);
    }
}
%end

// 首页头像透明（AWEAdAvatarView；隐藏头像是第 3 批的 DKXSHideAvatarButton，
// 本文件只做透明度，不重复隐藏逻辑）。
%hook AWEAdAvatarView
- (void)layoutSubviews {
    %orig;
    NSString *transparencyValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSAvatarViewTransparency"];
    if (transparencyValue && transparencyValue.length > 0) {
        CGFloat alphaValue = [transparencyValue floatValue];
        if (alphaValue >= 0.0 && alphaValue <= 1.0) {
            self.alpha = alphaValue;
        }
    }
}
%end

// 应用内推送毛玻璃效果 + 圆角。
%hook AWEInnerNotificationWindow
- (void)layoutSubviews {
    %orig;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSEnableNotificationTransparency"]) {
        [self dkxs_setupBlurEffectForNotificationView];
    }
}
- (void)didMoveToWindow {
    %orig;
    if (self.window && [[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSEnableNotificationTransparency"]) {
        [self dkxs_setupBlurEffectForNotificationView];
    }
}
%new
- (void)dkxs_setupBlurEffectForNotificationView {
    for (UIView *subview in self.subviews) {
        if ([NSStringFromClass([subview class]) containsString:@"AWEInnerNotificationContainerView"]) {
            [self dkxs_applyBlurEffectToView:subview];
            break;
        }
    }
}
%new
- (void)dkxs_applyBlurEffectToView:(UIView *)containerView {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!containerView) return;
        containerView.backgroundColor = [UIColor clearColor];
        float userRadius = [[[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSNotificationCornerRadius"] floatValue];
        if (!userRadius || userRadius < 0 || userRadius > 50) {
            userRadius = 12;
        }
        containerView.layer.cornerRadius = userRadius;
        containerView.layer.masksToBounds = YES;
        for (UIView *subview in containerView.subviews) {
            if ([subview isKindOfClass:[UIVisualEffectView class]] && subview.tag == 999) {
                [subview removeFromSuperview];
            }
        }
        BOOL isDarkMode = containerView.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
        UIBlurEffectStyle blurStyle = isDarkMode ? UIBlurEffectStyleDark : UIBlurEffectStyleLight;
        UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:blurStyle]];
        blurView.frame = containerView.bounds;
        blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        blurView.tag = 999;
        blurView.layer.cornerRadius = userRadius;
        blurView.layer.masksToBounds = YES;
        // 上游同款：复用评论毛玻璃透明度键（第 4 批），非法时 0.5。
        float userTransparency = [[[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSCommentBlurTransparent"] floatValue];
        if (userTransparency <= 0 || userTransparency > 1) {
            userTransparency = 0.5;
        }
        blurView.alpha = userTransparency;
        [containerView insertSubview:blurView atIndex:0];
        [self dkxs_clearBackgroundRecursivelyInView:containerView];
        [self dkxs_setLabelsColorWhiteInView:containerView];
    });
}
%new
- (void)dkxs_setLabelsColorWhiteInView:(UIView *)view {
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)subview;
            NSString *text = label.text;
            if (![text isEqualToString:@"回复"] && ![text isEqualToString:@"查看"] && ![text isEqualToString:@"续火花"]) {
                label.textColor = [UIColor whiteColor];
            }
        }
        [self dkxs_setLabelsColorWhiteInView:subview];
    }
}
%new
- (void)dkxs_clearBackgroundRecursivelyInView:(UIView *)view {
    for (UIView *subview in view.subviews) {
        subview.backgroundColor = [UIColor clearColor];
        [self dkxs_clearBackgroundRecursivelyInView:subview];
    }
}
%end

// 视频背景颜色：MTKView 层 + 模型层两处（上游同款）。
%hook MTKView
- (void)layoutSubviews {
    %orig;
    NSString *colorHex = [[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSVideoBGColor"];
    if (colorHex && colorHex.length > 0) {
        // 仅在播放页视频控制器内的 MTKView 上色，避免把所有 Metal 视图都染了；
        // 上游用 firstAvailableViewControllerFromView 判 AWEPlayVideoViewController，
        // 这里用 responder 链找最近的 UIViewController 做等价判断。
        UIResponder *responder = self.nextResponder;
        while (responder && ![responder isKindOfClass:[UIViewController class]]) {
            responder = responder.nextResponder;
        }
        Class playVCClass = NSClassFromString(@"AWEPlayVideoViewController");
        if (responder && playVCClass && [responder isKindOfClass:playVCClass]) {
            CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
            (void)screenWidth;
            UIColor *customColor = DKXSAppearanceColorFromHex(colorHex);
            if (customColor) self.backgroundColor = customColor;
        }
    }
}
%end

%hook AWEAwemeModel
- (NSUInteger)awe_playerBackgroundViewShowType {
    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSVideoBGColor"]) {
        return 1;
    }
    return %orig;
}
- (UIColor *)awe_smartBackgroundColor {
    NSString *colorHex = [[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSVideoBGColor"];
    if (colorHex && colorHex.length > 0) {
        UIColor *customColor = DKXSAppearanceColorFromHex(colorHex);
        if (customColor) return customColor;
    }
    return %orig;
}
%end

// 全局透明：系数存 DKXSGlobalTransparency（0–1 文本）；AWEElementStackView
// 的 setAlpha: 按“基础 alpha × 全局系数”输出，基础 alpha 用关联对象记下，
// 避免反复乘算导致 alpha 越乘越小（上游同款做法）。
@interface DKXSGlobalTransparencyObserver : NSObject
+ (instancetype)shared;
@end
@implementation DKXSGlobalTransparencyObserver
+ (instancetype)shared {
    static DKXSGlobalTransparencyObserver *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [DKXSGlobalTransparencyObserver new];
        [[NSUserDefaults standardUserDefaults] addObserver:instance
                                                forKeyPath:DKXSGlobalTransparencyKey
                                                   options:NSKeyValueObservingOptionNew
                                                   context:NULL];
    });
    return instance;
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:DKXSGlobalTransparencyKey]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:DKXSGlobalTransparencyDidChangeNotification object:nil];
    }
}
@end

static CGFloat DKXSGlobalTransparencyValue(void) {
    NSString *s = [[NSUserDefaults standardUserDefaults] objectForKey:DKXSGlobalTransparencyKey];
    if (!s || s.length == 0) return -1;
    CGFloat v = [s floatValue];
    if (v < 0 || v > 1) return -1;
    return v;
}

%hook AWEElementStackView
- (void)setAlpha:(CGFloat)alpha {
    // 全局透明重算路径（dkxs_applyGlobalTransparency）会回调到这里：
    // 此时不更新基础 alpha，否则基础值会被乘算污染（上游同款 mutationDepth 做法）。
    NSNumber *applying = objc_getAssociatedObject(self, &kDKXSGlobalTransparencyApplyingKey);
    if (![applying boolValue]) {
        objc_setAssociatedObject(self, &kDKXSGlobalTransparencyBaseAlphaKey, @(alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSNumber *stored = objc_getAssociatedObject(self, &kDKXSGlobalTransparencyBaseAlphaKey);
    CGFloat base = stored ? [stored floatValue] : alpha;
    CGFloat g = DKXSGlobalTransparencyValue();
    CGFloat finalAlpha = alpha;
    if (g >= 0 && self.tag != DKXSIgnoreGlobalAlphaTag) {
        finalAlpha = base * g;
    }
    %orig(finalAlpha);
}
- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(dkxs_applyGlobalTransparency)
                                                     name:DKXSGlobalTransparencyDidChangeNotification
                                                   object:nil];
    } else {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                         name:DKXSGlobalTransparencyDidChangeNotification
                                                       object:nil];
    }
}
%new
- (void)dkxs_applyGlobalTransparency {
    CGFloat g = DKXSGlobalTransparencyValue();
    if (g < 0) return;
    NSNumber *stored = objc_getAssociatedObject(self, &kDKXSGlobalTransparencyBaseAlphaKey);
    CGFloat base = stored ? [stored floatValue] : 1.0;
    if (self.tag != DKXSIgnoreGlobalAlphaTag) {
        objc_setAssociatedObject(self, &kDKXSGlobalTransparencyApplyingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        self.alpha = base * g;
        objc_setAssociatedObject(self, &kDKXSGlobalTransparencyApplyingKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
%end

%ctor {
    [DKXSGlobalTransparencyObserver shared];
}
