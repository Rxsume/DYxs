//  DKXSMessageUI.h
//  DY778 第 1 批 staging：聊天页装饰层。
//  对应上游 DY778MessageUI.h/.m 中本批用到的部分（设置页预览控件不移植）。
//  机制：hooks 文件在 willDisplay / layoutSubviews / prepareForReuse 里调用本文件，
//  由协调器把时间标签、撤回标记、编辑标记挂到 cell.contentView 上，
//  位置与避让走 DKXSMessageLayout.h（与上游同一算法）。

#import <UIKit/UIKit.h>

// 格式化消息时间（含智能日期：今天只显示时间，昨天加“昨天”，更早加日期）。
FOUNDATION_EXPORT NSString *DKXSFormatMessageTime(NSTimeInterval timestamp);
// 协调器：注册聊天列表控制器、请求重绘、绑定单个 cell。
FOUNDATION_EXPORT void DKXSMessageUIRegisterController(UIViewController *controller);
FOUNDATION_EXPORT void DKXSMessageUIInvalidate(BOOL immediately);
FOUNDATION_EXPORT void DKXSMessageUIBindCell(UITableViewCell *cell, UIViewController *controller);
FOUNDATION_EXPORT void DKXSMessageUICellLayout(UITableViewCell *cell);
FOUNDATION_EXPORT void DKXSMessageUICellReuse(UITableViewCell *cell);
// 官方时间头：隐藏 / 恢复（hideOfficial 开关用）。
FOUNDATION_EXPORT void DKXSMessageUIHideOfficialHeader(UIView *header);
FOUNDATION_EXPORT void DKXSMessageUIRestoreOfficialHeader(UIView *header);
