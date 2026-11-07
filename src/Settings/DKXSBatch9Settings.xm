//
//  DKXSBatch9Settings.xm
//  DYxs（第 9 批：Si-yi/DYads- f07ddb5 新模块移植）
//
//  第 9 批设置登记（%ctor + DKSettingsRegister + DKMakeSwitch，
//  与第 7/8 批同款写法）。5 个开关全部默认关；2 个动作行不落盘。
//  登记 7 项，全部在本批有读取方（DKXSRecallCoordinator / DKXSMessageListStyle）：
//  消息防撤回、显示撤回提示、保留媒体副本、留存状态、清理当前账号留存、
//  消息卡片、消息列表顶部毛玻璃。
//  改名一律 DYYY -> DKXS（键与类名同步改名，见各模块文件头）。
//  注意：上游的设置行构建方法不移植，行改由本文件登记；
//  状态行点一下刷新统计，清理行走系统弹窗确认（DYxs 惯例）。
//  消息卡片与顶部毛玻璃默认关（DYxs 移植惯例；上游卡片默认开，不跟随）。
//

#import "DKSettings.h"
#import "DKXSRecallCoordinator.h"
#import "DKXSMessageListStyle.h"

static AWESettingItemModel *sDKXSRecallStatusItem = nil;

%ctor {
    DKSettingsRegister(@"DKXSPreventRecall", ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(@"DKXSPreventRecall", @"消息防撤回",
                                                 @"只在本机留存收到的原内容；撤回后仅以标记提示，不改变已读/已撤回状态。请关闭其他插件中的同类防撤回后重启，以免重复接管。未收到的原内容不能恢复。仅在聊天页内生效，群聊已读/已撤回状态不作同步。");
        DKSettingsOnChange(item, ^{ [DKXSRecallCoordinator settingsChanged]; });
        return item;
    });
    DKSettingsRegister(@"DKXSRecallShowMarker", ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(@"DKXSRecallShowMarker", @"显示撤回提示",
                                                 @"在对应原消息下沿显示对方已撤回与发现时间。");
        DKSettingsOnChange(item, ^{ [DKXSRecallCoordinator settingsChanged]; });
        return item;
    });
    DKSettingsRegister(@"DKXSRecallKeepMedia", ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(@"DKXSRecallKeepMedia", @"保留媒体副本",
                                                 @"另存已取得的本机媒体文件，单文件 64MB、总计 512MB 上限。");
        DKSettingsOnChange(item, ^{ [DKXSRecallCoordinator settingsChanged]; });
        return item;
    });
    DKSettingsRegister(@"DKXSRecallStatus", ^AWESettingItemModel *{
        AWESettingItemModel *item = DKSettingsWithoutBackup(DKMakeAction(@"DKXSRecallStatus", @"留存状态",
                                                                          [DKXSRecallCoordinator statusText],
                                                                          ^(AWESettingItemModel *row, __unused UIViewController *presenter) {
            [DKXSRecallCoordinator updateStatusRow:row];
        }));
        sDKXSRecallStatusItem = item;
        return item;
    });
    DKSettingsRegister(@"DKXSRecallClear", ^AWESettingItemModel *{
        return DKSettingsWithoutBackup(DKSettingsMarkDestructive(DKMakeAction(@"DKXSRecallClear", @"清理当前账号留存",
                                                                               @"仅清理本插件副本",
                                                                               ^(__unused AWESettingItemModel *row, UIViewController *presenter) {
            [DKXSRecallCoordinator clearCurrentAccountFromPresenter:presenter statusRow:sDKXSRecallStatusItem];
        })));
    });
    DKSettingsRegister(@"DKXSEnableMessageListCards", ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(@"DKXSEnableMessageListCards", @"消息卡片",
                                                 @"将消息列表按连续会话分组为圆角面板，单条消息保留原生样式。");
        DKSettingsOnChange(item, ^{ [DKXSMessageListStyle refresh]; });
        return item;
    });
    DKSettingsRegister(@"DKXSEnableMessageListTopGlass", ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(@"DKXSEnableMessageListTopGlass", @"消息列表顶部毛玻璃",
                                                 @"聊天页顶栏下方左右按钮区叠加毛玻璃。");
        DKSettingsOnChange(item, ^{ [DKXSMessageListStyle refresh]; });
        return item;
    });
}
