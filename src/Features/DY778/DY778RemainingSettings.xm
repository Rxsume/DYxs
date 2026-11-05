//
//  DY778RemainingSettings.xm
//  DYxs — DY778 剩余模块（福袋助手 / 缓存清理 / Feed 过滤 / 播放倍速）的设置登记。
//
//  键桥接：DY778 模块读 DY778 专用 suite（com.dy778.douyin）的点分键，
//  DYxs 设置页写标准 defaults 的 DKXS* 键。本文件在 %ctor 里做一次同步，
//  每次改值后通过 DKSettingsOnChange 再同步一次；DY778Set 会钳制数值范围
//  并发出 DY778PreferencesChangedNotification，模块按原逻辑响应。
//  直播自动点赞（liveLike.*，上游 1.0-2 新增）同按此桥接：开关默认关，
//  次数 / 间隔 / 休息沿用 DY778RegisterDefaults 注册的默认值（100 次 / 1 秒 / 1.5 秒）。
//  1.0-3 新增（b41e81b）同按此桥接：推荐页直播信息（liveInfo.*）、星牌查询
//  （fans.enabled）、数字自定义（displayStats.enabled）。liveInfo.duration
//  只作 suite 内一致性同步：直播间开播时长悬浮 DYxs 已有等价实现
//  DKXSLiveDuration.xm，开关仍走 DKXSShowLiveDuration，不另设开关。
//  未在 DYxs 设置里动过的键沿用 DY778RegisterDefaults 注册的默认值（全部关闭）。
//  死键不登记：lucky.autoPhrase / lucky.autoJoin 只出现在 DY778 默认值表里，
//  本 commit 的福袋代码并不读取它们。
//

#import "DKSettings.h"
#import "DY778Core.h"
#import "DY778DisplayStats.h"

