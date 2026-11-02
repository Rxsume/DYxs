//  DKXSEditHistory.h
//  DY778 第 1 批 staging：编辑历史。
//  对应上游 DY778EditHistory.h，改名前缀；与撤回共用观测层（TIMXOMessage setEditInfo:），
//  但档案独立（EditHistory/history.sqlite），两批记录互不干扰。
//  语义（与上游一致）：首次见到已编辑消息时标注“未取得原文”；
//  只有拿到原文基线后的后续编辑才追加版本；编辑提醒默认关闭。

#import <UIKit/UIKit.h>

FOUNDATION_EXPORT NSNotificationName const DKXSEditHistoryChangedNotification;
FOUNDATION_EXPORT NSNotificationName const DKXSEditDetectedNotification;

// 由 hooks 文件在 setEditInfo: 与 apply* 里调用（content 为当前正文快照，可空）。
FOUNDATION_EXPORT void DKXSEditObserveMessage(id message, NSDictionary *content, NSDictionary *editInfo);
FOUNDATION_EXPORT void DKXSEditObserveContext(id viewModel);
FOUNDATION_EXPORT NSDictionary *DKXSEditRecordForMessage(id message);
FOUNDATION_EXPORT BOOL DKXSEditEnabledForConversation(NSString *conversation);
FOUNDATION_EXPORT void DKXSSetConversationEditEnabled(NSString *conversation, BOOL enabled);
FOUNDATION_EXPORT void DKXSEditHistoryPresentedFrom(UIViewController *source, NSString *conversation, NSString *messageKey);
FOUNDATION_EXPORT void DKXSEditClearHistory(void);
FOUNDATION_EXPORT void DKXSEditHistoryMaintenance(void);
FOUNDATION_EXPORT NSString *DKXSEditHistoryStatus(void);
FOUNDATION_EXPORT BOOL DKXSEditCaptureEnabled(void);
