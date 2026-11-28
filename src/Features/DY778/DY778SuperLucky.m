#import "DY778SuperLucky.h"
#import "DY778Core.h"
#import "DY778LiveInfo.h"
#import "DY778RedEnvelope.h"
#import "DY778RedEnvelopePolicy.h"
#import "DY778SuperLuckyPolicy.h"
#import "DY778LiveAnalysisPolicy.h"
#import <objc/message.h>

// DY778 1.0-8 模块 3 移植：超级福袋（SL）。
// 规格：~/workspace/plugin-merge/DY778/spec-module3-redenvelope-superlucky.md
// hook 常驻装载，行为全部由开关在调用时控制，默认全部关闭：
//   superLucky.enabled   总开关（关则不驱动参与）
//   superLucky.showEntry 显示入口按钮（默认开，未证实）
//   superLucky.notifyResult 领取结果通知（默认关）
//   superLucky.haptics   触觉反馈（默认开，未证实）
//   superLucky.compact   紧凑展示（默认关，未证实）
//   superLucky.delay     执行延迟（秒，默认 3，钳制 0–30，未证实）
//   superLucky.autoFollow 自动关注（参与任务用，默认关）
//   superLucky.drawReminder 开奖提醒（键归模块 3，行为归模块 4，默认关）
//   superLucky.drawReminderSeconds 提前提醒秒数（默认 60，钳制 0–3600，未证实）
//   superLucky.entryPosition.portrait/.landscape 入口位置（默认右下角，未证实）
//   superLucky.records   领取记录（持久化）
//   lucky.* 共享键见 DY778Core.m（1.0-3 已有默认值，模块 3 不得改动）。
// TODO（需真机验证，规格 §11）：
//   - 是否真能领到：只证明了原版「尝试领取」的代码路径，没有任何证据
//     证明这些调用在抖音 40.8.0 上仍能成功领取；服务端可能已改接口、
//     加签、限流或风控。真机验证前不得宣称「能参与/能中奖」。
//   - 观看任务是否须真实停留未证实（规格 §11.10）：DYxs 侧绝不伪造
//     观看时长，只认任务上下文上报的已完成状态（task_state /
//     hasParticipated）；观看时长不足时只记 watch-time-insufficient。
//   - SL 安装末尾的 4 个 NSNotificationCenter 观察者名字取自运行时全局，
//     静态不可恢复：DYxs 侧不注册猜测的通知名，pause/tick 改由 hook
//     与组心跳定时器驱动（见 DY778InstallSuperLuckyHooks 末尾说明）。
//   - 4 段 XOR 串（0x3cc2b0–0x3cc350）未解：可能是 URL 或签名字段，
//     DYxs 侧不猜；原生请求用 NSURLSession POST 到规格 §5 的 lottery
//     端点，服务端是否接受此路径未证实。
//   - S4 onStartLeaveRoomAnimation 的期望参数数组取自运行时全局，
//     静态未证实（应为空数组）：按空数组校验，不过则不装。
//   - SLGroup 记录键（0x38433c）XOR 混淆静态不可读：自拟前缀。

// ---------- 签名校验（照 DY778LiveLike.m / DY778LiveAnalysis.m 的做法） ----------
static const char *DY778SLType(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type ?: "";
}
static BOOL DY778SLMatches(const char *result, const char *arguments, NSMethodSignature *signature) {
    if (!signature) return NO;
    if (!strchr(result, *DY778SLType(signature.methodReturnType))) return NO;
    if (signature.numberOfArguments != strlen(arguments) + 2) return NO;
    for (NSUInteger i = 0; i < strlen(arguments); i++) {
        const char *actual = DY778SLType([signature getArgumentTypeAtIndex:i + 2]);
        char expected = arguments[i];
        if (expected == 'B' ? !(actual[0] == 'B' || actual[0] == 'c') :
            expected == 'q' ? !(actual[0] == 'q' || actual[0] == 'Q') :
            expected == 'P' ? strcmp(actual, @encode(CGPoint)) != 0 :
            expected == '^' ? !(actual[0] == '^' || actual[0] == '@') : actual[0] != expected) return NO;
    }
    return YES;
}
static BOOL DY778SLSignature(Class cls, SEL selector, const char *result, const char *arguments) {
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!method) return NO;
    return DY778SLMatches(result, arguments, [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)]);
}
static void DY778SLMain(dispatch_block_t block) {
    if (NSThread.isMainThread) block(); else dispatch_async(dispatch_get_main_queue(), block);
}

// ---------- 原 IMP 存储（S1–S4、G1） ----------
static IMP DY778SLOriginalViewDidAppear;          // S1
static IMP DY778SLOriginalRoomDidBecomeActive;    // S2
static IMP DY778SLOriginalRoomWillResignActive;   // S3
static IMP DY778SLOriginalStartLeaveRoom;         // S4
static IMP DY778SLOriginalSetHybridLotteryPanel;  // G1

// ---------- 安装 helper ----------
static void DY778SLInstall(NSString *className, NSString *selector, const char *result, const char *arguments, IMP replacement, IMP *original) {
    if (*original) return;
    Class cls = NSClassFromString(className); SEL sel = NSSelectorFromString(selector);
    NSString *recordKey = [NSString stringWithFormat:@"superLucky.%@.%@", className, selector];
    BOOL installed = DY778SLSignature(cls, sel, result, arguments) && DY778Hook(cls, sel, replacement, original);
    DY778RecordHook(recordKey, installed);
}

BOOL DY778SuperLuckyEnabled(void) { return DY778Bool(@"superLucky.enabled"); }

// ---------- 通用取值 helper ----------
static NSString *DY778SLText(id value) {
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) return [value stringValue];
    return nil;
}
static id DY778SLValue(id object, NSString *key) {
    if (!object || !key.length) return nil;
    id value = nil;
    @try {
        if ([object isKindOfClass:NSDictionary.class]) value = object[key];
        else value = DY778Read(object, key);
    } @catch (__unused NSException *exception) { return nil; }
    return [value isKindOfClass:NSNull.class] ? nil : value;
}
static NSTimeInterval DY778SLSeconds(id object, NSString *key) {
    id value = DY778SLValue(object, key);
    return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0;
}
static BOOL DY778SLFlag(id object, NSString *key) {
    id value = DY778SLValue(object, key);
    if ([value isKindOfClass:NSNumber.class]) return [value boolValue];
    NSString *text = DY778SLText(value);
    return text.length ? [text boolValue] : NO;
}

// ---------- 任务上下文（规格 §4.2） ----------
@implementation DY778SLTaskContext
- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    if ((self = [super init])) {
        _raw = [dictionary copy] ?: @{};
        id infos = DY778SLValue(dictionary, @"task_infos_v2");
        NSDictionary *task = nil;
        if ([infos isKindOfClass:NSArray.class] && ((NSArray *)infos).count && [infos[0] isKindOfClass:NSDictionary.class]) task = infos[0];
        else if ([infos isKindOfClass:NSDictionary.class]) task = infos;
        NSDictionary *source = task ?: dictionary;
        _taskID = DY778SLText(DY778SLValue(source, @"task_id")) ?: DY778SLText(DY778SLValue(dictionary, @"task_id")) ?: @"";
        _taskType = DY778SLText(DY778SLValue(source, @"task_type")) ?: DY778SLText(DY778SLValue(dictionary, @"task_type")) ?: @"";
        _taskState = DY778SLText(DY778SLValue(source, @"task_state")) ?: DY778SLText(DY778SLValue(dictionary, @"task_state")) ?: @"";
        _hasParticipated = DY778SLFlag(source, @"hasParticipated") || DY778SLFlag(dictionary, @"hasParticipated");
        _remainingSeconds = DY778SLSeconds(source, @"remainingSeconds");
        if (_remainingSeconds == 0) _remainingSeconds = DY778SLSeconds(dictionary, @"remainingSeconds");
        _activityID = DY778SLText(DY778SLValue(dictionary, @"activityID")) ?: DY778SLText(DY778SLValue(dictionary, @"activity_id")) ?: DY778SLText(DY778SLValue(dictionary, @"lottery_id")) ?: @"";
        _roomID = DY778SLText(DY778SLValue(dictionary, @"roomID")) ?: DY778SLText(DY778SLValue(dictionary, @"roomId")) ?:
            DY778SLText(DY778SLValue(dictionary, @"roomIdStr")) ?: @"";
    }
    return self;
}
- (BOOL)complete {
    if (_hasParticipated) return YES;
    NSString *state = _taskState.lowercaseString;
    return [state isEqualToString:@"complete"] || [state isEqualToString:@"completed"] || [state isEqualToString:@"finished"];
}
@end

