#import "DY778LiveTools.h"
#import "DY778Core.h"
#import "DY778LiveInfo.h"
#import "DY778LiveGuest.h"
#import "DY778LiveToolsPolicy.h"
#import <QuartzCore/QuartzCore.h>

// DY778 1.0-8 模块 1 移植：直播间工具（隐身进直播间、定时弹幕、礼物风控）。
// 规格：~/workspace/plugin-merge/DY778/spec-module1-livetools-guest.md §1；
// hook 表以 /tmp/dy778-108/livetools-hooks.txt（36 个 hook，反汇编实锤）为准。
// hook 常驻装载，行为全部由开关在调用时控制，默认全部关闭：
//   liveTools.stealth    隐身进直播间（isLogin 返回 NO；隐身期间拦截弹幕/礼物）
//   liveTools.scheduler  定时弹幕（按 liveTools.interval 发送 liveTools.selectedText）
//   liveTools.risk       隐身时拦截礼物（须与 stealth 同开才生效）
//   liveTools.interval   弹幕间隔（秒，5–300，默认 30）
//   liveTools.selectedText 定时弹幕文本（留空不发送）
//   liveTools.ttwid      游客 TTWID（注入进房/网络请求参数）
// TODO（需真机验证）：
//   - 直播登录拦截（loginWithUserInfo:*）：隐身时跳过是否影响进房流程。
//   - 定时弹幕上下文文本属性：当前按 content/text 依次尝试 KVC 写入，
//     若当前抖音版本的上下文不用这两个键，定时发送会静默跳过本轮。

static NSString *const DY778ToolsChannel = @"liveTools";

