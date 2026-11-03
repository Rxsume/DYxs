//
//  DY778RemainingSettings.xm
//  DYxs — DY778 剩余模块（福袋助手 / 缓存清理 / Feed 过滤 / 播放倍速）的设置登记。
//
//  键桥接：DY778 模块读 DY778 专用 suite（com.dy778.douyin）的点分键，
//  DYxs 设置页写标准 defaults 的 DKXS* 键。本文件在 %ctor 里做一次同步，
//  每次改值后通过 DKSettingsOnChange 再同步一次；DY778Set 会钳制数值范围
//  并发出 DY778PreferencesChangedNotification，模块按原逻辑响应。
//  未在 DYxs 设置里动过的键沿用 DY778RegisterDefaults 注册的默认值（全部关闭）。
//  死键不登记：lucky.autoPhrase / lucky.autoJoin 只出现在 DY778 默认值表里，
//  本 commit 的福袋代码并不读取它们。
//

#import "DKSettings.h"
#import "DY778Core.h"

static void DY778SyncRemainingSettings(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    // 开关（DY778 默认全部 NO，与 DKXS 开关默认一致）
    static NSString *const boolKeys[][2] = {
        {@"DKXSLuckyEnabled", @"lucky.enabled"},
        {@"DKXSLuckyHaptics", @"lucky.haptics"},
        {@"DKXSLuckyPrompt", @"lucky.prompt"},
        {@"DKXSLuckyShowStatus", @"lucky.showStatus"},
        {@"DKXSLuckyCompact", @"lucky.compact"},
        {@"DKXSPlaybackStopAtEnd", @"playback.stopAtEnd"},
        {@"DKXSPlaybackLongPressEnabled", @"playback.longPressEnabled"},
        {@"DKXSPlaybackDefaultEnabled", @"playback.defaultEnabled"},
        {@"DKXSCacheEnabled", @"cache.enabled"},
        {@"DKXSCacheOnLaunch", @"cache.onLaunch"},
        {@"DKXSCacheOnReturn", @"cache.onReturn"},
        {@"DKXSExperimentalSkipAds", @"experimental.skipAds"},
    };
    for (NSUInteger i = 0; i < sizeof(boolKeys) / sizeof(boolKeys[0]); i++) {
        if ([defaults objectForKey:boolKeys[i][0]]) {
            DY778Set(boolKeys[i][1], @([defaults boolForKey:boolKeys[i][0]]));
        }
    }
    // 福袋模式：选择下标 0 = 确认后参与（confirm），1 = 自动参与（auto）
    if ([defaults objectForKey:@"DKXSLuckyMode"]) {
        DY778Set(@"lucky.mode", [defaults integerForKey:@"DKXSLuckyMode"] == 1 ? @"auto" : @"confirm");
    }
    // 数值（文字输入，存字符串；同步时解析为 double，空值则清除回默认值）
    static NSString *const numberKeys[][2] = {
        {@"DKXSLuckyDelay", @"lucky.delay"},
        {@"DKXSPlaybackLongPressRate", @"playback.longPressRate"},
        {@"DKXSPlaybackDefaultRate", @"playback.defaultRate"},
        {@"DKXSCacheMaxMB", @"cache.maxMB"},
        {@"DKXSCacheMaxAgeHours", @"cache.maxAgeHours"},
    };
    for (NSUInteger i = 0; i < sizeof(numberKeys) / sizeof(numberKeys[0]); i++) {
        id value = [defaults objectForKey:numberKeys[i][0]];
        if ([value isKindOfClass:NSString.class]) {
            DY778Set(numberKeys[i][1], ((NSString *)value).length ? @([(NSString *)value doubleValue]) : nil);
        } else if ([value isKindOfClass:NSNumber.class]) {
            DY778Set(numberKeys[i][1], value);
        }
    }
}

%ctor {
    DY778SyncRemainingSettings();

    DKSettingsRegister(@"DKXSLuckyEnabled", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeSwitch(@"DKXSLuckyEnabled", @"福袋助手", @""),
            @"只处理当前直播间的普通免费福袋。需要灯牌、送礼、付费等额外条件时自动跳过，不代为点亮、升级或消费。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSLuckyMode", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeChoice(@"DKXSLuckyMode", @"福袋参与方式", @[@"确认后参与", @"自动参与"]),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSLuckyPrompt", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeSwitch(@"DKXSLuckyPrompt", @"福袋参与前提示", @""),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSLuckyHaptics", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeSwitch(@"DKXSLuckyHaptics", @"福袋触感反馈", @""),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSLuckyShowStatus", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeSwitch(@"DKXSLuckyShowStatus", @"显示福袋状态", @""),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSLuckyCompact", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeSwitch(@"DKXSLuckyCompact", @"福袋紧凑显示", @""),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSLuckyDelay", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeTextInput(@"DKXSLuckyDelay", @"福袋参与延迟（秒）", @"1.2", 6),
            ^{ DY778SyncRemainingSettings(); });
    });

    DKSettingsRegister(@"DKXSPlaybackDefaultEnabled", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeSwitch(@"DKXSPlaybackDefaultEnabled", @"默认倍速", @"视频作品按默认倍速播放，直播和图文不调整。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSPlaybackDefaultRate", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeTextInput(@"DKXSPlaybackDefaultRate", @"默认倍速值", @"1.25", 6),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSPlaybackLongPressEnabled", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeSwitch(@"DKXSPlaybackLongPressEnabled", @"长按倍速", @"长按视频时按设定倍速播放，松开恢复。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSPlaybackLongPressRate", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeTextInput(@"DKXSPlaybackLongPressRate", @"长按倍速值", @"2", 6),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSPlaybackStopAtEnd", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeSwitch(@"DKXSPlaybackStopAtEnd", @"播放结束暂停", @"视频作品播放结束后自动暂停。"),
            ^{ DY778SyncRemainingSettings(); });
    });

    DKSettingsRegister(@"DKXSCacheEnabled", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeSwitch(@"DKXSCacheEnabled", @"缓存管理", @"查看缓存用量并按容量/时长限制清理；插件自身的配置与数据不删。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSCacheOnLaunch", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeSwitch(@"DKXSCacheOnLaunch", @"启动时清理缓存", @""),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSCacheOnReturn", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeSwitch(@"DKXSCacheOnReturn", @"返回前台时清理缓存", @""),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSCacheMaxMB", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeTextInput(@"DKXSCacheMaxMB", @"缓存容量上限（MB，0 不限）", @"0", 8),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSCacheMaxAgeHours", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeTextInput(@"DKXSCacheMaxAgeHours", @"缓存最长保留（小时，0 不限）", @"0", 8),
            ^{ DY778SyncRemainingSettings(); });
    });

    DKSettingsRegister(@"DKXSExperimentalSkipAds", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeSwitch(@"DKXSExperimentalSkipAds", @"跳过推广内容（实验）", @""),
            @"实验功能：按文案与价格特征识别推广内容并跳过。误判可能跳过正常视频，默认关闭。"),
            ^{ DY778SyncRemainingSettings(); });
    });
}