// ---------- 参与计划（规格 §4.3） ----------
// 观看时长不足时只记 watch-time-insufficient，不伪造完成；过期只认
// task_state/reason 的过期表述，不按 remainingSeconds == 0 猜过期
// （无时长限制的任务 remainingSeconds 本来就是 0）。
@implementation DY778SLParticipationPlan
- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    if ((self = [super init])) {
        _watchRemainingSeconds = DY778SLSeconds(dictionary, @"watchRemainingSeconds");
        _watchRequiredSeconds = DY778SLSeconds(dictionary, @"watchRequiredSeconds");
        _watchTaskKey = DY778SLText(DY778SLValue(dictionary, @"watchTaskKey")) ?: @"";
        _watchAdmitted = DY778SLFlag(dictionary, @"watchAdmitted");
        _hasParticipated = DY778SLFlag(dictionary, @"hasParticipated");
        _taskID = DY778SLText(DY778SLValue(dictionary, @"task_id")) ?: @"";
        _taskType = DY778SLText(DY778SLValue(dictionary, @"task_type")) ?: @"";
        _taskState = DY778SLText(DY778SLValue(dictionary, @"task_state")) ?: @"";
        _reason = DY778SLText(DY778SLValue(dictionary, @"reason")) ?: DY778SLText(DY778SLValue(dictionary, @"reasonText")) ?: @"";
    }
    return self;
}
- (BOOL)watchTimeInsufficient {
    return _watchRequiredSeconds > 0 && _watchRemainingSeconds > 0 && _watchRemainingSeconds < _watchRequiredSeconds;
}
- (BOOL)expired {
    NSString *state = _taskState.lowercaseString;
    NSString *reason = _reason.lowercaseString;
    return [state isEqualToString:@"expired"] || [reason containsString:@"expired"] || [reason containsString:@"已过期"] || [reason containsString:@"过期"];
}
@end