static const char *DY778ToolsType(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type ?: "";
}
static BOOL DY778ToolsMatches(const char *result, const char *arguments, NSMethodSignature *signature) {
    if (!signature) return NO;
    if (!strchr(result, *DY778ToolsType(signature.methodReturnType))) return NO;
    if (signature.numberOfArguments != strlen(arguments) + 2) return NO;
    for (NSUInteger i = 0; i < strlen(arguments); i++) {
        char actual = *DY778ToolsType([signature getArgumentTypeAtIndex:i + 2]), expected = arguments[i];
        if (expected == 'B' ? !(actual == 'B' || actual == 'c') :
            expected == 'q' ? !(actual == 'q' || actual == 'Q') :
            expected == '^' ? !(actual == '^' || actual == '@') : actual != expected) return NO;
    }
    return YES;
}
static BOOL DY778ToolsSignature(Class cls, SEL selector, const char *result, const char *arguments) {
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!method) return NO;
    return DY778ToolsMatches(result, arguments, [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)]);
}
static void DY778ToolsInstall(NSString *className, NSString *selector, const char *result, const char *arguments, IMP replacement, IMP *original) {
    if (*original) return;
    Class cls = NSClassFromString(className); SEL sel = NSSelectorFromString(selector);
    BOOL installed = DY778ToolsSignature(cls, sel, result, arguments) && DY778Hook(cls, sel, replacement, original);
    DY778RecordHook([NSString stringWithFormat:@"直播间工具 / %@.%@", className, selector], installed);
}
static void DY778ToolsMain(dispatch_block_t block) {
    if (NSThread.isMainThread) block(); else dispatch_async(dispatch_get_main_queue(), block);
}
// 1.1-2 身份范围：房内用进房绑定身份，房外回退开关（见 DY778LiveGuest.h）。
static BOOL DY778ToolsStealth(void) { return DY778LiveIdentityGuestActive(); }
static BOOL DY778ToolsSchedulerOn(void) { return DY778Bool(@"liveTools.scheduler"); }
static BOOL DY778ToolsRisk(void) { return DY778Bool(@"liveTools.risk"); }
static double DY778ToolsInterval(void) { return DY778LiveToolsInterval(DY778Number(@"liveTools.interval")); }
static NSString *DY778ToolsGuestTTWID(void) {
    NSString *ttwid = [DY778String(@"liveTools.ttwid") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return DY778LiveToolsValidTTWID(ttwid.UTF8String) ? ttwid : nil;
}
static NSString *DY778ToolsSelectedText(void) {
    NSString *text = [DY778String(@"liveTools.selectedText") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *singleLine = [[text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] componentsJoinedByString:@" "];
    if (singleLine.length > DY778LiveToolsMaximumTextLength) singleLine = [singleLine substringToIndex:DY778LiveToolsMaximumTextLength];
    return DY778LiveToolsValidTextLength(singleLine.length) ? singleLine : nil;
}
static NSString *DY778ToolsRoomID(id object) {
    NSString *identifier = DY778LiveRoomIdentifier(object);
    if (identifier.length) return identifier;
    id model = DY778Read(object, @"roomModel");
    if (model && model != object) return DY778LiveRoomIdentifier(model);
    return nil;
}
static void DY778ToolsNoteEnter(id requestModel) {
    NSString *roomID = DY778ToolsRoomID(requestModel);
    if (roomID.length) DY778LiveToolsRoomDidEnter(roomID);
}

@interface DY778ToolsScheduler : NSObject
@property(nonatomic, weak) id fragment;
@property(nonatomic, weak) id store;
@property(nonatomic, strong) id commentContext;
@property(nonatomic, copy) NSString *roomID;
@property(nonatomic, copy) NSString *accountID;
@property(nonatomic, strong) NSTimer *timer;
+ (instancetype)shared;
- (void)captureFragment:(id)fragment context:(id)context;
- (void)captureStore:(id)store context:(id)context;
- (void)enterRoom:(NSString *)roomID;
- (void)exitRoom;
- (void)maybeStart;
- (void)stop;
- (void)tick;
@end

static IMP DY778ToolsOriginalSendComment;

@implementation DY778ToolsScheduler
+ (instancetype)shared {
    static DY778ToolsScheduler *value; static dispatch_once_t once;
    dispatch_once(&once, ^{ value = [self new]; }); return value;
}
- (void)captureFragment:(id)fragment context:(id)context {
    if (!fragment) return;
    DY778ToolsMain(^{
        self.fragment = fragment;
        if (context) self.commentContext = context;
        NSString *room = DY778ToolsRoomID(DY778Read(fragment, @"room")) ?: DY778ToolsRoomID(DY778Read(fragment, @"roomModel")) ?: DY778ToolsRoomID(fragment);
        if (room.length) self.roomID = room;
        self.accountID = DY778CurrentAccountID() ?: @"";
        [self maybeStart];
    });
}
- (void)captureStore:(id)store context:(id)context {
    if (!store) return;
    DY778ToolsMain(^{
        self.store = store;
        if (context) self.commentContext = context;
        NSString *room = DY778ToolsRoomID(DY778Read(store, @"roomModel")) ?: DY778ToolsRoomID(store);
        if (room.length) self.roomID = room;
        self.accountID = DY778CurrentAccountID() ?: @"";
        [self maybeStart];
    });
}
- (void)enterRoom:(NSString *)roomID {
    if (!roomID.length) return;
    if (self.roomID.length && ![self.roomID isEqualToString:roomID]) [self stop];
    self.roomID = roomID;
    self.accountID = DY778CurrentAccountID() ?: @"";
    [self maybeStart];
}
- (void)exitRoom {
    [self stop];
    self.roomID = nil; self.fragment = nil; self.store = nil; self.commentContext = nil;
}
- (void)maybeStart {
    if (self.timer || !DY778ToolsSchedulerOn()) return;
    if (!self.roomID.length || !DY778ToolsSelectedText().length || (!self.fragment && !self.store)) return;
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer timerWithTimeInterval:DY778ToolsInterval() repeats:YES block:^(__unused NSTimer *timer) { [weakSelf tick]; }];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}
- (void)stop {
    [self.timer invalidate]; self.timer = nil;
}
- (void)tick {
    if (!DY778ToolsSchedulerOn()) { [self stop]; return; }
    NSString *text = DY778ToolsSelectedText();
    id fragment = self.fragment, context = self.commentContext;
    if (!text.length || !fragment || !self.roomID.length || !DY778ToolsOriginalSendComment) return;
    NSString *current = DY778ToolsRoomID(DY778Read(fragment, @"room")) ?: DY778ToolsRoomID(DY778Read(fragment, @"roomModel")) ?: DY778ToolsRoomID(fragment);
    if (current.length && ![current isEqualToString:self.roomID]) { [self stop]; return; }
    if (![self.accountID isEqualToString:DY778CurrentAccountID() ?: @""]) { [self stop]; return; }
    if (!context) {
        Class contextClass = NSClassFromString(@"IESLiveCommentContext");
        context = contextClass ? [[contextClass alloc] init] : nil;
        if (context) {
            DY778Write(context, @"roomID", self.roomID);
            self.commentContext = context;
        }
    }
    if (!context) return;
    BOOL written = DY778Write(context, @"content", text);
    if (!written) written = DY778Write(context, @"text", text);
    if (!written) return;
    @try {
        ((void (*)(id, SEL, id, id, id))DY778ToolsOriginalSendComment)(fragment, @selector(sendComment:commentContext:completion:), nil, context, ^(__unused id response, __unused id error) {});
    } @catch (__unused NSException *exception) {
    }
}
@end

void DY778LiveToolsRoomDidEnter(NSString *roomID) {
    if (!roomID.length) return;
    DY778LiveIdentityRoomEntered(roomID);
    DY778ToolsMain(^{ [[DY778ToolsScheduler shared] enterRoom:roomID]; });
}
void DY778LiveToolsRoomDidExit(void) {
    DY778LiveIdentityRoomExited();
    DY778ToolsMain(^{ [[DY778ToolsScheduler shared] exitRoom]; });
}

// ---------- 隐身：进房请求模型 ----------
static IMP DY778ToolsOriginalRequestIsLogin, DY778ToolsOriginalBuildParams, DY778ToolsOriginalBuildPreloadParams;
static BOOL DY778ToolsRequestIsLogin(id model, SEL cmd) {
    if (DY778ToolsStealth()) return NO;
    return ((BOOL (*)(id, SEL))DY778ToolsOriginalRequestIsLogin)(model, cmd);
}
static id DY778ToolsBuildParams(id model, SEL cmd) {
    id params = ((id (*)(id, SEL))DY778ToolsOriginalBuildParams)(model, cmd);
    if (!DY778ToolsStealth() || ![params isKindOfClass:NSDictionary.class]) return params;
    NSMutableDictionary *mutable = [params mutableCopy];
    NSString *ttwid = DY778ToolsGuestTTWID();
    if (ttwid.length) mutable[@"ttwid"] = ttwid;
    return mutable;
}
static id DY778ToolsBuildPreloadParams(id model, SEL cmd) {
    id params = ((id (*)(id, SEL))DY778ToolsOriginalBuildPreloadParams)(model, cmd);
    if (!DY778ToolsStealth() || ![params isKindOfClass:NSDictionary.class]) return params;
    NSMutableDictionary *mutable = [params mutableCopy];
    NSString *ttwid = DY778ToolsGuestTTWID();
    if (ttwid.length) mutable[@"ttwid"] = ttwid;
    return mutable;
}

// ---------- 进房入口：记录房间后放行 ----------
static IMP DY778ToolsOriginalEnterRoomAPI, DY778ToolsOriginalEnterRoomService;
static IMP DY778ToolsOriginalEnterPreloadAPI, DY778ToolsOriginalEnterPreloadService;
static IMP DY778ToolsOriginalEnterRoomLogin, DY778ToolsOriginalEnterRoomLowLevel;
#define DY778_TOOLS_ENTER_ROOM(N, ORIGINAL) \
static void DY778ToolsEnterRoom##N(id target, SEL cmd, id requestModel, id finish) { \
    DY778ToolsNoteEnter(requestModel); \
    ((void (*)(id, SEL, id, id))ORIGINAL)(target, cmd, requestModel, finish); }
