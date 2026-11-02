//  DKXSRecallNotifications.m
//  DY778 第 1 批 staging：见头文件注释。
//  转发代理说明：不替换、不丢弃抖音原有 delegate；只在原 delegate 已存在时包一层，
//  本批标识的响应先处理（打开记录页），其余一律转发；原 delegate 为空时不接管。

#import "DKXSRecallNotifications.h"
#import "DKXSArchiveCore.h"
#import "DKXSRecall.h"
#import "DKXSEditHistory.h"
#import <UserNotifications/UserNotifications.h>
#import <CommonCrypto/CommonDigest.h>
#import <objc/runtime.h>

static NSString *DKXSNoticeDigest(NSString *key) {
    NSData *data = [key dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *value = [NSMutableString stringWithCapacity:16];
    for (NSUInteger i = 0; i < 8; i++) [value appendFormat:@"%02x", digest[i]];
    return value;
}
static NSString *DKXSNoticePrefix(NSDictionary *record) {
    return [record[@"noticeKind"] isEqualToString:@"edit"] ? @"DKXS.Edit." : @"DKXS.Recall.";
}
BOOL DKXSArchiveIsOwnNotification(NSString *identifier) {
    return [identifier hasPrefix:@"DKXS.Recall."] || [identifier hasPrefix:@"DKXS.Edit."];
}
static NSString *DKXSNoticeTitle(NSDictionary *record) {
    return [record[@"noticeKind"] isEqualToString:@"edit"] ? @"消息被编辑" : @"消息被撤回";
}
static NSString *DKXSNoticeBody(NSDictionary *record, BOOL preview) {
    if (!preview) return [record[@"noticeKind"] isEqualToString:@"edit"] ? @"有新的编辑历史记录" : @"有新的撤回记录";
    NSString *summary = record[@"summary"];
    if (!summary.length) summary = @"已留存原文";
    NSString *sender = record[@"senderName"];
    return sender.length ? [NSString stringWithFormat:@"%@：%@", sender, summary] : summary;
}
@interface DKXSNoticeBannerHandler : NSObject
@end
@implementation DKXSNoticeBannerHandler
- (void)bannerTapped:(UITapGestureRecognizer *)tap {
    NSDictionary *record = objc_getAssociatedObject(tap.view, @"DKXSNoticeRecord");
    [tap.view removeFromSuperview];
    if (!record) return;
    if ([record[@"noticeKind"] isEqualToString:@"edit"]) DKXSEditHistoryPresentedFrom(nil, record[@"conversation"], record[@"key"]);
    else DKXSRecallArchivePresentedFrom(nil, record[@"conversation"]);
}
@end
static void DKXSShowBanner(NSDictionary *record) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ DKXSShowBanner(record); }); return; }
    UIWindow *window = DKXSArchiveActiveWindow();
    if (!window) return;
    UIView *banner = [[UIView alloc] initWithFrame:CGRectMake(12, 54, window.bounds.size.width - 24, 64)];
    banner.backgroundColor = [UIColor.systemBackgroundColor colorWithAlphaComponent:0.96];
    banner.layer.cornerRadius = 12; banner.layer.borderWidth = 0.5; banner.layer.borderColor = UIColor.separatorColor.CGColor;
    banner.layer.shadowColor = UIColor.blackColor.CGColor; banner.layer.shadowOpacity = 0.15; banner.layer.shadowOffset = CGSizeMake(0, 2);
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(12, 8, banner.bounds.size.width - 24, 20)];
    title.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold]; title.text = DKXSNoticeTitle(record);
    UILabel *body = [[UILabel alloc] initWithFrame:CGRectMake(12, 30, banner.bounds.size.width - 24, 26)];
    body.font = [UIFont systemFontOfSize:13]; body.textColor = UIColor.secondaryLabelColor; body.numberOfLines = 1;
    body.text = DKXSNoticeBody(record, [record[@"noticeKind"] isEqualToString:@"edit"] ? DKXSArchiveBool(@"DKXSEditNotificationPreview") : DKXSArchiveBool(@"DKXSRecallNotificationPreview"));
    [banner addSubview:title]; [banner addSubview:body];
    DKXSNoticeBannerHandler *handler = [DKXSNoticeBannerHandler new];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:handler action:@selector(bannerTapped:)];
    // 手势不持有 target，handler 挂在 banner 上保活。
    objc_setAssociatedObject(banner, @"DKXSNoticeHandler", handler, OBJC_ASSOCIATION_RETAIN);
    // 点按横幅进入记录页：用关联对象带上记录，tap 回调里再打开。
    objc_setAssociatedObject(banner, @"DKXSNoticeRecord", record, OBJC_ASSOCIATION_RETAIN);
    [banner addGestureRecognizer:tap];
    [window addSubview:banner];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [banner removeFromSuperview]; });
}
static void DKXSNotify(NSDictionary *record, NSString *kind) {
    BOOL enabled = [kind isEqualToString:@"edit"] ? DKXSArchiveBool(@"DKXSEditNotifications") : DKXSArchiveBool(@"DKXSRecallNotifications");
    if (!enabled) return;
    NSMutableDictionary *notice = [record mutableCopy];
    notice[@"noticeKind"] = kind;
    notice[@"summary"] = record[@"card"][@"text"] ?: @"";
    if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive) { DKXSShowBanner(notice); return; }
    UNUserNotificationCenter *center = UNUserNotificationCenter.currentNotificationCenter;
    UNMutableNotificationContent *content = [UNMutableNotificationContent new];
    content.title = DKXSNoticeTitle(notice);
    content.body = DKXSNoticeBody(notice, [kind isEqualToString:@"edit"] ? DKXSArchiveBool(@"DKXSEditNotificationPreview") : DKXSArchiveBool(@"DKXSRecallNotificationPreview"));
    content.userInfo = @{@"DKXSKey": record[@"key"] ?: @"", @"DKXSConversation": record[@"conversation"] ?: @"", @"DKXSKind": kind};
    NSString *identifier = [DKXSNoticePrefix(notice) stringByAppendingString:DKXSNoticeDigest(record[@"key"] ?: @"")];
    [center addNotificationRequest:[UNNotificationRequest requestWithIdentifier:identifier content:content trigger:nil] withCompletionHandler:nil];
}
void DKXSRecallNotifyDetected(NSDictionary *record) { DKXSNotify(record, @"recall"); }
void DKXSEditNotifyDetected(NSDictionary *record) { DKXSNotify(record, @"edit"); }
static void DKXSRequestPermission(UIViewController *source, NSString *kind) {
    [UNUserNotificationCenter.currentNotificationCenter requestAuthorizationWithOptions:UNAuthorizationOptionAlert | UNAuthorizationOptionSound completionHandler:^(BOOL granted, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (granted) DKXSArchiveToast(@"通知权限已开启，提醒将在后台到达时发送");
            else DKXSArchiveShowNotice(source, @"通知权限未开启", error ? error.localizedDescription : @"请在系统设置中为抖音开启通知，否则后台提醒无法送达。");
        });
    }];
}
void DKXSRecallRequestNotificationPermission(UIViewController *source) { DKXSRequestPermission(source, @"recall"); }
void DKXSEditRequestNotificationPermission(UIViewController *source) { DKXSRequestPermission(source, @"edit"); }
void DKXSRecallShowNotificationStatus(UIViewController *source) {
    [UNUserNotificationCenter.currentNotificationCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *status = settings.authorizationStatus == UNAuthorizationStatusAuthorized ? @"已授权" : @"未授权";
            DKXSArchiveShowNotice(source, @"提醒状态", [NSString stringWithFormat:@"系统通知：%@\n撤回提醒：%@\n编辑提醒：%@\n（提醒默认关闭，预览默认关闭）",
                status, DKXSArchiveBool(@"DKXSRecallNotifications") ? @"开" : @"关", DKXSArchiveBool(@"DKXSEditNotifications") ? @"开" : @"关"]);
        });
    }];
}

