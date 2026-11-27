#import "DY778LiveGuest.h"
#import "DY778Core.h"
#import "DY778LiveInfo.h"
#import "DY778LiveTools.h"
#import "DY778LiveToolsPolicy.h"

// DY778 1.0-8 模块 1 移植：游客身份 + 直播身份。
// 规格：~/workspace/plugin-merge/DY778/spec-module1-livetools-guest.md §2–§3；
// hook 表以反汇编提取为准（liveguest.asm、liveidentity.asm）。
// 核心机制：假装未登录（isLogin 返回 NO）+ 请求层去 token（删 X-TT-TOKEN 请求头、
// 注入游客 TTWID）+ 进房/退房过程 hook。行为由 liveTools.stealth 开关在调用时
// 控制，默认关闭。
// TODO（反汇编未能确定的部分，需真机验证）：
//   - forceIgnore_X_TT_TOKEN：提取时未能确定其所属类，暂不单独 hook；
//     改为在网络拦截返回的任务对象上用 KVC 尽力设置（不存在则无操作）。
//   - IESLiveIMBaseActionCreator useUnifiedClient:：返回值在游客模式下的
//     正确取值未证实，当前直接放行原实现。
//   - channel:closed:：关闭时是否应停定时弹幕未证实，当前只放行原实现。
//   - 未安装的 hook：LiveGuest 首个未解析项（0x12dc74，v，无参）与
//     LiveIdentity 末个未解析项（0x12e3d0，v，@@），目标不明，留空。

static const char *DY778GuestType(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type ?: "";
}
static BOOL DY778GuestMatches(const char *result, const char *arguments, NSMethodSignature *signature) {
    if (!signature) return NO;
    if (!strchr(result, *DY778GuestType(signature.methodReturnType))) return NO;
    if (signature.numberOfArguments != strlen(arguments) + 2) return NO;
    for (NSUInteger i = 0; i < strlen(arguments); i++) {
        char actual = *DY778GuestType([signature getArgumentTypeAtIndex:i + 2]), expected = arguments[i];
        if (expected == 'B' ? !(actual == 'B' || actual == 'c') :
            expected == 'q' ? !(actual == 'q' || actual == 'Q') :
            expected == '^' ? !(actual == '^' || actual == '@') : actual != expected) return NO;
    }
    return YES;
}
static BOOL DY778GuestSignature(Class cls, SEL selector, const char *result, const char *arguments) {
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!method) return NO;
    return DY778GuestMatches(result, arguments, [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)]);
}
static BOOL DY778GuestHookClassMethod(Class cls, SEL selector, IMP replacement, IMP *original) {
    Class meta = object_getClass(cls);
    Method method = class_getInstanceMethod(meta, selector);
    if (!method) return NO;
    IMP previous = method_getImplementation(method);
    if (previous == replacement) return YES;
    *original = previous;
    if (!class_addMethod(meta, selector, replacement, method_getTypeEncoding(method)))
        method_setImplementation(class_getInstanceMethod(meta, selector), replacement);
    return YES;
}
static void DY778GuestInstall(NSString *className, NSString *selector, const char *result, const char *arguments, IMP replacement, IMP *original) {
    if (*original) return;
    Class cls = NSClassFromString(className); SEL sel = NSSelectorFromString(selector);
    BOOL installed = NO;
    if (DY778GuestSignature(cls, sel, result, arguments)) installed = DY778Hook(cls, sel, replacement, original);
    if (!installed && cls) {
        Method method = class_getInstanceMethod(object_getClass(cls), sel);
        if (method && DY778GuestMatches(result, arguments, [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)]))
            installed = DY778GuestHookClassMethod(cls, sel, replacement, original);
    }
    DY778RecordHook([NSString stringWithFormat:@"游客身份 / %@.%@", className, selector], installed);
}
static BOOL DY778GuestStealth(void) { return DY778LiveIdentityGuestActive(); }