DY778_TOOLS_ENTER_ROOM(API, DY778ToolsOriginalEnterRoomAPI)
DY778_TOOLS_ENTER_ROOM(Service, DY778ToolsOriginalEnterRoomService)
DY778_TOOLS_ENTER_ROOM(PreloadAPI, DY778ToolsOriginalEnterPreloadAPI)
DY778_TOOLS_ENTER_ROOM(PreloadService, DY778ToolsOriginalEnterPreloadService)
#undef DY778_TOOLS_ENTER_ROOM
static void DY778ToolsEnterRoomLogin(id api, SEL cmd, BOOL login, id roomModel, id sourcePage, id finish) {
    DY778ToolsNoteEnter(roomModel);
    ((void (*)(id, SEL, BOOL, id, id, id))DY778ToolsOriginalEnterRoomLogin)(api, cmd, login, roomModel, sourcePage, finish);
}
static void DY778ToolsEnterRoomLowLevel(id service, SEL cmd, id requestModel, BOOL preload, id finish) {
    DY778ToolsNoteEnter(requestModel);
    ((void (*)(id, SEL, id, BOOL, id))DY778ToolsOriginalEnterRoomLowLevel)(service, cmd, requestModel, preload, finish);
}

// ---------- 定时弹幕：发送拦截 + 上下文捕获 ----------
static IMP DY778ToolsOriginalSendBarrage, DY778ToolsOriginalSendBarrageTrack, DY778ToolsOriginalSendCommentSource;
static IMP DY778ToolsOriginalSendCommentStore, DY778ToolsOriginalSendBarrageStore, DY778ToolsOriginalBindService;
static BOOL DY778ToolsSendAllowed(void) {
    if (DY778ToolsStealth()) {
        DY778ShowToast(DY778ToolsChannel, @"隐身模式下暂不发送弹幕", NO, NO);
        return NO;
    }
    return YES;
}
static void DY778ToolsSendComment(id fragment, SEL cmd, id comment, id context, id completion) {
    [[DY778ToolsScheduler shared] captureFragment:fragment context:context];
    if (!DY778ToolsSendAllowed()) return;
    ((void (*)(id, SEL, id, id, id))DY778ToolsOriginalSendComment)(fragment, cmd, comment, context, completion);
}
static void DY778ToolsSendBarrage(id fragment, SEL cmd, id comment, id context, id completion) {
    [[DY778ToolsScheduler shared] captureFragment:fragment context:context];
    if (!DY778ToolsSendAllowed()) return;
    ((void (*)(id, SEL, id, id, id))DY778ToolsOriginalSendBarrage)(fragment, cmd, comment, context, completion);
}
static void DY778ToolsSendBarrageTrack(id fragment, SEL cmd, id barrage, id trackParams, id completion) {
    [[DY778ToolsScheduler shared] captureFragment:fragment context:nil];
    if (!DY778ToolsSendAllowed()) return;
    ((void (*)(id, SEL, id, id, id))DY778ToolsOriginalSendBarrageTrack)(fragment, cmd, barrage, trackParams, completion);
}
static void DY778ToolsSendCommentSource(id fragment, SEL cmd, id comment, long long enterSource, id requestSource, id trackParams, id completion) {
    [[DY778ToolsScheduler shared] captureFragment:fragment context:nil];
    if (!DY778ToolsSendAllowed()) return;
    ((void (*)(id, SEL, id, long long, id, id, id))DY778ToolsOriginalSendCommentSource)(fragment, cmd, comment, enterSource, requestSource, trackParams, completion);
}
static void DY778ToolsSendCommentStore(id store, SEL cmd, id context, id completion) {
    [[DY778ToolsScheduler shared] captureStore:store context:context];
    if (!DY778ToolsSendAllowed()) return;
    ((void (*)(id, SEL, id, id))DY778ToolsOriginalSendCommentStore)(store, cmd, context, completion);
}
static void DY778ToolsSendBarrageStore(id store, SEL cmd, id context, id completion) {
    [[DY778ToolsScheduler shared] captureStore:store context:context];
    if (!DY778ToolsSendAllowed()) return;
    ((void (*)(id, SEL, id, id))DY778ToolsOriginalSendBarrageStore)(store, cmd, context, completion);
}
static void DY778ToolsBindService(id fragment, SEL cmd) {
    [[DY778ToolsScheduler shared] captureFragment:fragment context:nil];
    ((void (*)(id, SEL))DY778ToolsOriginalBindService)(fragment, cmd);
}