// ---------- 原生请求（规格 §4.4；1.1-2 逆向修正） ----------
// 1.1-2 实证路径：IESLiveCommonNetworkRequester + IESLiveJSNetworkJsonRequest，
// 逐键动态 setter（set<Key>:，首字母大写），request:numToString:callback:。
// 请求 dict {url, method:GET, version:v1, params, data}；params 按命令过滤：
// participate 只留 task_ids/room_id/activity_id/has_participate/task_activity_id。
// 类或方法缺失时回退旧 NSURLSession POST（未证实服务端接受，仅兜底）。
static NSError *DY778SLNativeError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"DY778.SuperLucky.Native" code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @""}];
}
static NSDictionary *DY778SLNativeParseResponse(id value) {
    if ([value isKindOfClass:NSDictionary.class]) return value;
    if ([value isKindOfClass:NSData.class] && ((NSData *)value).length) {
        id json = [NSJSONSerialization JSONObjectWithData:value options:0 error:nil];
        if ([json isKindOfClass:NSDictionary.class]) return json;
    }
    if ([value isKindOfClass:NSString.class] && ((NSString *)value).length) {
        id json = [NSJSONSerialization JSONObjectWithData:[(NSString *)value dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if ([json isKindOfClass:NSDictionary.class]) return json;
    }
    return nil;
}
// 原生回调参数诊断：记录最近一次回调两参的形态（小整数 / 类名），导出可见。
static NSString *DY778SLLastCallbackArgs = nil;
static NSString *DY778SLDescribeArg(void *ptr) {
    uintptr_t value = (uintptr_t)ptr;
    if (!ptr) return @"nil";
    if (value < 0x1000) return [NSString stringWithFormat:@"int:%lu", (unsigned long)value];
    @try {
        return NSStringFromClass(object_getClass((__bridge id)ptr)) ?: @"?";
    } @catch (__unused NSException *exception) { return @"bad-ptr"; }
}
static id DY778SLObjectArg(void *ptr) {
    uintptr_t value = (uintptr_t)ptr;
    if (!ptr || value < 0x1000) return nil;
    return (__bridge id)ptr;
}
// 响应成功判定：键缺失不算成功（旧版 [nil integerValue]==0 把无 code/status
// 的响应误判为成功，participated 可能是假成功）。响应摘要按命令分别记入
// 诊断，导出可见服务端到底回了什么。
static NSMutableDictionary *DY778SLResponseSummaries = nil;
static NSString *DY778SLLastCandidate = nil;
static NSString *DY778SLLastTaskInfo = nil;
static NSString *DY778SLLastDetailKeys = nil;
static BOOL DY778SLResponseOK(NSDictionary *response) {
    if (![response isKindOfClass:NSDictionary.class]) return NO;
    if ([response[@"succeed"] boolValue]) return YES;
    if (response[@"status_code"] && [response[@"status_code"] integerValue] == 200) return YES;
    if (response[@"code"] && [response[@"code"] integerValue] == 0) return YES;
    if (response[@"status"] && [response[@"status"] integerValue] == 0) return YES;
    return NO;
}
static void DY778SLRecordResponse(NSString *command, NSDictionary *response, NSError *error) {
    if (!DY778SLResponseSummaries) DY778SLResponseSummaries = [NSMutableDictionary dictionary];
    if (error) {
        DY778SLResponseSummaries[command] = [NSString stringWithFormat:@"error:%@", error.localizedDescription ?: @""];
        return;
    }
    if (![response isKindOfClass:NSDictionary.class]) {
        DY778SLResponseSummaries[command] = @"(no-dict)";
        return;
    }
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *key in @[@"code", @"status", @"status_code", @"succeed", @"message", @"status_message", @"msg"]) {
        id value = response[key];
        if (value) [parts addObject:[NSString stringWithFormat:@"%@=%@", key, value]];
    }
    if (!parts.count) [parts addObject:[NSString stringWithFormat:@"keys=%@", [response.allKeys componentsJoinedByString:@","]]];
    DY778SLResponseSummaries[command] = [parts componentsJoinedByString:@" "];
    if ([command isEqualToString:@"detail"]) {
        // detail 响应结构转储：顶层键 + data/result 子键（任务信息到底在哪一层）。
        NSMutableArray *keyParts = [NSMutableArray arrayWithObject:[NSString stringWithFormat:@"top=%@", [response.allKeys componentsJoinedByString:@","]]];
        for (NSString *nestKey in @[@"data", @"result"]) {
            id nested = response[nestKey];
            if ([nested isKindOfClass:NSDictionary.class]) {
                [keyParts addObject:[NSString stringWithFormat:@"%@=%@", nestKey, [((NSDictionary *)nested).allKeys componentsJoinedByString:@","]]];
            } else if ([nested isKindOfClass:NSArray.class]) {
                [keyParts addObject:[NSString stringWithFormat:@"%@=[%lu]", nestKey, (unsigned long)((NSArray *)nested).count]];
            }
        }
        NSString *dump = [keyParts componentsJoinedByString:@" "];
        DY778SLLastDetailKeys = dump.length > 400 ? [dump substringToIndex:400] : dump;
    }
}

@implementation DY778SLNativeCall
- (void)finish:(NSDictionary *)response error:(NSError *)error {
    if (_finished) return;
    _finished = YES;
    _keeper = nil;
    void (^callback)(NSDictionary *, NSError *) = _response;
    _response = nil;
    if (callback) callback(response, error);
}
- (NSDictionary *)DY778SLRequestDictionary:(NSString *)command activity:(NSString *)activityID room:(NSString *)roomID params:(NSDictionary *)params {
    NSMutableDictionary *filtered = [NSMutableDictionary dictionary];
    if (roomID.length) filtered[@"room_id"] = roomID;
    if (activityID.length) filtered[@"activity_id"] = activityID;
    if ([command isEqualToString:@"participate"]) {
        for (NSString *key in @[@"task_ids", @"has_participate", @"task_activity_id"]) {
            if (params[key]) filtered[key] = params[key];
        }
    } else {
        for (NSString *key in @[@"task_id", @"task_type", @"task_activity_id", @"b_type_new", @"sub_b_type", @"sec_shop_id", @"extra"]) {
            if (params[key]) filtered[key] = params[key];
        }
        if (!filtered[@"scene"]) filtered[@"scene"] = @"1";
    }
    NSString *urlString = [NSString stringWithFormat:@"https://lianmengapi.snssdk.com/live/lottery/%@/", command ?: @"detail"];
    return @{@"url": urlString, @"method": @"GET", @"version": @"v1",
             @"params": [filtered copy], @"data": @{}};
}
- (BOOL)DY778SLSendNative:(NSDictionary *)requestDictionary {
    Class requesterClass = NSClassFromString(@"IESLiveCommonNetworkRequester");
    Class jsonRequestClass = NSClassFromString(@"IESLiveJSNetworkJsonRequest");
    if (!requesterClass || !jsonRequestClass) return NO;
    id requester = nil, jsonRequest = nil;
    @try {
        requester = [requesterClass new];
        jsonRequest = [jsonRequestClass new];
    } @catch (__unused NSException *exception) { return NO; }
    if (!requester || !jsonRequest) return NO;
    // 逐键动态 setter：set<CapitalizedKey>:（与 1.1-2 同款）。
    for (NSString *key in requestDictionary) {
        if (!key.length) continue;
        NSString *setterName = [NSString stringWithFormat:@"set%@%@:",
                                [[key substringToIndex:1] uppercaseString], [key substringFromIndex:1]];
        SEL setter = NSSelectorFromString(setterName);
        if (![jsonRequest respondsToSelector:setter]) continue;
        @try {
            ((void (*)(id, SEL, id))objc_msgSend)(jsonRequest, setter, requestDictionary[key]);
        } @catch (__unused NSException *exception) { }
    }
    SEL sendSelector = NSSelectorFromString(@"request:numToString:callback:");
    if (![requester respondsToSelector:sendSelector]) return NO;
    Method method = class_getInstanceMethod(requesterClass, sendSelector);
    if (!method) return NO;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    // 期望 (id, BOOL/c, block)；签名不符则不走原生路径（防崩）。
    if (signature.numberOfArguments != 5) return NO;
    char second = [signature getArgumentTypeAtIndex:3][0];
    if (second != 'B' && second != 'c') return NO;
    _keeper = @[requester, jsonRequest];
    _started = YES;
    __weak typeof(self) weakSelf = self;
    // 回调签名防御（2026-11-28 真机崩溃定案）：原生回调首参实为 BOOL/状态码小整数，
    // 旧版按 ^(id, id) 声明，ARC 在块入口 retain 首参（0x1）直接 EXC_BAD_ACCESS 崩。
    // 改按 void* 收参：小整数不当对象，其余按对象解析（响应 dict / NSError 任意位置）。
    void (^callback)(void *, void *) = ^(void *first, void *second) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        DY778SLLastCallbackArgs = [NSString stringWithFormat:@"%@,%@",
            DY778SLDescribeArg(first), DY778SLDescribeArg(second)];
        if (!strongSelf) return;
        NSError *failure = nil;
        NSDictionary *parsed = nil;
        @try {
            id firstObject = DY778SLObjectArg(first);
            id secondObject = DY778SLObjectArg(second);
            if ([secondObject isKindOfClass:NSError.class]) failure = secondObject;
            if ([firstObject isKindOfClass:NSError.class]) failure = firstObject;
            parsed = DY778SLNativeParseResponse(firstObject) ?: DY778SLNativeParseResponse(secondObject);
            if (!parsed && !failure && (uintptr_t)first < 0x1000 && (uintptr_t)first == 0) {
                failure = DY778SLNativeError(-3, @"native callback reported failure");
            }
        } @catch (__unused NSException *exception) {
            failure = DY778SLNativeError(-4, @"native callback parse exception");
        }
        if (!parsed && !failure) failure = DY778SLNativeError(-2, @"empty response");
        [strongSelf finish:parsed error:failure];
    };
    @try {
        ((void (*)(id, SEL, id, BOOL, id))objc_msgSend)(requester, sendSelector, jsonRequest, YES, callback);
    } @catch (__unused NSException *exception) {
        return NO;
    }
    return YES;
}
- (void)DY778SLFallbackPost:(NSDictionary *)requestDictionary completion:(void (^)(NSDictionary *response, NSError *error))completion {
    // 旧路径兜底：NSURLSession POST 到同一 URL（未证实服务端接受）。
    NSURL *url = [NSURL URLWithString:requestDictionary[@"url"]];
    if (!url) { if (completion) completion(nil, DY778SLNativeError(-1, @"bad request")); return; }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:requestDictionary options:0 error:nil];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) { if (completion) completion(nil, error); return; }
        NSDictionary *json = DY778SLNativeParseResponse(data) ?: @{};
        NSMutableDictionary *result = [json mutableCopy];
        if ([response isKindOfClass:NSHTTPURLResponse.class]) result[@"status_code"] = @(((NSHTTPURLResponse *)response).statusCode);
        result[@"via"] = @"fallback";
        if (completion) completion([result copy], nil);
    }];
    [task resume];
}
- (void)command:(NSString *)command activity:(NSString *)activityID room:(NSString *)roomID params:(NSDictionary *)params completion:(void (^)(NSDictionary *response, NSError *error))completion {
    if (!command.length) command = @"detail";
    _room = [roomID copy];
    _response = [completion copy];
    _finished = NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:[NSString stringWithUTF8String:DY778SLNativeRequestStartedNotification] object:nil
                                                      userInfo:@{@"command": command, @"activityID": activityID ?: @"", @"roomID": roomID ?: @""}];
    NSDictionary *requestDictionary = [self DY778SLRequestDictionary:command activity:activityID room:roomID params:params];
    if ([self DY778SLSendNative:requestDictionary]) return;
    // 原生路径不可用：回退旧 POST，完成后经 finish 收口（与原生同出口）。
    __weak typeof(self) weakSelf = self;
    [self DY778SLFallbackPost:requestDictionary completion:^(NSDictionary *response, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) [strongSelf finish:response error:error];
        else if (completion) completion(response, error);
    }];
}
- (void)postActivity:(NSString *)activityID room:(NSString *)roomID task:(NSDictionary *)task completion:(void (^)(NSDictionary *response, NSError *error))completion {
    [self command:@"detail" activity:activityID room:roomID params:task completion:completion];
}
- (void)executeTask:(NSString *)taskID activity:(NSString *)activityID room:(NSString *)roomID completion:(void (^)(NSDictionary *response, NSError *error))completion {
    NSDictionary *params = @{@"task_id": taskID ?: @"", @"task_activity_id": activityID ?: @""};
    [self command:@"execute_task" activity:activityID room:roomID params:params completion:completion];
}
@end

// ---------- 领取目标与记录 ----------
@implementation DY778SLOTarget
- (instancetype)initWithActivity:(NSString *)activityID room:(NSString *)roomID task:(NSString *)taskID {
    if ((self = [super init])) {
        _activityID = [activityID copy]; _roomID = [roomID copy]; _taskID = [taskID copy];
    }
    return self;
}
@end

