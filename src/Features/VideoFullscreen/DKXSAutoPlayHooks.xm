//
//  DKXSAutoPlayHooks.xm
//  DYxs（优先小批 staging，尚未并入 DYxs 源码）
//
//  移植来源：Wtrwx/DYYY 的 DYYY.xm %group AutoPlay（5 个 hook，原样移植，
//  仅改名）。上游在 %ctor 里还以 DYYYUserAgreementAccepted（用户协议流程）
//  为门，DYxs 没有这套流程，故本移植只以 DKXSEnableAutoPlay 开关为门，
//  开关关时整组不安装，与“装了但开关关”效果一致；其余逻辑与上游一致。
//  不 import 上游 AwemeHeaders 与 DouyinHeaders；Logos %hook 不需要类声明。
//  冲突核查：DYxs 里 3 个文件 hook AWEAwemeDetailTableViewController，
//  但无一 hook hasIphoneAutoPlaySwitch；其余 4 个类/方法在 DYxs 里均无 hook，
//  零同方法冲突。
//

#import <UIKit/UIKit.h>

#define DKXSGetBool(key) [[NSUserDefaults standardUserDefaults] boolForKey:key]

%group AutoPlay

%hook AWEAwemeDetailTableViewController

- (BOOL)hasIphoneAutoPlaySwitch {
    return YES;
}

%end

%hook AWEAwemeDetailContainerPlayControlConfig

- (BOOL)enableUserProfilePostAutoPlay {
    return YES;
}

%end

%hook AWEFeedIPhoneAutoPlayManager

- (BOOL)isAutoPlayOpen {
    return YES;
}

%end

%hook AWEFeedModuleService

- (BOOL)getFeedIphoneAutoPlayState {
    return YES;
}
%end

%hook AWEFeedIPhoneAutoPlayManager

- (BOOL)getFeedIphoneAutoPlayState {
    BOOL r = %orig;
    return YES;
}
%end

%end

%ctor {
    if (DKXSGetBool(@"DKXSEnableAutoPlay")) {
        %init(AutoPlay);
    }
}
