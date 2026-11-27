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
//  1.0-8 模块 1（直播间工具 + 游客身份）同按此桥接：隐身（liveTools.stealth）、
//  定时弹幕（liveTools.scheduler / interval / selectedText）、礼物风控
//  （liveTools.risk）、游客 TTWID（liveTools.ttwid），开关默认全部关闭。
//  1.0-8 模块 2（直播数据分析）同按此桥接：总开关（liveAnalysis.enabled，
//  默认关）、紧凑模式（liveAnalysis.compact）、入口位置
//  （liveAnalysis.entryPosition.portrait/.landscape，默认右下角）、观众
//  榜（liveAnalysis.audience）、数值展示（liveAnalysis.audienceValues，
//  默认开，未证实）、观众/礼物通知（liveAnalysis.audienceNotice/giftNotice，
//  默认关）。getVisitor/clearVisitor/resetPosition/info 是按钮动作，不桥接。
//  1.0-8 模块 3（红包自动抢 + 超级福袋）同按此桥接：总开关
//  （redEnvelope.enabled / superLucky.enabled，默认关）、自动领取
//  （redEnvelope.autoClaim，默认关）、模式（redEnvelope.mode，
//  0 = 静默观测、1 = 手动点按钮、2 = 网页，默认静默）、延迟
//  （redEnvelope.delay / superLucky.delay，默认 3 秒，钳制 0–30 秒）、
//  入口位置（redEnvelope/superLucky.entryPosition.portrait/.landscape，
//  默认右下角）、开奖提醒（superLucky/lucky.drawReminder，默认关，
//  键归模块 3、行为归模块 4）、提醒提前秒数（drawReminderSeconds，
//  默认 60 秒，钳制 0–3600 秒）。lucky.* 共享键的 1.0-3 默认值不动。
//  history/resetPosition/info 是按钮动作，不桥接。
//  未在 DYxs 设置里动过的键沿用 DY778RegisterDefaults 注册的默认值（全部关闭）。
//  死键不登记：lucky.autoPhrase / lucky.autoJoin 只出现在 DY778 默认值表里，
//  本 commit 的福袋代码并不读取它们。
//

