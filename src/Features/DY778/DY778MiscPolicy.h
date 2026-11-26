#ifndef DY778_MISC_POLICY_H
#define DY778_MISC_POLICY_H
#include <stdbool.h>
#include <stddef.h>
#include <string.h>

// DY778 1.0-8 模块 4（备份恢复 + 抽奖提醒 + 评论展开 + 清理关注 +
// 直播外观编辑）移植：纯数值/文本策略，与 DY778LiveToolsPolicy.h /
// DY778LiveAnalysisPolicy.h / DY778RedEnvelopePolicy.h 同款风格，
// 不含任何 ObjC 调用。
// 规格：~/workspace/plugin-merge/DY778/spec-module4-misc.md
//
// 默认值说明（规格 §10）：1.0-8 二进制里的模块 4 设置键默认值静态
// 未证实（外观 3 项除外：alignment=center、order=viewersFirst、
// scale=1.0 是反汇编实锤）。以下数值按模块 1 同类键的约定写——
// 总开关默认关——以设置页运行时实测为准，不要把本文件当默认值依据。
//
// 红线（规格 §6.8、§5.4、§3.3）：
//  - 清理关注是破坏性操作：取关是否走服务端接口、是否立即生效、
//    是否可逆、是否触发风控/限流，一律未证实；节流间隔/重试上限/
//    退避策略未还原；ListClearJob kind 枚举值未还原；Receipt verified
//    的核对方式未还原。以下数值是 DYxs 侧的保守设定，不是原版数值，
//    不得写成已确认。DY778ListClearCanSubmit 在未证实前恒为 NO，
//    即取关提交不执行，只做列表读取/选择/保护/排除与收据记录。
//  - 评论展开的“展开”具体 UI 动作未静态还原，不得按猜测实现；
//    DYxs 侧只做 hook 与扫描记录，展开动作留空。
//  - 备份恢复已于 0.6.9.45 去重删除（与 DYxs 本体 src/Settings/Backup/
//    重复，保留本体那套）；本文件不再含备份策略常量。

// ---------- 抽奖提醒（规格 §4） ----------
// 秒数字符串格式未证实（规格 §4.2，可能是 "90" 或 "90s"）；
// DY778DrawReminderParseSeconds 两者都接受。
// 提醒记录上限（DYxs 侧设定，未证实）。
enum { DY778DrawReminderMaximumRecords = 200 };
// 计时器容差（秒，DYxs 侧设定，未证实）。
enum { DY778DrawReminderTimerToleranceSeconds = 5 };
// canPresent 挡掉的 presented 控制器类名子串（规格 §4.2，实锤）。
static const char *DY778DrawReminderBlockedControllerSubstrings[] = {
    "pay", "cashier", "orderconfirm", "captcha", "verify", "camera",
    "record", "auth"
};
enum { DY778DrawReminderBlockedControllerSubstringCount = 8 };

// ---------- 评论展开（规格 §5） ----------
// 扫描节流：滚动停止后重扫的最小间隔（秒，DYxs 侧设定，未证实；
// 原版 resumeAfter 具体秒数未静态还原）。
enum { DY778CommentExpandRescanMinimumSeconds = 2 };
// 会话记录上限（DYxs 侧设定，未证实）。
enum { DY778CommentExpandMaximumRecords = 500 };

// ---------- 清理关注（规格 §6） ----------
// kind 枚举值未静态还原（规格 §6.8）。以下取值是 DYxs 侧内部编号，
// 只用于在两个引擎与设置页之间区分清理对象，不得写成原版数值。
typedef enum {
    DY778ListClearKindFollow = 0,     // 关注（DY778FollowJob 专用）
    DY778ListClearKindLike = 1,       // 点赞
    DY778ListClearKindRecommend = 2,  // 推荐
    DY778ListClearKindFavorite = 3    // 收藏夹
} DY778ListClearKind;
// confirmKind 里出现的 200 疑似单次上限，未证实（规格 §6.3）；
// DYxs 侧默认取 200，用户可在种类选择器里改。
enum { DY778ListClearDefaultLimit = 200, DY778ListClearMaximumLimit = 200 };
// 节流（DYxs 侧保守设定，未证实；原版 nextAt/slowed/timeoutAt 的
// 具体秒数未静态还原）。
enum { DY778ListClearItemIntervalSeconds = 2, DY778ListClearPageIntervalSeconds = 5,
       DY778ListClearRequestTimeoutSeconds = 30, DY778ListClearMaximumFailures = 3 };
// 验证码视图类名（规格 §6.1，实锤）。
static const char *DY778ListClearVerificationViewClass = "BDTuringVerifyView";

// ---------- 直播外观（规格 §7，全部实锤） ----------
// 默认 {alignment=1, order=0, scale=1.0}；scale 夹取 [0.75, 1.5]；
// 胶囊基宽 294.0、高 28×scale。
enum { DY778LiveAppearanceDefaultAlignment = 1, DY778LiveAppearanceDefaultOrder = 0 };
static const double DY778LiveAppearanceDefaultScale = 1.0;
static const double DY778LiveAppearanceMinimumScale = 0.75;
static const double DY778LiveAppearanceMaximumScale = 1.5;
static const double DY778LiveAppearanceCapsuleBaseWidth = 294.0;
static const double DY778LiveAppearanceCapsuleBaseHeight = 28.0;
// 枚举映射是高置信度静态推断（规格 §7.2），须运行时以 StoredValue
// 回读验证：alignment 0=left、1=center、2=right；
// order 0=viewersFirst、1=durationFirst。
static inline bool DY778LiveAppearanceValidAlignment(long long value) { return value >= 0 && value <= 2; }
static inline bool DY778LiveAppearanceValidOrder(long long value) { return value >= 0 && value <= 1; }
// scale 钳制实现在 DY778LiveAppearance.m（与 DY778LiveAppearance.h
// 的 FOUNDATION_EXPORT 声明一致）；这里不重复定义，避免与头文件冲突。

#endif
