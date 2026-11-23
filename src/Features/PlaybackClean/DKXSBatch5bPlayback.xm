//
//  DKXSBatch5bPlayback.xm
//  DYxs 全量合并第 5 批剩余部分（5b）staging，未并入 DYxs 源码。
//  移植来源：Wtrwx/DYYY 的 DYYY.xm（后台播放、投屏 VPN、上下控制倍速、
//  默认倍速应用、直播间真实人数），符号一律 DYYY* -> DKXS*。
//
//  与上游的差异（主 agent 复核必读）：
//  1. 默认倍速不新登记：DYxs 第 2 批已有 DKXSDefaultSpeed 值键（float 存法，
//     上游是 "1.0x" 字符串存法），本文件只在播放器 prepareForDisplay /
//     setIsAutoPlay 时把该 float 值应用到播放器；不要把 DKXSDefaultSpeed
//     登记成 DKMakeChoice，否则会破坏第 2 批倍速按钮的 float 读取。
//  2. 长按倍速值同样复用第 2 批已有的 DKXSLongPressSpeed float 键，不登记。
//  3. 上下控制倍速只移植手势调节部分：手势结束时恢复默认倍速值；上游的
//     changeSpeed: 改写（把 2.0 映射到长按倍速、锁定倍速清理）未搬，因为
//     第 2 批倍速按钮自有速度状态机，两套改写叠加会互相顶掉。
//  4. 本文件不 hook AWEPlayInteractionSpeedController 的 changeSpeed:，
//     手势调节直接调原生 changeSpeed: 生效。
//  5. huami DYYY 3.0 (4658034) 修复移植（2026-11-23）：
//     a. longPressFastSpeedValue 手势期间返回实时档位（原只返回设定值，
//        上下滑调档会被压回）；手势状态变量为此提到文件作用域。
//     b. UILabel.setText: 把倍速文案里的数字按正则替换为实时档位
//        （上游只替换 "2"，设定 1.5x/3x 时文案仍显示旧数字）；仅在
//        长按倍速开关开时改写。DPlayer 的 AWEDSpeed* 容器族是 41.x
//        新架构，40.8.0 头文件里没有，不搬。
//
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

// 最小接口声明：以下被 hook 的类在本文件内读写 UIView/NSObject 成员（hidden、alpha、superview、subviews、tag、window 等）或调用同文件 %new 方法，
// 原先只有 Logos 前置声明，编译器找不到这些成员；基类按视图身份声明为 UIView（模型类为 NSObject），不 import DouyinHeaders。
@interface AWEPlayInteractionSpeedController : UIView
@end

static BOOL DKXSBatch5bGetBool(NSString *key) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

static float DKXSBatch5bDefaultSpeedValue(void) {
    double v = [[NSUserDefaults standardUserDefaults] doubleForKey:@"DKXSDefaultSpeed"];
    if (!(v > 0)) return 1.0f;
    return (float)v;
}

static float DKXSBatch5bLongPressSpeedValue(void) {
    double v = [[NSUserDefaults standardUserDefaults] doubleForKey:@"DKXSLongPressSpeed"];
    if (!(v > 0)) return 2.0f;
    return (float)v;
}

// 对播放器控制器应用默认倍速：只在默认倍速被改成非 1.0 时生效，
// 与上游 DYYYShouldHandleSpeedFeatures 的“按钮开着也应用”分支不同，
// 避免在用户没改默认倍速时干扰第 2 批倍速按钮自己的恢复逻辑。
static void DKXSBatch5bApplyDefaultSpeed(id playerVC) {
    if (!playerVC) return;
    float speed = DKXSBatch5bDefaultSpeedValue();
    if (fabsf(speed - 1.0f) < 0.001f) return;
    if (![playerVC respondsToSelector:@selector(setVideoControllerPlaybackRate:)]) return;
    ((void (*)(id, SEL, double))objc_msgSend)(playerVC, @selector(setVideoControllerPlaybackRate:), (double)speed);
}

// 后台播放：上游把“受限视频”的 listen 状态 1 改成 2，使其可在后台继续播放。
%hook AWEAwemeStatusModel
- (void)setListenVideoStatus:(NSInteger)status {
    if (status == 1 && DKXSBatch5bGetBool(@"DKXSEnableBackgroundListen")) {
        status = 2;
    }
    %orig(status);
}
%end

