//  DKXSArchiveCore.m
//  DY778 第 1 批 staging：见头文件注释。

#import "DKXSArchiveCore.h"
#import <objc/message.h>
#import <objc/runtime.h>

static NSUserDefaults *DKXSArchiveDefaults(void) { return NSUserDefaults.standardUserDefaults; }

void DKXSArchiveRegisterDefaults(void) {
    // 只注册“默认开”的项与文字/颜色/数值默认值；已由用户写过的值不受影响。
    // 注意：DKMakeSwitch 行本身读 boolForKey，未注册时显示关——注册后行显示与功能一致。
    [DKXSArchiveDefaults() registerDefaults:@{
        @"DKXSRecallBadge": @YES, @"DKXSRecallBadgeText": @"已撤回", @"DKXSRecallArchiveEntry": @YES,
        @"DKXSRecallBubbleColor": @"#4A3038",
        @"DKXSEditBadge": @YES, @"DKXSEditBadgeText": @"编辑历史", @"DKXSEditArchiveEntry": @YES,
        @"DKXSEditBubbleColor": @"#3A6558",
        @"DKXSTimeFormat": @"HH:mm:ss", @"DKXSTimeSmartDate": @YES, @"DKXSTimeFontSize": @11,
        @"DKXSTimeColor": @"#66D8C5", @"DKXSTimeBackground": @YES, @"DKXSTimeOpacity": @0.94,
    }];
}

BOOL DKXSArchiveBool(NSString *key) { return [DKXSArchiveDefaults() boolForKey:key]; }
BOOL DKXSArchiveBoolDefault(NSString *key, BOOL fallback) {
    id value = [DKXSArchiveDefaults() objectForKey:key];
    return value ? [value boolValue] : fallback;
}
double DKXSArchiveNumber(NSString *key) {
    id value = [DKXSArchiveDefaults() objectForKey:key];
    if ([value isKindOfClass:NSNumber.class]) return [(NSNumber *)value doubleValue];
    if ([value isKindOfClass:NSString.class]) return [(NSString *)value doubleValue];
    return 0;
}
double DKXSArchiveNumberDefault(NSString *key, double fallback) {
    return [DKXSArchiveDefaults() objectForKey:key] ? DKXSArchiveNumber(key) : fallback;
}
NSString *DKXSArchiveString(NSString *key) {
    id value = [DKXSArchiveDefaults() objectForKey:key];
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) return [(NSNumber *)value stringValue];
    return @"";
}
void DKXSArchiveSet(NSString *key, id value) {
    if (!key) return;
    if (value) [DKXSArchiveDefaults() setObject:value forKey:key];
    else [DKXSArchiveDefaults() removeObjectForKey:key];
}
NSInteger DKXSArchivePositionIndex(NSString *key) {
    // 0 右侧 / 1 上方 / 2 下方；非法值回退右侧。
    NSInteger index = [DKXSArchiveDefaults() integerForKey:key];
    return index >= 0 && index <= 2 ? index : 0;
}

id DKXSArchiveRead(id object, NSString *key) {
    if (!object || !key.length) return nil;
    if ([object isKindOfClass:NSDictionary.class]) return object[key];
    @try { return [object valueForKey:key]; } @catch (__unused NSException *e) { return nil; }
}
BOOL DKXSArchiveWrite(id object, NSString *key, id value) {
    if (!object || !key.length) return NO;
    if ([object isKindOfClass:NSMutableDictionary.class]) { object[key] = value ?: NSNull.null; return YES; }
    @try { [object setValue:value forKey:key]; return YES; } @catch (__unused NSException *e) { return NO; }
}
NSString *DKXSArchiveIdentifier(id value) {
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) return [(NSNumber *)value stringValue];
    return @"";
}
NSTimeInterval DKXSArchiveTimestamp(id value) {
    double time = 0;
    if ([value isKindOfClass:NSNumber.class]) time = [(NSNumber *)value doubleValue];
    else if ([value isKindOfClass:NSDate.class]) return [(NSDate *)value timeIntervalSince1970];
    else if ([value isKindOfClass:NSString.class]) time = [(NSString *)value doubleValue];
    if (time > 1e12) time /= 1000; // 毫秒 → 秒
    return time > 0 && time < 1e11 ? time : 0;
}

