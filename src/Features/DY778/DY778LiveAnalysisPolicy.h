#ifndef DY778_LIVE_ANALYSIS_POLICY_H
#define DY778_LIVE_ANALYSIS_POLICY_H
#include <stdbool.h>
#include <stddef.h>
#include <string.h>

// DY778 1.0-8 模块 2（直播数据分析 LA）移植：纯数值/文本策略，
// 与 DY778LiveToolsPolicy.h 同款风格，不含任何 ObjC 调用。
// 规格：~/workspace/plugin-merge/DY778/spec-module2-liveanalysis.md
//
// 默认值说明（规格 §8、§10.6）：1.0-8 二进制里的 liveAnalysis.* 键
// 默认值静态未证实（多由 stringWithFormat 动态拼接）。以下默认值按
// 模块 1 同类键的约定写——总开关默认关、通知默认关、入口默认右下角、
// 数值展示默认开——以设置页运行时实测为准，不要把本文件当默认值依据。

// WebSocket host 三档（规格 §3.1）：选取逻辑未拆，先按 hl → lf → lq 轮询。
enum { DY778LiveAnalysisHostCount = 3 };
static const char *DY778LiveAnalysisHosts[DY778LiveAnalysisHostCount] = {
    "webcast100-ws-web-hl.douyin.com",
    "webcast100-ws-web-lf.douyin.com",
    "webcast100-ws-web-lq.douyin.com",
};
static const char *DY778LiveAnalysisWSEndpointFormat = "wss://%s/webcast/im/push/v2/";
static const char *DY778LiveAnalysisHTTPFetchURL = "https://live.douyin.com/webcast/im/fetch/";
static const char *DY778LiveAnalysisHTTPAudienceURL = "https://live.douyin.com/webcast/ranklist/audience/";
static const char *DY778LiveAnalysisNativeOriginFallback = "https://webcast.amemv.com";
static const char *DY778LiveAnalysisKeychainService = "com.dy778.live-analysis.session";
static const char *DY778LiveAnalysisVisitorRegisterURL = "https://ttwid.bytedance.com/ttwid/union/register/";
// Chrome 135 Windows UA（规格 §5，与 1.0-8 游客注册/网页登录一致）。
static const char *DY778LiveAnalysisUserAgent =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36";
static const char *DY778LiveAnalysisAccountInfoURL = "https://live.douyin.com/passport/web/account/info/?aid=6383";

// Protobuf 通用解析器上限（规格 §3.4）：单消息 4MB、最多 20000 字段。
enum { DY778LiveAnalysisProtoMaxBytes = 0x400000, DY778LiveAnalysisProtoMaxFields = 0x4e20 };

// 连接参数（规格 §3.1，baseQuery / fetchQuery）。
enum { DY778LiveAnalysisDefaultHeartbeatSeconds = 10, DY778LiveAnalysisMinimumHeartbeatSeconds = 5,
       DY778LiveAnalysisMaximumHeartbeatSeconds = 60, DY778LiveAnalysisDefaultPollSeconds = 5,
       DY778LiveAnalysisMinimumPollSeconds = 2, DY778LiveAnalysisMaximumPollSeconds = 30,
       DY778LiveAnalysisDefaultRetrySeconds = 3, DY778LiveAnalysisMaximumRetries = 5,
       DY778LiveAnalysisMaximumRows = 200, DY778LiveAnalysisMaximumGiftRows = 500 };

static inline double DY778LiveAnalysisHeartbeat(double value) {
    if (!(value > 0)) return DY778LiveAnalysisDefaultHeartbeatSeconds;
    if (value < DY778LiveAnalysisMinimumHeartbeatSeconds) return DY778LiveAnalysisMinimumHeartbeatSeconds;
    if (value > DY778LiveAnalysisMaximumHeartbeatSeconds) return DY778LiveAnalysisMaximumHeartbeatSeconds;
    return value;
}
static inline double DY778LiveAnalysisPollInterval(double value) {
    if (!(value > 0)) return DY778LiveAnalysisDefaultPollSeconds;
    if (value < DY778LiveAnalysisMinimumPollSeconds) return DY778LiveAnalysisMinimumPollSeconds;
    if (value > DY778LiveAnalysisMaximumPollSeconds) return DY778LiveAnalysisMaximumPollSeconds;
    return value;
}

// 入口位置：bottom-right / bottom-left / top-right / top-left。
// 规格 §8 的 entryPosition 含 .portrait / .landscape 两个子键，DYxs
// 侧用同一选择值写两个子键（见 DY778RemainingSettings.xm）。
static inline bool DY778LiveAnalysisValidEntryPosition(const char *position) {
    if (!position || !*position) return false;
    return strcmp(position, "bottom-right") == 0 || strcmp(position, "bottom-left") == 0 ||
        strcmp(position, "top-right") == 0 || strcmp(position, "top-left") == 0;
}

// 千分位分组：1234567 → "1,234,567"（规格 §4.4 _DY778LAGroupedNumber）。
static inline size_t DY778LiveAnalysisGroupedNumber(char *buffer, size_t capacity, long long value) {
    if (!buffer || capacity < 2) return 0;
    char digits[32];
    int count = 0;
    long long number = value < 0 ? -value : value;
    if (number == 0) digits[count++] = '0';
    while (number > 0 && count < (int)sizeof(digits)) { digits[count++] = (char)('0' + number % 10); number /= 10; }
    size_t used = 0;
    if (value < 0 && used + 1 < capacity) buffer[used++] = '-';
    for (int i = count - 1; i >= 0; i--) {
        if (used + 1 >= capacity) break;
        buffer[used++] = digits[i];
        if (i > 0 && i % 3 == 0 && used + 1 < capacity) buffer[used++] = ',';
    }
    buffer[used] = '\0';
    return used;
}
#endif