// ---------- 礼物风控：隐身且风控开时拦截 ----------
static BOOL DY778ToolsGiftAllowed(void) {
    if (DY778ToolsStealth() && DY778ToolsRisk()) {
        DY778ShowToast(DY778ToolsChannel, @"隐身模式下已拦截送礼，避免暴露身份", NO, NO);
        return NO;
    }
    return YES;
}
static IMP DY778ToolsOriginalGiftParamsService, DY778ToolsOriginalGiftParamsAdapter;
#define DY778_TOOLS_GIFT_PARAMS(N, ORIGINAL) \
static void DY778ToolsGiftParams##N(id service, SEL cmd, id params, long long diamondCount, id completion) { \
    if (!DY778ToolsGiftAllowed()) return; \
    ((void (*)(id, SEL, id, long long, id))ORIGINAL)(service, cmd, params, diamondCount, completion); }
DY778_TOOLS_GIFT_PARAMS(Service, DY778ToolsOriginalGiftParamsService)
DY778_TOOLS_GIFT_PARAMS(Adapter, DY778ToolsOriginalGiftParamsAdapter)
#undef DY778_TOOLS_GIFT_PARAMS
static IMP DY778ToolsOriginalGift1, DY778ToolsOriginalGift2, DY778ToolsOriginalGift3, DY778ToolsOriginalGift4;
static IMP DY778ToolsOriginalGift5, DY778ToolsOriginalGiftStore5, DY778ToolsOriginalGiftStoreConfig;
static void DY778ToolsGift1(id fragment, SEL cmd, id gift) {
    if (!DY778ToolsGiftAllowed()) return;
    ((void (*)(id, SEL, id))DY778ToolsOriginalGift1)(fragment, cmd, gift);
}
static void DY778ToolsGift2(id fragment, SEL cmd, id gift, unsigned long long count) {
    if (!DY778ToolsGiftAllowed()) return;
    ((void (*)(id, SEL, id, unsigned long long))DY778ToolsOriginalGift2)(fragment, cmd, gift, count);
}
static void DY778ToolsGift3(id fragment, SEL cmd, id gift, unsigned long long count, id extraTrack) {
    if (!DY778ToolsGiftAllowed()) return;
    ((void (*)(id, SEL, id, unsigned long long, id))DY778ToolsOriginalGift3)(fragment, cmd, gift, count, extraTrack);
}
static void DY778ToolsGift4(id fragment, SEL cmd, id gift, unsigned long long count, id toUser, id extraTrack) {
    if (!DY778ToolsGiftAllowed()) return;
    ((void (*)(id, SEL, id, unsigned long long, id, id))DY778ToolsOriginalGift4)(fragment, cmd, gift, count, toUser, extraTrack);
}
static void DY778ToolsGift5(id fragment, SEL cmd, id gift, unsigned long long count, id toUser, id params, id extraTrack, id successCallback, id errorCallback) {
    if (!DY778ToolsGiftAllowed()) return;
    ((void (*)(id, SEL, id, unsigned long long, id, id, id, id, id))DY778ToolsOriginalGift5)(fragment, cmd, gift, count, toUser, params, extraTrack, successCallback, errorCallback);
}
static void DY778ToolsGiftStore5(id store, SEL cmd, id gift, unsigned long long count, id toUser, id params, id extraTrack, id successCallback, id errorCallback) {
    if (!DY778ToolsGiftAllowed()) return;
    ((void (*)(id, SEL, id, unsigned long long, id, id, id, id, id))DY778ToolsOriginalGiftStore5)(store, cmd, gift, count, toUser, params, extraTrack, successCallback, errorCallback);
}
static void DY778ToolsGiftStoreConfig(id store, SEL cmd, id gift, id config, long long count, long long sendType, unsigned long long sendScene, id traceTool, id extraParams, id callback) {
    if (!DY778ToolsGiftAllowed()) return;
    ((void (*)(id, SEL, id, id, long long, long long, unsigned long long, id, id, id))DY778ToolsOriginalGiftStoreConfig)(store, cmd, gift, config, count, sendType, sendScene, traceTool, extraParams, callback);
}

