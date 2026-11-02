//
//  DKXSMessageArchiveSettings.xm
//  DY778 第 1 批 staging：消息留存 / 编辑历史 / 时间标签的设置登记。
//  只登记设置行，不含 hook；hook 见 DKXSMessageArchiveHooks.xm。
//  键命名：上游点分键一律改为 DKXS* 驼峰键，写入 DYxs 标准 defaults；
//  位置选项统一用 DKMakeChoice 存下标，顺序固定 [右侧, 上方, 下方]；
//  透明度 0–1 小数只能用文字输入，不能用 0–100 滑条（见 DKXSArchiveCore 钳制）；
//  保留天数 / 条数上限 0 = 不限，用文字输入整数，读取时钳制（见存储层 maintenance）。
//  默认值：DKXSArchiveRegisterDefaults() 在 %ctor 里先注册一次，
//  这样默认开的项（标记、智能日期、时间背景）在设置行里也显示为开，与功能一致。
//  布局表位置见 REPORT（父 agent 并入 DKSettingsLayout.m“消息留存”分区）。
//

#import "DKSettings.h"
#import "DKXSRecall.h"
#import "DKXSEditHistory.h"
#import "DKXSMessageUI.h"
#import "DKXSArchiveCore.h"
#import "DKXSRecallNotifications.h"

static DKColorSample *DKXSArchiveColorSample(NSString *text) {
    DKColorSample *sample = [DKColorSample new];
    sample.text = text;
    return sample;
}
static AWESettingItemModel *DKXSArchiveRefreshing(AWESettingItemModel *item) {
    return DKSettingsOnChange(item, ^{ DKXSMessageUIInvalidate(YES); });
}

