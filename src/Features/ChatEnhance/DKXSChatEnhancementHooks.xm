// 移植自 Si-yi/DYads- 5e9a5c0（DYYYChatEnhancementHooks.xm）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样。
// 最小接口声明（只声明本文件 hook 到的类与方法，不 import 上游 AwemeHeaders / DouyinHeaders）。
// 各组只在对应开关打开且原生方法签名核对通过后才安装；开关默认全部关闭。
#import "DKXSChatEnhancements.h"
#import "DKXSChatEnhancementPolicy.h"

@interface AWEIMInputStateManager : NSObject
- (void)reportInputStateWithText:(id)text;
@end
@interface AWEIMActiveUserUploader : NSObject
- (BOOL)checkEnableServerUploadActiveStatus;
- (void)updateUserActiveStatusWithEntrance:(id)entrance context:(id)context;
- (void)p_updateUserActiveWithContext:(id)context;
@end
@interface AWEIMReusableCommonCell : UITableViewCell
@end
@interface AWEIMMessageListViewController : UIViewController
@end
@interface AWEIMWatchOnceImageMessage : NSObject
- (BOOL)watchEnd;
@end
@interface AWEIMWatchOnceVideoMessage : NSObject
- (BOOL)watchEnd;
@end
@interface AWEIMWatchOnceMessageManager : NSObject
- (BOOL)isReadingWatchOnceMessage:(id)message;
- (long long)watchOnceMediaLoopTimes;
@end

%group DKXSChatTypingHooks
%hook AWEIMInputStateManager
- (void)reportInputStateWithText:(id)text {
    if ([DKXSChatEnhancements enabled:@"DKXSDisableInputStateReport"]) return;
    %orig(text);
}
%end
%end
%group DKXSChatOnlineGateHooks
%hook AWEIMActiveUserUploader
- (BOOL)checkEnableServerUploadActiveStatus {
    if ([DKXSChatEnhancements enabled:@"DKXSDisableOnlineUpload"]) return NO;
    return %orig;
}
%end
%end
%group DKXSChatOnlineUpdateHooks
%hook AWEIMActiveUserUploader
- (void)updateUserActiveStatusWithEntrance:(id)entrance context:(id)context {
    if ([DKXSChatEnhancements enabled:@"DKXSDisableOnlineUpload"]) return;
    %orig(entrance, context);
}
%end
%end
%group DKXSChatOnlinePrivateHooks
%hook AWEIMActiveUserUploader
- (void)p_updateUserActiveWithContext:(id)context {
    if ([DKXSChatEnhancements enabled:@"DKXSDisableOnlineUpload"]) return;
    %orig(context);
}
%end
%end
%group DKXSChatCellEnhancementHooks
%hook AWEIMReusableCommonCell
- (void)didMoveToWindow {
    %orig;
    [DKXSChatEnhancements cellChanged:self];
}
%end
%end
%group DKXSChatContextEnhancementHooks
%hook AWEIMReusableCommonCell
- (void)setCurrentContext:(id)context {
    %orig(context);
    [DKXSChatEnhancements cellChanged:self];
}
%end
%end
%group DKXSChatAppearanceEnhancementHooks
%hook AWEIMMessageListViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig(animated);
    [DKXSChatEnhancements controllerAppeared:self];
}
%end
%end

// 仅原生阅后即焚的本机展示标记；不拦截普通消息 markAsRead 或任何完成回调。
%group DKXSWatchOnceImageFlagHooks
%hook AWEIMWatchOnceImageMessage
- (BOOL)watchEnd {
    if ([DKXSChatEnhancements enabled:@"DKXSPreventWatchOnceDestroy"]) return NO;
    return %orig;
}
%end
%end
%group DKXSWatchOnceVideoFlagHooks
%hook AWEIMWatchOnceVideoMessage
- (BOOL)watchEnd {
    if ([DKXSChatEnhancements enabled:@"DKXSPreventWatchOnceDestroy"]) return NO;
    return %orig;
}
%end
%end
%group DKXSWatchOnceReadingHooks
%hook AWEIMWatchOnceMessageManager
- (BOOL)isReadingWatchOnceMessage:(id)message {
    if ([DKXSChatEnhancements enabled:@"DKXSPreventWatchOnceDestroy"]) return YES;
    return %orig(message);
}
%end
%end
%group DKXSWatchOnceLoopHooks
%hook AWEIMWatchOnceMessageManager
- (long long)watchOnceMediaLoopTimes {
    if ([DKXSChatEnhancements enabled:@"DKXSPreventWatchOnceDestroy"]) return 1000000;
    return %orig;
}
%end
%end