// ---------- 直播登录：隐身时跳过，保持游客身份 ----------
// TODO：需真机验证——跳过直播登录是否影响进房流程；若进房失败，
// 须改为放行登录并仅记录状态。
static IMP DY778ToolsOriginalLogin1AWE, DY778ToolsOriginalLogin1IES;
static IMP DY778ToolsOriginalLogin2AWE, DY778ToolsOriginalLogin2IES;
static IMP DY778ToolsOriginalLogin3AWE, DY778ToolsOriginalLogin3IES;
static IMP DY778ToolsOriginalLogin4AWE, DY778ToolsOriginalLogin4IES;
#define DY778_TOOLS_LOGIN1(N, ORIGINAL) \
static void DY778ToolsLogin1##N(id service, SEL cmd, id userInfo) { \
    if (DY778ToolsStealth()) return; \
    ((void (*)(id, SEL, id))ORIGINAL)(service, cmd, userInfo); }
DY778_TOOLS_LOGIN1(AWE, DY778ToolsOriginalLogin1AWE)
DY778_TOOLS_LOGIN1(IES, DY778ToolsOriginalLogin1IES)
#undef DY778_TOOLS_LOGIN1
#define DY778_TOOLS_LOGIN2(N, ORIGINAL) \
static void DY778ToolsLogin2##N(id service, SEL cmd, id userInfo, id completion) { \
    if (DY778ToolsStealth()) return; \
    ((void (*)(id, SEL, id, id))ORIGINAL)(service, cmd, userInfo, completion); }
