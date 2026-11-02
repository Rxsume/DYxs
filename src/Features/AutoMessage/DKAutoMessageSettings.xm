//
//  DKAutoMessageSettings.xm
//  DYxs
//
//  从 DYads- 移植的自动消息 / 好友分享的 DYxs 设置入口。
//  本文件只登记 DK 设置行，不直接 import 移植引擎头文件，
//  引擎调用走 NSClassFromString，避免 DKXSAwemeHeaders 与 DouyinHeaders
//  在同一编译单元重复声明同一抖音类。
//

#import "DKSettings.h"
// 这两个头只 import Foundation/UIKit（AWESettingSectionModel 仅 @class 前置声明），
// 与 DouyinHeaders 无冲突；必须 import 它们才能声明下面动态调用的三个类方法，
// 否则编译器会把 settingsSections/scanFriendShares/clearWatched 报成未声明
// （build #38 的 3 个错误，arm64/arm64e 各重复一次）。
#import "DKXSAutoMessage.h"
#import "DKXSFriendShareService.h"

%ctor {
    DKSettingsRegister(@"DKXSAutoMessageEnabled", ^AWESettingItemModel *{
        return DKSettingsWithInfo(DKMakeSwitch(@"DKXSAutoMessageEnabled", @"启用自动消息",
                                               @"使用抖音原生消息服务，每日去重；开启后在抖音启动时处理配置，不发送时间段内不会触发。"),
                                  @"移植自 DYads- 的自动消息：按配置给指定好友自动发送消息，每位用户每天只处理一次。");
    });
    DKSettingsRegister(@"DKXSAutoMessageToastEnabled", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSAutoMessageToastEnabled", @"显示发送提示", @"发送成功或失败时显示提示。");
    });
    DKSettingsRegister(@"DKXSAutoMessageAllSentToastEnabled", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSAutoMessageAllSentToastEnabled", @"显示已全部发送提示", @"全部配置发送完成后显示提示。");
    });
    DKSettingsRegister(@"DKXSAutoMessageIDQueryKeyword", ^AWESettingItemModel *{
        return DKMakeTextInput(@"DKXSAutoMessageIDQueryKeyword", @"ID 查询关键词", @"查询id", 32);
    });
    DKSettingsRegister(@"DKXSAutoMessageConfigPage", ^AWESettingItemModel *{
        return DKSettingsWithoutBackup(DKMakeAction(@"DKXSAutoMessageConfigPage", @"自动消息设置", @"", ^(AWESettingItemModel *item, UIViewController *presenter) {
            (void)item;
            Class autoMessage = NSClassFromString(@"DKXSAutoMessage");
            if (!autoMessage || ![autoMessage respondsToSelector:@selector(settingsSectionsWithRootViewController:)]) return;
            NSArray *sections = [autoMessage settingsSectionsWithRootViewController:presenter];
            if (sections.count) DKSettingsPushSections(presenter, @"自动消息", sections);
        }));
    });
    DKSettingsRegister(@"DKXSFriendShareFeedEnabled", ^AWESettingItemModel *{
        return DKSettingsWithInfo(DKMakeSwitch(@"DKXSFriendShareFeedEnabled", @"启用好友分享进推荐",
                                               @"未刷分享会保存到下次打开；刷视频途中收到的新分享接在当前视频后，刷完后继续原推荐。"),
                                  @"移植自 DYads- 的好友分享进推荐。手动划走或播完一轮记为已刷，搜索或退出保留未刷记录。");
    });
    DKSettingsRegister(@"DKXSFriendShareAutoRefreshEnabled", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSFriendShareAutoRefreshEnabled", @"每次打开抖音刷新", @"继续推送未刷分享，并加入新分享。");
    });
    DKSettingsRegister(@"DKXSFriendShareScan", ^AWESettingItemModel *{
        return DKSettingsWithoutBackup(DKMakeAction(@"DKXSFriendShareScan", @"立即扫描好友分享", @"扫描", ^(AWESettingItemModel *item, UIViewController *presenter) {
            (void)item; (void)presenter;
            Class autoMessage = NSClassFromString(@"DKXSAutoMessage");
            if ([autoMessage respondsToSelector:@selector(scanFriendSharesWithToast:)]) [autoMessage scanFriendSharesWithToast:YES];
        }));
    });
    DKSettingsRegister(@"DKXSFriendShareClear", ^AWESettingItemModel *{
        return DKSettingsWithoutBackup(DKMakeAction(@"DKXSFriendShareClear", @"清除已刷记录", @"", ^(AWESettingItemModel *item, UIViewController *presenter) {
            (void)item; (void)presenter;
            Class service = NSClassFromString(@"DKXSFriendShareService");
            if ([service respondsToSelector:@selector(clearWatched)]) [service clearWatched];
        }));
    });
}