%ctor {
    DKXSArchiveRegisterDefaults();

    // ---- 撤回（12 键） ----
    DKSettingsRegister(@"DKXSRecallEnabled", ^AWESettingItemModel *{
        return DKXSArchiveRefreshing(DKSettingsWithInfo(DKMakeSwitch(@"DKXSRecallEnabled", @"启用消息留存", @""),
            @"留存本机已收到的消息，对方撤回后仍可查看原文。只留存对方消息，自己的消息不进档案；档案只存本机，不外发。"));
    });
    DKSettingsRegister(@"DKXSRecallBadge", ^AWESettingItemModel *{
        return DKXSArchiveRefreshing(DKMakeSwitch(@"DKXSRecallBadge", @"撤回标记", @"对方撤回后，在气泡旁显示标记。"));
    });
    DKSettingsRegister(@"DKXSRecallBadgeText", ^AWESettingItemModel *{
        return DKXSArchiveRefreshing(DKMakeTextInput(@"DKXSRecallBadgeText", @"撤回标记文字", @"已撤回", 12));
    });
    DKSettingsRegister(@"DKXSRecallPosition", ^AWESettingItemModel *{
        return DKXSArchiveRefreshing(DKMakeChoice(@"DKXSRecallPosition", @"撤回标记位置", @[@"右侧", @"上方", @"下方"]));
    });
    DKSettingsRegister(@"DKXSRecallArchiveEntry", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSRecallArchiveEntry", @"聊天信息页显示撤回记录入口", @"在聊天信息页追加撤回记录入口；关闭后仍可从 DYxs 设置页的动作行进入。");
    });
    DKSettingsRegister(@"DKXSRecallNotifications", ^AWESettingItemModel *{
        return DKSettingsWithInfo(DKMakeSwitch(@"DKXSRecallNotifications", @"撤回提醒", @""),
            @"默认关闭。开启后：前台显示应用内横幅，后台收到事件时发本地通知，点按进入对应记录。");
    });
    DKSettingsRegister(@"DKXSRecallNotificationPreview", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSRecallNotificationPreview", @"提醒显示消息内容", @"默认关闭。关闭时提醒正文只写“有新的撤回记录”，不带原文。");
    });
    DKSettingsRegister(@"DKXSRecallTintBubble", ^AWESettingItemModel *{
        return DKXSArchiveRefreshing(DKMakeSwitch(@"DKXSRecallTintBubble", @"撤回后气泡染色", @"对方撤回后，给该气泡染上撤回颜色。"));
    });
    DKSettingsRegister(@"DKXSRecallPlainBubbleOnSkin", ^AWESettingItemModel *{
        return DKXSArchiveRefreshing(DKMakeSwitch(@"DKXSRecallPlainBubbleOnSkin", @"撤回后使用普通气泡", @"对方撤回后，气泡皮肤换回普通气泡样式；图片、视频和表情画面保持原样。"));
    });
    DKSettingsRegister(@"DKXSRecallBubbleColor", ^AWESettingItemModel *{
        return DKXSArchiveRefreshing(DKMakeColorPicker(@"DKXSRecallBubbleColor", @"撤回气泡颜色", DKXSArchiveColorSample(@"已撤回的消息")));
    });
    DKSettingsRegister(@"DKXSRecallRetentionDays", ^AWESettingItemModel *{
        return DKMakeTextInput(@"DKXSRecallRetentionDays", @"撤回记录保留天数", @"0（不限）", 8);
    });
    DKSettingsRegister(@"DKXSRecallMaxRecords", ^AWESettingItemModel *{
        return DKMakeTextInput(@"DKXSRecallMaxRecords", @"撤回记录数量上限", @"0（不限）", 10);
    });

    // ---- 编辑历史（11 键） ----
    DKSettingsRegister(@"DKXSEditEnabled", ^AWESettingItemModel *{
        return DKXSArchiveRefreshing(DKSettingsWithInfo(DKMakeSwitch(@"DKXSEditEnabled", @"启用编辑历史", @""),
            @"保存本机收到的原文及后续编辑版本。首次收到时已经编辑的消息会标注未取得原文；启用前、离线或应用未运行期间未收到的版本无法补回。"));
    });
    DKSettingsRegister(@"DKXSEditBadge", ^AWESettingItemModel *{
        return DKXSArchiveRefreshing(DKMakeSwitch(@"DKXSEditBadge", @"编辑标记", @"消息被编辑后，在气泡旁显示标记与编辑次数。"));
    });
    DKSettingsRegister(@"DKXSEditBadgeText", ^AWESettingItemModel *{
        return DKXSArchiveRefreshing(DKMakeTextInput(@"DKXSEditBadgeText", @"编辑标记文字", @"编辑历史", 12));
    });
    DKSettingsRegister(@"DKXSEditPosition", ^AWESettingItemModel *{
        return DKXSArchiveRefreshing(DKMakeChoice(@"DKXSEditPosition", @"编辑标记位置", @[@"右侧", @"上方", @"下方"]));
    });
    DKSettingsRegister(@"DKXSEditArchiveEntry", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSEditArchiveEntry", @"聊天信息页显示编辑历史入口", @"在聊天信息页追加编辑历史入口；关闭后仍可从 DYxs 设置页的动作行进入。");
    });
    DKSettingsRegister(@"DKXSEditTintBubble", ^AWESettingItemModel *{
        return DKXSArchiveRefreshing(DKMakeSwitch(@"DKXSEditTintBubble", @"编辑后气泡染色", @"消息被编辑后，给该气泡染上编辑颜色；同一消息也已撤回时，撤回底色优先。"));
    });
    DKSettingsRegister(@"DKXSEditBubbleColor", ^AWESettingItemModel *{
        return DKXSArchiveRefreshing(DKMakeColorPicker(@"DKXSEditBubbleColor", @"编辑气泡颜色", DKXSArchiveColorSample(@"被编辑的消息")));
    });
    DKSettingsRegister(@"DKXSEditNotifications", ^AWESettingItemModel *{
        return DKSettingsWithInfo(DKMakeSwitch(@"DKXSEditNotifications", @"编辑提醒", @""),
            @"默认关闭。开启后：前台显示应用内横幅，后台实际收到事件时发本地通知，点按进入对应历史。");
    });
    DKSettingsRegister(@"DKXSEditNotificationPreview", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSEditNotificationPreview", @"提醒显示消息内容", @"默认关闭。关闭时提醒正文只写“有新的编辑历史记录”，不带原文。");
    });
    DKSettingsRegister(@"DKXSEditRetentionDays", ^AWESettingItemModel *{
        return DKMakeTextInput(@"DKXSEditRetentionDays", @"编辑历史保留天数", @"0（不限）", 8);
    });
    DKSettingsRegister(@"DKXSEditMaxRecords", ^AWESettingItemModel *{
        return DKMakeTextInput(@"DKXSEditMaxRecords", @"编辑历史数量上限", @"0（不限）", 10);
    });

    // ---- 时间标签（9 键） ----
    DKSettingsRegister(@"DKXSTimeEnabled", ^AWESettingItemModel *{
        return DKXSArchiveRefreshing(DKMakeSwitch(@"DKXSTimeEnabled", @"启用聊天时间标签", @"在气泡旁叠加自定义时间标签；与撤回、编辑标记共用一列避让。"));
    });
    DKSettingsRegister(@"DKXSTimeFormat", ^AWESettingItemModel *{
        return DKXSArchiveRefreshing(DKMakeTextInput(@"DKXSTimeFormat", @"时间格式", @"HH:mm:ss", 40));
    });
    DKSettingsRegister(@"DKXSTimeSmartDate", ^AWESettingItemModel *{
        return DKXSArchiveRefreshing(DKMakeSwitch(@"DKXSTimeSmartDate", @"智能日期", @"今天只显示时间，昨天加“昨天”，更早加日期；格式里已含日期时不追加。"));
    });
    DKSettingsRegister(@"DKXSTimeFontSize", ^AWESettingItemModel *{
        return DKXSArchiveRefreshing(DKMakeUnitSlider(@"DKXSTimeFontSize", @"时间字号", @"时间标签字号，范围 9–17。", 9, 17, 11, @" pt", nil));
    });
    DKSettingsRegister(@"DKXSTimeColor", ^AWESettingItemModel *{
        return DKXSArchiveRefreshing(DKMakeColorPicker(@"DKXSTimeColor", @"时间颜色", DKXSArchiveColorSample(@"12:34:56")));
    });
    DKSettingsRegister(@"DKXSTimeBackground", ^AWESettingItemModel *{
        return DKXSArchiveRefreshing(DKMakeSwitch(@"DKXSTimeBackground", @"时间标签背景", @"给时间标签加底色与边框；关闭后只显示文字。"));
    });
    DKSettingsRegister(@"DKXSTimeOpacity", ^AWESettingItemModel *{
        return DKXSArchiveRefreshing(DKMakeTextInput(@"DKXSTimeOpacity", @"时间标签透明度", @"0.94（0.35–1）", 6));
    });
    DKSettingsRegister(@"DKXSTimePosition", ^AWESettingItemModel *{
        return DKXSArchiveRefreshing(DKMakeChoice(@"DKXSTimePosition", @"时间标签位置", @[@"右侧", @"上方", @"下方"]));
    });
    DKSettingsRegister(@"DKXSTimeHideOfficial", ^AWESettingItemModel *{
        return DKXSArchiveRefreshing(DKMakeSwitch(@"DKXSTimeHideOfficial", @"隐藏官方时间提示", @"隐藏抖音自带的消息时间提示，只显示自定义时间标签。"));
    });

    // ---- 动作行（不落盘，须排除备份） ----
    DKSettingsRegister(@"DKXSRecallArchiveAction", ^AWESettingItemModel *{
        return DKSettingsWithoutBackup(DKMakeAction(@"DKXSRecallArchiveAction", @"查看撤回记录", @"按会话查看本机留存的撤回记录。", ^(AWESettingItemModel *item, UIViewController *presenter) {
            (void)item; DKXSRecallArchivePresentedFrom(presenter, nil);
        }));
    });
    DKSettingsRegister(@"DKXSEditHistoryAction", ^AWESettingItemModel *{
        return DKSettingsWithoutBackup(DKMakeAction(@"DKXSEditHistoryAction", @"查看编辑历史", @"按会话查看本机留存的编辑历史。", ^(AWESettingItemModel *item, UIViewController *presenter) {
            (void)item; DKXSEditHistoryPresentedFrom(presenter, nil, nil);
        }));
    });
    DKSettingsRegister(@"DKXSArchiveNotificationAction", ^AWESettingItemModel *{
        return DKSettingsWithoutBackup(DKMakeAction(@"DKXSArchiveNotificationAction", @"提醒状态与权限", @"查看系统通知授权与本批提醒开关状态；未授权时可在此申请。", ^(AWESettingItemModel *item, UIViewController *presenter) {
            (void)item; DKXSRecallShowNotificationStatus(presenter);
        }));
    });
}
