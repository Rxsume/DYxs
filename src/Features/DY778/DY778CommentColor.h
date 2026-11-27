//
//  DY778CommentColor.h
//  评论蓝字（DY778 1.1-2 移植，2026-11-27）：六种样式（AI/私信/链接/
//  播放/对话/纯蓝色），符号可改、可增减为 1–8 组并在一句中混用。
//  默认符号：AI《》、私信、链接{}、播放<>、对话「」、纯蓝色〔〕。
//  发送时扫描符号对注入 text_extra segments；渲染时同样合并，保证
//  本地立即显示。总开关 comment.blue.enabled 默认关。
//

#import <UIKit/UIKit.h>

FOUNDATION_EXPORT void DY778InstallCommentColorHooks(void);

// 样式表：[{type, name, icon, hint}]（与 1.1-2 _DY778CommentStyles 一致）。
FOUNDATION_EXPORT NSArray<NSDictionary *> *DY778CommentStyles(void);
// 当前规则（无存档时返回默认六组）：[{type, open, close}]。
FOUNDATION_EXPORT NSArray<NSDictionary *> *DY778CommentRules(void);
// 校验规则；合法返回 nil，否则返回错误文案（同 1.1-2）。
FOUNDATION_EXPORT NSString *DY778CommentValidateRules(NSArray<NSDictionary *> *rules);
// 保存规则（先校验，失败返回错误文案且不写）。
FOUNDATION_EXPORT NSString *DY778CommentSaveRules(NSArray<NSDictionary *> *rules);
// 扫描文本产出 segments：[{type, range:{start, end}}]（range 为内层文字）。
FOUNDATION_EXPORT NSArray<NSDictionary *> *DY778CommentSegmentsForText(NSString *text);
// 符号编辑器控制器（设置页入口用）。
FOUNDATION_EXPORT UIViewController *DY778CommentSymbolEditorController(void);