DY778_TOOLS_LOGIN2(AWE, DY778ToolsOriginalLogin2AWE)
DY778_TOOLS_LOGIN2(IES, DY778ToolsOriginalLogin2IES)
#undef DY778_TOOLS_LOGIN2
#define DY778_TOOLS_LOGIN3(N, ORIGINAL) \
static void DY778ToolsLogin3##N(id service, SEL cmd, id userInfo, BOOL isFIFARoom, id completion) { \
    if (DY778ToolsStealth()) return; \
    ((void (*)(id, SEL, id, BOOL, id))ORIGINAL)(service, cmd, userInfo, isFIFARoom, completion); }
DY778_TOOLS_LOGIN3(AWE, DY778ToolsOriginalLogin3AWE)
DY778_TOOLS_LOGIN3(IES, DY778ToolsOriginalLogin3IES)
#undef DY778_TOOLS_LOGIN3
#define DY778_TOOLS_LOGIN4(N, ORIGINAL) \
static void DY778ToolsLogin4##N(id service, SEL cmd, id userInfo, id themeId, id loginDesc, id completion) { \
    if (DY778ToolsStealth()) return; \
    ((void (*)(id, SEL, id, id, id, id))ORIGINAL)(service, cmd, userInfo, themeId, loginDesc, completion); }
DY778_TOOLS_LOGIN4(AWE, DY778ToolsOriginalLogin4AWE)
DY778_TOOLS_LOGIN4(IES, DY778ToolsOriginalLogin4IES)
#undef DY778_TOOLS_LOGIN4

// ---------- 退出/关闭：停止定时弹幕后放行 ----------
static IMP DY778ToolsOriginalExitPopEnd, DY778ToolsOriginalExitProcess, DY778ToolsOriginalCloseButton;
static void DY778ToolsExitPopEnd(id process, SEL cmd) {
    DY778LiveToolsRoomDidExit();
    ((void (*)(id, SEL))DY778ToolsOriginalExitPopEnd)(process, cmd);
}
static BOOL DY778ToolsExitProcess(id process, SEL cmd, id context) {
    DY778LiveToolsRoomDidExit();
    return ((BOOL (*)(id, SEL, id))DY778ToolsOriginalExitProcess)(process, cmd, context);
}
static void DY778ToolsCloseButton(id host, SEL cmd) {
    DY778LiveToolsRoomDidExit();
    ((void (*)(id, SEL))DY778ToolsOriginalCloseButton)(host, cmd);
}

