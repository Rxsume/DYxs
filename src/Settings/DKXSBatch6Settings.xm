//
//  DKXSBatch6Settings.xm
//  DYxs（第 6 批 staging，尚未并入 DYxs 源码）
//
//  第 6 批设置登记（%ctor + DKSettingsRegister + DKMakeSwitch，
//  与第 1、2、4 批同款写法）。全部默认关。
//  登记 7 项，全部在本批有读取方（见 REPORT.md 键表；
//  刻意不登记的键也在 REPORT.md 里列出原因，杜绝登记了没人读的死键）：
//  全屏协调 2 项、全局隐藏 5 项。
//  注意：DKXSEnableCommentBlur 属第 4 批，本批只读不登记；
//  DKXSEnableFullScreen 与 DYxs 自带“视频全屏”（DKKeyVideoFullscreen）
//  同属布局调整，两者不要同时开（见 REPORT.md 互斥警告）。
//
#import "DKSettings.h"

%ctor {
    DKSettingsRegister(@"DKXSEnableFullScreen", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSEnableFullScreen", @"全屏布局协调",
                            @"推荐页、详情页、纯净模式按播放页承载结构协调全屏、底栏与评论避让；进出评论区时播放器与文案跟随避让。注意：与 DYxs 自带“视频全屏”开关同属布局调整，两者不要同时开。");
    });
    DKSettingsRegister(@"DKXSHideBottomBg", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideBottomBg", @"隐藏底栏背景",
                            @"底栏背景透明；不开全屏时也可单独开。");
    });
    DKSettingsRegister(@"DKXSHideBack", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideBack", @"隐藏返回按钮",
                            @"隐藏视频页等处的返回按钮；用户主页返回按钮与横屏返回按钮除外。");
    });
    DKSettingsRegister(@"DKXSHideScancode", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideScancode", @"隐藏扫一扫与拍照搜同款",
                            @"隐藏无障碍标签为“扫一扫”“拍照搜同款”的按钮。");
    });
    DKSettingsRegister(@"DKXSHideRightLabel", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideRightLabel", @"隐藏右侧标签",
                            @"隐藏昵称旁“X人共创”“图集”“下一章”等右侧标签。");
    });
    DKSettingsRegister(@"DKXSHideChapterPoints", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideChapterPoints", @"隐藏章节要点",
                            @"隐藏“章节要点”标签。");
    });
    DKSettingsRegister(@"DKXSHideCommentDiscover", ^AWESettingItemModel *{
        return DKMakeSwitch(@"DKXSHideCommentDiscover", @"隐藏评论发现图标",
                            @"隐藏评论区搜索入口旁的发现图标。");
    });
}
