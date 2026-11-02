//  DKXSRecall.h
//  DY778 第 1 批 staging：消息留存 / 防撤回。
//  对应上游 DY778Recall.h，改名前缀；Logos 钩子本身在 DKXSMessageArchiveHooks.xm，
//  本文件只提供观测、留存、恢复与记录页的逻辑入口。
//  关键语义（与上游一致）：
//  · 只留存对方发来的消息（sender != 当前账号）；自己的消息不进档案；
//  · 撤回后 UI 读到的 recalled 被压回 NO（气泡照常渲染），由气泡旁标记与记录页承载“已撤回”；
//  · 账号未知时不留存、不提醒，绝不把记录记到别的账号名下。

#import <UIKit/UIKit.h>

FOUNDATION_EXPORT NSNotificationName const DKXSRecallChangedNotification;
FOUNDATION_EXPORT NSNotificationName const DKXSRecallDetectedNotification;

// 观测入口（由 hooks 文件在 TIMXOMessage setter / apply 与 VM 方法里调用）。
FOUNDATION_EXPORT void DKXSObserveMessage(id message);
FOUNDATION_EXPORT void DKXSObserveMessageContext(id viewModel);
// hooks 文件 getter 恢复用：
// · DKXSRecallContentForMessage：快照已撤回且原文可用时返回留存内容（无则 nil，走原生）；
//   注意它不读 recalled，避免在被 hook 的 getter 里重入。
// · DKXSRecallRecalledDisplay：hook 把 %orig 的原始值传进来，函数只做“已留存可用时压回 NO”的掩码。
FOUNDATION_EXPORT id DKXSRecallContentForMessage(id message);
FOUNDATION_EXPORT BOOL DKXSRecallRecalledDisplay(id message, BOOL original);
FOUNDATION_EXPORT NSDictionary *DKXSRecallRecordForMessage(id message);
FOUNDATION_EXPORT BOOL DKXSMessageWasRecalled(id message);
// VM 装配后调用：若该消息有已撤回留存，挂接快照并请求界面刷新。
FOUNDATION_EXPORT BOOL DKXSRestoreRecallPresentation(id viewModel, id message);
// 开关（全局 + 按会话内部字典；按会话 UI 本批不做，只保留存储键）。
FOUNDATION_EXPORT BOOL DKXSRecallEnabledForMessage(id message);
FOUNDATION_EXPORT BOOL DKXSRecallEnabledForConversation(NSString *conversationID);
FOUNDATION_EXPORT void DKXSSetConversationRecallEnabled(NSString *conversationID, BOOL enabled);
// 记录页与维护。
FOUNDATION_EXPORT void DKXSRecallArchivePresentedFrom(UIViewController *source, NSString *conversationID);
FOUNDATION_EXPORT void DKXSRecallClearArchive(void);
FOUNDATION_EXPORT void DKXSRecallClearConversationArchive(NSString *conversationID);
FOUNDATION_EXPORT NSUInteger DKXSRecallCount(void);
FOUNDATION_EXPORT void DKXSRecallMaintenance(void);
FOUNDATION_EXPORT NSString *DKXSRecallStorageStatus(void);
FOUNDATION_EXPORT void DKXSRecallStorageStatistics(void (^completion)(NSDictionary *statistics));
// 身份：key = account|conversation|identifier（serverMessageID 优先于 identifier）。
FOUNDATION_EXPORT NSDictionary *DKXSMessageIdentity(id message);
// 聊天信息页入口的 item identifier（hooks 文件用，模型 API 见 REPORT 风险点）。
FOUNDATION_EXPORT NSString *const DKXSRecallChatItemIdentifier;