// 忽略投屏 VPN 检测：四处检测点全部返回 NO / 写入 NO，与上游一致。
%hook BDByteCastUtils
+ (BOOL)netVPNStatus {
    if (DKXSBatch5bGetBool(@"DKXSDisableCastVPNCheck")) return NO;
    return %orig;
}
%end

%hook BDByteCastNetUtilities
- (BOOL)getVPNStatus {
    if (DKXSBatch5bGetBool(@"DKXSDisableCastVPNCheck")) return NO;
    return %orig;
}
%end

%hook BDByteCastMonitorManager
- (BOOL)netVPNStatus {
    if (DKXSBatch5bGetBool(@"DKXSDisableCastVPNCheck")) return NO;
    return %orig;
}
- (void)setNetVPNStatus:(BOOL)netVPNStatus {
    if (DKXSBatch5bGetBool(@"DKXSDisableCastVPNCheck")) {
        %orig(NO);
        return;
    }
    %orig(netVPNStatus);
}
%end

%hook BDByteCastEnvInfo
- (BOOL)isVPNActive {
    if (DKXSBatch5bGetBool(@"DKXSDisableCastVPNCheck")) return NO;
    return %orig;
}
- (void)setIsVPNActive:(BOOL)isVPNActive {
    if (DKXSBatch5bGetBool(@"DKXSDisableCastVPNCheck")) {
        %orig(NO);
        return;
    }
    %orig(isVPNActive);
}
%end

%hook BDByteScreenCastContext
- (BOOL)isVPNActive {
    if (DKXSBatch5bGetBool(@"DKXSDisableCastVPNCheck")) return NO;
    return %orig;
}
- (void)setIsVPNActive:(BOOL)isVPNActive {
    if (DKXSBatch5bGetBool(@"DKXSDisableCastVPNCheck")) {
        %orig(NO);
        return;
    }
    %orig(isVPNActive);
}
%end

// 上下控制倍速：长按时上下滑动以 0.25 步进调倍速（0.5–3.0），松手恢复默认倍速。
// 注意：上游键名是 DYYYEnableLongPressSpeedGesture，DKXS 版键名见本文件
// DKXSEnableLongPressSpeedGesture；不要与第 2 批的长按倍速值键混淆。
// 手势状态放文件作用域，供 longPressFastSpeedValue 与倍速文案共用
// （huami DYYY 3.0 修复：长按期间抖音持续读 longPressFastSpeedValue，
// 必须返回实时档位，否则会被设定值压回）。
static CGFloat dkxsInitialTouchY = 0;
static BOOL dkxsGestureActive = NO;
static CGFloat dkxsCurrentSpeed = 0;

static CGFloat DKXSBatch5bLongPressDisplaySpeed(void) {
    if (dkxsGestureActive && dkxsCurrentSpeed > 0) {
        return dkxsCurrentSpeed;
    }
    return DKXSBatch5bLongPressSpeedValue();
}

%hook AWEPlayInteractionSpeedController

- (CGFloat)longPressFastSpeedValue {
    return DKXSBatch5bLongPressDisplaySpeed();
}

