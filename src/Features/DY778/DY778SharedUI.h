//
//  DY778SharedUI.h
//  DYxs — DY778 1.0-3 移植的本地共享 UI（替代上游 Radar 模块的两个直接依赖）。
//
//  上游 DY778FansUI / DY778DisplayStats 用到 DY778RadarUI.h 的两个符号：
//  DY778RadarCell（标题 + 副标题 + SF Symbol + 可选箭头的表格单元格）与
//  DY778RadarTableController（InsetGrouped 表格基类：主题刷新、offset 保持、
//  账号校验）。Radar 本身按范围排除不并入，这里只按上游实现原样复刻这两个
//  符号的行为，依赖的 DY778CardBackground / DY778MenuIcon / DY778Accent /
//  DY778Background / DY778InterfaceStyle / DY778ShowNotice 均由 DYxs 已有
//  的 DY778Core 提供。checkAccount 改为与 DY778CurrentAccountID 比对
//  （上游比对的是 Radar 自身的 Store 账号）。
//

#import <UIKit/UIKit.h>

UITableViewCell *DY778SharedCell(NSString *title, NSString *subtitle, NSString *symbol, BOOL disclosure);

@interface DY778SharedTableController : UITableViewController
- (void)refresh;
- (void)updateTheme;
- (BOOL)checkAccount:(NSString *)account;
@end