// ---------- 身份范围（1.1-2 DY778LiveIdentityScope 移植） ----------
// sessionOverrides：roomID → 进房时绑定的游客身份（NSNumber BOOL）。
// currentRoomID：当前所在房间；退房清 current、保留绑定（重进同房沿用）。
static NSMutableDictionary<NSString *, NSNumber *> *DY778IdentitySessionOverrides;
static NSString *DY778IdentityCurrentRoomID;
static NSObject *DY778IdentityLock;
static NSObject *DY778IdentityLockToken(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        DY778IdentityLock = [NSObject new];
        DY778IdentitySessionOverrides = [NSMutableDictionary dictionary];
    });
    return DY778IdentityLock;
}
BOOL DY778LiveIdentityGuestActive(void) {
    @synchronized (DY778IdentityLockToken()) {
        if (DY778IdentityCurrentRoomID.length) {
            NSNumber *bound = DY778IdentitySessionOverrides[DY778IdentityCurrentRoomID];
            if (bound) return bound.boolValue;
            // 进房绑定缺失（hook 未覆盖的进房路径）：按当前开关补绑定，
            // 与 1.1-2 prepareRoomID:defaultGuest: 同义。
            BOOL guest = DY778Bool(@"liveTools.stealth");
            DY778IdentitySessionOverrides[DY778IdentityCurrentRoomID] = @(guest);
            return guest;
        }
    }
    return DY778Bool(@"liveTools.stealth");
}
void DY778LiveIdentityRoomEntered(NSString *roomID) {
    if (!roomID.length) return;
    @synchronized (DY778IdentityLockToken()) {
        DY778IdentityCurrentRoomID = [roomID copy];
        if (!DY778IdentitySessionOverrides[roomID]) {
            DY778IdentitySessionOverrides[roomID] = @(DY778Bool(@"liveTools.stealth"));
        }
    }
}
void DY778LiveIdentityRoomExited(void) {
    @synchronized (DY778IdentityLockToken()) { DY778IdentityCurrentRoomID = nil; }
}
NSString *DY778LiveIdentityCurrentRoomID(void) {
    @synchronized (DY778IdentityLockToken()) { return [DY778IdentityCurrentRoomID copy]; }
}
static void DY778LiveIdentitySwitchChanged(void) {
    // 手动切换隐身开关：当前房间身份按新开关重新确定（1.1-2 语义）。
    @synchronized (DY778IdentityLockToken()) {
        if (DY778IdentityCurrentRoomID.length) {
            DY778IdentitySessionOverrides[DY778IdentityCurrentRoomID] = @(DY778Bool(@"liveTools.stealth"));
        }
    }
}
static NSString *DY778GuestTTWID(void) {
    NSString *ttwid = [DY778String(@"liveTools.ttwid") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return DY778LiveToolsValidTTWID(ttwid.UTF8String) ? ttwid : nil;
}
static NSDictionary *DY778GuestScrubbedParams(id params) {
    if (![params isKindOfClass:NSDictionary.class]) return params;
    NSMutableDictionary *mutable = [params mutableCopy];
    NSString *ttwid = DY778GuestTTWID();
    if (ttwid.length) mutable[@"ttwid"] = ttwid;
    return mutable;
}
static NSDictionary *DY778GuestScrubbedHeaders(id headers) {
    if (![headers isKindOfClass:NSDictionary.class]) return headers;
    NSMutableDictionary *mutable = [headers mutableCopy];
    for (NSString *key in [mutable allKeys]) {
        if ([key isKindOfClass:NSString.class] && [key caseInsensitiveCompare:@"X-TT-TOKEN"] == NSOrderedSame) [mutable removeObjectForKey:key];
    }
    return mutable;
}
static void DY778GuestForceIgnoreToken(id task) {
    if (task) DY778Write(task, @"forceIgnore_X_TT_TOKEN", @YES);
}

// ---------- 网络请求拦截：去登录 token + 注入游客 TTWID ----------
static IMP DY778GuestOriginalJSON1, DY778GuestOriginalJSON2, DY778GuestOriginalBinary;
static id DY778GuestBuildJSON1(id manager, SEL cmd, id params, id method, BOOL needCommonParams, id headerField, Class requestSerializer, Class responseSerializer, BOOL autoResume, BOOL verifyRequest, BOOL isCustomizedCookie, id callback, id callbackWithResponse, id dispatchQueue, SEL entrySelector) {
    if (DY778GuestStealth()) {
        params = DY778GuestScrubbedParams(params);
        headerField = DY778GuestScrubbedHeaders(headerField);
    }
    id task = ((id (*)(id, SEL, id, id, BOOL, id, Class, Class, BOOL, BOOL, BOOL, id, id, id, SEL))DY778GuestOriginalJSON1)(manager, cmd, params, method, needCommonParams, headerField, requestSerializer, responseSerializer, autoResume, verifyRequest, isCustomizedCookie, callback, callbackWithResponse, dispatchQueue, entrySelector);
    if (DY778GuestStealth()) DY778GuestForceIgnoreToken(task);
    return task;
}
static id DY778GuestBuildJSON2(id manager, SEL cmd, id params, id method, BOOL needCommonParams, int commonParamLevel, id headerField, Class requestSerializer, Class responseSerializer, BOOL autoResume, BOOL verifyRequest, BOOL isCustomizedCookie, id callback, id callbackWithResponse, id dispatchQueue, SEL entrySelector) {
    if (DY778GuestStealth()) {
        params = DY778GuestScrubbedParams(params);
        headerField = DY778GuestScrubbedHeaders(headerField);
    }
    id task = ((id (*)(id, SEL, id, id, BOOL, int, id, Class, Class, BOOL, BOOL, BOOL, id, id, id, SEL))DY778GuestOriginalJSON2)(manager, cmd, params, method, needCommonParams, commonParamLevel, headerField, requestSerializer, responseSerializer, autoResume, verifyRequest, isCustomizedCookie, callback, callbackWithResponse, dispatchQueue, entrySelector);
    if (DY778GuestStealth()) DY778GuestForceIgnoreToken(task);
    return task;
}
static id DY778GuestBuildBinary(id manager, SEL cmd, id params, id method, BOOL needCommonParams, id headerField, BOOL enableHttpCache, id formerRequest, Class requestSerializer, Class responseSerializer, BOOL autoResume, BOOL isCustomizedCookie, id headerCallback, id dataCallback, id callback, id callbackWithResponse, id redirectCallback, id progress, id dispatchQueue, SEL entrySelector) {
    if (DY778GuestStealth()) {
        params = DY778GuestScrubbedParams(params);
        headerField = DY778GuestScrubbedHeaders(headerField);
    }
    id task = ((id (*)(id, SEL, id, id, BOOL, id, BOOL, id, Class, Class, BOOL, BOOL, id, id, id, id, id, id, id, SEL))DY778GuestOriginalBinary)(manager, cmd, params, method, needCommonParams, headerField, enableHttpCache, formerRequest, requestSerializer, responseSerializer, autoResume, isCustomizedCookie, headerCallback, dataCallback, callback, callbackWithResponse, redirectCallback, progress, dispatchQueue, entrySelector);
    if (DY778GuestStealth()) DY778GuestForceIgnoreToken(task);
    return task;
}

// ---------- 游客身份：未登录 + 统一客户端 ----------
static IMP DY778GuestOriginalUserIsLogin, DY778GuestOriginalUseUnifiedClient;
static BOOL DY778GuestUserIsLogin(id service, SEL cmd) {
    if (DY778GuestStealth()) return NO;
    return ((BOOL (*)(id, SEL))DY778GuestOriginalUserIsLogin)(service, cmd);
}
static BOOL DY778GuestUseUnifiedClient(id creator, SEL cmd, id argument) {
    return ((BOOL (*)(id, SEL, id))DY778GuestOriginalUseUnifiedClient)(creator, cmd, argument);
}

// ---------- 直播身份：进房/退房过程 ----------
static IMP DY778GuestOriginalTryEnterRoom, DY778GuestOriginalNoNeedRetry, DY778GuestOriginalFetchPermission;
static IMP DY778GuestOriginalHandleRemoteError, DY778GuestOriginalPingStatus, DY778GuestOriginalSetupIM;
static void DY778GuestTryEnterRoom(id process, SEL cmd, long long roomID, unsigned long long retryIndex) {
    if (roomID > 0) {
        NSString *identifier = [NSString stringWithFormat:@"%lld", roomID];
        DY778LiveIdentityRoomEntered(identifier);
        DY778LiveToolsRoomDidEnter(identifier);
    }
    ((void (*)(id, SEL, long long, unsigned long long))DY778GuestOriginalTryEnterRoom)(process, cmd, roomID, retryIndex);
}
static BOOL DY778GuestNoNeedRetry(id process, SEL cmd, id argument) {
    return ((BOOL (*)(id, SEL, id))DY778GuestOriginalNoNeedRetry)(process, cmd, argument);
}
static void DY778GuestFetchPermission(id guarder, SEL cmd, id syncData) {
    ((void (*)(id, SEL, id))DY778GuestOriginalFetchPermission)(guarder, cmd, syncData);
}
static void DY778GuestHandleRemoteError(id guarder, SEL cmd, id error) {
    ((void (*)(id, SEL, id))DY778GuestOriginalHandleRemoteError)(guarder, cmd, error);
}
static void DY778GuestPingStatus(id api, SEL cmd, BOOL onlyStatus) {
    ((void (*)(id, SEL, BOOL))DY778GuestOriginalPingStatus)(api, cmd, onlyStatus);
}
static void DY778GuestSetupIM(id creator, SEL cmd, id messageConfig, id decoder) {
    ((void (*)(id, SEL, id, id))DY778GuestOriginalSetupIM)(creator, cmd, messageConfig, decoder);
}
static IMP DY778GuestOriginalEnterRoomService, DY778GuestOriginalEnterRoomAPI;
static IMP DY778GuestOriginalExitRoomService, DY778GuestOriginalExitRoomAPI;
#define DY778_GUEST_ENTER_ROOM(N, ORIGINAL) \
static void DY778GuestEnterRoom##N(id target, SEL cmd, id requestModel, id finish) { \
    NSString *roomID = DY778LiveRoomIdentifier(requestModel); \
    if (!roomID.length) { id model = DY778Read(requestModel, @"roomModel"); if (model && model != requestModel) roomID = DY778LiveRoomIdentifier(model); } \
    if (roomID.length) { DY778LiveIdentityRoomEntered(roomID); DY778LiveToolsRoomDidEnter(roomID); } \
    ((void (*)(id, SEL, id, id))ORIGINAL)(target, cmd, requestModel, finish); }
