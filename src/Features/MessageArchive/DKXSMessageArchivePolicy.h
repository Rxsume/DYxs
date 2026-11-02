//  DKXSMessageArchivePolicy.h
//  DY778 第 1 批 staging：消息留存 / 编辑历史 / 时间标签。
//  由上游 DY778RecallPolicy.h、DY778EditPolicy.h、DY778ArchivePolicy.h、DY778RecallReentry.h
//  改名前缀而来，逻辑一字未改；DY778Hook 的重装语义不在这里，见 DKXSMessageArchiveHooks.xm。
//  纯 C，不依赖任何抖音类。

#ifndef DKXSMessageArchivePolicy_h
#define DKXSMessageArchivePolicy_h

#include <stdbool.h>
#include <string.h>

// ---- 撤回：是否落盘、是否提醒（上游 DY778RecallDecide） ----
typedef struct { bool persist; bool notify; } DKXSRecallDecision;
static inline DKXSRecallDecision DKXSRecallDecide(bool enabled, bool hasPrevious, bool samePayload,
                                                  bool previousRecalled, bool recalled,
                                                  bool previousAvailable, bool available) {
    DKXSRecallDecision result = { false, false };
    if (!enabled) return result;
    result.persist = !hasPrevious || !samePayload || previousRecalled != recalled;
    result.notify = (!previousRecalled && recalled) || (recalled && !previousAvailable && available);
    return result;
}
// 气泡皮肤是否应被普通气泡替代（仅普通文字 + 有皮肤时）。
static inline bool DKXSRecallShouldNormalizeBubbleSkin(bool recalled, bool enabled, bool ordinaryText, bool hasSkin) {
    return recalled && enabled && ordinaryText && hasSkin;
}
// UI 读到的 recalled：已留存且内容可用时，对 UI 隐藏撤回态（由标记显示），气泡照常渲染。
static inline bool DKXSRecallDisplayState(bool enabled, bool original, bool recorded, bool available) {
    return enabled && recorded && available ? false : original;
}
// 是否把留存内容写回当前消息实例（VM 恢复路径）。
static inline bool DKXSRecallShouldRestore(bool enabled, bool recalled, bool available, bool systemNotice,
                                           bool mutationInProgress, bool sameMessage, unsigned long revision,
                                           unsigned long renderedRevision) {
    return enabled && recalled && available && !systemNotice && !mutationInProgress && revision > 0 && (!sameMessage || revision != renderedRevision);
}
// 留存记录是否应覆盖当前实例的快照。
static inline bool DKXSRecallShouldHydrate(bool storedAvailable, bool currentAvailable, bool storedRecalled, bool currentRecalled) {
    return storedAvailable && (!currentAvailable || storedRecalled || currentRecalled);
}

// ---- 编辑：版本事件判定（上游 DY778DecideEdit） ----
typedef enum { DKXSEditIgnore, DKXSEditBaseline, DKXSEditFirstSeenEdited, DKXSEditAppend } DKXSEditDecision;
static inline DKXSEditDecision DKXSDecideEdit(bool valid, bool previous, bool edited, bool same,
                                              double previousTime, double currentTime,
                                              long long previousCount, long long currentCount) {
    if (!valid) return DKXSEditIgnore;
    if (!previous) return edited ? DKXSEditFirstSeenEdited : DKXSEditBaseline;
    if (!edited) return DKXSEditIgnore;
    if (currentTime > 0 && previousTime > currentTime) return DKXSEditIgnore;
    if (currentCount > 0 && previousCount > currentCount) return DKXSEditIgnore;
    bool newer = currentTime > previousTime || currentCount > previousCount;
    // 修订标识为准：正文被改回去时也不追加新版本；元数据可能先于新正文到达。
    if (same) return DKXSEditIgnore;
    if (newer) return DKXSEditAppend;
    if (same || previousTime > 0 || previousCount > 0) return DKXSEditIgnore;
    return DKXSEditAppend; // 明确编辑但无可用服务端修订：以观察时间标注。
}
static inline bool DKXSEditShouldNotify(bool hadPrevious, bool hadCapturedVersion, long long previousChanges, long long currentChanges) {
    return hadPrevious && hadCapturedVersion && currentChanges > previousChanges;
}

// ---- 档案身份（上游 DY778ArchivePolicy） ----
static inline bool DKXSArchiveIDPresent(const char *value) {
    return value && value[0] && strcmp(value, "0") != 0;
}
static inline bool DKXSArchiveSameID(const char *left, const char *right) {
    return DKXSArchiveIDPresent(left) && DKXSArchiveIDPresent(right) && strcmp(left, right) == 0;
}
static inline bool DKXSArchiveMediaSelectable(const char *messageKind, const char *candidateKind,
                                              bool directMessage, bool cover, bool shared) {
    if (!directMessage) return true;
    return DKXSArchiveSameID(messageKind, candidateKind) && !cover && !shared;
}
static inline bool DKXSArchiveIdentityMatches(const char *account, const char *currentAccount,
                                              const char *conversation, const char *actualConversation,
                                              const char *client, const char *actualClient,
                                              const char *server, const char *actualServer) {
    if (!DKXSArchiveSameID(account, currentAccount) || !DKXSArchiveSameID(conversation, actualConversation)) return false;
    if (DKXSArchiveIDPresent(server) && DKXSArchiveIDPresent(actualServer) && !DKXSArchiveSameID(server, actualServer)) return false;
    return DKXSArchiveSameID(client, actualClient) || DKXSArchiveSameID(server, actualServer);
}

// ---- 重入防护（上游 DY778RecallReentry）：getter 恢复时读写同一对象会重入，
// 帧栈记录 (object, operation)，写操作进行中禁止同一对象的读恢复。
typedef struct DKXSRecallFrame {
    const void *object;
    unsigned int operation;
    struct DKXSRecallFrame *previous;
} DKXSRecallFrame;
enum { DKXSRecallReadContent = 1, DKXSRecallReadFlag, DKXSRecallWriteContent,
       DKXSRecallWriteFlag, DKXSRecallWriteOriginal, DKXSRecallApply, DKXSRecallApplyV2, DKXSRecallWriteEdit };
static inline bool DKXSRecallFrameContains(const DKXSRecallFrame *frame, const void *object, unsigned int operation) {
    for (; frame; frame = frame->previous)
        if (frame->object == object && frame->operation == operation) return true;
    return false;
}
static inline bool DKXSRecallFrameIsMutating(const DKXSRecallFrame *frame, const void *object) {
    for (; frame; frame = frame->previous)
        if (frame->object == object && frame->operation >= DKXSRecallWriteContent) return true;
    return false;
}

#endif