@implementation DY778SLRecords
+ (NSArray<NSDictionary *> *)records {
    id records = [DY778Preferences() objectForKey:@"superLucky.records"];
    if (![records isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *valid = [NSMutableArray array];
    for (id record in records) if ([record isKindOfClass:NSDictionary.class]) [valid addObject:record];
    return [valid copy];
}
+ (void)rememberRecord:(NSDictionary *)record status:(NSString *)status {
    if (![record isKindOfClass:NSDictionary.class]) return;
    NSMutableDictionary *entry = [record mutableCopy];
    if (status.length) entry[@"status"] = status;
    entry[@"at"] = @([[NSDate date] timeIntervalSince1970]);
    NSMutableArray *records = [[self records] mutableCopy];
    NSString *activityID = DY778SLText(entry[@"activityID"]) ?: DY778SLText(entry[@"activity_id"]);
    // 最新一条已是同活动同状态时跳过写盘（watch/expired 路径每拍都会调，
    // 避免每 5 秒重写偏好造成卡顿）。
    if (activityID.length && records.count) {
        NSDictionary *newest = records.firstObject;
        NSString *newestID = DY778SLText(newest[@"activityID"]) ?: DY778SLText(newest[@"activity_id"]);
        if ([newestID isEqualToString:activityID] && [DY778SLText(newest[@"status"]) isEqualToString:DY778SLText(entry[@"status"])]) return;
    }
    if (activityID.length) {
        NSMutableArray *kept = [NSMutableArray array];
        for (NSDictionary *old in records) {
            NSString *oldID = DY778SLText(old[@"activityID"]) ?: DY778SLText(old[@"activity_id"]);
            if (oldID.length && [oldID isEqualToString:activityID] && [DY778SLText(old[@"status"]) isEqualToString:DY778SLText(entry[@"status"])]) continue;
            [kept addObject:old];
        }
        records = kept;
    }
    [records insertObject:[entry copy] atIndex:0];
    while (records.count > DY778SLMaximumRecords) [records removeLastObject];
    [DY778Preferences() setObject:[records copy] forKey:@"superLucky.records"];
}
+ (BOOL)hasParticipatedActivity:(NSString *)activityID {
    if (!activityID.length) return NO;
    for (NSDictionary *record in [self records]) {
        NSString *recordID = DY778SLText(record[@"activityID"]) ?: DY778SLText(record[@"activity_id"]);
        if (![recordID isEqualToString:activityID]) continue;
        NSString *status = DY778SLText(record[@"status"]);
        if ([status isEqualToString:@"participated"] || [status isEqualToString:@"submitted"] || [status isEqualToString:@"succeed"]) return YES;
    }
    return NO;
}
@end

// ---------- 开奖提醒记录（规格 §9.3：键归模块 3，行为归模块 4） ----------
// 模块 3 只做记录键的写入（recordStage），提醒的到点弹窗/通知实现
// 留给模块 4，不得在本模块重复实现。
void DY778SLRecordStage(NSString *message) {
    if (!message.length) return;
    [DY778SLRecords rememberRecord:@{@"kind": @"stage", @"message": message} status:@"stage"];
}

// ---------- 状态机：DY778SLCoordinator（规格 §4.1，50 方法的精简复刻） ----------
@interface DY778SLCoordinator ()
@property(nonatomic, strong) DY778SLAuto *automatic;
@property(nonatomic, strong) DY778SLNativeCall *nativeCall;
@property(nonatomic, copy) NSString *currentActivityID;
@property(nonatomic, strong) DY778SLTaskContext *taskContext;
@property(nonatomic) NSUInteger groupFailures;
// 1.1-2 发现/流程状态（诊断段读）。
@property(nonatomic) NSTimeInterval lastDiscoveryAt;
@property(nonatomic, copy) NSString *lastDiscoverySource;
@property(nonatomic, copy) NSString *lastCommand;
@property(nonatomic, copy) NSString *lastResult;
@property(nonatomic) BOOL requestInFlight;
@property(nonatomic) NSTimeInterval activatedAt;
@property(nonatomic, copy) NSString *entryRoomID;
- (id)DY778SLFindEntryButtonInView:(UIView *)view depth:(NSUInteger)depth;
- (NSDictionary *)DY778SLDiscoverCandidate;
- (void)DY778SLRunDiscoveryFlow;
@end

@implementation DY778SLCoordinator
+ (instancetype)shared {
    static DY778SLCoordinator *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[DY778SLCoordinator alloc] init]; });
    return shared;
}
- (instancetype)init {
    if ((self = [super init])) {
        _nativeCall = [[DY778SLNativeCall alloc] init];
        _automatic = [[DY778SLAuto alloc] initWithCoordinator:self];
    }
    return self;
}
- (BOOL)canRun {
    if (!DY778SuperLuckyEnabled()) return NO;
    if (!_roomActive || !_roomID.length) return NO;
    if (DY778LuckyAutomationBlocked(_host)) return NO;
    return YES;
}
- (BOOL)isViewing { return _roomActive && _host != nil; }
- (void)activate:(id)host {
    if (host) _host = host;
    NSString *roomID = DY778LiveContextRoomID(host ?: _host);
    if (roomID.length) _roomID = roomID;
    if (!_accountID.length) _accountID = DY778CurrentAccountID();
    _roomActive = YES;
    _activatedAt = [NSDate date].timeIntervalSince1970;
    // 入口搜索延后到下一轮 runloop：下滑切房转场期不做整树 DFS。
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf && strongSelf.roomActive) [strongSelf discoverEntry];
    });
    [self scheduleAutomatic];
    [[DY778SLEntry shared] refresh];
}
- (void)resign:(id)host {
    if (host && host != _host) return;
    _roomActive = NO;
    [self pauseAutomatic];
}
- (void)leave {
    _roomActive = NO;
    [self pauseAutomatic];
    [self clearState];
    [[DY778SLEntry shared] hide];
}
- (void)open {
    DY778SLPanel *panel = [[DY778SLPanel alloc] initWithCoordinator:self];
    UIViewController *presenter = DY778TopController();
    if (presenter) DY778PresentController(presenter, panel);
}
- (void)pauseAutomatic {
    [_actionTimer invalidate]; _actionTimer = nil;
    [_timer invalidate]; _timer = nil;
}
- (void)scheduleAutomatic {
    [_actionTimer invalidate]; _actionTimer = nil;
    if (![self canRun]) return;
    double delay = DY778REDelay(DY778Number(@"superLucky.delay"));
    __weak typeof(self) weakSelf = self;
    _actionTimer = [NSTimer scheduledTimerWithTimeInterval:delay repeats:NO block:^(NSTimer *timer) {
        (void)timer;
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) [strongSelf runAutomatic];
    }];
}
- (void)runAutomatic {
    if (![self canRun]) return;
    [_automatic run];
}
- (void)publishStatus {
    if (DY778Bool(@"superLucky.notifyResult")) DY778ShowToast(@"superLucky", [self displayState], NO, YES);
    [[DY778SLEntry shared] refresh];
}
- (void)tick {
    if (!DY778SuperLuckyEnabled()) return;
    if (![self canRun]) return;
    [self runAutomatic];
    [self publishStatus];
}
static NSUInteger DY778SLFindEntryVisited = 0;
- (void)discoverEntry {
    // 从房间的组件图里找福袋入口（规格 §4.5 Seeds 的 DYxs 侧简化版）：
    // 只读 host 视图层级里标题含「福袋」/lottery 的按钮并记为 button，
    // 不改任何状态、不触发点击。同房已找到过就不再整树搜索；单次搜索
    // 访问节点上限 600，避免直播间大视图树在切房时卡主线程。
    if (_button && _roomID.length && [_entryRoomID isEqualToString:_roomID]) return;
    UIView *view = nil;
    if ([_host isKindOfClass:UIViewController.class]) view = ((UIViewController *)_host).view;
    else if ([_host isKindOfClass:UIView.class]) view = _host;
    if (!view) return;
    DY778SLFindEntryVisited = 0;
    _button = [self DY778SLFindEntryButtonInView:view depth:0];
    if (_button) _entryRoomID = [_roomID copy];
}
- (id)DY778SLFindEntryButtonInView:(UIView *)view depth:(NSUInteger)depth {
    if (!view || depth > 8 || view.hidden) return nil;
    if (++DY778SLFindEntryVisited > 600) return nil;
    if ([view isKindOfClass:UIButton.class]) {
        NSString *title = [((UIButton *)view) titleForState:UIControlStateNormal] ?: @"";
        NSString *lower = title.lowercaseString;
        if ([title containsString:@"福袋"] || [lower containsString:@"lottery"] || [lower containsString:@"lucky"]) return view;
    }
    for (UIView *subview in view.subviews) {
        id found = [self DY778SLFindEntryButtonInView:subview depth:depth + 1];
        if (found) return found;
    }
    return nil;
}
- (void)clearState {
    _roomID = nil; _accountID = nil; _roomTitle = nil;
    _currentActivityID = nil; _taskContext = nil; _visit = 0;
    _groupFailures = 0;
    _lastDiscoveryAt = 0; _lastDiscoverySource = nil;
    _lastCommand = nil; _lastResult = nil; _requestInFlight = NO;
}
// ---------- 发现（1.1-2 Seeds 移植，2026-11-27） ----------
// 两条线索：① RE 的 BDX 路由记录（DY778LastLotteryBDXURL，电商间面板
// URL 自带 activity_id/room_id，10:51 导出实证）；② 组件图 BFS
// （componentLoader/realLoader/componentProcess/componentMaps/components/
// store → shortTouchAreaConfig/elements/items），找 activity_id。
// 只读不改状态；预算封顶，失败返回 nil。
static NSString *DY778SLQueryValue(NSString *text, NSString *key) {
    if (!text.length || !key.length) return nil;
    NSString *needle = [key stringByAppendingString:@"="];
    NSRange range = [text rangeOfString:needle];
    if (range.location == NSNotFound) return nil;
    NSString *rest = [text substringFromIndex:range.location + range.length];
    NSCharacterSet *stop = [NSCharacterSet characterSetWithCharactersInString:@"&\"' <>\n"];
    NSRange end = [rest rangeOfCharacterFromSet:stop];
    NSString *value = end.location == NSNotFound ? rest : [rest substringToIndex:end.location];
    return value.length ? [value stringByRemovingPercentEncoding] ?: value : nil;
}
- (NSDictionary *)DY778SLDiscoverCandidate {
    // 线索 ①：BDX 福袋 URL。
    NSString *bdxURL = DY778LastLotteryBDXURL();
    if (bdxURL.length) {
        NSString *activityID = DY778SLQueryValue(bdxURL, @"activity_id") ?: DY778SLQueryValue(bdxURL, @"activityId") ?: DY778SLQueryValue(bdxURL, @"lottery_id");
        NSString *roomID = DY778SLQueryValue(bdxURL, @"room_id") ?: DY778SLQueryValue(bdxURL, @"roomId");
        if (activityID.length) {
            return @{@"activityID": activityID, @"roomID": roomID ?: _roomID ?: @"", @"source": @"bdx"};
        }
    }
    // 线索 ②：组件图 BFS（Seeds）。KVC 遍历主线程开销大，单独 120 秒节流，
    // 预算 80，避免超级福袋房间掉帧/切房卡顿。
    if (!_host) return nil;
    static NSTimeInterval lastSeedsAt = 0;
    NSTimeInterval seedsNow = [NSDate date].timeIntervalSince1970;
    if (seedsNow - lastSeedsAt < 120) return nil;
    lastSeedsAt = seedsNow;
    static NSArray<NSString *> *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = @[@"componentLoader", @"realLoader", @"componentProcess", @"componentMaps",
                 @"components", @"store", @"roomDI", @"roomGuarder", @"roomModel",
                 @"shortTouchAreaConfig", @"elements", @"items", @"_dictionary",
                 @"views", @"lazyViews", @"subItemListArray", @"shortTouchURL", @"jumpSchema"];
    });
    NSMutableArray *queue = [NSMutableArray arrayWithObject:_host];
    NSHashTable *visited = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    NSUInteger budget = 80;
    while (queue.count && budget > 0) {
        id node = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (!node || [visited containsObject:node]) continue;
        [visited addObject:node];
        budget--;
        if ([node isKindOfClass:NSDictionary.class]) {
            NSDictionary *dict = node;
            NSString *activityID = DY778SLText(dict[@"activity_id"]) ?: DY778SLText(dict[@"activityID"]) ?: DY778SLText(dict[@"lottery_id"]);
            if (activityID.length) {
                NSString *roomID = DY778SLText(dict[@"room_id"]) ?: DY778SLText(dict[@"roomID"]);
                return @{@"activityID": activityID, @"roomID": roomID ?: _roomID ?: @"", @"source": @"seeds-dict"};
            }
            for (id value in dict.allValues) if (value) [queue addObject:value];
            continue;
        }
        if ([node isKindOfClass:NSArray.class]) {
            for (id value in (NSArray *)node) if (value) [queue addObject:value];
            continue;
        }
        if ([node isKindOfClass:NSString.class]) {
            NSString *text = node;
            if ([text containsString:@"activity_id"] || [text containsString:@"lottery_id"]) {
                NSString *activityID = DY778SLQueryValue(text, @"activity_id") ?: DY778SLQueryValue(text, @"lottery_id");
                if (activityID.length) {
                    NSString *roomID = DY778SLQueryValue(text, @"room_id");
                    return @{@"activityID": activityID, @"roomID": roomID ?: _roomID ?: @"", @"source": @"seeds-url"};
                }
            }
            continue;
        }
        for (NSString *key in keys) {
            id value = DY778SLValue(node, key);
            if (value && value != node) [queue addObject:value];
        }
    }
    return nil;
}
- (void)DY778SLRunDiscoveryFlow {
    if (_requestInFlight || ![self canRun]) return;
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    // 切房转场后 2 秒内不跑发现，避免转场期主线程再加负。
    if (now - _activatedAt < 2) return;
    if (now - _lastDiscoveryAt < 15) return;
    _lastDiscoveryAt = now;
    NSDictionary *candidate = [self DY778SLDiscoverCandidate];
    NSString *activityID = candidate[@"activityID"];
    if (!activityID.length) { _lastResult = @"no-candidate"; return; }
    _lastDiscoverySource = candidate[@"source"];
    DY778SLLastCandidate = [NSString stringWithFormat:@"%@ via %@", activityID, candidate[@"source"] ?: @"?"];
    _currentActivityID = activityID;
    NSString *roomID = candidate[@"roomID"];
    if (!roomID.length) roomID = _roomID;
    if ([DY778SLRecords hasParticipatedActivity:activityID]) { _lastResult = @"already-participated"; return; }
    _requestInFlight = YES;
    _lastCommand = @"detail";
    __weak typeof(self) weakSelf = self;
    [_nativeCall command:@"detail" activity:activityID room:roomID params:nil completion:^(NSDictionary *response, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.requestInFlight = NO;
        DY778SLRecordResponse(@"detail", response, error);
        if (error || !response.count) {
            strongSelf.lastResult = error ? [NSString stringWithFormat:@"detail-error:%@", error.localizedDescription ?: @""] : @"detail-empty";
            return;
        }
        // detail 响应里找任务上下文：task_infos_v2 / tasks / data 下同名键。
        id tasks = response[@"task_infos_v2"] ?: response[@"tasks"] ?: response[@"taskInfos"];
        if (!tasks && [response[@"data"] isKindOfClass:NSDictionary.class]) {
            NSDictionary *data = response[@"data"];
            tasks = data[@"task_infos_v2"] ?: data[@"tasks"] ?: data[@"taskInfos"];
        }
        NSMutableDictionary *context = [NSMutableDictionary dictionary];
        if ([tasks isKindOfClass:NSDictionary.class]) [context addEntriesFromDictionary:tasks];
        else if ([tasks isKindOfClass:NSArray.class] && ((NSArray *)tasks).count) {
            id first = ((NSArray *)tasks).firstObject;
            if ([first isKindOfClass:NSDictionary.class]) [context addEntriesFromDictionary:first];
            context[@"tasks"] = tasks;
        }
        context[@"activityID"] = activityID;
        context[@"activity_id"] = activityID;
        if (roomID.length) { context[@"roomID"] = roomID; context[@"room_id"] = roomID; }
        [DY778Preferences() setObject:[context copy] forKey:[NSString stringWithUTF8String:DY778SLTaskContextRecordKey]];
        DY778SLTaskContext *detailContext = [[DY778SLTaskContext alloc] initWithDictionary:context];
        DY778SLLastTaskInfo = [NSString stringWithFormat:@"taskID=%@ type=%@ state=%@ hasParticipated=%d",
            detailContext.taskID ?: @"", detailContext.taskType ?: @"", detailContext.taskState ?: @"", detailContext.hasParticipated];
        strongSelf.lastResult = @"detail-ok";
        [strongSelf.automatic performBoundTask:[context copy]];
    }];
}
- (NSString *)displayState {
    if (!_roomActive) return @"未在直播间";
    if (_taskContext) return [NSString stringWithFormat:@"福袋 %@ · %@", _taskContext.activityID, _taskContext.taskState];
    return @"福袋待发现";
}
@end

