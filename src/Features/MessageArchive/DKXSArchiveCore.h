//  DKXSArchiveCore.h
//  DY778 第 1 批 staging：档案层共用基础。
//  对应上游 DY778Core.h 中本批用到的部分（偏好读写、安全取值、身份、颜色、提示、顶层控制器）。
//  关键改动：
//  · 偏好全部走 DYxs 标准 defaults，不用上游独立 suite（com.dy778.douyin），不做旧域迁移；
//  · 丢弃上游主题/点缀色/设置页/测速提示等本批无关能力；
//  · DY778Hook / HookReport 机制不移植，改由 DKXSMessageArchiveHooks.xm 做存在性自检。

#import <UIKit/UIKit.h>

// ---- 偏好（标准 defaults；带默认值的读法，见 .m 的 DKXSArchiveRegisterDefaults） ----
FOUNDATION_EXPORT BOOL DKXSArchiveBool(NSString *key);
FOUNDATION_EXPORT BOOL DKXSArchiveBoolDefault(NSString *key, BOOL fallback);
FOUNDATION_EXPORT double DKXSArchiveNumber(NSString *key);
FOUNDATION_EXPORT double DKXSArchiveNumberDefault(NSString *key, double fallback);
FOUNDATION_EXPORT NSString *DKXSArchiveString(NSString *key);
FOUNDATION_EXPORT void DKXSArchiveSet(NSString *key, id value);
FOUNDATION_EXPORT void DKXSArchiveRegisterDefaults(void);
// 位置选项：DKMakeChoice 存下标，顺序固定 [右侧, 上方, 下方]，对应 0/1/2。
FOUNDATION_EXPORT NSInteger DKXSArchivePositionIndex(NSString *key);

// ---- 安全取值（KVC/字典双路，异常吞掉；上游 DY778Read/DY778Write/DY778Identifier） ----
FOUNDATION_EXPORT id DKXSArchiveRead(id object, NSString *key);
FOUNDATION_EXPORT BOOL DKXSArchiveWrite(id object, NSString *key, id value);
FOUNDATION_EXPORT NSString *DKXSArchiveIdentifier(id value);
// 秒/毫秒时间戳归一化为秒；无效返回 0。
FOUNDATION_EXPORT NSTimeInterval DKXSArchiveTimestamp(id value);

// ---- 身份与界面 ----
FOUNDATION_EXPORT NSString *DKXSArchiveCurrentAccountID(void);
FOUNDATION_EXPORT UIColor *DKXSArchiveColorFromHex(NSString *hex, UIColor *fallback);
FOUNDATION_EXPORT UIWindow *DKXSArchiveActiveWindow(void);
FOUNDATION_EXPORT UIViewController *DKXSArchiveTopController(void);
FOUNDATION_EXPORT void DKXSArchiveToast(NSString *message);
FOUNDATION_EXPORT void DKXSArchiveShowNotice(UIViewController *source, NSString *title, NSString *message);

// ---- 标记文字（空值回退默认） ----
FOUNDATION_EXPORT NSString *DKXSRecallMarkerText(void);
FOUNDATION_EXPORT NSString *DKXSEditMarkerText(void);