static void DY778SyncRemainingSettings(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    // 开关（DY778 默认全部 NO，与 DKXS 开关默认一致）
    static NSString *const boolKeys[][2] = {
        {@"DKXSLuckyEnabled", @"lucky.enabled"},
        {@"DKXSLuckyHaptics", @"lucky.haptics"},
        {@"DKXSLuckyPrompt", @"lucky.prompt"},
        {@"DKXSLuckyShowStatus", @"lucky.showStatus"},
        {@"DKXSLuckyCompact", @"lucky.compact"},
        {@"DKXSLiveLikeEnabled", @"liveLike.enabled"},
        // 1.0-3 新增：推荐页直播信息、星牌查询、数字自定义。
        {@"DKXSLivePreviewViewers", @"liveInfo.viewers"},
        {@"DKXSLivePreviewCardDuration", @"liveInfo.cardDuration"},
        {@"DKXSFansEnabled", @"fans.enabled"},
        {@"DKXSDisplayStatsEnabled", @"displayStats.enabled"},
        // 桥接用：DKXSShowLiveDuration 登记在 DKXSBatch5RestSettings.xm，
        // 这里只把它的值同步进 DY778 suite，保持 liveInfo.duration 一致。
        {@"DKXSShowLiveDuration", @"liveInfo.duration"},
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
    // 人数格式：选择下标 0 = 简洁（compact），1 = 完整（exact）
    if ([defaults objectForKey:@"DKXSLivePreviewCountFormat"]) {
        DY778Set(@"liveInfo.countFormat", [defaults integerForKey:@"DKXSLivePreviewCountFormat"] == 1 ? @"exact" : @"compact");
    }
    // 数值（文字输入，存字符串；同步时解析为 double，空值则清除回默认值）
    static NSString *const numberKeys[][2] = {
        {@"DKXSLuckyDelay", @"lucky.delay"},
        {@"DKXSLiveLikeTarget", @"liveLike.target"},
        {@"DKXSLiveLikeInterval", @"liveLike.interval"},
        {@"DKXSLiveLikePause", @"liveLike.pause"},
        // 1.0-3 新增：人数刷新间隔（秒），DY778Set 钳制在 2–10 秒。
        {@"DKXSLivePreviewRefresh", @"liveInfo.refresh"},
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
            @"只处理当前直播间的普通免费福袋，暂不支持超级福袋。需要灯牌、送礼、付费等额外条件时自动跳过，不代为点亮、升级或消费。"),
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
    DKSettingsRegister(@"DKXSLiveLikeEnabled", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeSwitch(@"DKXSLiveLikeEnabled", @"启用自动点赞", @""),
            @"开启后，在正在观看的直播画面双击开始一轮，再次双击可随时停止。离开或切换直播间、进入后台、修改次数或节奏、关闭开关都会结束本轮，返回后需重新双击。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSLiveLikeTarget", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeTextInput(@"DKXSLiveLikeTarget", @"每轮点赞次数", @"100", 4),
            @"1–9999 次，默认 100 次。达到目标并完成提交后停止；修改次数会结束正在进行的任务。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSLiveLikeInterval", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeTextInput(@"DKXSLiveLikeInterval", @"点赞间隔（秒）", @"1", 4),
            @"0.6–2 秒，默认 1 秒，以 0.1 秒调整。间隔越短、连续使用越频繁，越容易触发频率限制，建议优先使用默认节奏。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSLiveLikePause", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeTextInput(@"DKXSLiveLikePause", @"每 20 次休息（秒）", @"1.5", 4),
            @"1–3 秒，默认 1.5 秒，以 0.1 秒调整。每完成 20 次自动点赞，下一次间隔取点赞间隔与休息时间中的较大值，之后恢复普通节奏。"),
            ^{ DY778SyncRemainingSettings(); });
    });

    // ---------- DY778 1.0-3 新增：推荐页直播信息 ----------
    DKSettingsRegister(@"DKXSLivePreviewViewers", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeSwitch(@"DKXSLivePreviewViewers", @"推荐页显示在线人数", @""),
            @"在推荐页直播卡片上显示实时在线人数，无需进入直播间。人数以本次可读取的数据为准，可能随直播间刷新节奏变化。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSLivePreviewCountFormat", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeChoice(@"DKXSLivePreviewCountFormat", @"推荐页人数格式", @[@"简洁 · 1.2万", @"完整 · 12345"]),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSLivePreviewRefresh", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeTextInput(@"DKXSLivePreviewRefresh", @"人数刷新间隔（秒）", @"3", 4),
            @"2–10 秒，默认 3 秒。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSLivePreviewCardDuration", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeSwitch(@"DKXSLivePreviewCardDuration", @"推荐页显示开播时长", @""),
            @"在推荐页直播卡片上显示开播时长，独立于在线人数开关。开播时长依据房间返回的开播时间计算。"),
            ^{ DY778SyncRemainingSettings(); });
    });

    // ---------- DY778 1.0-3 新增：星牌查询 ----------
    DKSettingsRegister(@"DKXSFansEnabled", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeSwitch(@"DKXSFansEnabled", @"启用星牌查询", @""),
            @"开启后，用户主页左上角出现“星牌”按钮，可查询该用户在某主播那里的粉丝灯牌与消费等级。只展示当前可查询且归属匹配的资料。"),
            ^{ DY778SyncRemainingSettings(); });
    });

    // ---------- DY778 1.0-3 新增：数字自定义 ----------
    DKSettingsRegister(@"DKXSDisplayStatsEnabled", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeSwitch(@"DKXSDisplayStatsEnabled", @"启用数字自定义", @""),
            @"开启后，已填写的主页和本人作品数字直接生效。仅改变本机显示，不修改真实数据；不同账号分别保存。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSDisplayStatsPage", ^AWESettingItemModel *{
        return DKSettingsWithoutBackup(DKMakeAction(@"DKXSDisplayStatsPage", @"数字自定义设置", @"", ^(AWESettingItemModel *item, UIViewController *presenter) {
            (void)item;
            DY778PresentController(presenter, DY778DisplayStatsController());
        }));
    });

}
