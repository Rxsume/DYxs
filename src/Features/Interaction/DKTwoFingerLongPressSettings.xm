//
//  DKTwoFingerLongPressSettings.xm
//  双指长按打开 DYxs 设置面板：双指在播放页长按 0.5 秒，推开 DYxs 设置主面板。
//  只在播放页交互控制器的 view 上挂一个双指长按手势；开关默认关闭。
//  双指手势与抖音原有单指手势（单击、双击、单指长按倍速）触点数不同，不冲突。
//  其余页面（Story、关联视频、听抖音）不挂，保持原样。
//

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import <objc/runtime.h>

static char kDKTwoFingerPressKey;

// 找到能 push 设置页的宿主：先沿父链找带导航栏的祖先，找不到时退到窗口根视图的导航栈顶。
static UIViewController *DKTwoFingerSettingsPresenter(UIViewController *owner) {
    for (UIViewController *node = owner; node; node = node.parentViewController) {
        if (node.navigationController) return node;
    }
    UIWindow *window = UIApplication.sharedApplication.keyWindow ?: UIApplication.sharedApplication.delegate.window;
    UIViewController *root = window.rootViewController;
    if ([root isKindOfClass:UITabBarController.class]) root = ((UITabBarController *)root).selectedViewController;
    if ([root isKindOfClass:UINavigationController.class]) return ((UINavigationController *)root).topViewController;
    return [root isKindOfClass:UIViewController.class] ? root : nil;
}

%group DKTwoFingerLongPressSettingsHooks

%hook AWEPlayInteractionViewController

- (void)viewDidLoad {
    %orig;
    if (objc_getAssociatedObject(self, &kDKTwoFingerPressKey)) return;
    UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(dk_openSettingsWithTwoFingerPress:)];
    press.numberOfTouchesRequired = 2;
    press.minimumPressDuration = 0.5;
    press.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:press];
    objc_setAssociatedObject(self, &kDKTwoFingerPressKey, press, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (void)dk_openSettingsWithTwoFingerPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    if (!DKPrefBool(DKKeyTwoFingerLongPressOpenSettings)) return;
    UIViewController *presenter = DKTwoFingerSettingsPresenter(self);
    if (!presenter.navigationController) return;
    DKSettingsOpenMain(presenter);
}

%end

%end

%ctor {
    DKSettingsRegister(DKKeyTwoFingerLongPressOpenSettings, ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyTwoFingerLongPressOpenSettings, @"双指长按打开设置面板", @"双指在播放页长按打开 DYxs 设置面板");
    });

    Class feed = NSClassFromString(@"AWEPlayInteractionViewController");
    if ([feed isSubclassOfClass:UIViewController.class]) {
        %init(DKTwoFingerLongPressSettingsHooks);
    }
}
