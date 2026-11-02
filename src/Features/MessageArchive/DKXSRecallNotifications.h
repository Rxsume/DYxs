//  DKXSRecallNotifications.h
//  DY778 第 1 批 staging：撤回 / 编辑提醒。
//  对应上游 DY778RecallNotifications.h，改名前缀；行为保留：
//  · 两个提醒开关默认全部关闭（DKXSRecallNotifications / DKXSEditNotifications）；
//  · 前台时只显示应用内横幅，不发系统通知；后台时才发本地通知；
//  · 预览开关（notificationPreview）关时，通知正文只写“有新记录”，不带消息内容；
//  · 点按通知进入对应记录页（经 DKXSArchiveNotificationDelegate 转发实现，见 .m）。

#import <UIKit/UIKit.h>

// 由观测层在“新撤回边 / 新编辑版本”确认后调用；开关关时直接返回。
FOUNDATION_EXPORT void DKXSRecallNotifyDetected(NSDictionary *record);
FOUNDATION_EXPORT void DKXSEditNotifyDetected(NSDictionary *record);
// 设置页动作行用：申请系统通知权限、展示当前提醒状态。
FOUNDATION_EXPORT void DKXSRecallRequestNotificationPermission(UIViewController *source);
FOUNDATION_EXPORT void DKXSEditRequestNotificationPermission(UIViewController *source);
FOUNDATION_EXPORT void DKXSRecallShowNotificationStatus(UIViewController *source);
// hooks 文件用：把 UNUserNotificationCenter 的 delegate 包一层转发代理（只拦截本批标识）。
FOUNDATION_EXPORT void DKXSArchiveInstallNotificationDelegate(void);
FOUNDATION_EXPORT BOOL DKXSArchiveIsOwnNotification(NSString *identifier);