// ---------- 自动任务执行器：DY778SLAuto（规格 §4.1，19 方法的精简复刻） ----------
@implementation DY778SLAuto
- (instancetype)initWithCoordinator:(DY778SLCoordinator *)coordinator {
    if ((self = [super init])) _coordinator = coordinator;
    return self;
}
- (void)run {
    DY778SLCoordinator *coordinator = _coordinator;
    if (!coordinator || ![coordinator canRun]) return;
    // 任务上下文来自持久化的 DY778.superLucky.taskContext（规格 §4.2）；
    // 无上下文时走 1.1-2 发现流程（BDX URL / Seeds 组件图 → detail），
    // 不再干等 hybrid 面板（电商间不触发 G1，旧版 phase 恒 0 的根因）。
    id stored = [DY778Preferences() objectForKey:[NSString stringWithUTF8String:DY778SLTaskContextRecordKey]];
    NSDictionary *context = [stored isKindOfClass:NSDictionary.class] ? stored : nil;
    if (!context.count) {
        coordinator.taskContext = nil;
        [coordinator DY778SLRunDiscoveryFlow];
        return;
    }
    DY778SLTaskContext *taskContext = [[DY778SLTaskContext alloc] initWithDictionary:context];
    coordinator.taskContext = taskContext;
    // 存量上下文没真正发出请求（已参与/过期/观看不足/已完成）时继续走发现，
    // 否则第一场福袋的上下文会永久挡住后续新福袋（2026-11-28 导出实证：
    // activityID 停在已参与的旧场，当前 BDX 已是新场）。
    if (![self performBoundTask:context]) [coordinator DY778SLRunDiscoveryFlow];
}
- (BOOL)performBoundTask:(NSDictionary *)task {
    DY778SLCoordinator *coordinator = _coordinator;
    if (!coordinator || ![coordinator canRun]) return NO;
    DY778SLParticipationPlan *plan = [[DY778SLParticipationPlan alloc] initWithDictionary:task];
    DY778SLTaskContext *context = [[DY778SLTaskContext alloc] initWithDictionary:task];
    NSString *activityID = context.activityID.length ? context.activityID : plan.taskID;
    if (!activityID.length) return NO;
    if ([DY778SLRecords hasParticipatedActivity:activityID]) return NO;
    // detail 没给出任务（taskID 为空）时不发 execute/participate：空任务的
    // participate 服务端回 code=0 但并不真参与（2026-11-28 导出实证，面板
    // 仍显示未参与），记 no-task 等下轮 detail，不写假 participated。
    if (!context.taskID.length) {
        [DY778SLRecords rememberRecord:@{@"activityID": activityID, @"reason": @"no-task"} status:@"no-task"];
        coordinator.lastResult = @"detail-no-task";
        return NO;
    }
    // 加入粉丝团类任务默认跳过（用户 2026-11-28 定；superLucky.skipFansClub
    // 缺省即开，显式关才参与）。
    BOOL skipFansClub = ![DY778Preferences() objectForKey:@"superLucky.skipFansClub"] || DY778Bool(@"superLucky.skipFansClub");
    if (skipFansClub && [context.taskType.lowercaseString containsString:@"fans"]) {
        [DY778SLRecords rememberRecord:@{@"activityID": activityID, @"taskID": context.taskID, @"reason": @"fans-club"} status:@"skipped-fans-club"];
        coordinator.lastResult = @"skipped-fans-club";
        return NO;
    }
    if ([plan expired]) {
        [DY778SLRecords rememberRecord:@{@"activityID": activityID, @"taskID": context.taskID, @"reason": @"expired"} status:@"skipped"];
        return NO;
    }
    if ([plan watchTimeInsufficient]) {
        // 观看时长不足：只记 watch-time-insufficient，不伪造观看完成
        // （规格 §11.10）。等用户真实观看满时长、任务上下文更新后再试。
        [DY778SLRecords rememberRecord:@{@"activityID": activityID, @"taskID": context.taskID,
                                          @"watchRemainingSeconds": @(plan.watchRemainingSeconds),
                                          @"watchRequiredSeconds": @(plan.watchRequiredSeconds)} status:@"watch-time-insufficient"];
        return NO;
    }
    if (context.complete) {
        [DY778SLRecords rememberRecord:@{@"activityID": activityID, @"taskID": context.taskID} status:@"participated"];
        return NO;
    }
    // 其余任务类型（关注/加团/送礼等）是否须真实操作未证实（规格 §11.10）：
    // autoFollow 关时不自动关注；其余一律不代做，只调 execute_task 参与
    // 接口——服务端是否接受此调用未证实，失败记 record 不再重试。
    // 1.1-2 流程：execute_task 成功后补 participate（task_ids）。
    coordinator.lastCommand = @"execute_task";
    __weak typeof(self) weakSelf = self;
    [coordinator.nativeCall executeTask:context.taskID activity:activityID room:coordinator.roomID completion:^(NSDictionary *response, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        DY778SLRecordResponse(@"execute_task", response, error);
        if (error) {
            coordinator.lastResult = [NSString stringWithFormat:@"execute-error:%@", error.localizedDescription ?: @""];
            [DY778SLRecords rememberRecord:@{@"activityID": activityID, @"taskID": context.taskID,
                                              @"error": error.localizedDescription ?: @""} status:@"failed"];
            return;
        }
        BOOL ok = DY778SLResponseOK(response);
        coordinator.lastResult = ok ? @"execute-ok" : @"execute-rejected";
        [DY778SLRecords rememberRecord:@{@"activityID": activityID, @"taskID": context.taskID} status:ok ? @"submitted" : @"failed"];
        if (!ok) return;
        [coordinator publishStatus];
        coordinator.lastCommand = @"participate";
        NSDictionary *params = @{@"task_ids": context.taskID ?: @"",
                                 @"task_activity_id": activityID,
                                 @"has_participate": @NO};
        [coordinator.nativeCall command:@"participate" activity:activityID room:coordinator.roomID params:params completion:^(NSDictionary *joinResponse, NSError *joinError) {
            DY778SLRecordResponse(@"participate", joinResponse, joinError);
            if (joinError) {
                coordinator.lastResult = [NSString stringWithFormat:@"participate-error:%@", joinError.localizedDescription ?: @""];
                return;
            }
            BOOL joined = DY778SLResponseOK(joinResponse);
            coordinator.lastResult = joined ? @"participated" : @"participate-rejected";
            if (joined) {
                [DY778SLRecords rememberRecord:@{@"activityID": activityID, @"taskID": context.taskID} status:@"participated"];
                coordinator.currentActivityID = activityID;
                coordinator.taskContext = context;
                // 已参与的活动清掉存量上下文，避免挡住下一场发现。
                id stored = [DY778Preferences() objectForKey:[NSString stringWithUTF8String:DY778SLTaskContextRecordKey]];
                if ([stored isKindOfClass:NSDictionary.class]) {
                    DY778SLTaskContext *storedContext = [[DY778SLTaskContext alloc] initWithDictionary:stored];
                    if ([storedContext.activityID isEqualToString:activityID]) {
                        [DY778Preferences() removeObjectForKey:[NSString stringWithUTF8String:DY778SLTaskContextRecordKey]];
                    }
                }
                [coordinator publishStatus];
            }
        }];
    }];
    return YES;
}
- (void)stop { [_coordinator pauseAutomatic]; }
@end