// ---- 转发代理 ----
@interface DKXSArchiveNotificationDelegate : NSObject <UNUserNotificationCenterDelegate>
@property(nonatomic, weak) id original;
@end
@implementation DKXSArchiveNotificationDelegate
- (id)forwardingTargetForSelector:(SEL)selector { return self.original; }
- (BOOL)respondsToSelector:(SEL)selector {
    if ([super respondsToSelector:selector]) return YES;
    return [self.original respondsToSelector:selector];
}
- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    if (DKXSArchiveIsOwnNotification(notification.request.identifier)) {
        if ([self.original respondsToSelector:@selector(userNotificationCenter:willPresentNotification:withCompletionHandler:)])
            [self.original userNotificationCenter:center willPresentNotification:notification withCompletionHandler:completionHandler];
        else completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionSound);
        return;
    }
    if ([self.original respondsToSelector:@selector(userNotificationCenter:willPresentNotification:withCompletionHandler:)])
        [self.original userNotificationCenter:center willPresentNotification:notification withCompletionHandler:completionHandler];
    else completionHandler(UNNotificationPresentationOptionNone);
}
- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(void (^)(void))completionHandler {
    NSString *identifier = response.notification.request.identifier;
    if (DKXSArchiveIsOwnNotification(identifier)) {
        NSDictionary *info = response.notification.request.content.userInfo;
        NSString *kind = info[@"DKXSKind"];
        NSString *conversation = info[@"DKXSConversation"];
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([kind isEqualToString:@"edit"]) DKXSEditHistoryPresentedFrom(nil, conversation, nil);
            else DKXSRecallArchivePresentedFrom(nil, conversation);
        });
    }
    if ([self.original respondsToSelector:@selector(userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:)])
        [self.original userNotificationCenter:center didReceiveNotificationResponse:response withCompletionHandler:completionHandler];
    else completionHandler();
}
@end
void DKXSArchiveInstallNotificationDelegate(void) {
    UNUserNotificationCenter *center = UNUserNotificationCenter.currentNotificationCenter;
    id delegate = center.delegate;
    if (!delegate || [delegate isKindOfClass:DKXSArchiveNotificationDelegate.class]) return;
    DKXSArchiveNotificationDelegate *wrapper = [DKXSArchiveNotificationDelegate new];
    wrapper.original = delegate;
    center.delegate = wrapper;
    objc_setAssociatedObject(center, @selector(DKXSArchiveInstallNotificationDelegate), wrapper, OBJC_ASSOCIATION_RETAIN);
}
