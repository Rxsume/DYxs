//
//  DKTwoFingerLongPressSettings.xm
//  双指长按打开 DYxs 设置面板：双指在播放页长按 0.5 秒，在当前页原地
//  弹出 DYxs 设置面板（毛玻璃纯黑 sheet），不跳转抖音设置页。
//  只在播放页交互控制器的 view 上挂一个双指长按手势；开关默认开启。
//  双指手势与抖音原有单指手势（单击、双击、单指长按倍速）触点数不同，不冲突。
//  其余页面（Story、关联视频、听抖音）不挂，保持原样。
//

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import <objc/runtime.h>

static char kDKTwoFingerPressKey;

// 当前最顶层控制器：从窗口根一路跟 presented / 导航栈顶 / 标签选中页。
static UIViewController *DKTwoFingerTopViewController(void) {
    UIWindow *window = UIApplication.sharedApplication.keyWindow ?: UIApplication.sharedApplication.delegate.window;
    UIViewController *top = window.rootViewController;
    while (top) {
        if (top.presentedViewController) { top = top.presentedViewController; continue; }
        if ([top isKindOfClass:UINavigationController.class]) {
            UIViewController *visible = ((UINavigationController *)top).visibleViewController;
            if (visible && visible != top) { top = visible; continue; }
        }
        if ([top isKindOfClass:UITabBarController.class]) {
            UIViewController *selected = ((UITabBarController *)top).selectedViewController;
            if (selected && selected != top) { top = selected; continue; }
        }
        break;
    }
    return top;
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
    UIViewController *presenter = DKTwoFingerTopViewController();
    if (!presenter) return;
    DKSettingsPresentMainPanel(presenter);
}

%end

%end

%ctor {
    // 默认开启：从未设置过时写一次 YES（用户关过则保留关闭）。
    if (![NSUserDefaults.standardUserDefaults objectForKey:DKKeyTwoFingerLongPressOpenSettings]) {
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:DKKeyTwoFingerLongPressOpenSettings];
    }
    DKSettingsRegister(DKKeyTwoFingerLongPressOpenSettings, ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyTwoFingerLongPressOpenSettings, @"双指长按打开设置面板", @"双指在播放页长按，在当前页弹出 DYxs 设置面板");
    });

    Class feed = NSClassFromString(@"AWEPlayInteractionViewController");
    if ([feed isSubclassOfClass:UIViewController.class]) {
        %init(DKTwoFingerLongPressSettingsHooks);
    }
}