// ---------- 组心跳（规格 §4.7） ----------
// 读 superLucky.enabled/delay；受 SL 的 4 门控约束（与模块 1 的接口）；
// 原版另调 _DY778SLNativeGroupFragment / _DY778SLNativeTaskContext /
// _DY778SLPushTaskContext / _DY778SLOPerformBoundTask /
// _DY778SLRestoreTaskContext——这些是抖音内部原生调用，DYxs 侧无对应
// 接口，改由 coordinator tick + auto runner 驱动；连续失败达上限即停。
void DY778SLGroupTick(void) {
    if (!DY778SuperLuckyEnabled()) return;
    DY778SLCoordinator *coordinator = [DY778SLCoordinator shared];
    if (DY778LuckyAutomationBlocked(coordinator.host)) return;
    if (![coordinator canRun]) return;
    @try {
        [coordinator tick];
        coordinator.groupFailures = 0;
    } @catch (__unused NSException *exception) {
        coordinator.groupFailures += 1;
        if (coordinator.groupFailures >= DY778SLMaximumGroupFailures) [coordinator pauseAutomatic];
    }
    // 下一拍：5 秒后（规格 §4.7 的组心跳间隔，DYxs 侧保守设定）。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(DY778SLGroupTickSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (DY778SuperLuckyEnabled()) DY778SLGroupTick();
    });
}

