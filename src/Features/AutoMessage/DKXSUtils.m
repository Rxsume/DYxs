#import "DKXSUtils.h"
#import "DKXSAwemeHeaders.h"
#import <os/log.h>

// DKXSAwemeHeaders 把 NSLog 重定义为 DKXSNSLog；这里先取消重定义，
// 再实现 DKXSNSLog 本体，否则实现体内调用 NSLog 会递归回自身导致链接 / 运行时问题。
#undef NSLog

void DKXSNSLog(NSString *format, ...) {
    if (!format.length) return;
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    if (!message.length) return;
    static os_log_t logger = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        logger = os_log_create("com.dyxs.tweak", "runtime");
    });
    os_log_with_type(logger, OS_LOG_TYPE_DEFAULT, "%{public}@", message);
    NSLog(@"%@", message);
}

@implementation DKXSUtils

+ (void)showToast:(NSString *)text {
    if (!text.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        Class toastClass = NSClassFromString(@"DUXToast");
        if (toastClass && [toastClass respondsToSelector:@selector(showText:)]) {
            [toastClass showText:text];
            return;
        }
        UIWindow *window = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:UIWindowScene.class]) {
                for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                    if (w.isKeyWindow) { window = w; break; }
                }
            }
            if (window) break;
        }
        if (!window) return;
        UILabel *label = [[UILabel alloc] init];
        label.text = text;
        label.textColor = UIColor.whiteColor;
        label.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.8];
        label.textAlignment = NSTextAlignmentCenter;
        label.numberOfLines = 0;
        label.font = [UIFont systemFontOfSize:14];
        label.layer.cornerRadius = 8;
        label.clipsToBounds = YES;
        CGSize size = [label sizeThatFits:CGSizeMake(window.bounds.size.width - 64, CGFLOAT_MAX)];
        label.frame = CGRectMake((window.bounds.size.width - size.width - 32) / 2,
                                 window.bounds.size.height - 160,
                                 size.width + 32, size.height + 20);
        [window addSubview:label];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.3 animations:^{ label.alpha = 0; } completion:^(__unused BOOL f) { [label removeFromSuperview]; }];
        });
    });
}

+ (BOOL)isDarkMode {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class]) {
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) { window = w; break; }
            }
        }
        if (window) break;
    }
    UIUserInterfaceStyle style = window ? window.traitCollection.userInterfaceStyle : UIScreen.mainScreen.traitCollection.userInterfaceStyle;
    return style == UIUserInterfaceStyleDark;
}

+ (UIViewController *)firstAvailableViewControllerFromView:(UIView *)view {
    UIResponder *responder = view;
    while (responder) {
        if ([responder isKindOfClass:UIViewController.class]) return (UIViewController *)responder;
        responder = responder.nextResponder;
    }
    return nil;
}

@end
