//
//  DKXSBatch8Settings.xm
//  DYxs（第 8 批：Si-yi/DYads- 5e9a5c0 新模块移植）
//
//  第 8 批设置登记（%ctor + DKSettingsRegister + DKMakeSwitch，
//  与第 7 批同款写法）。全部默认关。
//  登记 5 项，全部在本批有读取方（DKXSChatEnhancements / DKXSChatEnhancementHooks.xm）：
//  语音自动转文字、消息左滑快速引用、屏蔽输入状态回报、禁用上传在线状态、阻止仅看一次销毁。
//  改名一律 DYYY -> DKXS（键与类名同步改名，见各模块文件头）。
//  注意：本批只登记聊天增强 5 键；DKXSSkipHotSpot 已在 DYxs 存在，不重复登记；
//  POI 卡片适配与好友分享提示避让无开关，分别跟随视频全屏与好友分享进推荐开关生效，故不登记。
//

#import "DKSettings.h"
#import "DKXSChatEnhancements.h"
#import "DKXSUtils.h"

%ctor {
    DKSettingsRegister(@"DKXSAutoTranslateAudio", ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(@"DKXSAutoTranslateAudio", @"语音自动转文字",
                                                 @"仅转换当前可见的收到语音，不自动播放或扫描历史。");
        DKSettingsOnChange(item, ^{
            [DKXSChatEnhancements installHooks];
            [DKXSUtils showToast:@"已保存，重新进入聊天页生效"];
        });
        return item;
    });
    DKSettingsRegister(@"DKXSSwipeToQuote", ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(@"DKXSSwipeToQuote", @"消息左滑快速引用",
                                                 @"左滑消息后松手，使用抖音原生引用回复。");
        DKSettingsOnChange(item, ^{
            [DKXSChatEnhancements installHooks];
            [DKXSUtils showToast:@"已保存，重新进入聊天页生效"];
        });
        return item;
    });
    DKSettingsRegister(@"DKXSDisableInputStateReport", ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(@"DKXSDisableInputStateReport", @"屏蔽输入状态回报",
                                                 @"停止上传正在输入提示，保留正常发送与已读同步。");
        DKSettingsOnChange(item, ^{ [DKXSChatEnhancements installHooks]; });
        return item;
    });
    DKSettingsRegister(@"DKXSDisableOnlineUpload", ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(@"DKXSDisableOnlineUpload", @"禁用上传在线状态",
                                                 @"停止主动在线上报；发送消息仍可能暴露在线状态。");
        DKSettingsOnChange(item, ^{ [DKXSChatEnhancements installHooks]; });
        return item;
    });
    DKSettingsRegister(@"DKXSPreventWatchOnceDestroy", ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(@"DKXSPreventWatchOnceDestroy", @"阻止仅看一次销毁",
                                                 @"试用：阻止本机结束标记，不保证服务端过期后仍可查看。");
        DKSettingsOnChange(item, ^{ [DKXSChatEnhancements installHooks]; });
        return item;
    });
}