NSString *DKXSArchiveCurrentAccountID(void) {
    // 尽力而为的三路解析（40.8.0 漂移风险点，见 REPORT）：
    // 1) AWEUserService 当前用户；2) HTSServiceCenter 的用户服务；3) 无。
    // 拿不到时返回空串，调用方必须把“账号未知”当作不留存、不提醒处理，
    // 绝不能 fallback 到另一个账号，否则会把 A 的记录记到 B 名下。
    @try {
        Class serviceClass = NSClassFromString(@"AWEUserService");
        id service = nil;
        if ([serviceClass respondsToSelector:@selector(sharedInstance)]) service = ((id (*)(id, SEL))objc_msgSend)(serviceClass, @selector(sharedInstance));
        if (!service && [serviceClass respondsToSelector:@selector(shared)]) service = ((id (*)(id, SEL))objc_msgSend)(serviceClass, @selector(shared));
        id user = service ? DKXSArchiveRead(service, @"currentUser") : nil;
        NSString *uid = DKXSArchiveIdentifier(DKXSArchiveRead(user, @"uid") ?: DKXSArchiveRead(user, @"userID"));
        if (uid.length && ![uid isEqualToString:@"0"]) return uid;
    } @catch (__unused NSException *e) { }
    return @"";
}

UIColor *DKXSArchiveColorFromHex(NSString *hex, UIColor *fallback) {
    NSString *clean = [[hex stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if (clean.length != 6) return fallback ?: UIColor.labelColor;
    unsigned int rgb = 0;
    if (![[NSScanner scannerWithString:clean] scanHexInt:&rgb]) return fallback ?: UIColor.labelColor;
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1];
}

UIWindow *DKXSArchiveActiveWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in [(UIWindowScene *)scene windows]) if (window.isKeyWindow) return window;
    }
    return UIApplication.sharedApplication.windows.firstObject;
}
UIViewController *DKXSArchiveTopController(void) {
    UIViewController *top = DKXSArchiveActiveWindow().rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    if ([top isKindOfClass:UINavigationController.class]) top = [(UINavigationController *)top topViewController];
    if ([top isKindOfClass:UITabBarController.class]) top = [(UITabBarController *)top selectedViewController];
    return top;
}

void DKXSArchiveToast(NSString *message) {
    if (!message.length || !NSThread.isMainThread) {
        if (message.length) dispatch_async(dispatch_get_main_queue(), ^{ DKXSArchiveToast(message); });
        return;
    }
    UIWindow *window = DKXSArchiveActiveWindow();
    if (!window) return;
    UILabel *label = [UILabel new];
    label.text = message; label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    label.textColor = UIColor.whiteColor; label.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:.82];
    label.textAlignment = NSTextAlignmentCenter; label.numberOfLines = 0;
    label.layer.cornerRadius = 10; label.layer.masksToBounds = YES;
    CGSize size = [label sizeThatFits:CGSizeMake(window.bounds.size.width - 80, CGFLOAT_MAX)];
    label.frame = CGRectMake((window.bounds.size.width - size.width - 32) / 2, window.bounds.size.height - 180, size.width + 32, size.height + 20);
    [window addSubview:label];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [label removeFromSuperview]; });
}
void DKXSArchiveShowNotice(UIViewController *source, NSString *title, NSString *message) {
    UIViewController *presenter = source ?: DKXSArchiveTopController();
    if (!presenter) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

static NSString *DKXSArchiveNormalizeMarker(NSString *value, NSString *fallback) {
    NSString *trimmed = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length || trimmed.length > 12) return fallback;
    return trimmed;
}
NSString *DKXSRecallMarkerText(void) { return DKXSArchiveNormalizeMarker(DKXSArchiveString(@"DKXSRecallBadgeText"), @"已撤回"); }
NSString *DKXSEditMarkerText(void) { return DKXSArchiveNormalizeMarker(DKXSArchiveString(@"DKXSEditBadgeText"), @"编辑历史"); }
