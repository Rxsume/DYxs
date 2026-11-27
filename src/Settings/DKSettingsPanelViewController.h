//
//  DKSettingsPanelViewController.h
//  DYxs 设置面板（DYYY 风格，2026-11-27 移植）：深色毛玻璃背景、
//  内嵌分组表格、可折叠分区、渐变标题。数据仍走 DYxs 的布局表与
//  注册表（AWESettingSectionModel/AWESettingItemModel），行行为仍由
//  项上的 switchChangedBlock/cellTappedBlock 驱动，联动锁照常生效。
//

#import <UIKit/UIKit.h>
#import "DouyinHeaders.h"

@interface DKSettingsPanelViewController : UIViewController

/// DYxs 一级面板（布局表主分区 + 未归类分区）。
+ (instancetype)mainPanel;

/// 子页/自定义分区页。note 为顶部说明，可空。
- (instancetype)initWithTitle:(NSString *)title
                     sections:(NSArray<AWESettingSectionModel *> *)sections
                         note:(NSString *)note;

/// 本页分区数据（联动锁重算用）。
- (NSArray<AWESettingSectionModel *> *)dk_sections;

/// 重算联动锁并整表刷新。
- (void)dk_reload;

/// 只刷新这些项所在的行（找不到时整表刷新）。
- (void)dk_reloadItems:(NSArray<AWESettingItemModel *> *)items;

@end