// ---------- 摇一摇导出诊断段 ----------
NSString *DY778SLDiagnosticsText(void) {
    DY778SLCoordinator *coordinator = [DY778SLCoordinator shared];
    NSMutableString *text = [NSMutableString stringWithString:@"\n=== DY778 super lucky diagnostics ===\n"];
    [text appendFormat:@"enabled=%d roomActive=%d canRun=%d\n",
        DY778SuperLuckyEnabled(), coordinator.roomActive, [coordinator canRun]];
    [text appendFormat:@"roomID=%@ accountID=%@\n", coordinator.roomID ?: @"(nil)", coordinator.accountID ?: @"(nil)"];
    [text appendFormat:@"activityID=%@ taskState=%@\n",
        coordinator.taskContext.activityID ?: coordinator.currentActivityID ?: @"(nil)",
        coordinator.taskContext.taskState ?: @"(nil)"];
    [text appendFormat:@"discoverySource=%@ lastCommand=%@ lastResult=%@ inFlight=%d\n",
        coordinator.lastDiscoverySource ?: @"(none)", coordinator.lastCommand ?: @"(none)",
        coordinator.lastResult ?: @"(none)", coordinator.requestInFlight];
    [text appendFormat:@"bdxLotteryURL=%@\n", DY778LastLotteryBDXURL() ?: @"(nil)"];
    [text appendFormat:@"lastCallbackArgs=%@\n", DY778SLLastCallbackArgs ?: @"(none)"];
    for (NSString *command in @[@"detail", @"execute_task", @"participate"]) {
        NSString *summary = DY778SLResponseSummaries[command];
        if (summary) [text appendFormat:@"lastResponse.%@=%@\n", command, summary];
    }
    [text appendFormat:@"lastCandidate=%@\n", DY778SLLastCandidate ?: @"(none)"];
    [text appendFormat:@"lastTaskInfo=%@\n", DY778SLLastTaskInfo ?: @"(none)"];
    [text appendFormat:@"lastDetailKeys=%@\n", DY778SLLastDetailKeys ?: @"(none)"];
    NSArray *recentRecords = [DY778SLRecords records];
    NSUInteger shown = MIN((NSUInteger)3, recentRecords.count);
    for (NSUInteger index = 0; index < shown; index++) {
        NSDictionary *record = recentRecords[index];
        [text appendFormat:@"record[%lu]=%@ %@ at=%.0f\n", (unsigned long)index,
            DY778SLText(record[@"activityID"]) ?: DY778SLText(record[@"activity_id"]) ?: @"?",
            DY778SLText(record[@"status"]) ?: @"?",
            [record[@"at"] doubleValue]];
    }
    [text appendFormat:@"records=%lu groupFailures=%lu\n",
        (unsigned long)[DY778SLRecords records].count, (unsigned long)coordinator.groupFailures];
    return [text copy];
}

// ---------- 面板 / 历史 / 入口 ----------
@interface DY778SLPanel () <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, strong) DY778SLCoordinator *coordinator;
@property(nonatomic, strong) UITableView *tableView;
@end

@implementation DY778SLPanel
- (instancetype)initWithCoordinator:(DY778SLCoordinator *)coordinator {
    if ((self = [super init])) _coordinator = coordinator ?: [DY778SLCoordinator shared];
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"超级福袋";
    DY778StyleController(self);
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.dataSource = self; _tableView.delegate = self;
    [self.view addSubview:_tableView];
}
- (void)refresh { [_tableView reloadData]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return 1;
    return MAX(1, (NSInteger)[DY778SLRecords records].count);
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return section == 0 ? @"当前福袋" : @"参与记录";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DY778SLCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"DY778SLCell"];
    if (indexPath.section == 0) {
        cell.textLabel.text = [_coordinator displayState];
        cell.detailTextLabel.text = @"观看任务须真实停留，DYxs 不伪造观看时长";
    } else {
        NSArray *records = [DY778SLRecords records];
        if (!records.count) { cell.textLabel.text = @"暂无记录"; cell.detailTextLabel.text = @""; }
        else {
            NSDictionary *record = records[indexPath.row];
            cell.textLabel.text = DY778SLText(record[@"activityID"]) ?: DY778SLText(record[@"activity_id"]) ?: DY778SLText(record[@"message"]) ?: @"未知福袋";
            cell.detailTextLabel.text = DY778SLText(record[@"status"]) ?: @"";
        }
    }
    return cell;
}
@end

@interface DY778SLHistoryController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation DY778SLHistoryController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"福袋记录";
    DY778StyleController(self);
    UITableView *tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tableView.dataSource = self; tableView.delegate = self;
    [self.view addSubview:tableView];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return MAX(1, (NSInteger)[DY778SLRecords records].count);
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DY778SLHistoryCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"DY778SLHistoryCell"];
    NSArray *records = [DY778SLRecords records];
    if (!records.count) { cell.textLabel.text = @"暂无记录"; cell.detailTextLabel.text = @""; return cell; }
    NSDictionary *record = records[indexPath.row];
    cell.textLabel.text = DY778SLText(record[@"activityID"]) ?: DY778SLText(record[@"activity_id"]) ?: DY778SLText(record[@"message"]) ?: @"未知福袋";
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:[record[@"at"] doubleValue]];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"MM-dd HH:mm:ss";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", DY778SLText(record[@"status"]) ?: @"", [formatter stringFromDate:date]];
    return cell;
}
@end

// ---------- 入口悬浮按钮 ----------
@interface DY778SLEntry ()
@property(nonatomic, strong) UIButton *button;
@end

@implementation DY778SLEntry
+ (instancetype)shared {
    static DY778SLEntry *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[DY778SLEntry alloc] init]; });
    return shared;
}
- (NSString *)DY778SLEntryPosition {
    UIWindow *window = DY778ActiveWindow();
    BOOL landscape = window && window.bounds.size.width > window.bounds.size.height;
    NSString *position = DY778String(landscape ? @"superLucky.entryPosition.landscape" : @"superLucky.entryPosition.portrait");
    return DY778LiveAnalysisValidEntryPosition(position.UTF8String) ? position : @"bottom-right";
}
- (void)refresh {
    if (!DY778SuperLuckyEnabled() || !DY778Bool(@"superLucky.showEntry")) { [self hide]; return; }
    DY778SLMain(^{
        UIWindow *window = DY778ActiveWindow();
        if (!window) return;
        if (!self->_button) {
            self->_button = [UIButton buttonWithType:UIButtonTypeSystem];
            UIImage *image = [UIImage systemImageNamed:@"star.fill"];
            [self->_button setImage:image forState:UIControlStateNormal];
            self->_button.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.64];
            self->_button.tintColor = UIColor.whiteColor;
            self->_button.layer.cornerRadius = 22;
            self->_button.layer.masksToBounds = YES;
            [self->_button addTarget:self action:@selector(DY778SLEntryTapped) forControlEvents:UIControlEventTouchUpInside];
            self->_button.accessibilityLabel = @"超级福袋";
        }
        NSString *position = [self DY778SLEntryPosition];
        CGFloat margin = 16, size = 44;
        CGRect bounds = window.bounds;
        CGFloat x = [position containsString:@"left"] ? margin : bounds.size.width - margin - size;
        CGFloat y = [position containsString:@"top"] ? margin + 44 : bounds.size.height - margin - size - 44;
        self->_button.frame = CGRectMake(x, y, size, size);
        if (self->_button.superview != window) [window addSubview:self->_button];
        [window bringSubviewToFront:self->_button];
    });
}
- (void)hide {
    DY778SLMain(^{
        [self->_button removeFromSuperview];
        self->_button = nil;
    });
}
- (void)DY778SLEntryTapped {
    DY778SLPanel *panel = [[DY778SLPanel alloc] initWithCoordinator:[DY778SLCoordinator shared]];
    UIViewController *presenter = DY778TopController();
    if (presenter) DY778PresentController(presenter, panel);
}
@end

