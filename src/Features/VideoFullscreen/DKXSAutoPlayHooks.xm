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
//  39.6.0 兜底（0.6.9.24）：39.5 头文件导出里“AutoPlay”出现 0 次——
//  AWEFeedIPhoneAutoPlayManager、AWEAwemeDetailContainerPlayControlConfig、
//  AWEFeedModuleService 三个类是 40.x 才有的，39.6.0 上原有 5 个 hook 是
//  静默空操作，功能装了等于没装。兜底（%group AutoPlayFallback）直接改
//  播放器控制器 AWEAwemePlayVideoViewController 的 isAutoPlay：详情页
//  （AWEAwemeDetailTableViewController）内的播放器一律置 YES。原有 5 个
//  hook 保留不动，在 40.x 上仍有效。
//  兜底冲突核查（0.6.9.24）：
//  - DKXSBatch5bPlayback.xm 已 hook 同类同方法 setIsAutoPlay: /
//    prepareForDisplay（常驻，无开关门控）。Logos 同方法双 hook 是串联，
//    Batch5b 只在 %orig 后应用默认倍速（默认倍速为 1.0 时直接返回），不改
//    开关语义；无论串联顺序如何，详情页内最终 isAutoPlay 均为 YES，
//    不互相顶掉。
//  - 其余 hook AWEAwemeDetailTableViewController 的文件（DKVideoDetailTable.xm、
//    DKVideoFeedTable.xm、DKChatVideoBottomBar.xm）只 hook 布局/高度/底栏方法，
//    不碰播放状态；兜底只读控制器层级（parent/presenting 链），不与它们冲突。
//  - DY778LivePreview.m 的 prepareForDisplay 是另一套挂载 hook，不在
//    AWEAwemePlayVideoViewController 上。
//

#import <UIKit/UIKit.h>

#define DKXSGetBool(key) [[NSUserDefaults standardUserDefaults] boolForKey:key]

// 最小接口声明：39.5 头文件里 AWEAwemePlayVideoViewController 只有极简声明
// （observeValueForKeyPath:/setVideoControllerPlaybackRate:，无 setIsAutoPlay: /
// isAutoPlay）；本文件不 import 上游头文件，按 PR #31 的教训在此补声明，
// 供兜底读写 isAutoPlay。调用前另有 respondsToSelector: 守卫，防止 39.6.0
// 上属性不存在时直接调用崩溃。
@interface AWEAwemePlayVideoViewController : UIViewController
- (void)setIsAutoPlay:(BOOL)isAutoPlay;
- (BOOL)isAutoPlay;
@end

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

%group AutoPlayFallback

// 该播放器是否处于详情页内：沿 parentViewController / presentingViewController
// 链向上找 AWEAwemeDetailTableViewController。类不存在时 NSClassFromString
// 返回 nil，isKindOfClass: 返回 NO，不会崩。
static BOOL DKXSAutoPlayInDetailPage(UIViewController *vc) {
    for (UIViewController *c = vc; c != nil; ) {
        if ([c isKindOfClass:NSClassFromString(@"AWEAwemeDetailTableViewController")]) {
            return YES;
        }
        UIViewController *next = c.parentViewController;
        if (!next) next = c.presentingViewController;
        if (next == c) break;
        c = next;
    }
    return NO;
}

%hook AWEAwemePlayVideoViewController

// 调用方传 NO 时，详情页内的播放器改为 YES 再 %orig；详情页外原样 %orig。
- (void)setIsAutoPlay:(BOOL)arg0 {
    if (!arg0 && DKXSAutoPlayInDetailPage(self)) {
        %orig(YES);
    } else {
        %orig;
    }
}

// 39.6.0 的详情页可能根本不调 setter、属性默认 NO：%orig 后再强制置 YES。
- (void)prepareForDisplay {
    %orig;
    if ([self respondsToSelector:@selector(isAutoPlay)] &&
        [self respondsToSelector:@selector(setIsAutoPlay:)] &&
        DKXSAutoPlayInDetailPage(self) && ![self isAutoPlay]) {
        [self setIsAutoPlay:YES];
    }
}

%end

%end

%ctor {
    if (DKXSGetBool(@"DKXSEnableAutoPlay")) {
        %init(AutoPlay);
        %init(AutoPlayFallback);
    }
}