DY778_GUEST_ENTER_ROOM(Service, DY778GuestOriginalEnterRoomService)
DY778_GUEST_ENTER_ROOM(API, DY778GuestOriginalEnterRoomAPI)
#undef DY778_GUEST_ENTER_ROOM
#define DY778_GUEST_EXIT_ROOM(N, ORIGINAL) \
static void DY778GuestExitRoom##N(id target, SEL cmd, id room) { \
    DY778LiveIdentityRoomExited(); \
    DY778LiveToolsRoomDidExit(); \
    ((void (*)(id, SEL, id))ORIGINAL)(target, cmd, room); }
DY778_GUEST_EXIT_ROOM(Service, DY778GuestOriginalExitRoomService)
DY778_GUEST_EXIT_ROOM(API, DY778GuestOriginalExitRoomAPI)
#undef DY778_GUEST_EXIT_ROOM
static IMP DY778GuestOriginalChannelClosedWrapper, DY778GuestOriginalChannelClosedMessageClient;
#define DY778_GUEST_CHANNEL_CLOSED(N, ORIGINAL) \
static void DY778GuestChannelClosed##N(id client, SEL cmd, id channel, id closed) { \
    ((void (*)(id, SEL, id, id))ORIGINAL)(client, cmd, channel, closed); }
