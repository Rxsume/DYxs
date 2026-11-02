//  DKXSRecallContent.h
//  DY778 第 1 批 staging：留存记录的内容解析。
//  对应上游 DY778RecallContent.h，改名前缀；逻辑保留：
//  · 内容种类判定（recall-notice / image / audio / video / live / goods / sticker / work / location）；
//  · 分享评论只保留首次实际取得的文字（后续删除提示不覆盖）；
//  · 作品标识只取校验过的 aweme/item id，绝不拼任意 URL。

#import <Foundation/Foundation.h>

// AWEIM* 消息类名 → 直发媒体种类（audio/image/video/location），其余返回 @""。
FOUNDATION_EXPORT NSString *DKXSRecallMessageKind(NSString *className);
// 给一条 sqlite 记录补齐 card（kind/summary/media/author/workID 等展示字段），返回新字典。
FOUNDATION_EXPORT NSDictionary *DKXSRecallEnrichRecord(NSDictionary *record);
// 从内容字典中抽出媒体候选（去重、按质量排过序的子集）。
FOUNDATION_EXPORT NSArray *DKXSRecallMediaFromContent(id content);
// 记录的一行摘要（文字优先，其次种类文案）。
FOUNDATION_EXPORT NSString *DKXSRecallSummary(NSDictionary *record);
// 内容本身是不是系统撤回提示（type 40001 且在官方非用户生成类型集合内）。
FOUNDATION_EXPORT BOOL DKXSRecallContentIsNotice(id content);
// 分享内容里的评论节点；与旧记录合并时首次文字优先。
FOUNDATION_EXPORT NSDictionary *DKXSRecallCommentFromContent(id content);
FOUNDATION_EXPORT NSDictionary *DKXSMergeCapturedComment(NSDictionary *previous, NSDictionary *candidate);
// 校验过的作品标识（aweme_id/item_id），无则返回 nil。
FOUNDATION_EXPORT NSString *DKXSRecallWorkIdentifier(NSDictionary *record);
// 该记录是否应从列表隐藏（系统提示类、空内容）。
FOUNDATION_EXPORT BOOL DKXSRecallRecordShouldHide(NSDictionary *record);
// 记录的媒体预览候选（本地路径优先于远程地址）。
FOUNDATION_EXPORT NSArray *DKXSRecallPreviewCandidates(NSDictionary *record);
// 首选媒体（质量最高者），无则返回 nil。
FOUNDATION_EXPORT NSDictionary *DKXSRecallPrimaryMedia(NSDictionary *record);
