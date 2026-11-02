//
//  DKXSBatch2Settings.xm
//  DYxs 全量合并第 2 批 staging（尚未并入 DYxs 源码）
//  参照第 1 批 DKXSBatch1Settings.xm 的写法：%ctor 里用 DKSettingsRegister /
//  DKMakeSwitch 登记开关，滑条用 DKMakeUnitSlider；不 import 上游 AwemeHeaders，
//  不搬上游 DYYYSettingsHelper / DYYYSettingViewController。
//  所有开关默认关（NSUserDefaults 未写入即为 NO），与已移植各批的做法一致。
//  数值类键（倍速列表、默认倍速、自动隐藏间隔、按钮坐标）不在此登记，见 REPORT。
//

#import "DKSettings.h"
#import "DKXSExactInteractionCountHooks.h"
#import "DKXSFloatingButtonCoordinator.h"

%ctor {
    DKSettingsRegister(@"DKXSEnableFloatSpeedButton", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSEnableFloatSpeedButton", @"启用快捷倍速按钮",
                            @"播放页悬浮一个可拖动的倍速按钮，点击切换倍速。");
    });
    DKSettingsRegister(@"DKXSEnableFloatClearButton", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSEnableFloatClearButton", @"一键清屏按钮",
                            @"播放页悬浮一个清屏按钮，点击隐藏页面元素，再点恢复。");
    });
    DKSettingsRegister(@"DKXSShowExactInteractionCounts", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSShowExactInteractionCounts", @"显示完整互动数",
                            @"点赞、评论、收藏、转发显示完整数字，1 万以上不再缩写。");
    });
    DKSettingsRegister(@"DKXSHideSpeed", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideSpeed", @"清屏隐藏倍速按钮",
                            @"进入清屏时隐藏倍速按钮。");
    });
    DKSettingsRegister(@"DKXSAutoHideSpeedButton", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSAutoHideSpeedButton", @"自动隐藏快捷倍速按钮",
                            @"一段时间不操作后倍速按钮收到屏幕边缘。");
    });
    DKSettingsRegister(@"DKXSSpeedButtonStickToEdge", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSSpeedButtonStickToEdge", @"固定倍速按钮贴边",
                            @"拖动倍速按钮时贴边吸附。");
    });
    DKSettingsRegister(@"DKXSClearButtonStickToEdge", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSClearButtonStickToEdge", @"固定清屏按钮贴边",
                            @"拖动清屏按钮时贴边吸附。");
    });
    DKSettingsRegister(@"DKXSSpeedButtonShowX", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSSpeedButtonShowX", @"倍速按钮显示后缀",
                            @"倍速数字后加 x，如 2x。");
    });
    DKSettingsRegister(@"DKXSHideTabBar", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideTabBar", @"清屏隐藏底栏",
                            @"清屏时把底栏也纳入隐藏范围。");
    });
    DKSettingsRegister(@"DKXSHideDanmaku", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideDanmaku", @"清屏隐藏弹幕",
                            @"清屏时把弹幕也纳入隐藏范围。");
    });
    DKSettingsRegister(@"DKXSRemoveTimeProgress", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSRemoveTimeProgress", @"清屏移除进度",
                            @"清屏时移除进度条（连同交互一起关掉）。");
    });
    DKSettingsRegister(@"DKXSHideTimeProgress", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideTimeProgress", @"清屏隐藏进度",
                            @"清屏时隐藏进度条（仅视觉隐藏）。");
    });
    DKSettingsRegister(@"DKXSHideSlider", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideSlider", @"清屏隐藏滑条",
                            @"清屏时把故事进度滑条也纳入隐藏范围。");
    });
    DKSettingsRegister(@"DKXSHideChapter", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideChapter", @"清屏隐藏章节",
                            @"清屏时把章节进度也纳入隐藏范围。");
    });
    DKSettingsRegister(@"DKXSHideClearButtonOnTap", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideClearButtonOnTap", @"清屏隐藏清屏按钮",
                            @"清屏时清屏按钮本身也收到边缘，只留一条边缘指示。");
    });
    DKSettingsRegister(@"DKXSHidePauseVideoIcon", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHidePauseVideoIcon", @"清屏隐藏暂停图标",
                            @"清屏时把视频中央的播放 / 暂停图标也纳入隐藏范围。");
    });
    DKSettingsRegister(@"DKXSHideStatusBarOnClear", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideStatusBarOnClear", @"清屏隐藏状态栏",
                            @"清屏时触发系统重新评估状态栏显隐。");
    });
    DKSettingsRegister(@"DKXSSpeedButtonSize", ^AWESettingItemModel *{
        return DKMakeUnitSlider(@"DKXSSpeedButtonSize", @"快捷倍速按钮大小", @"倍速按钮的直径。",
                                20, 60, 32, @" pt", ^(NSInteger value) {
                                  [DKXSFloatingButtonCoordinator reloadConfiguration];
                                });
    });
    DKSettingsRegister(@"DKXSEnableFloatClearButtonSize", ^AWESettingItemModel *{
        // 键名是上游原名的直译（DYYYEnableFloatClearButtonSize），虽然读起来像开关，
        // 但它存的是清屏按钮直径（float），不要改名，否则已落盘的值对不上。
        return DKMakeUnitSlider(@"DKXSEnableFloatClearButtonSize", @"清屏按钮大小", @"清屏按钮的直径。",
                                20, 60, 40, @" pt", ^(NSInteger value) {
                                  [DKXSFloatingButtonCoordinator reloadConfiguration];
                                });
    });

    // 完整互动数是运行时 hook：安装本身与开关无关，替换函数实时读设置，
    // 开关关闭时透传原实现（这是上游的设计，本移植保持原样）。
    DKXSStartExactInteractionCountHooks();
}