DY778_GUEST_CHANNEL_CLOSED(Wrapper, DY778GuestOriginalChannelClosedWrapper)
DY778_GUEST_CHANNEL_CLOSED(MessageClient, DY778GuestOriginalChannelClosedMessageClient)
#undef DY778_GUEST_CHANNEL_CLOSED

void DY778InstallLiveGuestHooks(void) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ DY778InstallLiveGuestHooks(); }); return; }
    // 身份范围：隐身开关手动切换时，当前房间身份重新确定（只注册一次）。
    static BOOL identityObserverInstalled;
    if (!identityObserverInstalled) {
        identityObserverInstalled = YES;
        [NSNotificationCenter.defaultCenter addObserverForName:DY778PreferencesChangedNotification object:nil
            queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
                NSString *key = notification.userInfo[@"key"];
                if ([key isEqualToString:@"liveTools.stealth"]) DY778LiveIdentitySwitchChanged();
            }];
    }
    // 游客身份：网络请求拦截（实例方法优先，不存在时按类方法再试一次）。
    DY778GuestInstall(@"TTNetworkManagerChromium", @"buildJSONHttpTask:params:method:needCommonParams:headerField:requestSerializer:responseSerializer:autoResume:verifyRequest:isCustomizedCookie:callback:callbackWithResponse:dispatch_queue:entrySelector:", "@", "@@B@##BBB@@@:", (IMP)DY778GuestBuildJSON1, &DY778GuestOriginalJSON1);
    DY778GuestInstall(@"TTNetworkManagerChromium", @"buildJSONHttpTask:params:method:needCommonParams:commonParamLevel:headerField:requestSerializer:responseSerializer:autoResume:verifyRequest:isCustomizedCookie:callback:callbackWithResponse:dispatch_queue:entrySelector:", "@", "@@Bi@##BBB@@@:", (IMP)DY778GuestBuildJSON2, &DY778GuestOriginalJSON2);
    DY778GuestInstall(@"TTNetworkManagerChromium", @"buildBinaryHttpTask:params:method:needCommonParams:headerField:enableHttpCache:formerRequest:requestSerializer:responseSerializer:autoResume:isCustomizedCookie:headerCallback:dataCallback:callback:callbackWithResponse:redirectCallback:progress:dispatch_queue:entrySelector:", "@", "@@B@B@##BB@@@@@^@:", (IMP)DY778GuestBuildBinary, &DY778GuestOriginalBinary);
    DY778GuestInstall(@"IESLiveUserServiceImpl", @"isLogin", "Bc", "", (IMP)DY778GuestUserIsLogin, &DY778GuestOriginalUserIsLogin);
    DY778GuestInstall(@"IESLiveIMBaseActionCreator", @"useUnifiedClient:", "Bc", "@", (IMP)DY778GuestUseUnifiedClient, &DY778GuestOriginalUseUnifiedClient);
    // 直播身份：进房/退房过程。
    DY778GuestInstall(@"IESLiveAudienceRoomEnterProcess", @"tryEnterRoom:retryIndex:", "v", "qQ", (IMP)DY778GuestTryEnterRoom, &DY778GuestOriginalTryEnterRoom);
    DY778GuestInstall(@"IESLiveAudienceRoomEnterProcess", @"noNeedRetryEnterRoom:", "Bc", "@", (IMP)DY778GuestNoNeedRetry, &DY778GuestOriginalNoNeedRetry);
    DY778GuestInstall(@"IESLiveAudienceRoomStateGuarder", @"fetchPermissionaWithSyncData:", "v", "@", (IMP)DY778GuestFetchPermission, &DY778GuestOriginalFetchPermission);
    DY778GuestInstall(@"IESLiveAudienceRoomStateGuarder", @"handleRemoteError:", "v", "@", (IMP)DY778GuestHandleRemoteError, &DY778GuestOriginalHandleRemoteError);
    DY778GuestInstall(@"HTSLiveAudiencePingApi", @"requestWithOnlyStatus:", "v", "B", (IMP)DY778GuestPingStatus, &DY778GuestOriginalPingStatus);
    DY778GuestInstall(@"IESLiveIMBaseActionCreator", @"setupWithMessageConfig:decoder:", "v", "@@", (IMP)DY778GuestSetupIM, &DY778GuestOriginalSetupIM);
    DY778GuestInstall(@"IESLiveRoomService", @"enterRoomWithRequestModel:finish:", "v", "@@", (IMP)DY778GuestEnterRoomService, &DY778GuestOriginalEnterRoomService);
    DY778GuestInstall(@"HTSLiveRoomAPI", @"enterRoomWithRequestModel:finish:", "v", "@@", (IMP)DY778GuestEnterRoomAPI, &DY778GuestOriginalEnterRoomAPI);
    DY778GuestInstall(@"IESLiveRoomService", @"exitRoom:", "v", "@", (IMP)DY778GuestExitRoomService, &DY778GuestOriginalExitRoomService);
    DY778GuestInstall(@"HTSLiveRoomAPI", @"exitRoom:", "v", "@", (IMP)DY778GuestExitRoomAPI, &DY778GuestOriginalExitRoomAPI);
    DY778GuestInstall(@"IESLiveIMClientWrapper", @"channel:closed:", "v", "@@", (IMP)DY778GuestChannelClosedWrapper, &DY778GuestOriginalChannelClosedWrapper);
    DY778GuestInstall(@"IESLiveIMMessageClient", @"channel:closed:", "v", "@@", (IMP)DY778GuestChannelClosedMessageClient, &DY778GuestOriginalChannelClosedMessageClient);
}