void DY778InstallLiveToolsHooks(void) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ DY778InstallLiveToolsHooks(); }); return; }
    // 隐身：进房请求模型。
    DY778ToolsInstall(@"LiveEnterRoomRequestModel", @"isLogin", "Bc", "", (IMP)DY778ToolsRequestIsLogin, &DY778ToolsOriginalRequestIsLogin);
    DY778ToolsInstall(@"LiveEnterRoomRequestModel", @"buildRequestParams", "@", "", (IMP)DY778ToolsBuildParams, &DY778ToolsOriginalBuildParams);
    DY778ToolsInstall(@"LiveEnterRoomRequestModel", @"buildPreloadRequestParams", "@", "", (IMP)DY778ToolsBuildPreloadParams, &DY778ToolsOriginalBuildPreloadParams);
    // 进房入口。
    DY778ToolsInstall(@"HTSLiveRoomAPI", @"enterRoomWithLogin:roomModel:sourcePage:finish:", "v", "B@@@", (IMP)DY778ToolsEnterRoomLogin, &DY778ToolsOriginalEnterRoomLogin);
    DY778ToolsInstall(@"HTSLiveRoomAPI", @"enterRoomWithRequestModel:finish:", "v", "@@", (IMP)DY778ToolsEnterRoomAPI, &DY778ToolsOriginalEnterRoomAPI);
    DY778ToolsInstall(@"HTSLiveRoomAPI", @"enterRoomPreloadWithRequestModel:finish:", "v", "@@", (IMP)DY778ToolsEnterRoomPreloadAPI, &DY778ToolsOriginalEnterPreloadAPI);
    DY778ToolsInstall(@"IESLiveRoomService", @"enterRoomWithRequestModel:finish:", "v", "@@", (IMP)DY778ToolsEnterRoomService, &DY778ToolsOriginalEnterRoomService);
    DY778ToolsInstall(@"IESLiveRoomService", @"enterRoomPreloadWithRequestModel:finish:", "v", "@@", (IMP)DY778ToolsEnterRoomPreloadService, &DY778ToolsOriginalEnterPreloadService);
    DY778ToolsInstall(@"IESLiveRoomService", @"_enterRoomWithRequestModel:preload:finish:", "v", "@B@", (IMP)DY778ToolsEnterRoomLowLevel, &DY778ToolsOriginalEnterRoomLowLevel);
    // 定时弹幕：发送拦截 + 上下文捕获。
    DY778ToolsInstall(@"HTSLiveCommentFragment", @"sendComment:commentContext:completion:", "v", "@@@", (IMP)DY778ToolsSendComment, &DY778ToolsOriginalSendComment);
    DY778ToolsInstall(@"HTSLiveCommentFragment", @"sendBarrage:commentContext:completion:", "v", "@@@", (IMP)DY778ToolsSendBarrage, &DY778ToolsOriginalSendBarrage);
    DY778ToolsInstall(@"HTSLiveCommentFragment", @"sendBarrage:trackParams:completion:", "v", "@@@", (IMP)DY778ToolsSendBarrageTrack, &DY778ToolsOriginalSendBarrageTrack);
    DY778ToolsInstall(@"HTSLiveCommentFragment", @"sendComment:enterSource:requestSource:trackParams:completion:", "v", "@q@@@", (IMP)DY778ToolsSendCommentSource, &DY778ToolsOriginalSendCommentSource);
    DY778ToolsInstall(@"HTSLiveCommentStore", @"sendCommentWithCommentContext:completion:", "v", "@@", (IMP)DY778ToolsSendCommentStore, &DY778ToolsOriginalSendCommentStore);
    DY778ToolsInstall(@"HTSLiveCommentStore", @"sendBarrageWithCommentContext:completion:", "v", "@@", (IMP)DY778ToolsSendBarrageStore, &DY778ToolsOriginalSendBarrageStore);
    DY778ToolsInstall(@"HTSLiveCommentFragment", @"componentBindService", "v", "", (IMP)DY778ToolsBindService, &DY778ToolsOriginalBindService);
    // 礼物风控。
    DY778ToolsInstall(@"AWELiveModuleService", @"sendGiftWithParams:diamondCount:completion:", "v", "@q@", (IMP)DY778ToolsGiftParamsService, &DY778ToolsOriginalGiftParamsService);
    DY778ToolsInstall(@"AWELiveModuleServiceCommonAdaperDefault", @"sendGiftWithParams:diamondCount:completion:", "v", "@q@", (IMP)DY778ToolsGiftParamsAdapter, &DY778ToolsOriginalGiftParamsAdapter);
    DY778ToolsInstall(@"IESLiveGiveGiftFragment", @"sendGift:", "v", "@", (IMP)DY778ToolsGift1, &DY778ToolsOriginalGift1);
    DY778ToolsInstall(@"IESLiveGiveGiftFragment", @"sendGift:count:", "v", "@Q", (IMP)DY778ToolsGift2, &DY778ToolsOriginalGift2);
    DY778ToolsInstall(@"IESLiveGiveGiftFragment", @"sendGift:count:extraTrack:", "v", "@Q@", (IMP)DY778ToolsGift3, &DY778ToolsOriginalGift3);
    DY778ToolsInstall(@"IESLiveGiveGiftFragment", @"sendGift:count:toUser:extraTrack:", "v", "@Q@@", (IMP)DY778ToolsGift4, &DY778ToolsOriginalGift4);
    DY778ToolsInstall(@"IESLiveGiveGiftFragment", @"sendGift:count:toUser:params:extraTrack:successCallback:errorCallback:", "v", "@Q@@@@@", (IMP)DY778ToolsGift5, &DY778ToolsOriginalGift5);
    DY778ToolsInstall(@"IESLiveGiveGiftStore", @"sendGift:count:toUser:params:extraTrack:successCallback:errorCallback:", "v", "@Q@@@@@", (IMP)DY778ToolsGiftStore5, &DY778ToolsOriginalGiftStore5);
    DY778ToolsInstall(@"IESLiveGiveGiftStore", @"sendGift:config:count:sendType:sendScene:traceTool:extraParams:callback:", "v", "@@qqQ@@@", (IMP)DY778ToolsGiftStoreConfig, &DY778ToolsOriginalGiftStoreConfig);
    // 直播登录。
    DY778ToolsInstall(@"AWELiveLoginServiceImpl", @"loginWithUserInfo:", "v", "@", (IMP)DY778ToolsLogin1AWE, &DY778ToolsOriginalLogin1AWE);
    DY778ToolsInstall(@"AWELiveLoginServiceImpl", @"loginWithUserInfo:completion:", "v", "@@", (IMP)DY778ToolsLogin2AWE, &DY778ToolsOriginalLogin2AWE);
    DY778ToolsInstall(@"AWELiveLoginServiceImpl", @"loginWithUserInfo:isFIFARoom:completion:", "v", "@B@", (IMP)DY778ToolsLogin3AWE, &DY778ToolsOriginalLogin3AWE);
    DY778ToolsInstall(@"AWELiveLoginServiceImpl", @"loginWithUserInfo:themeId:loginDesc:completion:", "v", "@@@@", (IMP)DY778ToolsLogin4AWE, &DY778ToolsOriginalLogin4AWE);
    DY778ToolsInstall(@"IESLiveUserServiceImpl", @"loginWithUserInfo:", "v", "@", (IMP)DY778ToolsLogin1IES, &DY778ToolsOriginalLogin1IES);
    DY778ToolsInstall(@"IESLiveUserServiceImpl", @"loginWithUserInfo:completion:", "v", "@@", (IMP)DY778ToolsLogin2IES, &DY778ToolsOriginalLogin2IES);
    DY778ToolsInstall(@"IESLiveUserServiceImpl", @"loginWithUserInfo:isFIFARoom:completion:", "v", "@B@", (IMP)DY778ToolsLogin3IES, &DY778ToolsOriginalLogin3IES);
    DY778ToolsInstall(@"IESLiveUserServiceImpl", @"loginWithUserInfo:themeId:loginDesc:completion:", "v", "@@@@", (IMP)DY778ToolsLogin4IES, &DY778ToolsOriginalLogin4IES);
    // 退出/关闭。
    DY778ToolsInstall(@"IESLiveAudienceRoomExitProcess", @"fullScreenPopEnd", "v", "", (IMP)DY778ToolsExitPopEnd, &DY778ToolsOriginalExitPopEnd);
    DY778ToolsInstall(@"IESLiveAudienceRoomExitProcess", @"processExitRoomWithContext:", "Bc", "@", (IMP)DY778ToolsExitProcess, &DY778ToolsOriginalExitProcess);
    DY778ToolsInstall(@"IESLiveAudienceViewController", @"closeButtonAction", "v", "", (IMP)DY778ToolsCloseButton, &DY778ToolsOriginalCloseButton);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue
                       usingBlock:^(__unused NSNotification *note) { [DY778ToolsScheduler.shared stop]; }];
        [center addObserverForName:DY778PreferencesChangedNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            NSString *key = note.userInfo[@"key"];
            if (!key.length || [key hasPrefix:@"liveTools."]) {
                [DY778ToolsScheduler.shared stop];
                [DY778ToolsScheduler.shared maybeStart];
            }
        }];
    });
}
