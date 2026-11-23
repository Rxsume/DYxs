#ifndef DY778_SUPER_LUCKY_POLICY_H
#define DY778_SUPER_LUCKY_POLICY_H
#include <stdbool.h>
#include <stddef.h>
#include <string.h>
#include "DY778RedEnvelopePolicy.h"

// DY778 1.0-8 模块 3（超级福袋 SL）移植：纯数值/文本策略，
// 与 DY778RedEnvelopePolicy.h 同款风格，不含任何 ObjC 调用。
// 规格：~/workspace/plugin-merge/DY778/spec-module3-redenvelope-superlucky.md
//
// 命名说明：见 DY778RedEnvelopePolicy.h（DY778LuckyPolicy.h 已是 1.0-3
// 福袋助手的策略头文件）。本文件符号前缀为 DY778SL*；延迟/退避等
// 通用钳制复用 DY778RE*（同一保守设定，见上）。
//
// 默认值说明与红线见 DY778RedEnvelopePolicy.h（规格 §8、§11.1–§11.2）：
// 只证明了原版「尝试领取」的代码路径，没有任何证据证明这些调用在
// 抖音 40.8.0 上仍能成功领取；观看任务是否须真实停留未证实（规格
// §11.10）——DYxs 侧绝不伪造观看时长，只认任务上下文上报的已完成状态。

// SL 组心跳间隔（秒）与连续失败上限（规格 §4.7）。
enum { DY778SLGroupTickSeconds = 5, DY778SLMaximumGroupFailures = 5 };
// SL 执行延迟：复用 DY778REDelay 钳制（默认 3 秒，0–30 秒）。
// 开奖提醒提前秒数：默认 60 秒，钳制 0–3600 秒（键归模块 3，行为归模块 4）。
enum { DY778SLDefaultDrawReminderSeconds = 60, DY778SLMinimumDrawReminderSeconds = 0,
       DY778SLMaximumDrawReminderSeconds = 3600 };
// SL 领取记录上限（superLucky.records）。
enum { DY778SLMaximumRecords = 200 };
// SL 任务上下文记录键与通知（规格 §4.2）。
static const char *DY778SLTaskContextRecordKey = "DY778.superLucky.taskContext";
static const char *DY778SLNativeRecordPrefix = "DY778.SuperLucky.Native";
static const char *DY778SLNativeRequestStartedNotification = "DY778SLNativeRequestStarted";

// ---------- 网络端点（规格 §5） ----------
// 福袋 lottery API：%@ 为 activity 相关参数（未证实具体是哪个字段）。
static const char *DY778SLLotteryAPIFormat = "https://lianmengapi.snssdk.com/live/lottery/%@/";
static const char *DY778SLLotteryTemplateHost = "lf-webcast-sourcecdn-tos.bytegecko.com";
static const char *DY778SLLotteryTemplateFormat = "/fe_lynx_ecommerce_lottery/%@/template.%@";

// 提醒提前秒数钳制。
static inline double DY778SLDrawReminderSeconds(double value) {
    if (!(value >= 0)) return DY778SLDefaultDrawReminderSeconds;
    if (value > DY778SLMaximumDrawReminderSeconds) return DY778SLMaximumDrawReminderSeconds;
    return value;
}
#endif