- (void)handleLongPressFastSpeed:(UILongPressGestureRecognizer *)gesture {
    BOOL isBeginning = gesture.state == UIGestureRecognizerStateBegan;
    BOOL isEnding = gesture.state == UIGestureRecognizerStateEnded ||
                    gesture.state == UIGestureRecognizerStateCancelled ||
                    gesture.state == UIGestureRecognizerStateFailed;
    if (isBeginning) {
        dkxsGestureActive = NO;
        dkxsCurrentSpeed = 0;
        dkxsInitialTouchY = 0;
    } else if (isEnding) {
        dkxsGestureActive = NO;
        dkxsCurrentSpeed = 0;
        dkxsInitialTouchY = 0;
    }

    %orig;

    if (!DKXSBatch5bGetBool(@"DKXSEnableLongPressSpeedGesture")) {
        return;
    }
    if (isBeginning) {
        CGPoint location = [gesture locationInView:gesture.view];
        dkxsInitialTouchY = location.y;
        dkxsGestureActive = YES;
        dkxsCurrentSpeed = DKXSBatch5bLongPressSpeedValue();
    } else if (gesture.state == UIGestureRecognizerStateChanged && dkxsGestureActive) {
        CGPoint location = [gesture locationInView:gesture.view];
        CGFloat deltaY = location.y - dkxsInitialTouchY;
        if (fabs(deltaY) > 10.0) {
            CGFloat step = (deltaY > 0) ? 0.25 : -0.25;
            CGFloat newSpeed = MAX(0.5, MIN(3.0, dkxsCurrentSpeed + step));
            if (newSpeed != dkxsCurrentSpeed) {
                dkxsCurrentSpeed = newSpeed;
                dkxsInitialTouchY = location.y;
                if ([self respondsToSelector:@selector(changeSpeed:)]) {
                    ((void (*)(id, SEL, double))objc_msgSend)(self, @selector(changeSpeed:), (double)newSpeed);
                }
            }
        }
    } else if (isEnding) {
        float def = DKXSBatch5bDefaultSpeedValue();
        if ([self respondsToSelector:@selector(changeSpeed:)]) {
            ((void (*)(id, SEL, double))objc_msgSend)(self, @selector(changeSpeed:), (double)def);
        }
    }
}
%end

// 长按倍速文案：官方倍速浮层（AFDFastSpeedView）里的数字按实时档位改写。
// huami DYYY 3.0 (4658034) 原只把 "2" 换成设定值；改为正则替换任意数字，
// 否则设定 1.5x/3x 时文案仍显示旧数字。只在长按倍速开关开时改写，
// 其余 UILabel 原样放行（DKInnerNotificationGlass.xm 另有一处 setText:
// hook，两处经 %orig 串联，各改各的，不冲突）。
%hook UILabel

- (void)setText:(NSString *)text {
    UIView *superview = self.superview;
    if (superview && [superview isKindOfClass:%c(AFDFastSpeedView)] && text &&
        DKXSBatch5bGetBool(@"DKXSEnableLongPressSpeedGesture")) {
        CGFloat displaySpeed = DKXSBatch5bLongPressDisplaySpeed();
        NSString *speedString = [NSString stringWithFormat:@"%.2f", displaySpeed];
        if ([speedString hasSuffix:@".00"]) {
            speedString = [speedString substringToIndex:speedString.length - 3];
        } else if ([speedString hasSuffix:@"0"]) {
            speedString = [speedString substringToIndex:speedString.length - 1];
        }
        NSRegularExpression *dkxsSpeedRe = [NSRegularExpression regularExpressionWithPattern:@"[0-9]+(\\.[0-9]+)?" options:0 error:nil];
        NSTextCheckingResult *dkxsSpeedMatch = [dkxsSpeedRe firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
        if (dkxsSpeedMatch) {
            text = [text stringByReplacingCharactersInRange:dkxsSpeedMatch.range withString:speedString];
        }
    }
    %orig(text);
}

%end

// 默认倍速应用：新视频准备播放 / 自动播放切换时应用默认倍速值。
// DYxs 现有代码未 hook 这两个类的这两个方法，无撞点。
%hook AWEAwemePlayVideoViewController
- (void)setIsAutoPlay:(BOOL)arg0 {
    %orig(arg0);
    DKXSBatch5bApplyDefaultSpeed(self);
}
- (void)prepareForDisplay {
    %orig;
    DKXSBatch5bApplyDefaultSpeed(self);
}
%end

%hook AWEDPlayerFeedPlayerViewController
- (void)setIsAutoPlay:(BOOL)arg0 {
    %orig(arg0);
    DKXSBatch5bApplyDefaultSpeed(self);
}
- (void)prepareForDisplay {
    %orig;
    DKXSBatch5bApplyDefaultSpeed(self);
}
%end

// 直播间真实人数：把竖/横向人数都换成未缩写的真实值。
%hook IESLiveUserSeqlistFragment
- (void)refreshVerticalUserCount:(id)arg1 horizontalUserCount:(id)arg2 trueValue:(NSInteger)trueValue {
    if (trueValue > 0 && DKXSBatch5bGetBool(@"DKXSEnableLiveRealCount")) {
        NSString *realStr = [NSString stringWithFormat:@"%ld", (long)trueValue];
        %orig(realStr, realStr, trueValue);
    } else {
        %orig;
    }
}
%end
