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



}
