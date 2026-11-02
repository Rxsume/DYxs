//
//  DKXSBatch5cMisc.xm
//  DYxs 全量合并第 5 批剩余部分（5c）staging，未并入 DYxs 源码。
//  移植来源：Wtrwx/DYYY 的 DYYY.xm（青少年弹窗、直播 PCDN、作者声明），
//  符号一律 DYYY* -> DKXS*。DYxs 现有代码未 hook 本文件涉及的类，无撞点。
//
//  刻意不移植：DYYYNoUpdates（屏蔽检测更新）——上游唯一实现点在
//  DYYYLoginBypassHooks.xm 里（与登录绕过共用一个返回函数），属于排除项，
//  本批不登记该键；若主 agent 日后单独立项，可从该文件拆出纯更新屏蔽。
//
#import <UIKit/UIKit.h>

static BOOL DKXSMiscGetBool(NSString *key) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

// 去青少年弹窗：两处 Alert 的 show 直接返回 NO。
%hook AWETeenModeAlertView
- (BOOL)show {
    if (DKXSMiscGetBool(@"DKXSHideTeenMode")) {
        return NO;
    }
    return %orig;
}
%end

%hook AWETeenModeSimpleAlertView
- (BOOL)show {
    if (DKXSMiscGetBool(@"DKXSHideTeenMode")) {
        return NO;
    }
    return %orig;
}
%end

// 禁用直播 PCDN：三处启动入口直接跳过（保留上游 NSLog，便于真机确认）。
%hook HTSLiveStreamPcdnManager
+ (void)start {
    if (!DKXSMiscGetBool(@"DKXSDisableLivePCDN")) {
        %orig;
    } else {
        NSLog(@"[DKXS] HTSLiveStreamPcdnManager start blocked");
    }
}
+ (void)configAndStartLiveIO {
    if (!DKXSMiscGetBool(@"DKXSDisableLivePCDN")) {
        %orig;
    } else {
        NSLog(@"[DKXS] HTSLiveStreamPcdnManager configAndStartLiveIO blocked");
    }
}
%end

%hook IESLiveLaunchTaskPcdn
- (void)excute {
    if (DKXSMiscGetBool(@"DKXSDisableLivePCDN")) {
        NSLog(@"[DKXS] IESLiveLaunchTaskPcdn excute blocked");
        return;
    }
    %orig;
}
%end

// 屏蔽作者声明及风险提示：riskInfoModel 置空（上游同款，位于 AWEAwemeModel）。
%hook AWEAwemeModel
- (id)riskInfoModel {
    if (DKXSMiscGetBool(@"DKXSHideAntiAddictedNotice")) {
        return nil;
    }
    return %orig;
}
- (void)setRiskInfoModel:(id)model {
    if (DKXSMiscGetBool(@"DKXSHideAntiAddictedNotice")) {
        %orig(nil);
        return;
    }
    %orig;
}
%end
