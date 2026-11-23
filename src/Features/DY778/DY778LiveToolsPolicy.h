#ifndef DY778_LIVE_TOOLS_POLICY_H
#define DY778_LIVE_TOOLS_POLICY_H
#include <stdbool.h>
#include <math.h>
#include <stddef.h>
#include <string.h>

// DY778 1.0-8 模块 1（直播间工具 + 游客身份）移植：纯数值/文本策略，
// 与 DY778LiveLikePolicy.h 同款风格，不含任何 ObjC 调用。

enum { DY778LiveToolsDefaultInterval = 30, DY778LiveToolsMinimumInterval = 5,
       DY778LiveToolsMaximumInterval = 300, DY778LiveToolsMaximumTextLength = 200,
       DY778LiveToolsMinimumTTWIDLength = 16, DY778LiveToolsMaximumTTWIDLength = 64 };

static inline double DY778LiveToolsInterval(double value) {
    if (!isfinite(value) || value <= 0) return DY778LiveToolsDefaultInterval;
    return round(fmin(DY778LiveToolsMaximumInterval, fmax(DY778LiveToolsMinimumInterval, value)));
}

// TTWID 为十六进制串（见 DY778LiveGuestNormalizeTTWID）：只接受
// 16–64 位十六进制字符，其余一律视为未配置。
static inline bool DY778LiveToolsValidTTWID(const char *ttwid) {
    if (!ttwid || !*ttwid) return false;
    size_t length = strlen(ttwid);
    if (length < DY778LiveToolsMinimumTTWIDLength || length > DY778LiveToolsMaximumTTWIDLength) return false;
    for (size_t i = 0; i < length; i++) {
        char c = ttwid[i];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) return false;
    }
    return true;
}

// 定时弹幕文本：去首尾空白、去换行、截断到上限；空串返回 NULL 表示不发送。
static inline bool DY778LiveToolsValidTextLength(size_t length) {
    return length > 0 && length <= DY778LiveToolsMaximumTextLength;
}
#endif
