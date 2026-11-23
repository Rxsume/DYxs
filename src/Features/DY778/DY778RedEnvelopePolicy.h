#ifndef DY778_RED_ENVELOPE_POLICY_H
#define DY778_RED_ENVELOPE_POLICY_H
#include <stdbool.h>
#include <stddef.h>
#include <string.h>

// DY778 1.0-8 模块 3（红包自动抢 RE）移植：纯数值/文本策略，
// 与 DY778LiveToolsPolicy.h / DY778LiveAnalysisPolicy.h 同款风格，
// 不含任何 ObjC 调用。
// 规格：~/workspace/plugin-merge/DY778/spec-module3-redenvelope-superlucky.md
//
// 命名说明：DY778LuckyPolicy.h 已是 1.0-3 福袋助手（DY778LuckyBag）的
// 策略头文件（DY778LuckyClassifyButton 等），故模块 3 的策略按规格 §10
// 拆成 DY778RedEnvelopePolicy.h 与 DY778SuperLuckyPolicy.h，符号前缀
// 为 DY778RE* / DY778SL*，不与 1.0-3 的 DY778Lucky* 冲突。
//
// 默认值说明（规格 §8、§11.2–§11.3）：1.0-8 二进制里的 redEnvelope.* /
// superLucky.* / lucky.* 键默认值静态未证实（安装函数本身 0 处 DY778Read
// 调用，读键集中在 coordinator/tick 函数里）。以下数值按模块 1 同类键的
// 约定写——总开关默认关、通知默认关、入口默认右下角——并按规格 §11.2
// 保守设限（默认关、延迟可配、失败即停），以设置页运行时实测为准，
// 不要把本文件当默认值依据。
//
// 红线（规格 §11.1–§11.2）：本规格只证明了原版「尝试领取」的代码路径，
// 没有任何证据证明这些调用在抖音 40.8.0 上仍能成功领取。以下节流/重试/
// 退避数值是 DYxs 侧的保守设定，不是原版数值，不得写成已确认。

// 领取延迟（秒）：红包执行前的等待，默认 3 秒，钳制 0–30 秒。
enum { DY778REDefaultDelaySeconds = 3, DY778REMinimumDelaySeconds = 0,
       DY778REMaximumDelaySeconds = 30 };
// 列表拉取：连续失败上限，超限即停，等进新房间再恢复（规格 §3.9）。
enum { DY778REMaximumListFailures = 3, DY778REMaximumListRetries = 2 };
// 领取：每个 box 每个会话最多尝试 1 次（claimAttempted，规格 §3.9）；
// 失败重试上限 2 次，退避 2 秒起、每次翻倍、上限 30 秒。
enum { DY778REMaximumClaimAttempts = 1, DY778REMaximumClaimRetries = 2,
       DY778RERetryBackoffBaseSeconds = 2, DY778RERetryBackoffMaximumSeconds = 30 };
// 领取记录上限（redEnvelope.records）。
enum { DY778REMaximumRecords = 200 };
// 领取模式（redEnvelope.mode，规格 §8.1 取值未证实）：quiet / manual / web。
static inline bool DY778REValidMode(const char *mode) {
    if (!mode || !*mode) return false;
    return strcmp(mode, "quiet") == 0 || strcmp(mode, "manual") == 0 || strcmp(mode, "web") == 0;
}
// 延迟钳制（SL 的 delay 复用同一钳制，见 DY778SuperLuckyPolicy.h）。
static inline double DY778REDelay(double value) {
    if (!(value >= 0)) return DY778REDefaultDelaySeconds;
    if (value > DY778REMaximumDelaySeconds) return DY778REMaximumDelaySeconds;
    return value;
}
// 退避：失败次数 n（从 1 起）→ 2、4、8…秒，上限 30 秒。
static inline double DY778REBackoffSeconds(unsigned failures) {
    if (failures == 0) return 0;
    double seconds = (double)DY778RERetryBackoffBaseSeconds;
    for (unsigned i = 1; i < failures && seconds < DY778RERetryBackoffMaximumSeconds; i++) seconds *= 2;
    if (seconds > DY778RERetryBackoffMaximumSeconds) seconds = DY778RERetryBackoffMaximumSeconds;
    return seconds;
}

// ---------- 红包条件分类关键词（规格 §3.3，原文照抄） ----------
// 分类是文本匹配，不是服务端字段；「免费」不等于「能领到」。
static const char *DY778REFreeConditionKeywords[] = {
    "无需额外条件", "免费领取", "免费无条件领取", "免费且无需条件",
    "免费领取，无需任何条件", "免费", "免费红包", "免费普通红包",
    "无需条件", "无需任何条件", "无参与条件", "无条件领取",
};
static const char *DY778REPresentConditionKeywords[] = {
    "开奖时需在直播间", "开奖时需在直播间内",
    "随机开奖，开奖时需在直播间", "随机开奖,开奖时需在直播间",
};
static const char *DY778REGatedConditionKeywords[] = {
    "灯牌", "粉丝", "钻", "关注", "条件", "等级", "要求", "需", "需要",
    "门槛", "口令", "任务", "付费", "送礼", "规则", "红包规则",
    "支付", "充值", "消耗", "扣除", "购买", "花费", "开通",
    "送人气票", "赠送人气票", "抖币", "人气票", "已关注",
};
enum { DY778REFreeConditionKeywordCount = 12, DY778REPresentConditionKeywordCount = 4,
       DY778REGatedConditionKeywordCount = 29 };

// ---------- 手动抢按钮文本（规格 §3.5，原文照抄） ----------
// 文本匹配是界面自动化（点按钮），不是服务端调用；按钮文本在抖音 40.8.0
// 是否一致须真机核对。
static const char *DY778REClaimButtonTexts[] = {
    "抢", "抢红包", "立即抢", "领取", "立即领取", "领取红包", "免费领取", "免费无条件领取",
};
enum { DY778REClaimButtonTextCount = 8 };

// ---------- box 类型判定串（规格 §8.5） ----------
static const char *DY778REBoxTypeStrings[] = {
    "luckybox", "lucky_box", "redenvelope", "red_envelope", "luckymoney",
};
enum { DY778REBoxTypeStringCount = 5 };

// ---------- 网页抢通道名（规格 §3.6） ----------
static const char *DY778REWebChannelName = "DY778RedEnvelopeWeb";
#endif