@implementation DKXSChatEnhancements (Hooks)
+ (void)installHooks {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self installHooks]; }); return; }
    static BOOL typing, onlineGate, onlineUpdate, onlinePrivate, cells, context, appearance, image, video, reading, loops;
    Class typingClass = NSClassFromString(@"AWEIMInputStateManager");
    BOOL typingReady = [DKXSChatEnhancementPolicy class:typingClass selector:@selector(reportInputStateWithText:) result:'v' arguments:@"@"];
    [self recordCapability:@"typingReport" available:typingReady];
    if (!typing && [self enabled:@"DKXSDisableInputStateReport"] && typingReady) { %init(DKXSChatTypingHooks); typing = YES; }
    Class uploader = NSClassFromString(@"AWEIMActiveUserUploader");
    BOOL gateReady = [DKXSChatEnhancementPolicy class:uploader selector:@selector(checkEnableServerUploadActiveStatus) result:'B' arguments:@""];
    BOOL updateReady = [DKXSChatEnhancementPolicy class:uploader selector:@selector(updateUserActiveStatusWithEntrance:context:) result:'v' arguments:@"@@"];
    BOOL privateReady = [DKXSChatEnhancementPolicy class:uploader selector:@selector(p_updateUserActiveWithContext:) result:'v' arguments:@"@"];
    [self recordCapability:@"onlineUpload" available:gateReady && updateReady && privateReady];
    if ([self enabled:@"DKXSDisableOnlineUpload"]) {
        if (!onlineGate && gateReady) { %init(DKXSChatOnlineGateHooks); onlineGate = YES; }
        if (!onlineUpdate && updateReady) { %init(DKXSChatOnlineUpdateHooks); onlineUpdate = YES; }
        if (!onlinePrivate && privateReady) { %init(DKXSChatOnlinePrivateHooks); onlinePrivate = YES; }
    }
    Class cellClass = NSClassFromString(@"AWEIMReusableCommonCell");
    BOOL cellReady = [cellClass isSubclassOfClass:UIView.class] && [DKXSChatEnhancementPolicy class:cellClass selector:@selector(didMoveToWindow) result:'v' arguments:@""];
    BOOL contextReady = [DKXSChatEnhancementPolicy class:cellClass selector:@selector(setCurrentContext:) result:'v' arguments:@"@"];
    BOOL appearanceReady = [DKXSChatEnhancementPolicy class:NSClassFromString(@"AWEIMMessageListViewController") selector:@selector(viewDidAppear:) result:'v' arguments:@"B"];
    [self recordCapability:@"chatCellEvents" available:cellReady && contextReady && appearanceReady];
    if ([self enabled:@"DKXSSwipeToQuote"] || [self enabled:@"DKXSAutoTranslateAudio"]) {
        if (!cells && cellReady) { %init(DKXSChatCellEnhancementHooks); cells = YES; }
        if (!context && contextReady) { %init(DKXSChatContextEnhancementHooks); context = YES; }
        if (!appearance && appearanceReady) { %init(DKXSChatAppearanceEnhancementHooks); appearance = YES; }
    }
    Class imageClass = NSClassFromString(@"AWEIMWatchOnceImageMessage"), videoClass = NSClassFromString(@"AWEIMWatchOnceVideoMessage");
    Class watch = NSClassFromString(@"AWEIMWatchOnceMessageManager");
    BOOL imageReady = [DKXSChatEnhancementPolicy class:imageClass selector:@selector(watchEnd) result:'B' arguments:@""];
    BOOL videoReady = [DKXSChatEnhancementPolicy class:videoClass selector:@selector(watchEnd) result:'B' arguments:@""];
    BOOL readingReady = [DKXSChatEnhancementPolicy class:watch selector:@selector(isReadingWatchOnceMessage:) result:'B' arguments:@"@"];
    BOOL loopReady = [DKXSChatEnhancementPolicy class:watch selector:@selector(watchOnceMediaLoopTimes) result:'q' arguments:@""];
    [self recordCapability:@"watchOnceLocalFlags" available:imageReady && videoReady && readingReady && loopReady];
    if ([self enabled:@"DKXSPreventWatchOnceDestroy"]) {
        if (!image && imageReady) { %init(DKXSWatchOnceImageFlagHooks); image = YES; }
        if (!video && videoReady) { %init(DKXSWatchOnceVideoFlagHooks); video = YES; }
        if (!reading && readingReady) { %init(DKXSWatchOnceReadingHooks); reading = YES; }
        if (!loops && loopReady) { %init(DKXSWatchOnceLoopHooks); loops = YES; }
    }
    [self recordCapability:@"typingHookInstalled" available:typing];
    [self recordCapability:@"onlineHooksInstalled" available:onlineGate && onlineUpdate && onlinePrivate];
    [self recordCapability:@"chatCellHooksInstalled" available:cells && context && appearance];
    [self recordCapability:@"watchOnceHooksInstalled" available:image && video && reading && loops];
}
@end
%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{ [DKXSChatEnhancements installHooks]; });
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { [DKXSChatEnhancements installHooks]; }];
}