#import "DKSettings.h"
#import "DY778Core.h"
#import "DY778DisplayStats.h"
#import "DY778LiveAnalysis.h"
#import "DY778RedEnvelope.h"
#import "DY778SuperLucky.h"
#import "DY778CommentColor.h"
#import "DY778DrawReminder.h"
#import "DY778CommentExpand.h"
#import "DY778ListClear.h"
#import "DY778LiveAppearance.h"

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
        // 1.1-2：主页消费等级单独开关（星牌查询未开时不显示）。
        {@"DKXSFansProfileLevel", @"fans.profileLevel"},
        {@"DKXSDisplayStatsEnabled", @"displayStats.enabled"},
        // 1.0-8 模块 1：直播间工具（开关默认全部关闭）。
        {@"DKXSLiveToolsStealth", @"liveTools.stealth"},
        {@"DKXSLiveToolsScheduler", @"liveTools.scheduler"},
        {@"DKXSLiveToolsRisk", @"liveTools.risk"},
        // 1.0-8 模块 2：直播数据分析（总开关与通知默认关，数值展示默认开，未证实）。
        {@"DKXSLiveAnalysisEnabled", @"liveAnalysis.enabled"},
        {@"DKXSLiveAnalysisCompact", @"liveAnalysis.compact"},
        {@"DKXSLiveAnalysisAudienceNotice", @"liveAnalysis.audienceNotice"},
        {@"DKXSLiveAnalysisGiftNotice", @"liveAnalysis.giftNotice"},
        {@"DKXSLiveAnalysisAudience", @"liveAnalysis.audience"},
        {@"DKXSLiveAnalysisAudienceValues", @"liveAnalysis.audienceValues"},
        // 1.0-8 模块 3：红包自动抢 + 超级福袋（总开关与通知默认关）。
        {@"DKXSRedEnvelopeEnabled", @"redEnvelope.enabled"},
        {@"DKXSRedEnvelopeAutoClaim", @"redEnvelope.autoClaim"},
        {@"DKXSRedEnvelopeShowEntry", @"redEnvelope.showEntry"},
        {@"DKXSRedEnvelopeHaptics", @"redEnvelope.haptics"},
        {@"DKXSRedEnvelopeCompact", @"redEnvelope.compact"},
        {@"DKXSRedEnvelopeNotifyResult", @"redEnvelope.notifyResult"},
        {@"DKXSRedEnvelopePrompt", @"redEnvelope.prompt"},
        {@"DKXSSuperLuckyEnabled", @"superLucky.enabled"},
        {@"DKXSSuperLuckyShowEntry", @"superLucky.showEntry"},
        {@"DKXSSuperLuckyNotifyResult", @"superLucky.notifyResult"},
        {@"DKXSSuperLuckyHaptics", @"superLucky.haptics"},
        {@"DKXSSuperLuckyCompact", @"superLucky.compact"},
        {@"DKXSSuperLuckyAutoFollow", @"superLucky.autoFollow"},
        {@"DKXSSuperLuckyDrawReminder", @"superLucky.drawReminder"},
        {@"DKXSLuckyDrawReminder", @"lucky.drawReminder"},
        // 1.1-2：评论蓝字总开关（默认关）。
        {@"DKXSCommentBlueEnabled", @"comment.blue.enabled"},
        // 1.0-8 模块 4：评论展开与清理关注总开关（默认关，未证实）。
        {@"DKXSMiscCommentsEnabled", @"comments.enabled"},
        {@"DKXSMiscListClearEnabled", @"listClear.enabled"},
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
    // 入口位置：选择下标 0 = 右下角，1 = 左下角，2 = 右上角，3 = 左上角；
    // portrait 与 landscape 两个子键写同一值（规格 §8）。
    if ([defaults objectForKey:@"DKXSLiveAnalysisEntryPosition"]) {
        NSArray<NSString *> *positions = @[@"bottom-right", @"bottom-left", @"top-right", @"top-left"];
        NSInteger index = [defaults integerForKey:@"DKXSLiveAnalysisEntryPosition"];
        NSString *position = positions[(NSUInteger)MAX(0, MIN(3, index))];
        DY778Set(@"liveAnalysis.entryPosition.portrait", position);
        DY778Set(@"liveAnalysis.entryPosition.landscape", position);
    }
    // 1.0-8 模块 3：红包/福袋入口位置（同款四值）。
    if ([defaults objectForKey:@"DKXSRedEnvelopeEntryPosition"]) {
        NSArray<NSString *> *positions = @[@"bottom-right", @"bottom-left", @"top-right", @"top-left"];
        NSInteger index = [defaults integerForKey:@"DKXSRedEnvelopeEntryPosition"];
        NSString *position = positions[(NSUInteger)MAX(0, MIN(3, index))];
        DY778Set(@"redEnvelope.entryPosition.portrait", position);
        DY778Set(@"redEnvelope.entryPosition.landscape", position);
    }
    if ([defaults objectForKey:@"DKXSSuperLuckyEntryPosition"]) {
        NSArray<NSString *> *positions = @[@"bottom-right", @"bottom-left", @"top-right", @"top-left"];
        NSInteger index = [defaults integerForKey:@"DKXSSuperLuckyEntryPosition"];
        NSString *position = positions[(NSUInteger)MAX(0, MIN(3, index))];
        DY778Set(@"superLucky.entryPosition.portrait", position);
        DY778Set(@"superLucky.entryPosition.landscape", position);
    }
    // 红包领取模式：选择下标 0 = 静默（只观测、不拦截官方领取视图），
    // 1 = 手动（点按钮），2 = 网页（WKWebView JS）。
    if ([defaults objectForKey:@"DKXSRedEnvelopeMode"]) {
        NSArray<NSString *> *modes = @[@"quiet", @"manual", @"web"];
        NSInteger index = [defaults integerForKey:@"DKXSRedEnvelopeMode"];
        DY778Set(@"redEnvelope.mode", modes[(NSUInteger)MAX(0, MIN(2, index))]);
    }
    // 1.1-2：消费等级胶囊配色（选择下标 0 = 金色，1 = 蓝色，2 = 粉色，3 = 灰色）。
    if ([defaults objectForKey:@"DKXSFansLevelColor"]) {
        NSArray<NSString *> *colors = @[@"gold", @"blue", @"pink", @"gray"];
        NSInteger index = [defaults integerForKey:@"DKXSFansLevelColor"];
        DY778Set(@"fans.levelColor", colors[(NSUInteger)MAX(0, MIN(3, index))]);
    }
    // 1.0-8 模块 4：直播外观对齐/顺序（选择下标 0/1/2 与 0/1）。
    if ([defaults objectForKey:@"DKXSMiscLiveAppearanceAlignment"]) {
        NSArray<NSString *> *alignments = @[@"left", @"center", @"right"];
        NSInteger index = [defaults integerForKey:@"DKXSMiscLiveAppearanceAlignment"];
        DY778Set(@"liveAppearance.alignment", alignments[(NSUInteger)MAX(0, MIN(2, index))]);
    }
    if ([defaults objectForKey:@"DKXSMiscLiveAppearanceOrder"]) {
        NSArray<NSString *> *orders = @[@"viewersFirst", @"durationFirst"];
        NSInteger index = [defaults integerForKey:@"DKXSMiscLiveAppearanceOrder"];
        DY778Set(@"liveAppearance.order", orders[(NSUInteger)MAX(0, MIN(1, index))]);
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
        // 1.0-8 模块 1：弹幕间隔（秒），DY778Set 钳制在 5–300 秒。
        {@"DKXSLiveToolsInterval", @"liveTools.interval"},
        // 1.0-8 模块 3：领取延迟（秒），DY778Set 钳制在 0–30 秒；
        // 提醒提前秒数，DY778Set 钳制在 0–3600 秒。
        {@"DKXSRedEnvelopeDelay", @"redEnvelope.delay"},
        {@"DKXSSuperLuckyDelay", @"superLucky.delay"},
        {@"DKXSSuperLuckyDrawReminderSeconds", @"superLucky.drawReminderSeconds"},
        {@"DKXSLuckyDrawReminderSeconds", @"lucky.drawReminderSeconds"},
        // 1.0-8 模块 4：外观缩放，DY778Set 钳制在 0.75–1.5。
        {@"DKXSMiscLiveAppearanceScale", @"liveAppearance.scale"},
        // 1.1-2：消费等级胶囊大小与字号。
        {@"DKXSFansLevelScale", @"fans.levelScale"},
        {@"DKXSFansLevelFontSize", @"fans.levelFontSize"},
    };
    for (NSUInteger i = 0; i < sizeof(numberKeys) / sizeof(numberKeys[0]); i++) {
        id value = [defaults objectForKey:numberKeys[i][0]];
        if ([value isKindOfClass:NSString.class]) {
            DY778Set(numberKeys[i][1], ((NSString *)value).length ? @([(NSString *)value doubleValue]) : nil);
        } else if ([value isKindOfClass:NSNumber.class]) {
            DY778Set(numberKeys[i][1], value);
        }
    }
    // 文本（直接存字符串；留空则清除回默认值）。
    static NSString *const stringKeys[][2] = {
        // 1.0-8 模块 1：定时弹幕文本、游客 TTWID。
        {@"DKXSLiveToolsText", @"liveTools.selectedText"},
        {@"DKXSLiveToolsTTWID", @"liveTools.ttwid"},
    };
    for (NSUInteger i = 0; i < sizeof(stringKeys) / sizeof(stringKeys[0]); i++) {
        id value = [defaults objectForKey:stringKeys[i][0]];
        if ([value isKindOfClass:NSString.class]) {
            DY778Set(stringKeys[i][1], ((NSString *)value).length ? value : nil);
        } else if ([value isKindOfClass:NSNumber.class]) {
            DY778Set(stringKeys[i][1], [value description]);
        }
    }
    // 1.0-8 模块 4：外观三值同步进 liveInfo.cardAppearance（编辑器与
    // 直播间胶囊只读该字典）。选择行/文本框改的是 liveAppearance.*，
    // 这里再合成为 cardAppearance 字典。
    if ([defaults objectForKey:@"DKXSMiscLiveAppearanceAlignment"] ||
        [defaults objectForKey:@"DKXSMiscLiveAppearanceOrder"] ||
        [defaults objectForKey:@"DKXSMiscLiveAppearanceScale"]) {
        DY778LiveAppearance appearance = DY778LiveAppearanceCurrent();
        NSString *alignment = DY778String(@"liveAppearance.alignment");
        if (alignment.length) appearance.alignment = [alignment isEqualToString:@"left"] ? 0 : [alignment isEqualToString:@"right"] ? 2 : 1;
        NSString *order = DY778String(@"liveAppearance.order");
        if (order.length) appearance.order = [order isEqualToString:@"durationFirst"] ? 1 : 0;
        appearance.scale = DY778Number(@"liveAppearance.scale");
        DY778Set(@"liveInfo.cardAppearance", DY778LiveAppearanceStoredValue(appearance));
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
    // 1.1-2：主页消费等级（粉丝区旁胶囊，单独开关）。
    DKSettingsRegister(@"DKXSFansProfileLevel", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeSwitch(@"DKXSFansProfileLevel", @"主页显示消费等级", @""),
            @"开启后，在自己和他人主页的粉丝区域旁显示消费等级胶囊。需先开启上方星牌查询，未开启时不显示。默认关闭。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSFansLevelScale", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeTextInput(@"DKXSFansLevelScale", @"消费等级胶囊大小", @"1.0", 4),
            @"0.6–1.6 倍，默认 1.0。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSFansLevelFontSize", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeTextInput(@"DKXSFansLevelFontSize", @"消费等级字号", @"11", 3),
            @"默认 11。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSFansLevelColor", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeChoice(@"DKXSFansLevelColor", @"消费等级配色", @[@"金色", @"蓝色", @"粉色", @"灰色"]),
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

    // ---------- DY778 1.0-8 模块 1 新增：直播间工具 ----------
    DKSettingsRegister(@"DKXSLiveToolsStealth", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeSwitch(@"DKXSLiveToolsStealth", @"隐身进直播间", @""),
            @"开启后，进直播间时不携带登录身份，服务端按游客处理。隐身期间无法发送弹幕与礼物（礼物拦截另需开启下方风控开关），退出直播间后恢复。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSLiveToolsScheduler", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeSwitch(@"DKXSLiveToolsScheduler", @"定时弹幕", @""),
            @"开启后，在直播间内按间隔自动发送下方设置的弹幕文本。切换或离开直播间、进入后台、修改文本或间隔都会停止本轮，返回后需重新触发。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSLiveToolsInterval", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeTextInput(@"DKXSLiveToolsInterval", @"弹幕发送间隔（秒）", @"30", 4),
            @"5–300 秒，默认 30 秒。间隔越短、连续使用越频繁，越容易触发频率限制，建议优先使用默认节奏。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSLiveToolsText", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeTextInput(@"DKXSLiveToolsText", @"定时弹幕文本", @"输入弹幕内容", 12),
            @"定时发送的弹幕内容，最多 200 字。留空则不发送。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSLiveToolsRisk", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeSwitch(@"DKXSLiveToolsRisk", @"隐身时拦截礼物", @""),
            @"开启后，隐身进直播间期间发送礼物的操作会被拦截，避免暴露身份。仅在隐身开关同时开启时生效。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSLiveToolsTTWID", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeTextInput(@"DKXSLiveToolsTTWID", @"游客 TTWID", @"留空则不注入", 12),
            @"游客模式使用的 TTWID（16–64 位十六进制串），留空则不注入。需要时从抓包获取。"),
            ^{ DY778SyncRemainingSettings(); });
    });

    // ---------- DY778 1.0-8 模块 2 新增：直播数据分析 ----------
    DKSettingsRegister(@"DKXSLiveAnalysisEnabled", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeSwitch(@"DKXSLiveAnalysisEnabled", @"启用直播数据分析", @""),
            @"开启后，在直播间内观测观众榜、礼物、PK 与人气数据，入口按钮出现在直播画面角落。只读展示，不修改直播间行为；关闭后 hook 不安装。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSLiveAnalysisCompact", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeSwitch(@"DKXSLiveAnalysisCompact", @"紧凑模式", @""),
            @"入口按钮与数据面板使用更小的布局。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSLiveAnalysisEntryPosition", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeChoice(@"DKXSLiveAnalysisEntryPosition", @"入口位置", @[@"右下角", @"左下角", @"右上角", @"左上角"]),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSLiveAnalysisAudience", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeSwitch(@"DKXSLiveAnalysisAudience", @"观众榜弹层", @""),
            @"开启后，观众榜数据在弹层中展示，支持分页加载。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSLiveAnalysisAudienceValues", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeSwitch(@"DKXSLiveAnalysisAudienceValues", @"显示观众数值", @""),
            @"观众榜行显示分数与名次。默认值未证实，以运行时实测为准。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSLiveAnalysisAudienceNotice", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeSwitch(@"DKXSLiveAnalysisAudienceNotice", @"观众通知", @""),
            @"观众榜数据变化时提示。默认关闭。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSLiveAnalysisGiftNotice", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeSwitch(@"DKXSLiveAnalysisGiftNotice", @"礼物通知", @""),
            @"收到礼物数据时提示。默认关闭。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSLiveAnalysisGetVisitor", ^AWESettingItemModel *{
        return DKSettingsWithoutBackup(DKMakeAction(@"DKXSLiveAnalysisGetVisitor", @"获取游客身份", @"", ^(AWESettingItemModel *item, UIViewController *presenter) {
            (void)item; (void)presenter;
            DY778LiveAnalysisRegisterVisitor(^(NSString *ttwid) {
                if (ttwid.length) { DY778ShowToast(@"liveAnalysis", @"已获取游客身份", NO, YES); return; }
                // 注册失败时走网页登录抓 Cookie（规格 §5）。
                DY778LiveAnalysisAcquireCredential(^(BOOL success) {
                    DY778ShowToast(@"liveAnalysis", success ? @"已获取登录凭证" : @"获取身份失败，请稍后重试", NO, success);
                });
            });
        }));
    });
    DKSettingsRegister(@"DKXSLiveAnalysisClearVisitor", ^AWESettingItemModel *{
        return DKSettingsWithoutBackup(DKMakeAction(@"DKXSLiveAnalysisClearVisitor", @"清除游客身份", @"", ^(AWESettingItemModel *item, UIViewController *presenter) {
            (void)item; (void)presenter;
            DY778LiveAnalysisClearCredential();
        }));
    });
    DKSettingsRegister(@"DKXSLiveAnalysisResetPosition", ^AWESettingItemModel *{
        return DKSettingsWithoutBackup(DKMakeAction(@"DKXSLiveAnalysisResetPosition", @"重置入口位置", @"", ^(AWESettingItemModel *item, UIViewController *presenter) {
            (void)item; (void)presenter;
            DY778Set(@"liveAnalysis.entryPosition.portrait", @"bottom-right");
            DY778Set(@"liveAnalysis.entryPosition.landscape", @"bottom-right");
            [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:@"DKXSLiveAnalysisEntryPosition"];
            DY778SyncRemainingSettings();
            DY778ShowToast(@"liveAnalysis", @"入口位置已重置为右下角", NO, YES);
        }));
    });
    DKSettingsRegister(@"DKXSLiveAnalysisInfo", ^AWESettingItemModel *{
        return DKSettingsWithoutBackup(DKMakeAction(@"DKXSLiveAnalysisInfo", @"关于直播数据分析", @"", ^(AWESettingItemModel *item, UIViewController *presenter) {
            (void)item;
            DY778ShowNotice(presenter, @"直播数据分析",
                @"观测当前直播间的观众榜、礼物、PK 与人气数据，只读展示。数据经 WebSocket（protobuf）拉取，失败时走 HTTP 兜底。Protobuf 字段映射须运行时抓包反推，首次使用部分字段可能不完整。");
        }));
    });

    // ---------- DY778 1.0-8 模块 3 新增：红包自动抢 + 超级福袋 ----------
    // 风险提示（规格 §11.2）：红包与福袋是真实利益发放，频繁自动领取
    // 极可能触发限流、验证码或账号风控；只证明了原版「尝试领取」的代码
    // 路径，没有任何证据证明在抖音 40.8.0 上仍能成功领取。默认全部关闭。
    DKSettingsRegister(@"DKXSRedEnvelopeEnabled", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeSwitch(@"DKXSRedEnvelopeEnabled", @"启用红包自动抢", @""),
            @"开启后，在直播间内发现红包并按下方模式处理。只证明了原版「尝试领取」的代码路径，没有证据证明在抖音 40.8.0 上仍能成功领取；频繁自动领取可能触发限流、验证码或账号风控。默认关闭。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSRedEnvelopeAutoClaim", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeSwitch(@"DKXSRedEnvelopeAutoClaim", @"自动领取红包", @""),
            @"关闭时只观测、不执行领取。开启后按所选模式尝试领取，仅免费/无条件红包会进入领取流程，有门槛的（灯牌/粉丝/钻/关注/口令/付费/送礼）一律跳过。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSRedEnvelopeMode", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeChoice(@"DKXSRedEnvelopeMode", @"红包领取模式", @[@"静默（只观测）", @"手动（点按钮）", @"网页（WKWebView）"]),
            @"静默模式在 DYxs 侧只做观测与记录，不拦截官方领取视图（静默领取的原生调用未静态还原，拦截会使用户丢红包）；手动模式在官方红包面板里按按钮文本点领取；网页模式在找到的 WKWebView 里用 JS 点领取。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSRedEnvelopeShowEntry", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeSwitch(@"DKXSRedEnvelopeShowEntry", @"显示红包入口按钮", @""),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSRedEnvelopeEntryPosition", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeChoice(@"DKXSRedEnvelopeEntryPosition", @"红包入口位置", @[@"右下角", @"左下角", @"右上角", @"左上角"]),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSRedEnvelopeDelay", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeTextInput(@"DKXSRedEnvelopeDelay", @"红包领取延迟（秒）", @"3", 4),
            @"0–30 秒，默认 3 秒。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSRedEnvelopeHaptics", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeSwitch(@"DKXSRedEnvelopeHaptics", @"红包触感反馈", @""),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSRedEnvelopeCompact", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeSwitch(@"DKXSRedEnvelopeCompact", @"红包紧凑显示", @""),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSRedEnvelopeNotifyResult", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeSwitch(@"DKXSRedEnvelopeNotifyResult", @"红包领取结果通知", @""),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSRedEnvelopePrompt", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeSwitch(@"DKXSRedEnvelopePrompt", @"红包提示文案", @""),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSRedEnvelopeResetPosition", ^AWESettingItemModel *{
        return DKSettingsWithoutBackup(DKMakeAction(@"DKXSRedEnvelopeResetPosition", @"重置红包入口位置", @"", ^(AWESettingItemModel *item, UIViewController *presenter) {
            (void)item; (void)presenter;
            DY778Set(@"redEnvelope.entryPosition.portrait", @"bottom-right");
            DY778Set(@"redEnvelope.entryPosition.landscape", @"bottom-right");
            [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:@"DKXSRedEnvelopeEntryPosition"];
            DY778SyncRemainingSettings();
            DY778ShowToast(@"redEnvelope", @"入口位置已重置为右下角", NO, YES);
        }));
    });
    DKSettingsRegister(@"DKXSRedEnvelopeHistory", ^AWESettingItemModel *{
        return DKSettingsWithoutBackup(DKMakeAction(@"DKXSRedEnvelopeHistory", @"红包记录", @"", ^(AWESettingItemModel *item, UIViewController *presenter) {
            (void)item;
            DY778PresentController(presenter, [[DY778REHistoryController alloc] init]);
        }));
    });
    DKSettingsRegister(@"DKXSSuperLuckyEnabled", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeSwitch(@"DKXSSuperLuckyEnabled", @"启用超级福袋", @""),
            @"开启后，在直播间内发现超级福袋并按任务上下文尝试参与。观看任务须真实停留，DYxs 不伪造观看时长；关注/加团/送礼类任务不代做。只证明了原版「尝试领取」的代码路径，没有证据证明在抖音 40.8.0 上仍能成功参与。默认关闭。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSSuperLuckyShowEntry", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeSwitch(@"DKXSSuperLuckyShowEntry", @"显示福袋入口按钮", @""),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSSuperLuckyEntryPosition", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeChoice(@"DKXSSuperLuckyEntryPosition", @"福袋入口位置", @[@"右下角", @"左下角", @"右上角", @"左上角"]),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSSuperLuckyDelay", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeTextInput(@"DKXSSuperLuckyDelay", @"福袋执行延迟（秒）", @"3", 4),
            @"0–30 秒，默认 3 秒。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSSuperLuckyHaptics", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeSwitch(@"DKXSSuperLuckyHaptics", @"福袋触感反馈", @""),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSSuperLuckyCompact", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeSwitch(@"DKXSSuperLuckyCompact", @"福袋紧凑显示", @""),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSSuperLuckyNotifyResult", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeSwitch(@"DKXSSuperLuckyNotifyResult", @"福袋参与结果通知", @""),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSSuperLuckyAutoFollow", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeSwitch(@"DKXSSuperLuckyAutoFollow", @"福袋自动关注", @""),
            @"参与任务需要关注主播时是否自动关注。默认关闭。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSSuperLuckyDrawReminder", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeSwitch(@"DKXSSuperLuckyDrawReminder", @"福袋开奖提醒", @""),
            @"开奖提醒的键归本模块，提醒行为（到点弹窗/通知）由模块 4 的抽奖提醒实现。默认关闭。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSSuperLuckyDrawReminderSeconds", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeTextInput(@"DKXSSuperLuckyDrawReminderSeconds", @"福袋提醒提前（秒）", @"60", 4),
            @"0–3600 秒，默认 60 秒。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSLuckyDrawReminder", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeSwitch(@"DKXSLuckyDrawReminder", @"共享开奖提醒", @""),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSLuckyDrawReminderSeconds", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeTextInput(@"DKXSLuckyDrawReminderSeconds", @"共享提醒提前（秒）", @"60", 4),
            @"0–3600 秒，默认 60 秒。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSSuperLuckyResetPosition", ^AWESettingItemModel *{
        return DKSettingsWithoutBackup(DKMakeAction(@"DKXSSuperLuckyResetPosition", @"重置福袋入口位置", @"", ^(AWESettingItemModel *item, UIViewController *presenter) {
            (void)item; (void)presenter;
            DY778Set(@"superLucky.entryPosition.portrait", @"bottom-right");
            DY778Set(@"superLucky.entryPosition.landscape", @"bottom-right");
            [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:@"DKXSSuperLuckyEntryPosition"];
            DY778SyncRemainingSettings();
            DY778ShowToast(@"superLucky", @"入口位置已重置为右下角", NO, YES);
        }));
    });
    DKSettingsRegister(@"DKXSSuperLuckyHistory", ^AWESettingItemModel *{
        return DKSettingsWithoutBackup(DKMakeAction(@"DKXSSuperLuckyHistory", @"福袋记录", @"", ^(AWESettingItemModel *item, UIViewController *presenter) {
            (void)item;
            DY778PresentController(presenter, [[DY778SLHistoryController alloc] init]);
        }));
    });
    // 1.1-2：评论蓝字（六样式：AI/私信/链接/播放/对话/纯蓝色；符号 1–8 组混用）。
    DKSettingsRegister(@"DKXSCommentBlueEnabled", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeSwitch(@"DKXSCommentBlueEnabled", @"评论蓝字", @""),
            @"开启后，评论里用符号包住的文字发送后变蓝。支持 AI、私信、链接、播放、对话和纯蓝色六种样式，符号可在下方编辑（1–8 组，一句中可混用）。默认符号：AI《》、私信、链接{}、播放<>、对话「」、纯蓝色〔〕。默认关闭。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSCommentBlueSymbols", ^AWESettingItemModel *{
        return DKSettingsWithoutBackup(DKMakeAction(@"DKXSCommentBlueSymbols", @"蓝字符号编辑", @"", ^(AWESettingItemModel *item, UIViewController *presenter) {
            (void)item;
            DY778PresentController(presenter, DY778CommentSymbolEditorController());
        }));
    });
    DKSettingsRegister(@"DKXSRedEnvelopeInfo", ^AWESettingItemModel *{
        return DKSettingsWithoutBackup(DKMakeAction(@"DKXSRedEnvelopeInfo", @"关于红包福袋", @"", ^(AWESettingItemModel *item, UIViewController *presenter) {
            (void)item;
            DY778ShowNotice(presenter, @"红包福袋",
                @"红包自动抢与超级福袋：发现直播间红包/福袋并按模式尝试领取。只证明了原版「尝试领取」的代码路径，没有证据证明在抖音 40.8.0 上仍能成功领取；频繁自动领取可能触发限流、验证码或账号风控。静默模式只做观测、不拦截官方领取视图；观看任务须真实停留，DYxs 不伪造观看时长；开奖提醒行为由模块 4 实现。");
        }));
    });

    // ---------- DY778 1.0-8 模块 4：抽奖提醒 + 评论展开 +
    // 清理关注 + 直播外观编辑（备份恢复已于 0.6.9.45 去重删除） ----------
    DKSettingsRegister(@"DKXSMiscCommentsEnabled", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeSwitch(@"DKXSMiscCommentsEnabled", @"启用评论展开", @""),
            @"开启后，在评论列表里扫描长评论并记录展开候选。展开的具体 UI 动作未静态还原，当前版本只做 hook 与扫描记录，不改评论显示。默认关闭。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSMiscListClearEnabled", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeSwitch(@"DKXSMiscListClearEnabled", @"启用清理关注", @""),
            @"开启后，可读取关注列表并选择要取关的用户。取关是否走服务端接口、是否立即生效、是否可逆，一律未证实；当前版本不会发出任何取关请求。默认关闭。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSMiscListClearSettings", ^AWESettingItemModel *{
        return DKSettingsWithoutBackup(DKMakeAction(@"DKXSMiscListClearSettings", @"清理关注设置", @"", ^(AWESettingItemModel *item, UIViewController *presenter) {
            (void)item;
            DY778PresentController(presenter, DY778ListClearSettingsController());
        }));
    });
    DKSettingsRegister(@"DKXSMiscLiveAppearanceEditor", ^AWESettingItemModel *{
        return DKSettingsWithoutBackup(DKMakeAction(@"DKXSMiscLiveAppearanceEditor", @"直播外观编辑", @"", ^(AWESettingItemModel *item, UIViewController *presenter) {
            (void)item;
            DY778PresentLiveAppearanceEditor(presenter);
        }));
    });
    DKSettingsRegister(@"DKXSMiscLiveAppearanceAlignment", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeChoice(@"DKXSMiscLiveAppearanceAlignment", @"外观对齐", @[@"左", @"中", @"右"]),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSMiscLiveAppearanceOrder", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKMakeChoice(@"DKXSMiscLiveAppearanceOrder", @"外观顺序", @[@"人数在前", @"时长在前"]),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSMiscLiveAppearanceScale", ^AWESettingItemModel *{
        return DKSettingsOnChange(DKSettingsWithInfo(DKMakeTextInput(@"DKXSMiscLiveAppearanceScale", @"外观缩放", @"1.0", 4),
            @"0.75–1.5，默认 1.0。"),
            ^{ DY778SyncRemainingSettings(); });
    });
    DKSettingsRegister(@"DKXSMiscDrawReminderInfo", ^AWESettingItemModel *{
        return DKSettingsWithoutBackup(DKMakeAction(@"DKXSMiscDrawReminderInfo", @"关于抽奖提醒", @"", ^(AWESettingItemModel *item, UIViewController *presenter) {
            (void)item;
            DY778ShowNotice(presenter, @"抽奖提醒",
                @"红包/福袋开奖前按提前秒数弹窗提醒，点「去直播间」可跳回开奖直播间。提醒开关与提前秒数在「红包福袋」节里设置（键归模块 3，提醒行为归本模块）。");
        }));
    });
    DKSettingsRegister(@"DKXSMiscInfo", ^AWESettingItemModel *{
        return DKSettingsWithoutBackup(DKMakeAction(@"DKXSMiscInfo", @"关于杂项", @"", ^(AWESettingItemModel *item, UIViewController *presenter) {
            (void)item;
            DY778ShowNotice(presenter, @"杂项",
                @"清理关注是破坏性操作：取关是否可逆未证实，当前版本不会发出任何取关请求。评论展开只做扫描记录，不改评论显示。");
        }));
    });

}