// ---------- 替换实现：SL 主安装体（S1–S4，类固定 IESLiveAudienceViewController） ----------
// 注意：S1–S4 与 RE 的 W12/W17/W16/W15 是同一类上的同一方法
// （viewDidAppear: / roomDidBecomeActive: / roomWillResignActive: /
// onStartLeaveRoomAnimation）；入口先装 RE、后装 SL，故 SL 的替换实现
// 外层包 RE 的替换实现，orig 链完整，两模块互不干扰。
// S2/S3/S4 对应 coordinator 方法的映射是推断（规格 §2.3 只说「对应状态
// 方法」，未逐一指明）：S2 → activate:，S3 → pauseAutomatic，
// S4（开始离房）→ leave。
static void DY778SLViewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (DY778SLOriginalViewDidAppear) ((void (*)(id, SEL, BOOL))DY778SLOriginalViewDidAppear)(self, _cmd, animated);
    @try { if (DY778SuperLuckyEnabled()) [[DY778SLCoordinator shared] activate:self]; } @catch (__unused NSException *exception) { }
}
static void DY778SLRoomDidBecomeActive(id self, SEL _cmd, id room) {
    if (DY778SLOriginalRoomDidBecomeActive) ((void (*)(id, SEL, id))DY778SLOriginalRoomDidBecomeActive)(self, _cmd, room);
    @try { if (DY778SuperLuckyEnabled()) [[DY778SLCoordinator shared] activate:self]; } @catch (__unused NSException *exception) { }
    (void)room;
}
static void DY778SLRoomWillResignActive(id self, SEL _cmd, id room) {
    if (DY778SLOriginalRoomWillResignActive) ((void (*)(id, SEL, id))DY778SLOriginalRoomWillResignActive)(self, _cmd, room);
    @try { if (DY778SuperLuckyEnabled()) [[DY778SLCoordinator shared] pauseAutomatic]; } @catch (__unused NSException *exception) { }
    (void)room;
}
static void DY778SLStartLeaveRoom(id self, SEL _cmd) {
    if (DY778SLOriginalStartLeaveRoom) ((void (*)(id, SEL))DY778SLOriginalStartLeaveRoom)(self, _cmd);
    @try { if (DY778SuperLuckyEnabled()) [[DY778SLCoordinator shared] leave]; } @catch (__unused NSException *exception) { }
}

// ---------- 替换实现：SLGroup（G1） ----------
static const char DY778SLHybridLotteryPanelKey;
static void DY778SLSetHybridLotteryPanel(id self, SEL _cmd, id panel) {
    if (DY778SLOriginalSetHybridLotteryPanel) ((void (*)(id, SEL, id))DY778SLOriginalSetHybridLotteryPanel)(self, _cmd, panel);
    // 原版同款：先调原 IMP，再 objc_setAssociatedObject（policy 1 =
    // OBJC_ASSOCIATION_RETAIN_NONATOMIC）。记录键 XOR 混淆静态不可读，
    // 自拟 superLucky.group.* 前缀。
    @try { objc_setAssociatedObject(self, &DY778SLHybridLotteryPanelKey, panel, OBJC_ASSOCIATION_RETAIN_NONATOMIC); } @catch (__unused NSException *exception) { }
    @try {
        if (DY778SuperLuckyEnabled() && panel) {
            // 面板到达即尝试恢复任务上下文（规格 §4.2 的 Restore 路径）：
            // 只读 panel 上的任务字段，不改状态。
            id taskInfo = DY778SLValue(panel, @"task_infos_v2") ?: DY778SLValue(panel, @"taskInfo");
            if ([taskInfo isKindOfClass:NSDictionary.class]) {
                [DY778Preferences() setObject:taskInfo forKey:[NSString stringWithUTF8String:DY778SLTaskContextRecordKey]];
            }
        }
    } @catch (__unused NSException *exception) { }
}

// ---------- 安装 ----------
void DY778InstallSLGroupHooks(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        DY778SLInstall(@"IESLiveLotteryFragment", @"setHybridLotteryPanel:", "v", "@",
                       (IMP)DY778SLSetHybridLotteryPanel, &DY778SLOriginalSetHybridLotteryPanel);
    });
}

void DY778InstallSuperLuckyHooks(void) {
    // SL 安装可在任意线程调用：非主线程 dispatch_async 到主队列重调
    // （规格 §1.3）。dispatch_once 保证只装一次。
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ DY778InstallSuperLuckyHooks(); });
        return;
    }
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // 先装 SLGroup，再装主安装体（规格 §1.3）。
        DY778InstallSLGroupHooks();
        // S1–S4：期望参数类型数组（规格 §2.3）。S4 的期望参数取自运行时
        // 全局，静态未证实（应为空数组）：按空数组校验，不过则不装。
        DY778SLInstall(@"IESLiveAudienceViewController", @"viewDidAppear:", "v", "B",
                       (IMP)DY778SLViewDidAppear, &DY778SLOriginalViewDidAppear);
        DY778SLInstall(@"IESLiveAudienceViewController", @"roomDidBecomeActive:", "v", "@",
                       (IMP)DY778SLRoomDidBecomeActive, &DY778SLOriginalRoomDidBecomeActive);
        DY778SLInstall(@"IESLiveAudienceViewController", @"roomWillResignActive:", "v", "@",
                       (IMP)DY778SLRoomWillResignActive, &DY778SLOriginalRoomWillResignActive);
        DY778SLInstall(@"IESLiveAudienceViewController", @"onStartLeaveRoomAnimation", "v", "",
                       (IMP)DY778SLStartLeaveRoom, &DY778SLOriginalStartLeaveRoom);
        // 偏好变更观察：superLucky.* 键变化时刷新入口与 coordinator。
        [NSNotificationCenter.defaultCenter addObserverForName:DY778PreferencesChangedNotification object:nil
            queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
                NSString *key = notification.userInfo[@"key"];
                if (!key.length || [key hasPrefix:@"superLucky."]) {
                    [[DY778SLCoordinator shared] tick];
                    [[DY778SLEntry shared] refresh];
                }
            }];
        // 组心跳启动（5 秒一拍，见 DY778SLGroupTick）。
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(DY778SLGroupTickSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (DY778SuperLuckyEnabled()) DY778SLGroupTick();
        });
        // 尾部取 coordinator 做 host 初始化（原版同款）。
        (void)[DY778SLCoordinator shared];
    });
}

// ---------- 未安装的 hook/通知（规格 §11.7，须在汇报里说明） ----------
// SL 安装末尾注册的 4 个 NSNotificationCenter 观察者名字取自运行时全局
// （0x3901c0、0x392ff8、0x396870、0x3901a0），静态不可恢复；DYxs 侧不
// 注册猜测的通知名。原版观察块做的两件事——pauseAutomatic + 隐藏 entry
// button、tick——改由 S3/S4 hook 与组心跳定时器驱动，功能等价，
// 不依赖通知名。须运行时抓名后才能补齐。
