#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// DY778 1.0-8 模块 4 移植：备份恢复。
// 规格：~/workspace/plugin-merge/DY778/spec-module4-misc.md §3
//
// 导出格式（实锤）：文件名 DY778_backup_yyyyMMdd_HHmmss_SSS.zip
// （en_US_POSIX、Asia/Shanghai）；manifest.json 字段 version（1.0-8）、
// schema（com.dy778.backup）、format、created、accounts、files[]
// （每项 size、sha256）；内容为 preferences.plist（经黑名单过滤，
// 域名 com.dy778.douyin）、joker.plist（域名 com.dy778.joker）、
// stores/DY778/Recall/messages.sqlite（+ -wal / -shm）、
// stores/DY778/EditHistory/history.sqlite、
// stores/DY778Radar/account-*.json。
// 恢复是合并不是覆盖（setPersistentDomain + sqlite BEGIN IMMEDIATE
// 事务），走 operation.plist 两阶段（ready→committed），失败可回滚
// 到 previous-pending。
//
// DYxs 侧偏离（已注明原因）：
//  - 导出目录取 Documents/DY778Backup（Documents 还是 Caches 未证实，
//    规格 §3.2；Documents 用户可见、便于导出）。
//  - ZIP 写侧用 stored（method 0，不压缩）——写侧是否 deflate 未完全
//    还原（规格 §3.2）；stored 是合法 ZIP，读侧同时支持 method 0 与
//    method 8（inflate），故与原版 DY778 的备份互读。
//  - Recall/编辑历史/Radar 已于 2026-11-03 从 DYxs 删除，
//    stores 下的文件通常不存在；导出时只打包实际存在的文件，
//    manifest 只列已打包的条目，缺失不报错。
//  - _DY778BackupClear（0x30 字节）与 _DY778BackupTakeCompletion
//    （0x10 字节）的确切行为未解析：Clear 实现为删除备份目录下的
//    backup.zip/extracted/status 文件并写 pending clear 动作；
//    TakeCompletion 返回待处理的完成标记（无则为 nil）。
//  - _DY778BackupAccountID 首字符 '0' 的特殊处理未全拆：DYxs 侧只做
//    纯数字校验，首字符为 '0' 时仍接受并在校验信息里注明。
//  - _DY778BackupMergePreferences 的冲突裁决未完全还原：DYxs 侧以
//    备份值覆盖同键（addEntriesFromDictionary 语义），但
//    listClear.followExcluded./followUncertain. 前缀键做并集合并，
//    snapshot/workCache/spark.settings/displayStats.accounts 按原版
//    特殊处理（保留备份值）。

// 备份目录（Documents/DY778Backup）。
FOUNDATION_EXPORT NSURL *DY778BackupDirectoryURL(void);
// 备份状态：读 DY778Backup/status.plist；无文件时返回空字典。
FOUNDATION_EXPORT NSDictionary *DY778BackupStatus(void);
// 偏好键黑名单（规格 §3.3）：命中任一黑名单子串/前缀即不进备份。
FOUNDATION_EXPORT BOOL DY778BackupPreferenceAllowed(NSString *key);
// 过滤后的偏好字典（com.dy778.douyin 域，Joker 键单独分出）。
FOUNDATION_EXPORT NSDictionary *DY778BackupFilteredPreferences(void);
// Joker 键字典（com.dy778.joker 域，只含 7 个 Joker 键）。
FOUNDATION_EXPORT NSDictionary *DY778BackupJokerPreferences(void);
// SHA256 十六进制（CC_SHA256 + %02x，规格 §3.3）。
FOUNDATION_EXPORT NSString *DY778BackupDigest(NSData *data);
// 条目白名单（规格 §3.3，路径级）。
FOUNDATION_EXPORT BOOL DY778BackupEntryAllowed(NSString *relativePath);
// 校验偏好字典（错误域 DY778.Backup.Policy）。
FOUNDATION_EXPORT BOOL DY778BackupValidatePreferences(NSDictionary *preferences, NSError **error);
// 校验 manifest（version/accounts/每文件 size+sha256/条目白名单）。
FOUNDATION_EXPORT BOOL DY778BackupValidateManifest(NSDictionary *manifest, NSError **error);

// 设置页调用的三个动作（规格 §3.1，didSelectRowAtIndexPath 内）。
// Export：生成 zip → 弹 UIDocumentPickerViewController 导出。
FOUNDATION_EXPORT void DY778BackupExport(UIViewController *presenter);
// Import：弹 UIDocumentPickerViewController（只开 zip）→ 校验 →
// 解到 extracted → 写 operation.plist（phase=ready）→ ApplyPending。
FOUNDATION_EXPORT void DY778BackupImport(UIViewController *presenter);
// Clear：删除备份文件并写 pending clear 动作。
FOUNDATION_EXPORT void DY778BackupClear(void);
// 两阶段恢复：执行 operation.plist（ready→committed），失败回滚。
FOUNDATION_EXPORT BOOL DY778BackupApplyPending(NSError **error);
// 待处理的完成标记（未解析的 _DY778BackupTakeCompletion；无则 nil）。
FOUNDATION_EXPORT id DY778BackupTakeCompletion(void);

// DocumentPicker delegate（规格 §3.1，DY778BackupPicker，10 方法）。
@interface DY778BackupPicker : NSObject <UIDocumentPickerDelegate>
@property(nonatomic, copy) NSString *source;
@property(nonatomic, copy) NSString *temporary;
@property(nonatomic) BOOL importing;
- (instancetype)initForExportWithURL:(NSURL *)url;
- (instancetype)initForImportWithPresenter:(UIViewController *)presenter;
- (UIDocumentPickerViewController *)documentPickerForExport;
- (void)finish;
@end
