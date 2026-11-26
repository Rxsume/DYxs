#import "DY778RedEnvelope.h"
#import "DY778Core.h"
#import "DY778LiveInfo.h"
#import "DY778RedEnvelopePolicy.h"
#import "DY778LiveAnalysisPolicy.h"
#import <WebKit/WebKit.h>
#import <objc/message.h>

// DY778 1.0-8 模块 3 移植：红包自动抢（RE）。
// 规格：~/workspace/plugin-merge/DY778/spec-module3-redenvelope-superlucky.md
// hook 常驻装载，行为全部由开关在调用时控制，默认全部关闭：
//   redEnvelope.enabled   总开关（关则不驱动领取）
//   redEnvelope.autoClaim 自动领取（关则只观测、不执行）
//   redEnvelope.mode      领取模式：quiet（静默）/ manual（手动点按钮）/ web（网页）
//   redEnvelope.showEntry 显示入口按钮（默认开，未证实）
//   redEnvelope.delay     领取延迟（秒，默认 3，钳制 0–30，未证实）
//   redEnvelope.haptics   触觉反馈（默认开，未证实）
//   redEnvelope.compact   紧凑展示（默认关，未证实）
//   redEnvelope.notifyResult 领取结果通知（默认关）
//   redEnvelope.prompt    提示文案开关（类型未证实）
//   redEnvelope.priority  入口优先级（未证实）
//   redEnvelope.cardX / cardY 卡片位置（未证实）
//   redEnvelope.entryPosition.portrait/.landscape 入口位置（默认右下角，未证实）
//   redEnvelope.records   领取记录（持久化）
//   lucky.* 共享键见 DY778Core.m（1.0-3 已有默认值，模块 3 不得改动，
//     只补 drawReminder/drawReminderSeconds/handled/promptDismissed/
//     records/enableNoticeShown 的默认值）。
// TODO（需真机验证，规格 §11）：
//   - 是否真能领到：只证明了原版「尝试领取」的代码路径，没有任何证据
//     证明这些调用在抖音 40.8.0 上仍能成功领取；服务端可能已改接口、
//     加签、限流或风控。真机验证前不得宣称「能抢到」。
//   - 节流/重试/退避数值未静态还原：本文件用 DY778RedEnvelopePolicy.h
//     的保守设定（默认关、延迟可配、失败即停），不是原版数值。
//   - D1 dispatchTouchEvent: 的参数类型：规格表作 `Bc / @`，
//     按正文「返回 B 参数 c」取 arg c；为防 40.8.0 上实为对象参数，
//     安装时 c 不匹配再试 @（见 DY778InstallRedEnvelopeHooks）。
//   - 1 个静默直接 hook（0x244354，类/方法动态算出）未解析：
//     DYxs 侧不安装、不猜测（见本文件末尾说明）。
//   - JS 注入脚本原文未静态还原：DY778REWebPage 按结果字段名重新设计，
//     不得声称与原版脚本一致。
//   - baseGate/actionGate 是否调 SL 的 4 个阻塞 helper 未证实：
//     按 SL 的 4 门控同款实现并标明（见 DY778RECoordinator）。
//   - 手动抢的 8 个按钮文本在抖音 40.8.0 是否一致，须真机核对。

// ---------- 签名校验（照 DY778LiveLike.m / DY778LiveAnalysis.m 的做法） ----------
static const char *DY778REType(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type ?: "";
}
static BOOL DY778REMatches(const char *result, const char *arguments, NSMethodSignature *signature) {
    if (!signature) return NO;
    if (!strchr(result, *DY778REType(signature.methodReturnType))) return NO;
    if (signature.numberOfArguments != strlen(arguments) + 2) return NO;
    for (NSUInteger i = 0; i < strlen(arguments); i++) {
        const char *actual = DY778REType([signature getArgumentTypeAtIndex:i + 2]);
        char expected = arguments[i];
        if (expected == 'B' ? !(actual[0] == 'B' || actual[0] == 'c') :
            expected == 'q' ? !(actual[0] == 'q' || actual[0] == 'Q') :
            expected == 'P' ? strcmp(actual, @encode(CGPoint)) != 0 :
            expected == '^' ? !(actual[0] == '^' || actual[0] == '@') : actual[0] != expected) return NO;
    }
    return YES;
}
static BOOL DY778RESignature(Class cls, SEL selector, const char *result, const char *arguments) {
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!method) return NO;
    return DY778REMatches(result, arguments, [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)]);
}
static void DY778REMain(dispatch_block_t block) {
    if (NSThread.isMainThread) block(); else dispatch_async(dispatch_get_main_queue(), block);
}

// ---------- 原 IMP 存储（D1–D4、W1–W31、Q1–Q9） ----------
// Q9 与 W5 是同一个方法 openGrabLuckyBoxView 的双重 hook：Q9 的 orig
// 是抖音原实现，W5 的 orig 是 Q9 的替换实现；安装顺序必须先静默后主安装
// （见 DY778InstallRedEnvelopeHooks），否则链断。
static IMP DY778REOriginalDispatchTouchEvent;          // D1
static IMP DY778REOriginalGetLynxRedEnvelopeParams;   // D2
static IMP DY778REOriginalFetchAllRedEnvelopes;       // D3
static IMP DY778REOriginalOpenHybridWithScheme;        // D4
static IMP DY778REOriginalLynxBaseViewTapped;          // W1
static IMP DY778REOriginalCreateShortTouchItem;        // W2
static IMP DY778REOriginalShortTouchIsReady;           // W3
static IMP DY778REOriginalLuckyBoxMessageReceived;     // W4
static IMP DY778REOriginalOpenGrabLuckyBoxView;        // W5（orig = Q9 替换）
static IMP DY778REOriginalRemoveShortTouchItem;        // W6
static IMP DY778REOriginalLuckyBoxBindService;         // W7
static IMP DY778REOriginalLuckyBoxSetRoomModel;        // W8
static IMP DY778REOriginalLuckyBoxSubscribeBackend;    // W9
static IMP DY778REOriginalRequestBackendData;          // W10
static IMP DY778REOriginalAudienceViewDidLayout;       // W11
static IMP DY778REOriginalAudienceViewDidAppear;       // W12
static IMP DY778REOriginalAudienceDidEnterRoom;        // W13
static IMP DY778REOriginalAudienceDidCloseRoom;        // W14
static IMP DY778REOriginalAudienceStartLeaveRoom;      // W15
static IMP DY778REOriginalAudienceRoomWillResign;      // W16
static IMP DY778REOriginalAudienceRoomDidBecomeActive; // W17
static IMP DY778REOriginalStoreComponentMount;         // W18
static IMP DY778REOriginalStoreDidUpdateRoom;          // W19
static IMP DY778REOriginalStoreSetRedEnvelopeQueue;    // W20
static IMP DY778REOriginalStoreFetchAllInRoom;         // W21
static IMP DY778REOriginalStoreSetResultArray;         // W22
static IMP DY778REOriginalFragmentSetRoom;             // W23
static IMP DY778REOriginalFragmentRemoteRoomDataReady; // W24
static IMP DY778REOriginalFragmentComponentMount;      // W25
static IMP DY778REOriginalFragmentComponentBindService;// W26
static IMP DY778REOriginalFragmentComponentUnmount;    // W27
static IMP DY778REOriginalFragmentSetStore;            // W28
static IMP DY778REOriginalFragmentShowViewWith;        // W29
static IMP DY778REOriginalFragmentShowView;            // W30
static IMP DY778REOriginalFragmentShowLynxView;        // W31
static IMP DY778REOriginalQuietPopupOpen;              // Q1（元类）
static IMP DY778REOriginalQuietPopupCreate;            // Q2（元类）
static IMP DY778REOriginalQuietPopupShowContainer;     // Q3（元类）
static IMP DY778REOriginalQuietPopupShowContainerVc;   // Q4
static IMP DY778REOriginalQuietPopupDismiss;           // Q5
static IMP DY778REOriginalQuietRouterTransition;       // Q6
static IMP DY778REOriginalQuietOpenHybridDialog;       // Q7
static IMP DY778REOriginalQuietResolveRedirectScheme;  // Q8
static IMP DY778REOriginalQuietOpenGrabLuckyBoxView;   // Q9（orig = 抖音原实现）

// ---------- 安装 helper ----------
// 记录键格式串原版 XOR 混淆静态不可读（规格 §8.4）：按模块 1/2 的
// liveTools.* / liveAnalysis.* 前缀约定自拟，不得声称与原版一致。
static void DY778REInstall(NSString *className, NSString *selector, const char *result, const char *arguments, IMP replacement, IMP *original, BOOL quiet) {
    if (*original) return;
    Class cls = NSClassFromString(className); SEL sel = NSSelectorFromString(selector);
    NSString *recordKey = [NSString stringWithFormat:@"redEnvelope.%@%@.%@", quiet ? @"quiet." : @"", className, selector];
    BOOL installed = DY778RESignature(cls, sel, result, arguments) && DY778Hook(cls, sel, replacement, original);
    DY778RecordHook(recordKey, installed);
}
// 元类方法（Q1–Q3）：object_getClass 取元类再校验与安装。
static void DY778REInstallMeta(NSString *className, NSString *selector, const char *result, const char *arguments, IMP replacement, IMP *original) {
    if (*original) return;
    Class cls = NSClassFromString(className); SEL sel = NSSelectorFromString(selector);
    NSString *recordKey = [NSString stringWithFormat:@"redEnvelope.quiet.%@.%@", className, selector];
    Class meta = cls ? object_getClass(cls) : Nil;
    BOOL installed = DY778RESignature(meta, sel, result, arguments) && DY778Hook(meta, sel, replacement, original);
    DY778RecordHook(recordKey, installed);
}

BOOL DY778RedEnvelopeEnabled(void) { return DY778Bool(@"redEnvelope.enabled"); }
BOOL DY778RedEnvelopeAutoClaim(void) { return DY778Bool(@"redEnvelope.autoClaim"); }
NSString *DY778RedEnvelopeMode(void) {
    NSString *mode = DY778String(@"redEnvelope.mode");
    return DY778REValidMode(mode.UTF8String) ? mode : @"quiet";
}

// ---------- 4 门控（规格 §4.7、§9.1，与 SL 共用） ----------
// 原版 4 个 helper 的内部逻辑未全拆；DYxs 侧按函数名与模块 1 的现有
// 状态推断实现，未证实。任一成立时自动任务不执行。
BOOL DY778LuckyLiveToolsStealthActive(void) {
    // 隐身是否激活：模块 1 的 liveTools.stealth 开关。
    return DY778Bool(@"liveTools.stealth");
}
BOOL DY778LuckyLiveIdentityBlocksAutomation(void) {
    // 游客身份是否禁止自动化：DYxs 里游客身份即由 stealth 开关驱动
    // （见 DY778LiveGuest.m），故与 StealthActive 重合；为保原版
    // 4 门控结构仍单独保留，未证实两者在原版是否确为同一条件。
    return DY778Bool(@"liveTools.stealth");
}
BOOL DY778LuckyLiveToolsOwnerIsCurrent(id host) {
    // 当前房间是否归属本账号的 LiveTools 会话：按 host 取 roomModel →
    // owner 链比对账号 ID。取不到主播信息时返回 NO（不阻断）。
    // 另一种可能读法是「LiveTools 会话归属账号仍为当前账号」，未证实。
    if (!host) return NO;
    NSString *accountID = DY778CurrentAccountID();
    if (!accountID.length) return NO;
    id roomModel = DY778Read(host, @"roomModel");
    if (!roomModel) roomModel = host;
    for (NSString *key in @[@"owner", @"anchor", @"user", @"author"]) {
        id owner = DY778Read(roomModel, key);
        if (!owner || owner == roomModel) continue;
        for (NSString *idKey in @[@"userID", @"secUserID", @"secUid", @"uid", @"idStr", @"id"]) {
            NSString *ownerID = DY778Identifier(DY778Read(owner, idKey));
            if (ownerID.length) return [ownerID isEqualToString:accountID];
        }
        NSString *ownerID = DY778Identifier(owner);
        if (ownerID.length) return [ownerID isEqualToString:accountID];
    }
    return NO;
}
BOOL DY778LuckyLiveAssistantPresentationBlocksAutomation(void) {
    // 助手面板展示是否禁止自动化：模块 3 的面板/历史正展示时不自动执行，
    // 避免自动任务与用户操作打架。按顶层控制器类名判定（推断，未证实）。
    UIViewController *top = DY778TopController();
    if (!top) return NO;
    NSString *name = NSStringFromClass(top.class);
    return [name containsString:@"DY778REPanel"] || [name containsString:@"DY778SLPanel"] ||
        [name containsString:@"DY778REHistory"] || [name containsString:@"DY778SLHistory"];
}
BOOL DY778LuckyAutomationBlocked(id host) {
    return DY778LuckyLiveToolsOwnerIsCurrent(host) || DY778LuckyLiveToolsStealthActive() ||
        DY778LuckyLiveIdentityBlocksAutomation() || DY778LuckyLiveAssistantPresentationBlocksAutomation();
}

// ---------- 房间上下文（规格 §6.3） ----------
NSString *DY778LiveContextRoomID(id object) {
    if (!object) return nil;
    NSString *identifier = DY778LiveRoomIdentifier(object);
    if (identifier.length) return identifier;
    for (NSString *key in @[@"roomModel", @"room", @"rawRoom", @"rawHTSLiveRoomModel", @"liveRoom",
                            @"currentRoom", @"roomConfig", @"roomGuarder", @"roomAisle", @"originRoom", @"owner"]) {
        id nested = DY778Read(object, key);
        if (!nested || nested == object) continue;
        identifier = DY778LiveRoomIdentifier(nested);
        if (identifier.length) return identifier;
    }
    return nil;
}

// ---------- 模型取值与条件分类（规格 §3.3、§3.7） ----------
static NSString *DY778REText(id value) {
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) return [value stringValue];
    return nil;
}
id DY778REModelValue(id model, NSString *key) {
    if (!model || !key.length) return nil;
    id value = nil;
    @try {
        if ([model isKindOfClass:NSDictionary.class]) value = model[key];
        else value = DY778Read(model, key);
    } @catch (__unused NSException *exception) { return nil; }
    return [value isKindOfClass:NSNull.class] ? nil : value;
}
BOOL DY778REModelFlag(id model, NSString *key) {
    id value = DY778REModelValue(model, key);
    if ([value isKindOfClass:NSNumber.class]) return [value boolValue];
    NSString *text = DY778REText(value);
    return text.length ? [text boolValue] : NO;
}
NSString *DY778REModelID(id model) {
    // box ID 多键名匹配（规格 §3.7 的 16 个键名中与 ID 有关的 7 个）。
    for (NSString *key in @[@"box", @"boxid", @"boxidstr", @"luckyboxid", @"redenvelopeid", @"databoxid", @"databoxidstr"]) {
        NSString *identifier = DY778Identifier(DY778REModelValue(model, key));
        if (identifier.length) return identifier;
    }
    return nil;
}
static BOOL DY778RETextContainsAny(NSString *text, const char **keywords, int count) {
    if (!text.length) return NO;
    for (int i = 0; i < count; i++) {
        NSString *keyword = [NSString stringWithUTF8String:keywords[i]];
        if (keyword.length && [text rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}
DY778REConditionCategory DY778REConditionCategoryForText(NSString *text) {
    if (!text.length) return DY778REConditionUnknown;
    if (DY778RETextContainsAny(text, DY778REFreeConditionKeywords, DY778REFreeConditionKeywordCount)) return DY778REConditionFree;
    if (DY778RETextContainsAny(text, DY778REPresentConditionKeywords, DY778REPresentConditionKeywordCount)) return DY778REConditionPresent;
    if (DY778RETextContainsAny(text, DY778REGatedConditionKeywords, DY778REGatedConditionKeywordCount)) return DY778REConditionGated;
    return DY778REConditionUnknown;
}
NSDictionary *DY778REReadResult(NSDictionary *result) {
    if (![result isKindOfClass:NSDictionary.class]) return @{};
    NSMutableDictionary *read = [NSMutableDictionary dictionary];
    id succeed = result[@"succeed"];
    if (succeed) read[@"succeed"] = @([succeed boolValue]);
    for (NSString *key in @[@"diamondCount", @"cashCount"]) {
        id value = result[key];
        if ([value respondsToSelector:@selector(longLongValue)]) read[key] = @([value longLongValue]);
    }
    for (NSString *key in @[@"giftName", @"giftId", @"box", @"text"]) {
        NSString *text = DY778REText(result[key]);
        if (text.length) read[key] = text;
    }
    return [read copy];
}
static NSArray *DY778REListModels(id list) {
    if ([list isKindOfClass:NSArray.class]) return list;
    id dataArray = DY778REModelValue(list, @"dataArray");
    if ([dataArray isKindOfClass:NSArray.class]) return dataArray;
    if (list) return @[list];
    return @[];
}
static NSString *DY778REModelConditionText(id model) {
    NSString *text = DY778REText(DY778REModelValue(model, @"conditionText"));
    if (text.length) return text;
    text = DY778REText(DY778REModelValue(model, @"condition"));
    if (text.length) return text;
    return DY778REText(DY778REModelValue(model, @"desc")) ?: @"";
}
static long long DY778REModelTime(id model, NSString *key) {
    id value = DY778REModelValue(model, key);
    if ([value respondsToSelector:@selector(longLongValue)]) return [value longLongValue];
    return 0;
}

// ---------- 领取记录（规格 §3.9：redEnvelope.records，持久化） ----------
NSArray<NSDictionary *> *DY778RERecords(void) {
    id records = [DY778Preferences() objectForKey:@"redEnvelope.records"];
    if (![records isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *valid = [NSMutableArray array];
    for (id record in records) if ([record isKindOfClass:NSDictionary.class]) [valid addObject:record];
    return [valid copy];
}
void DY778RERememberRecord(NSDictionary *record, NSString *status) {
    if (![record isKindOfClass:NSDictionary.class]) return;
    NSMutableDictionary *entry = [record mutableCopy];
    if (status.length) entry[@"status"] = status;
    entry[@"at"] = @([[NSDate date] timeIntervalSince1970]);
    NSMutableArray *records = [DY778RERecords() mutableCopy];
    NSString *boxID = DY778REText(entry[@"boxID"]) ?: DY778REText(entry[@"box"]);
    if (boxID.length) {
        NSMutableArray *kept = [NSMutableArray array];
        for (NSDictionary *old in records) {
            NSString *oldID = DY778REText(old[@"boxID"]) ?: DY778REText(old[@"box"]);
            if (oldID.length && [oldID isEqualToString:boxID] && [DY778REText(old[@"status"]) isEqualToString:DY778REText(entry[@"status"])]) continue;
            [kept addObject:old];
        }
        records = kept;
    }
    [records insertObject:[entry copy] atIndex:0];
    while (records.count > DY778REMaximumRecords) [records removeLastObject];
    [DY778Preferences() setObject:[records copy] forKey:@"redEnvelope.records"];
}
BOOL DY778REHasClaimedRecord(NSString *boxID) {
    if (!boxID.length) return NO;
    for (NSDictionary *record in DY778RERecords()) {
        NSString *recordID = DY778REText(record[@"boxID"]) ?: DY778REText(record[@"box"]);
        if (![recordID isEqualToString:boxID]) continue;
        NSString *status = DY778REText(record[@"status"]);
        if ([status isEqualToString:@"claimed"] || [status isEqualToString:@"succeed"] || [status isEqualToString:@"submitted"]) return YES;
    }
    return NO;
}

// ---------- 红包目标是否疑似红包（box 类型判定串，规格 §8.5） ----------
static BOOL DY778REStringLooksLikeBox(NSString *text) {
    if (!text.length) return NO;
    NSString *lower = text.lowercaseString;
    for (int i = 0; i < DY778REBoxTypeStringCount; i++) {
        if ([lower rangeOfString:[NSString stringWithUTF8String:DY778REBoxTypeStrings[i]]].location != NSNotFound) return YES;
    }
    for (NSString *marker in @[@"revenue_lucky_box_rush_schema", @"lucky_box_open_auth", @"opengrabluckyboxview", @"red envelope", @"红包"]) {
        if ([lower rangeOfString:marker].location != NSNotFound) return YES;
    }
    return NO;
}
static BOOL DY778REObjectLooksLikeBox(id object) {
    if (!object) return NO;
    NSString *description = nil;
    @try { description = [object description]; } @catch (__unused NSException *exception) { return NO; }
    if (DY778REStringLooksLikeBox(description)) return YES;
    for (NSString *key in @[@"schema", @"url", @"type", @"boxType", @"kind", @"title", @"text"]) {
        if (DY778REStringLooksLikeBox(DY778REText(DY778REModelValue(object, key)))) return YES;
    }
    return NO;
}

// ---------- 租约：DY778RELease（规格 §9.3，51 方法的精简复刻） ----------
// 租约窗口 300 秒是 DYxs 侧的保守设定（未证实）；原版按 box 的
// sendTime/delayTime 计租约，DYxs 侧取不到可信的倒计时字段，
// 故用固定窗口，到期即失效，不再领取。
@implementation DY778RELease
- (instancetype)initWithBox:(NSString *)boxID room:(NSString *)roomID {
    if ((self = [super init])) {
        _boxID = [boxID copy]; _roomID = [roomID copy];
        _expiresAt = [NSDate date].timeIntervalSince1970 + 300;
    }
    return self;
}
- (BOOL)valid {
    return !_retired && !_claimed && _boxID.length && [NSDate date].timeIntervalSince1970 < _expiresAt;
}
- (void)retire { _retired = YES; }
@end

// ---------- 领取目标（替代原版不透明 entry 结构体，规格 §3.2） ----------
@implementation DY778RETarget
- (instancetype)initWithBox:(NSString *)boxID room:(NSString *)roomID conditionText:(NSString *)text {
    if ((self = [super init])) {
        _boxID = [boxID copy]; _roomID = [roomID copy]; _conditionText = [text copy] ?: @"";
        _condition = DY778REConditionCategoryForText(_conditionText);
        _observedAt = [NSDate date].timeIntervalSince1970;
    }
    return self;
}
@end

// ---------- 静默抢：DY778REQuietTicket / DY778REQuietSession（规格 §3.4） ----------
@implementation DY778REQuietTicket
@end

@interface DY778REQuietSession ()
@property(nonatomic, weak) id host;
@property(nonatomic, strong) NSMutableArray<NSString *> *seedBoxIDs;
@property(nonatomic, weak) UIView *rootView;
@property(nonatomic) BOOL mounting;
@property(nonatomic) BOOL appeared;
@property(nonatomic, weak) id parent;
@property(nonatomic, weak) id controller;
@property(nonatomic) BOOL manualValidation;
@end

@implementation DY778REQuietSession
+ (instancetype)beginWithHost:(id)host room:(NSString *)roomID valid:(BOOL)valid {
    DY778REQuietSession *session = [[DY778REQuietSession alloc] init];
    session->_host = host; session->_roomID = [roomID copy]; session->_valid = valid;
    session->_seedBoxIDs = [NSMutableArray array];
    return session;
}
- (BOOL)manual { return _manualValidation; }
- (void)setManual:(BOOL)manual { _manualValidation = manual; }
- (BOOL)openModernWithManager:(id)manager models:(NSArray *)models remaining:(double)remaining {
    if (!_valid || _stopped) return NO;
    if (!DY778RedEnvelopeEnabled() || !DY778RedEnvelopeAutoClaim()) return NO;
    if (![DY778RedEnvelopeMode() isEqualToString:@"quiet"]) return NO;
    if (DY778LuckyAutomationBlocked(_host)) return NO;
    if (!models.count) return NO;
    // 静默路径在 DYxs 侧只做观测：把模型喂给 coordinator 做发现记录，
    // 返回 NO 表示未接管——官方视图照常弹出（见 driveQuiet 的说明）。
    // remaining 仅作参考，不作领取判定。
    (void)manager; (void)remaining;
    [[DY778RECoordinator shared] receiveList:models store:nil room:_roomID account:DY778CurrentAccountID() session:nil];
    return NO;
}
- (BOOL)ownsView:(UIView *)view {
    if (!view || !_rootView) return NO;
    for (UIView *cursor = view; cursor; cursor = cursor.superview) if (cursor == _rootView) return YES;
    return NO;
}
- (void)attach:(id)router schema:(NSString *)schema context:(id)context completion:(void (^)(BOOL handled))completion {
    BOOL handled = NO;
    if (_valid && !_stopped && DY778RedEnvelopeEnabled() && DY778RedEnvelopeAutoClaim() &&
        [DY778RedEnvelopeMode() isEqualToString:@"quiet"] && DY778REStringLooksLikeBox(schema)) {
        // 路由层只做观测与接管登记，不拦截跳转本身（见 Q6/Q7/Q8 说明）；
        // 真正的静默拦截在 BDXPopup 层（Q1–Q3）与 openGrabLuckyBoxView（Q9）。
        handled = NO;
        (void)router; (void)context;
    }
    if (completion) completion(handled);
}
- (void)perform:(id)models {
    if (!_valid || _stopped) return;
    NSArray *list = DY778REListModels(models);
    if (!list.count) return;
    [[DY778RECoordinator shared] receiveList:list store:nil room:_roomID account:DY778CurrentAccountID() session:nil];
}
- (void)cancel { _stopped = YES; }
@end

// ---------- 网页读取/领取（规格 §3.6） ----------
// JS 脚本原文未静态还原；以下脚本按结果字段名重新设计（按 8 个领取按钮
// 文本找按钮并点击，读 succeed/diamondCount/giftName/cashCount），
// 不得声称与原版脚本一致。claimAttempted 置位后只尝试一次（规格 §3.9）。
@interface DY778REWebPage ()
@property(nonatomic) BOOL cancelled;
@end

@implementation DY778REWebPage
- (instancetype)initWithWebView:(WKWebView *)webView box:(NSString *)boxID {
    if ((self = [super init])) { _webView = webView; _boxID = [boxID copy]; }
    return self;
}
- (NSString *)DY778REWebReadScript {
    return @"(function(){var texts=[];var walker=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT);var n;while((n=walker.nextNode())){var t=(n.textContent||'').trim();if(t)texts.push(t.slice(0,120));}var btns=[];var els=document.querySelectorAll('button,[role=button],a,div,span');for(var i=0;i<els.length;i++){var e=els[i];var t=(e.innerText||e.textContent||'').trim();if(t)btns.push(t.slice(0,40));}var claim=['抢','抢红包','立即抢','领取','立即领取','领取红包','免费领取','免费无条件领取'];var found=null;for(var j=0;j<claim.length;j++){for(var k=0;k<btns.length;k++){if(btns[k]===claim[j]){found=claim[j];break;}}if(found)break;}return JSON.stringify({documentURL:location.href,texts:texts.slice(0,200),targets:btns.slice(0,100),identified:!!found,complete:!!found,blocked:false,box:(window.__DY778BoxID||''),conditionText:'',claimButton:found||''});})()";
}
- (NSString *)DY778REWebClaimScript {
    return @"(function(){var claim=['抢','抢红包','立即抢','领取','立即领取','领取红包','免费领取','免费无条件领取'];var els=document.querySelectorAll('button,[role=button],a');for(var j=0;j<claim.length;j++){for(var i=0;i<els.length;i++){var e=els[i];var t=(e.innerText||e.textContent||'').trim();if(t===claim[j]&&e.offsetParent!==null){e.click();return JSON.stringify({submitted:true,clicked:claim[j],succeed:null,diamondCount:0,giftName:'',cashCount:0});}}}return JSON.stringify({submitted:false,clicked:'',succeed:null,diamondCount:0,giftName:'',cashCount:0});})()";
}
- (void)readPageWithCompletion:(void (^)(NSDictionary *state))completion {
    if (_cancelled || !_webView) { if (completion) completion(@{@"reason": @"cancelled"}); return; }
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
        if (completion) completion(@{@"reason": @"background"}); return;
    }
    __weak typeof(self) weakSelf = self;
    [_webView evaluateJavaScript:[self DY778REWebReadScript] completionHandler:^(id result, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf->_cancelled) { if (completion) completion(@{@"reason": @"cancelled"}); return; }
        strongSelf->_observedAt = [NSDate date].timeIntervalSince1970;
        if (error) { if (completion) completion(@{@"reason": @"error", @"errorText": error.localizedDescription ?: @""}); return; }
        NSDictionary *state = nil;
        if ([result isKindOfClass:NSString.class]) state = [NSJSONSerialization JSONObjectWithData:[result dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        else if ([result isKindOfClass:NSDictionary.class]) state = result;
        if (completion) completion(state ?: @{@"reason": @"empty"});
    }];
}
- (void)claimWithCompletion:(void (^)(BOOL submitted, NSDictionary *result))completion {
    if (_claimAttempted) { if (completion) completion(NO, @{@"reason": @"already-attempted"}); return; }
    _claimAttempted = YES; _observedAt = [NSDate date].timeIntervalSince1970;
    if (_cancelled || !_webView) { if (completion) completion(NO, @{@"reason": @"cancelled"}); return; }
    __weak typeof(self) weakSelf = self;
    [_webView evaluateJavaScript:[self DY778REWebClaimScript] completionHandler:^(id result, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf->_cancelled) { if (completion) completion(NO, @{@"reason": @"cancelled"}); return; }
        if (error) { if (completion) completion(NO, @{@"reason": @"error", @"errorText": error.localizedDescription ?: @""}); return; }
        NSDictionary *state = nil;
        if ([result isKindOfClass:NSString.class]) state = [NSJSONSerialization JSONObjectWithData:[result dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        else if ([result isKindOfClass:NSDictionary.class]) state = result;
        BOOL submitted = [state[@"submitted"] boolValue];
        if (completion) completion(submitted, DY778REReadResult(state));
    }];
}
- (void)cancel { _cancelled = YES; }
@end

// ---------- 页面扫描（规格 §3.7 _DY778REReadPageState 族） ----------
// 按视图层级文本重新设计：读倒计时/状态/条件文本与 box ID，不照搬原版。
@interface DY778REScan ()
- (NSString *)pageCountdown:(UIView *)view;
- (NSString *)pageStatusText:(UIView *)view;
- (NSString *)pageConditionText:(UIView *)view;
- (NSArray<NSString *> *)boxIDsInView:(UIView *)view;
@end

@implementation DY778REScan
- (void)DY778RECollectTexts:(UIView *)view into:(NSMutableArray<NSString *> *)texts depth:(NSUInteger)depth {
    if (!view || depth > 8) return;
    @try {
        if ([view isKindOfClass:UILabel.class]) { NSString *text = ((UILabel *)view).text; if (text.length) [texts addObject:text]; }
        if ([view isKindOfClass:UIButton.class]) { NSString *text = [((UIButton *)view) titleForState:UIControlStateNormal]; if (text.length) [texts addObject:text]; }
        NSString *identifier = view.accessibilityIdentifier;
        if (identifier.length) [texts addObject:identifier];
        for (UIView *subview in view.subviews) [self DY778RECollectTexts:subview into:texts depth:depth + 1];
    } @catch (__unused NSException *exception) { }
}
- (NSArray<NSString *> *)DY778REPageTexts:(UIView *)view {
    NSMutableArray *texts = [NSMutableArray array];
    [self DY778RECollectTexts:view into:texts depth:0];
    return [texts copy];
}
- (NSDictionary *)readPageState:(UIView *)view {
    NSArray *texts = [self DY778REPageTexts:view];
    return @{@"texts": texts, @"countdown": [self pageCountdown:view] ?: @"", @"status": [self pageStatusText:view] ?: @"",
             @"condition": [self pageConditionText:view] ?: @"", @"boxIDs": [self boxIDsInView:view]};
}
- (NSString *)pageCountdown:(UIView *)view {
    for (NSString *text in [self DY778REPageTexts:view]) {
        NSRange range = [text rangeOfString:@"\\d{1,2}:[0-5]\\d" options:NSRegularExpressionSearch];
        if (range.location != NSNotFound) return [text substringWithRange:range];
        if ([text rangeOfString:@"秒"].location != NSNotFound && [text rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet].location != NSNotFound) return text;
    }
    return nil;
}
- (NSString *)pageStatusText:(UIView *)view {
    for (NSString *text in [self DY778REPageTexts:view]) {
        if ([text containsString:@"已领取"] || [text containsString:@"领取成功"] || [text containsString:@"已抢完"] ||
            [text containsString:@"开奖"] || [text containsString:@"待开奖"] || [text containsString:@"进行中"]) return text;
    }
    return nil;
}
- (NSString *)pageConditionText:(UIView *)view {
    for (NSString *text in [self DY778REPageTexts:view]) {
        if (DY778REConditionCategoryForText(text) != DY778REConditionUnknown) return text;
    }
    return nil;
}
- (NSArray<NSString *> *)boxIDsInView:(UIView *)view {
    NSMutableArray *found = [NSMutableArray array];
    for (NSString *text in [self DY778REPageTexts:view]) {
        NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length >= 6 && trimmed.length <= 32 &&
            [trimmed rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound &&
            ![found containsObject:trimmed]) [found addObject:trimmed];
    }
    return [found copy];
}
@end

// ---------- WKWebView 查找（规格 §3.7 _DY778REFindWebView） ----------
// 在视图层级里找第一个 WKWebView（网页抢的载体）；找不到返回 nil，
// driveWeb 记 no-webview，不伪造网页领取。
static WKWebView *DY778REFindWebView(UIView *view, NSUInteger depth) {
    if (!view || depth > 10) return nil;
    if ([view isKindOfClass:WKWebView.class]) return (WKWebView *)view;
    for (UIView *subview in view.subviews) {
        WKWebView *found = DY778REFindWebView(subview, depth + 1);
        if (found) return found;
    }
    return nil;
}

// ---------- 状态机：DY778RECoordinator（规格 §3.2，212 方法的精简复刻） ----------
// 只实现驱动领取所需的核心方法；entryForBox:/selectedEntry 的不透明
// 结构体语义未解码，DYxs 侧按字段用途重新设计为 DY778RETarget，
// 不照搬内存布局。baseGate/actionGate 是否调 SL 的 4 个阻塞 helper
// 未证实（规格 §9.1）：按 SL 的 4 门控同款实现并标明。
@interface DY778RECoordinator ()
@property(nonatomic, strong) NSHashTable *stores;
@property(nonatomic, strong) NSHashTable *fragments;
@property(nonatomic, strong) NSHashTable *managers;
@property(nonatomic, strong) NSMutableDictionary<NSString *, DY778RETarget *> *targets;
@property(nonatomic, strong) NSMutableDictionary<NSString *, DY778RELease *> *leases;
@property(nonatomic, strong) DY778REQuietSession *quietSession;
@property(nonatomic, strong) DY778REWebPage *webPage;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, copy) NSString *discoverySession;
@property(nonatomic) NSTimeInterval listRequestedAt;
@property(nonatomic) BOOL discoveryDirty;
@property(nonatomic, copy) NSString *listIssue;
@property(nonatomic, weak) id officialContainer;
- (BOOL)acceptsListToken:(NSString *)session room:(NSString *)roomID account:(NSString *)accountID;
- (DY778RETarget *)DY778RENextTarget;
- (void)driveQuiet:(DY778RETarget *)target;
- (void)driveModern:(DY778RETarget *)target;
- (void)driveWeb:(DY778RETarget *)target;
- (void)scheduleTick;
@end

@implementation DY778RECoordinator
+ (instancetype)shared {
    static DY778RECoordinator *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[DY778RECoordinator alloc] init]; });
    return shared;
}
- (instancetype)init {
    if ((self = [super init])) {
        _stores = [NSHashTable weakObjectsHashTable];
        _fragments = [NSHashTable weakObjectsHashTable];
        _managers = [NSHashTable weakObjectsHashTable];
        _targets = [NSMutableDictionary dictionary];
        _leases = [NSMutableDictionary dictionary];
        _discoveredIDs = @[];
    }
    return self;
}
- (void)registerStore:(id)store { if (store) [_stores addObject:store]; _store = store; }
- (void)registerManager:(id)manager reset:(BOOL)reset {
    if (manager) [_managers addObject:manager];
    _manager = manager;
    if (reset) { _dispatchingClaim = NO; }
}
- (void)registerFragment:(id)fragment { if (fragment) [_fragments addObject:fragment]; _fragment = fragment; }
- (void)unregisterFragment:(id)fragment {
    if (fragment) [_fragments removeObject:fragment];
    if (_fragment == fragment) _fragment = nil;
}
- (BOOL)acceptsListToken:(NSString *)session room:(NSString *)roomID account:(NSString *)accountID {
    if (!session.length) return YES;
    if ([session isEqualToString:_listToken] && [roomID isEqualToString:_roomID] && [accountID isEqualToString:_accountID]) return NO;
    return YES;
}
- (void)receiveList:(NSArray *)list store:(id)store room:(NSString *)roomID account:(NSString *)accountID session:(NSString *)session {
    if (!DY778RedEnvelopeEnabled()) return;
    if (![self acceptsListToken:session room:roomID account:accountID]) return;
    if (session.length) _listToken = [session copy];
    if (roomID.length) _roomID = [roomID copy];
    if (accountID.length) _accountID = [accountID copy];
    if (store) [self registerStore:store];
    _listLoaded = YES; _listFailures = 0; _discoveryDirty = NO;
    NSMutableArray *discovered = [NSMutableArray array];
    for (id model in DY778REListModels(list)) {
        NSString *boxID = DY778REModelID(model);
        if (!boxID.length) continue;
        if (![discovered containsObject:boxID]) [discovered addObject:boxID];
        if (!_targets[boxID]) {
            DY778RETarget *target = [[DY778RETarget alloc] initWithBox:boxID room:_roomID conditionText:DY778REModelConditionText(model)];
            _targets[boxID] = target;
            if (!_leases[boxID]) _leases[boxID] = [[DY778RELease alloc] initWithBox:boxID room:_roomID];
        }
    }
    _discoveredIDs = [discovered copy];
    [self drive];
}
- (void)receiveBackend:(id)backend manager:(id)manager room:(NSString *)roomID account:(NSString *)accountID session:(NSString *)session now:(NSTimeInterval)now {
    (void)backend; (void)now;
    if (manager) [self registerManager:manager reset:NO];
    if (roomID.length) _roomID = [roomID copy];
    if (accountID.length) _accountID = [accountID copy];
    if (session.length) _discoverySession = [session copy];
    [self drive];
}
- (BOOL)canDiscover {
    if (!DY778RedEnvelopeEnabled() || !_roomID.length) return NO;
    if (_listFailures >= DY778REMaximumListFailures) return NO;
    if (_nextListFetch > 0 && [NSDate date].timeIntervalSince1970 < _nextListFetch) return NO;
    return YES;
}
- (void)refreshDiscovery {
    if (![self canDiscover]) return;
    _listRequestedAt = [NSDate date].timeIntervalSince1970;
    _discoveryDirty = NO;
    // 请 store/fragment 重新拉取列表（若对方响应取列表方法）；失败计数
    // 与下次拉取时间按规格 §3.9 由 W21/W22 的回调维护，不在此处自增。
    for (id store in _stores) {
        if ([store respondsToSelector:@selector(fetchAllRedEnvelopesInRoom)]) {
            @try { ((void (*)(id, SEL))objc_msgSend)(store, @selector(fetchAllRedEnvelopesInRoom)); } @catch (__unused NSException *exception) { }
        }
    }
}
- (void)clearDiscovery {
    [_targets removeAllObjects]; [_leases removeAllObjects];
    _discoveredIDs = @[]; _listToken = nil; _listLoaded = NO; _listFailures = 0;
    _nextListFetch = 0; _discoveryDirty = NO; _dispatchingClaim = NO;
}
- (int)baseGate {
    // 按 SL 的 4 门控同款实现，未证实 RE 的 baseGate 是否调同一批 helper
    // （规格 §9.1）：总开关开且 4 门控均不阻塞时放行。
    if (!DY778RedEnvelopeEnabled()) return 0;
    if (DY778LuckyAutomationBlocked(nil)) return 0;
    return 1;
}
- (int)actionGate {
    if ([self baseGate] == 0) return 0;
    if (!DY778RedEnvelopeAutoClaim()) return 0;
    if (_dispatchingClaim) return 0;
    if (![self canDiscover] && !_targets.count) return 0;
    return 1;
}
- (DY778RETarget *)DY778RENextTarget {
    // 只选免费/无条件且未尝试、未领过、租约有效的目标；有门槛的
    // （灯牌/粉丝/钻/关注/口令/付费/送礼）一律跳过，不代为满足条件。
    for (NSString *boxID in _discoveredIDs) {
        DY778RETarget *target = _targets[boxID];
        if (!target || target.attempted) continue;
        if (DY778REHasClaimedRecord(boxID)) continue;
        DY778RELease *lease = _leases[boxID];
        if (lease && ![lease valid]) continue;
        if (target.condition == DY778REConditionFree) return target;
    }
    return nil;
}
- (void)drive {
    if ([self actionGate] == 0) return;
    DY778RETarget *target = [self DY778RENextTarget];
    if (!target) return;
    NSString *mode = DY778RedEnvelopeMode();
    if ([mode isEqualToString:@"manual"]) { [self driveModern:target]; return; }
    if ([mode isEqualToString:@"web"]) { [self driveWeb:target]; return; }
    [self driveQuiet:target];
}
- (void)driveQuiet:(DY778RETarget *)target {
    if (!target) return;
    _dispatchingClaim = YES;
    double delay = DY778REDelay(DY778Number(@"redEnvelope.delay"));
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_dispatchingClaim = NO;
        if ([strongSelf actionGate] == 0) return;
        target.attempted = YES;
        // 静默模式在 DYxs 侧只做观测与记录，不发领取请求：静默领取的
        // 原生调用（经 IESLiveLuckyBoxServiceManager 的内部方法）未静态
        // 还原，无法确认调哪个方法能领到；若拦截官方领取视图又领不到，
        // 会使用户丢红包。官方视图照常弹出，用户可手动领；面板/历史里
        // 可见该红包。租约不置 claimed，状态记 observed（非 submitted）。
        DY778REQuietSession *session = strongSelf->_quietSession;
        if (!session || !session.valid) {
            session = [DY778REQuietSession beginWithHost:strongSelf->_fragment room:strongSelf->_roomID valid:YES];
            strongSelf->_quietSession = session;
        }
        DY778RERememberRecord(@{@"boxID": target.boxID, @"roomID": target.roomID ?: @"", @"mode": @"quiet",
                                  @"condition": @(target.condition)}, @"observed");
        [strongSelf notifyProgress];
    });
}
- (void)driveModern:(DY778RETarget *)target {
    if (!target) return;
    _dispatchingClaim = YES;
    double delay = DY778REDelay(DY778Number(@"redEnvelope.delay"));
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_dispatchingClaim = NO;
        if ([strongSelf actionGate] == 0) return;
        target.attempted = YES;
        // 手动路径：在当前红包面板视图里按 8 个按钮文本点按钮（界面自动化，
        // 不是服务端调用；按钮文本在 40.8.0 是否一致须真机核对）。
        UIView *view = nil;
        id fragment = strongSelf->_fragment;
        if ([fragment isKindOfClass:UIViewController.class]) view = ((UIViewController *)fragment).view;
        else if ([fragment isKindOfClass:UIView.class]) view = fragment;
        BOOL tapped = view ? DY778REManualClaimBox(view) : NO;
        DY778RELease *lease = strongSelf->_leases[target.boxID];
        if (lease) lease.claimed = tapped;
        DY778RERememberRecord(@{@"boxID": target.boxID, @"roomID": target.roomID ?: @"", @"mode": @"manual",
                                  @"condition": @(target.condition)}, tapped ? @"submitted" : @"no-button");
        [strongSelf notifyProgress];
    });
}
- (void)driveWeb:(DY778RETarget *)target {
    if (!target) return;
    _dispatchingClaim = YES;
    double delay = DY778REDelay(DY778Number(@"redEnvelope.delay"));
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_dispatchingClaim = NO;
        if ([strongSelf actionGate] == 0) return;
        target.attempted = YES;
        DY778REWebPage *page = strongSelf->_webPage;
        if (!page || !page.webView) {
            UIView *view = nil;
            id fragment = strongSelf->_fragment;
            if ([fragment isKindOfClass:UIViewController.class]) view = ((UIViewController *)fragment).view;
            else if ([fragment isKindOfClass:UIView.class]) view = fragment;
            if (!view) view = DY778TopController().view;
            WKWebView *webView = view ? DY778REFindWebView(view, 0) : nil;
            if (webView) {
                page = [[DY778REWebPage alloc] initWithWebView:webView box:target.boxID];
                strongSelf->_webPage = page;
            }
        }
        if (!page || !page.webView) {
            // 无可用 WKWebView 时不伪造网页领取：记一条未执行记录即停。
            DY778RERememberRecord(@{@"boxID": target.boxID, @"roomID": target.roomID ?: @"", @"mode": @"web",
                                      @"condition": @(target.condition)}, @"no-webview");
            [strongSelf notifyProgress];
            return;
        }
        [page claimWithCompletion:^(BOOL submitted, NSDictionary *result) {
            DY778RELease *lease = strongSelf->_leases[target.boxID];
            if (lease) lease.claimed = submitted;
            NSMutableDictionary *record = [@{@"boxID": target.boxID, @"roomID": target.roomID ?: @"", @"mode": @"web",
                                             @"condition": @(target.condition)} mutableCopy];
            if (result[@"succeed"]) record[@"succeed"] = result[@"succeed"];
            if (result[@"giftName"]) record[@"giftName"] = result[@"giftName"];
            DY778RERememberRecord([record copy], submitted ? @"submitted" : @"no-button");
            [strongSelf notifyProgress];
        }];
    });
}
- (void)tick {
    if (!DY778RedEnvelopeEnabled()) return;
    if (_discoveryDirty) [self refreshDiscovery];
    [self drive];
    [self scheduleTick];
}
- (void)scheduleTick {
    [_timer invalidate]; _timer = nil;
    if (!DY778RedEnvelopeEnabled()) return;
    __weak typeof(self) weakSelf = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:30 repeats:NO block:^(NSTimer *timer) {
        (void)timer;
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) [strongSelf tick];
    }];
}
- (void)enterRoom:(NSString *)roomID {
    if (roomID.length && ![roomID isEqualToString:_roomID]) [self clearDiscovery];
    if (roomID.length) _roomID = [roomID copy];
    _accountID = DY778CurrentAccountID();
    _discoveryDirty = YES;
    [self scheduleTick];
    [[DY778REEntry shared] refresh];
}
- (void)leaveRoom {
    [self clearDiscovery];
    [_timer invalidate]; _timer = nil;
    _roomID = nil; _officialVisible = NO;
    if (_quietSession) [_quietSession cancel];
    [[DY778REEntry shared] hide];
}
- (void)suspend {
    [_timer invalidate]; _timer = nil;
    _dispatchingClaim = NO;
}
- (void)manualOpen:(id)box {
    NSString *boxID = DY778REModelID(box) ?: DY778REText(box);
    if (!boxID.length) return;
    DY778REPanel *panel = [[DY778REPanel alloc] initWithCoordinator:self];
    UIViewController *presenter = DY778TopController();
    if (presenter) DY778PresentController(presenter, panel);
}
- (void)closeOwnedPanel {
    UIViewController *top = DY778TopController();
    if ([top isKindOfClass:DY778REPanel.class]) [top dismissViewControllerAnimated:YES completion:nil];
}
- (NSString *)progressText {
    NSUInteger claimed = 0;
    for (NSDictionary *record in DY778RERecords()) {
        NSString *status = DY778REText(record[@"status"]);
        if ([status isEqualToString:@"claimed"] || [status isEqualToString:@"submitted"] || [status isEqualToString:@"succeed"]) claimed++;
    }
    return [NSString stringWithFormat:@"已发现 %lu · 已提交 %lu", (unsigned long)_discoveredIDs.count, (unsigned long)claimed];
}
- (void)notifyProgress {
    if (DY778Bool(@"redEnvelope.notifyResult")) DY778ShowToast(@"redEnvelope", [self progressText], NO, YES);
    [[DY778REEntry shared] refresh];
}
- (NSArray<DY778RETarget *> *)allTargets {
    NSMutableArray *targets = [NSMutableArray array];
    for (NSString *boxID in _discoveredIDs) {
        DY778RETarget *target = _targets[boxID];
        if (target) [targets addObject:target];
    }
    return [targets copy];
}
@end

// ---------- 手动抢与参与确认（规格 §3.5、§3.7） ----------
// 手动抢是界面自动化（点按钮），不是服务端调用；按钮文本在抖音 40.8.0
// 是否一致须真机核对。只点精确匹配 8 个文本的可用按钮，不点标签。
static BOOL DY778REClaimTapInView(UIView *view, NSUInteger depth) {
    if (!view || depth > 10 || view.hidden || view.alpha < 0.01) return NO;
    if ([view isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)view;
        NSString *title = [[button titleForState:UIControlStateNormal] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (button.enabled && title.length) {
            for (int i = 0; i < DY778REClaimButtonTextCount; i++) {
                if ([title isEqualToString:[NSString stringWithUTF8String:DY778REClaimButtonTexts[i]]]) {
                    [button sendActionsForControlEvents:UIControlEventTouchUpInside];
                    return YES;
                }
            }
        }
    }
    for (UIView *subview in view.subviews) if (DY778REClaimTapInView(subview, depth + 1)) return YES;
    return NO;
}
BOOL DY778REManualClaimBox(UIView *view) {
    if (!view) return NO;
    BOOL tapped = NO;
    @try { tapped = DY778REClaimTapInView(view, 0); } @catch (__unused NSException *exception) { tapped = NO; }
    return tapped;
}
static BOOL DY778REPayloadContainsBoxID(id value, NSString *boxID, NSUInteger depth) {
    if (!value || depth > 6) return NO;
    if ([value isKindOfClass:NSString.class]) {
        NSString *text = value;
        if (boxID.length) return [text isEqualToString:boxID] || [text containsString:boxID];
        return text.length > 0;
    }
    if ([value isKindOfClass:NSDictionary.class]) {
        for (NSString *key in @[@"box", @"boxid", @"boxidstr", @"luckyboxid", @"redenvelopeid", @"databoxid", @"databoxidstr",
                                @"roomid", @"roomidstr", @"dataroomid", @"initialdata", @"extra", @"unavailable", @"item", @"params", @"data"]) {
            id nested = value[key];
            if ([nested isKindOfClass:NSString.class] && [nested hasPrefix:@"{"]) {
                NSData *data = [nested dataUsingEncoding:NSUTF8StringEncoding];
                id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if (parsed && DY778REPayloadContainsBoxID(parsed, boxID, depth + 1)) return YES;
            }
            if (DY778REPayloadContainsBoxID(nested, boxID, depth + 1)) return YES;
        }
        return NO;
    }
    if ([value isKindOfClass:NSArray.class]) {
        for (id item in value) if (DY778REPayloadContainsBoxID(item, boxID, depth + 1)) return YES;
        return NO;
    }
    if ([value respondsToSelector:@selector(stringValue)]) {
        NSString *text = [value stringValue];
        return boxID.length ? [text isEqualToString:boxID] : text.length > 0;
    }
    return NO;
}
BOOL DY778REConfirmParticipation(NSDictionary *payload, NSString *boxID) {
    if (![payload isKindOfClass:NSDictionary.class]) return NO;
    BOOL confirmed = NO;
    @try { confirmed = DY778REPayloadContainsBoxID(payload, boxID, 0); } @catch (__unused NSException *exception) { confirmed = NO; }
    return confirmed;
}

// ---------- 面板 / 历史 / 入口 ----------
@interface DY778REPanel () <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, strong) DY778RECoordinator *coordinator;
@property(nonatomic, strong) UITableView *tableView;
@end

@implementation DY778REPanel
- (instancetype)initWithCoordinator:(DY778RECoordinator *)coordinator {
    if ((self = [super init])) _coordinator = coordinator ?: [DY778RECoordinator shared];
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"红包";
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
    if (section == 0) return MAX(1, (NSInteger)[_coordinator allTargets].count);
    return MAX(1, (NSInteger)DY778RERecords().count);
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return section == 0 ? @"本房间已发现的红包" : @"领取记录";
}
- (NSString *)DY778REConditionLabel:(DY778REConditionCategory)condition {
    switch (condition) {
        case DY778REConditionFree: return @"免费";
        case DY778REConditionPresent: return @"需在场";
        case DY778REConditionGated: return @"有门槛（跳过）";
        default: return @"未知条件";
    }
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DY778RECell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"DY778RECell"];
    if (indexPath.section == 0) {
        NSArray *targets = [_coordinator allTargets];
        if (!targets.count) { cell.textLabel.text = @"暂未发现红包"; cell.detailTextLabel.text = @"进直播间后有红包时出现在这里"; }
        else {
            DY778RETarget *target = targets[indexPath.row];
            cell.textLabel.text = target.boxID;
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", [self DY778REConditionLabel:target.condition],
                                         target.attempted ? @"已处理" : @"待处理"];
        }
    } else {
        NSArray *records = DY778RERecords();
        if (!records.count) { cell.textLabel.text = @"暂无记录"; cell.detailTextLabel.text = @""; }
        else {
            NSDictionary *record = records[indexPath.row];
            cell.textLabel.text = DY778REText(record[@"boxID"]) ?: DY778REText(record[@"box"]) ?: @"未知红包";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", DY778REText(record[@"status"]) ?: @"",
                                         DY778REText(record[@"mode"]) ?: @""];
        }
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 0) return;
    NSArray *targets = [_coordinator allTargets];
    if (indexPath.row >= (NSInteger)targets.count) return;
    // 点一行：先关面板，再在直播间视图里按按钮文本尝试手动领取。
    // 官方视图若未弹出则点不到，记一条 no-button，不伪造结果。
    DY778RETarget *target = targets[indexPath.row];
    __weak typeof(self) weakSelf = self;
    [self dismissViewControllerAnimated:YES completion:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        (void)strongSelf;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIViewController *top = DY778TopController();
            BOOL tapped = top.view ? DY778REManualClaimBox(top.view) : NO;
            DY778RERememberRecord(@{@"boxID": target.boxID, @"roomID": target.roomID ?: @"", @"mode": @"manual",
                                      @"condition": @(target.condition)}, tapped ? @"submitted" : @"no-button");
        });
    }];
}
@end

@interface DY778REHistoryController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation DY778REHistoryController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"红包记录";
    DY778StyleController(self);
    UITableView *tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tableView.dataSource = self; tableView.delegate = self;
    [self.view addSubview:tableView];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return MAX(1, (NSInteger)DY778RERecords().count);
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DY778REHistoryCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"DY778REHistoryCell"];
    NSArray *records = DY778RERecords();
    if (!records.count) { cell.textLabel.text = @"暂无记录"; cell.detailTextLabel.text = @""; return cell; }
    NSDictionary *record = records[indexPath.row];
    cell.textLabel.text = DY778REText(record[@"boxID"]) ?: DY778REText(record[@"box"]) ?: @"未知红包";
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:[record[@"at"] doubleValue]];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"MM-dd HH:mm:ss";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ · %@", DY778REText(record[@"status"]) ?: @"",
                                 DY778REText(record[@"mode"]) ?: @"", [formatter stringFromDate:date]];
    return cell;
}
@end

// ---------- 入口悬浮按钮 ----------
@interface DY778REEntry ()
@property(nonatomic, strong) UIButton *button;
@end

@implementation DY778REEntry
+ (instancetype)shared {
    static DY778REEntry *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[DY778REEntry alloc] init]; });
    return shared;
}
- (NSString *)DY778REEntryPosition {
    UIWindow *window = DY778ActiveWindow();
    BOOL landscape = window && window.bounds.size.width > window.bounds.size.height;
    NSString *position = DY778String(landscape ? @"redEnvelope.entryPosition.landscape" : @"redEnvelope.entryPosition.portrait");
    return DY778LiveAnalysisValidEntryPosition(position.UTF8String) ? position : @"bottom-right";
}
- (void)refresh {
    if (!DY778RedEnvelopeEnabled() || !DY778Bool(@"redEnvelope.showEntry")) { [self hide]; return; }
    DY778REMain(^{
        UIWindow *window = DY778ActiveWindow();
        if (!window) return;
        if (!self->_button) {
            self->_button = [UIButton buttonWithType:UIButtonTypeSystem];
            UIImage *image = [UIImage systemImageNamed:@"gift.fill"];
            [self->_button setImage:image forState:UIControlStateNormal];
            self->_button.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.64];
            self->_button.tintColor = UIColor.whiteColor;
            self->_button.layer.cornerRadius = 22;
            self->_button.layer.masksToBounds = YES;
            [self->_button addTarget:self action:@selector(DY778REEntryTapped) forControlEvents:UIControlEventTouchUpInside];
            self->_button.accessibilityLabel = @"红包";
        }
        NSString *position = [self DY778REEntryPosition];
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
    DY778REMain(^{
        [self->_button removeFromSuperview];
        self->_button = nil;
    });
}
- (void)DY778REEntryTapped {
    DY778REPanel *panel = [[DY778REPanel alloc] initWithCoordinator:[DY778RECoordinator shared]];
    UIViewController *presenter = DY778TopController();
    if (presenter) DY778PresentController(presenter, panel);
}
@end

// ---------- 替换实现：直接 hook（D1–D4，返回类型各不相同） ----------
static BOOL DY778REDispatchTouchEvent(id self, SEL _cmd, id arg) {
    BOOL result = NO;
    if (DY778REOriginalDispatchTouchEvent) result = ((BOOL (*)(id, SEL, id))DY778REOriginalDispatchTouchEvent)(self, _cmd, arg);
    // 观测点：Lynx 触摸事件透传，不改行为。
    (void)self; (void)arg;
    return result;
}
static id DY778REGetLynxRedEnvelopeParams(id self, SEL _cmd, id params, BOOL showResult) {
    id result = nil;
    if (DY778REOriginalGetLynxRedEnvelopeParams) result = ((id (*)(id, SEL, id, BOOL))DY778REOriginalGetLynxRedEnvelopeParams)(self, _cmd, params, showResult);
    @try {
        if (DY778RedEnvelopeEnabled()) {
            DY778RECoordinator *coordinator = [DY778RECoordinator shared];
            [coordinator registerFragment:self];
            NSArray *list = DY778REListModels(result);
            if (list.count) [coordinator receiveList:list store:nil room:DY778LiveContextRoomID(self) account:DY778CurrentAccountID() session:nil];
        }
    } @catch (__unused NSException *exception) { }
    (void)params; (void)showResult;
    return result;
}
static id DY778REFetchAllRedEnvelopes(id self, SEL _cmd, id roomID) {
    id signal = nil;
    if (DY778REOriginalFetchAllRedEnvelopes) signal = ((id (*)(id, SEL, id))DY778REOriginalFetchAllRedEnvelopes)(self, _cmd, roomID);
    @try {
        if (DY778RedEnvelopeEnabled() && signal) {
            // 原版订阅 RACSignal 的 doNext:；DYxs 侧 doNext: 不存在时
            // 退回 subscribeNext:，都不存在则只记一次拉取，不订阅。
            NSString *room = DY778REText(roomID) ?: DY778LiveContextRoomID(self);
            NSString *account = DY778CurrentAccountID();
            void (^feed)(id) = ^(id value) {
                NSArray *list = DY778REListModels(value);
                if (list.count) [[DY778RECoordinator shared] receiveList:list store:nil room:room account:account session:nil];
            };
            if ([signal respondsToSelector:@selector(doNext:)]) ((id (*)(id, SEL, id))objc_msgSend)(signal, @selector(doNext:), feed);
            else if ([signal respondsToSelector:@selector(subscribeNext:)]) ((id (*)(id, SEL, id))objc_msgSend)(signal, @selector(subscribeNext:), feed);
        }
    } @catch (__unused NSException *exception) { }
    return signal;
}
static NSUInteger DY778HybridSchemeSeen;
static NSString *DY778HybridSchemeLast, *DY778LotterySchemeLast;
NSUInteger DY778HybridSchemeCount(void) { return DY778HybridSchemeSeen; }
NSString *DY778LastHybridScheme(void) { return DY778HybridSchemeLast; }
NSString *DY778LastLotteryScheme(void) { return DY778LotterySchemeLast; }
static id DY778REOpenHybridWithScheme(id self, SEL _cmd, id scheme, id params, id props, id completion) {
    id result = nil;
    @try {
        DY778HybridSchemeSeen++;
        NSString *text = [scheme isKindOfClass:NSString.class] ? scheme : [scheme description];
        if (text.length) {
            DY778HybridSchemeLast = text;
            if ([text rangeOfString:@"lottery" options:NSCaseInsensitiveSearch].location != NSNotFound)
                DY778LotterySchemeLast = text;
        }
    } @catch (__unused NSException *exception) { }
    if (DY778REOriginalOpenHybridWithScheme) result = ((id (*)(id, SEL, id, id, id, id))DY778REOriginalOpenHybridWithScheme)(self, _cmd, scheme, params, props, completion);
    @try {
        if (DY778RedEnvelopeEnabled() && DY778REObjectLooksLikeBox(scheme)) {
            // 只观测：路由契约（返回值）未证实，DYxs 侧不拦截跳转；
            // 若参数里带红包列表模型，喂给 coordinator 做发现。
            NSArray *list = DY778REListModels(DY778REModelValue(params, @"dataArray"));
            if (list.count) [[DY778RECoordinator shared] receiveList:list store:nil room:DY778LiveContextRoomID(self) account:DY778CurrentAccountID() session:nil];
        }
    } @catch (__unused NSException *exception) { }
    (void)props;
    return result;
}

// ---------- 替换实现：包装器 hook（W1–W31，全部 void 返回） ----------
static void DY778RELynxBaseViewTapped(id self, SEL _cmd) {
    if (DY778REOriginalLynxBaseViewTapped) ((void (*)(id, SEL))DY778REOriginalLynxBaseViewTapped)(self, _cmd);
    @try {
        if (DY778RedEnvelopeEnabled() && DY778RedEnvelopeAutoClaim() && [DY778RedEnvelopeMode() isEqualToString:@"quiet"]) {
            // 原版调 _DY778REModelValue 与 _DY778REQuietPerformManual；
            // DYxs 侧只把视图的 dataArray 模型喂给 coordinator 做发现，
            // 不做静默接管（见 driveQuiet 说明）。
            id models = DY778REModelValue(self, @"dataArray");
            if ([models isKindOfClass:NSArray.class] && ((NSArray *)models).count) {
                [[DY778RECoordinator shared] receiveList:models store:nil room:DY778LiveContextRoomID(self) account:DY778CurrentAccountID() session:nil];
            }
        }
    } @catch (__unused NSException *exception) { }
}
static void DY778RECreateShortTouchItem(id self, SEL _cmd, id item, id data, BOOL animated) {
    if (DY778REOriginalCreateShortTouchItem) ((void (*)(id, SEL, id, id, BOOL))DY778REOriginalCreateShortTouchItem)(self, _cmd, item, data, animated);
    @try { if (DY778RedEnvelopeEnabled()) [[DY778RECoordinator shared] registerManager:self reset:NO]; } @catch (__unused NSException *exception) { }
    (void)item; (void)data; (void)animated;
}
static void DY778REShortTouchIsReady(id self, SEL _cmd) {
    if (DY778REOriginalShortTouchIsReady) ((void (*)(id, SEL))DY778REOriginalShortTouchIsReady)(self, _cmd);
    // 观测点：短触入口就绪，无额外动作。
}
static void DY778RELuckyBoxMessageReceived(id self, SEL _cmd, id message) {
    if (DY778REOriginalLuckyBoxMessageReceived) ((void (*)(id, SEL, id))DY778REOriginalLuckyBoxMessageReceived)(self, _cmd, message);
    @try {
        if (DY778RedEnvelopeEnabled() && DY778REObjectLooksLikeBox(message)) {
            NSArray *list = DY778REListModels(message);
            if (list.count) [[DY778RECoordinator shared] receiveList:list store:nil room:DY778LiveContextRoomID(self) account:DY778CurrentAccountID() session:nil];
        }
    } @catch (__unused NSException *exception) { }
}
static void DY778REOpenGrabLuckyBoxView(id self, SEL _cmd) {
    // 双重 hook 的外层（主安装体 W5）：先调原 IMP（其内是 Q9 的替换实现，
    // 见 DY778REQuietOpenGrabLuckyBoxView），官方视图照常弹出；
    // 再驱动 coordinator（manual/web 模式在此处触发领取尝试）。
    @try { if (DY778RedEnvelopeEnabled()) [[DY778RECoordinator shared] registerManager:self reset:NO]; } @catch (__unused NSException *exception) { }
    if (DY778REOriginalOpenGrabLuckyBoxView) ((void (*)(id, SEL))DY778REOriginalOpenGrabLuckyBoxView)(self, _cmd);
    @try { if (DY778RedEnvelopeEnabled()) [[DY778RECoordinator shared] drive]; } @catch (__unused NSException *exception) { }
}
static void DY778RERemoveShortTouchItem(id self, SEL _cmd) {
    if (DY778REOriginalRemoveShortTouchItem) ((void (*)(id, SEL))DY778REOriginalRemoveShortTouchItem)(self, _cmd);
    // 观测点：短触入口移除，无额外动作。
}
static void DY778RELuckyBoxBindService(id self, SEL _cmd) {
    if (DY778REOriginalLuckyBoxBindService) ((void (*)(id, SEL))DY778REOriginalLuckyBoxBindService)(self, _cmd);
    @try { if (DY778RedEnvelopeEnabled()) [[DY778RECoordinator shared] registerManager:self reset:NO]; } @catch (__unused NSException *exception) { }
}
static void DY778RELuckyBoxSetRoomModel(id self, SEL _cmd, id roomModel) {
    if (DY778REOriginalLuckyBoxSetRoomModel) ((void (*)(id, SEL, id))DY778REOriginalLuckyBoxSetRoomModel)(self, _cmd, roomModel);
    @try {
        if (DY778RedEnvelopeEnabled()) {
            NSString *roomID = DY778LiveContextRoomID(roomModel);
            if (roomID.length) [[DY778RECoordinator shared] enterRoom:roomID];
        }
    } @catch (__unused NSException *exception) { }
}
static void DY778RELuckyBoxSubscribeBackend(id self, SEL _cmd) {
    if (DY778REOriginalLuckyBoxSubscribeBackend) ((void (*)(id, SEL))DY778REOriginalLuckyBoxSubscribeBackend)(self, _cmd);
    @try { if (DY778RedEnvelopeEnabled()) [[DY778RECoordinator shared] registerManager:self reset:NO]; } @catch (__unused NSException *exception) { }
}
static void DY778RERequestBackendData(id self, SEL _cmd, id data) {
    if (DY778REOriginalRequestBackendData) ((void (*)(id, SEL, id))DY778REOriginalRequestBackendData)(self, _cmd, data);
    @try {
        if (DY778RedEnvelopeEnabled()) {
            [[DY778RECoordinator shared] receiveBackend:data manager:nil room:DY778LiveContextRoomID(self)
                                                 account:DY778CurrentAccountID() session:nil now:[NSDate date].timeIntervalSince1970];
        }
    } @catch (__unused NSException *exception) { }
}
static void DY778REAudienceViewDidLayout(id self, SEL _cmd) {
    if (DY778REOriginalAudienceViewDidLayout) ((void (*)(id, SEL))DY778REOriginalAudienceViewDidLayout)(self, _cmd);
    @try { if (DY778RedEnvelopeEnabled()) [[DY778REEntry shared] refresh]; } @catch (__unused NSException *exception) { }
}
static void DY778REAudienceViewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (DY778REOriginalAudienceViewDidAppear) ((void (*)(id, SEL, BOOL))DY778REOriginalAudienceViewDidAppear)(self, _cmd, animated);
    @try {
        if (DY778RedEnvelopeEnabled()) {
            NSString *roomID = DY778LiveContextRoomID(self);
            if (roomID.length) [[DY778RECoordinator shared] enterRoom:roomID];
            [[DY778REEntry shared] refresh];
        }
    } @catch (__unused NSException *exception) { }
}
static void DY778REAudienceDidEnterRoom(id self, SEL _cmd, id room) {
    if (DY778REOriginalAudienceDidEnterRoom) ((void (*)(id, SEL, id))DY778REOriginalAudienceDidEnterRoom)(self, _cmd, room);
    @try {
        if (DY778RedEnvelopeEnabled()) {
            NSString *roomID = DY778LiveContextRoomID(room);
            if (roomID.length) [[DY778RECoordinator shared] enterRoom:roomID];
        }
    } @catch (__unused NSException *exception) { }
}
static void DY778REAudienceDidCloseRoom(id self, SEL _cmd, id room, long long closeType) {
    if (DY778REOriginalAudienceDidCloseRoom) ((void (*)(id, SEL, id, long long))DY778REOriginalAudienceDidCloseRoom)(self, _cmd, room, closeType);
    @try { if (DY778RedEnvelopeEnabled()) [[DY778RECoordinator shared] leaveRoom]; } @catch (__unused NSException *exception) { }
    (void)room;
}
static void DY778REAudienceStartLeaveRoom(id self, SEL _cmd) {
    if (DY778REOriginalAudienceStartLeaveRoom) ((void (*)(id, SEL))DY778REOriginalAudienceStartLeaveRoom)(self, _cmd);
    @try { if (DY778RedEnvelopeEnabled()) [[DY778RECoordinator shared] leaveRoom]; } @catch (__unused NSException *exception) { }
}
static void DY778REAudienceRoomWillResign(id self, SEL _cmd, id room) {
    if (DY778REOriginalAudienceRoomWillResign) ((void (*)(id, SEL, id))DY778REOriginalAudienceRoomWillResign)(self, _cmd, room);
    @try { if (DY778RedEnvelopeEnabled()) [[DY778RECoordinator shared] suspend]; } @catch (__unused NSException *exception) { }
    (void)room;
}
static void DY778REAudienceRoomDidBecomeActive(id self, SEL _cmd, id room) {
    if (DY778REOriginalAudienceRoomDidBecomeActive) ((void (*)(id, SEL, id))DY778REOriginalAudienceRoomDidBecomeActive)(self, _cmd, room);
    @try { if (DY778RedEnvelopeEnabled()) [[DY778RECoordinator shared] tick]; } @catch (__unused NSException *exception) { }
    (void)room;
}
static void DY778REStoreComponentMount(id self, SEL _cmd) {
    if (DY778REOriginalStoreComponentMount) ((void (*)(id, SEL))DY778REOriginalStoreComponentMount)(self, _cmd);
    @try { if (DY778RedEnvelopeEnabled()) [[DY778RECoordinator shared] registerStore:self]; } @catch (__unused NSException *exception) { }
}
static void DY778REStoreDidUpdateRoom(id self, SEL _cmd, id room) {
    if (DY778REOriginalStoreDidUpdateRoom) ((void (*)(id, SEL, id))DY778REOriginalStoreDidUpdateRoom)(self, _cmd, room);
    @try {
        if (DY778RedEnvelopeEnabled()) {
            NSString *roomID = DY778LiveContextRoomID(room);
            if (roomID.length) [[DY778RECoordinator shared] enterRoom:roomID];
        }
    } @catch (__unused NSException *exception) { }
}
static void DY778REStoreSetRedEnvelopeQueue(id self, SEL _cmd, id queue) {
    if (DY778REOriginalStoreSetRedEnvelopeQueue) ((void (*)(id, SEL, id))DY778REOriginalStoreSetRedEnvelopeQueue)(self, _cmd, queue);
    @try {
        if (DY778RedEnvelopeEnabled()) {
            NSArray *list = DY778REListModels(queue);
            if (list.count) [[DY778RECoordinator shared] receiveList:list store:self room:DY778LiveContextRoomID(self) account:DY778CurrentAccountID() session:nil];
        }
    } @catch (__unused NSException *exception) { }
}
static void DY778REStoreFetchAllInRoom(id self, SEL _cmd) {
    if (DY778REOriginalStoreFetchAllInRoom) ((void (*)(id, SEL))DY778REOriginalStoreFetchAllInRoom)(self, _cmd);
    // 观测点：store 主动拉取列表，无额外动作（失败计数由 W22 回调维护）。
}
static void DY778REStoreSetResultArray(id self, SEL _cmd, id array) {
    if (DY778REOriginalStoreSetResultArray) ((void (*)(id, SEL, id))DY778REOriginalStoreSetResultArray)(self, _cmd, array);
    @try {
        if (DY778RedEnvelopeEnabled()) {
            for (id item in DY778REListModels(array)) {
                NSDictionary *result = DY778REReadResult([item isKindOfClass:NSDictionary.class] ? item : nil);
                NSString *boxID = DY778REModelID(item) ?: DY778REText(result[@"box"]);
                if (!boxID.length) continue;
                if ([result[@"succeed"] boolValue]) DY778RERememberRecord(@{@"boxID": boxID, @"mode": @"store"}, @"succeed");
            }
        }
    } @catch (__unused NSException *exception) { }
}
static void DY778REFragmentSetRoom(id self, SEL _cmd, id room, id componentContext, id trackContext) {
    if (DY778REOriginalFragmentSetRoom) ((void (*)(id, SEL, id, id, id))DY778REOriginalFragmentSetRoom)(self, _cmd, room, componentContext, trackContext);
    @try { if (DY778RedEnvelopeEnabled()) [[DY778RECoordinator shared] registerFragment:self]; } @catch (__unused NSException *exception) { }
    (void)componentContext; (void)trackContext;
}
static void DY778REFragmentRemoteRoomDataReady(id self, SEL _cmd, id room) {
    if (DY778REOriginalFragmentRemoteRoomDataReady) ((void (*)(id, SEL, id))DY778REOriginalFragmentRemoteRoomDataReady)(self, _cmd, room);
    @try {
        if (DY778RedEnvelopeEnabled()) {
            NSString *roomID = DY778LiveContextRoomID(room);
            if (roomID.length) [[DY778RECoordinator shared] enterRoom:roomID];
            [[DY778RECoordinator shared] refreshDiscovery];
        }
    } @catch (__unused NSException *exception) { }
}
static void DY778REFragmentComponentMount(id self, SEL _cmd) {
    if (DY778REOriginalFragmentComponentMount) ((void (*)(id, SEL))DY778REOriginalFragmentComponentMount)(self, _cmd);
    @try { if (DY778RedEnvelopeEnabled()) [[DY778RECoordinator shared] registerFragment:self]; } @catch (__unused NSException *exception) { }
}
static void DY778REFragmentComponentBindService(id self, SEL _cmd) {
    if (DY778REOriginalFragmentComponentBindService) ((void (*)(id, SEL))DY778REOriginalFragmentComponentBindService)(self, _cmd);
    @try { if (DY778RedEnvelopeEnabled()) [[DY778RECoordinator shared] registerFragment:self]; } @catch (__unused NSException *exception) { }
}
static void DY778REFragmentComponentUnmount(id self, SEL _cmd) {
    if (DY778REOriginalFragmentComponentUnmount) ((void (*)(id, SEL))DY778REOriginalFragmentComponentUnmount)(self, _cmd);
    @try { if (DY778RedEnvelopeEnabled()) [[DY778RECoordinator shared] unregisterFragment:self]; } @catch (__unused NSException *exception) { }
}
static void DY778REFragmentSetStore(id self, SEL _cmd, id store) {
    if (DY778REOriginalFragmentSetStore) ((void (*)(id, SEL, id))DY778REOriginalFragmentSetStore)(self, _cmd, store);
    @try { if (DY778RedEnvelopeEnabled()) [[DY778RECoordinator shared] registerStore:store]; } @catch (__unused NSException *exception) { }
}
static void DY778REFragmentShowViewWith(id self, SEL _cmd, id model) {
    if (DY778REOriginalFragmentShowViewWith) ((void (*)(id, SEL, id))DY778REOriginalFragmentShowViewWith)(self, _cmd, model);
    @try {
        if (DY778RedEnvelopeEnabled()) {
            [DY778RECoordinator shared].officialVisible = YES;
            [[DY778RECoordinator shared] drive];
        }
    } @catch (__unused NSException *exception) { }
}
static void DY778REFragmentShowView(id self, SEL _cmd) {
    if (DY778REOriginalFragmentShowView) ((void (*)(id, SEL))DY778REOriginalFragmentShowView)(self, _cmd);
    @try { if (DY778RedEnvelopeEnabled()) [DY778RECoordinator shared].officialVisible = YES; } @catch (__unused NSException *exception) { }
}
static void DY778REFragmentShowLynxView(id self, SEL _cmd, id model) {
    if (DY778REOriginalFragmentShowLynxView) ((void (*)(id, SEL, id))DY778REOriginalFragmentShowLynxView)(self, _cmd, model);
    @try {
        if (DY778RedEnvelopeEnabled()) {
            [DY778RECoordinator shared].officialVisible = YES;
            [[DY778RECoordinator shared] drive];
        }
    } @catch (__unused NSException *exception) { }
    (void)model;
}

// ---------- 替换实现：静默抢（Q1–Q9） ----------
// DYxs 侧的偏离（见文件头与 DY778RedEnvelope.h）：静默领取的原生调用
// 未静态还原，无法确认调哪个内部方法能领到；若拦截官方容器弹出又
// 领不到，会使用户丢红包。故 Q1–Q9 的替换实现一律调原 IMP（官方容器
// 照常弹出），只做观测与发现记录；安装顺序仍保持先静默后主安装，
// 以保 Q9/W5 的双重 hook 链完整。
static id DY778REQuietPopupOpen(id self, SEL _cmd, id config, id context, id completion) {
    id result = nil;
    if (DY778REOriginalQuietPopupOpen) result = ((id (*)(id, SEL, id, id, id))DY778REOriginalQuietPopupOpen)(self, _cmd, config, context, completion);
    @try {
        if (DY778RedEnvelopeEnabled() && DY778REObjectLooksLikeBox(config)) {
            NSArray *models = DY778REListModels(DY778REModelValue(config, @"dataArray"));
            if (models.count) [[DY778RECoordinator shared] receiveList:models store:nil room:DY778LiveContextRoomID(config) account:DY778CurrentAccountID() session:nil];
        }
    } @catch (__unused NSException *exception) { }
    return result;
}
static NSUInteger DY778BDXSeen, DY778AnnieSeen;
static NSString *DY778BDXLastURL, *DY778BDXLastLotteryURL, *DY778AnnieLastSchema, *DY778AnnieLastLotterySchema;
NSUInteger DY778BDXCreateCount(void) { return DY778BDXSeen; }
NSString *DY778LastBDXURL(void) { return DY778BDXLastURL; }
NSString *DY778LastLotteryBDXURL(void) { return DY778BDXLastLotteryURL; }
NSUInteger DY778AnnieSchemaCount(void) { return DY778AnnieSeen; }
NSString *DY778LastAnnieSchema(void) { return DY778AnnieLastSchema; }
NSString *DY778LastLotteryAnnieSchema(void) { return DY778AnnieLastLotterySchema; }
static void DY778RecordRouteText(id value, NSUInteger *counter, NSString * __strong *last, NSString * __strong *lastLottery) {
    @try {
        (*counter)++;
        NSString *text = [value isKindOfClass:NSString.class] ? value : [value description];
        if (text.length) {
            *last = text;
            if ([text rangeOfString:@"lottery" options:NSCaseInsensitiveSearch].location != NSNotFound)
                *lastLottery = text;
        }
    } @catch (__unused NSException *exception) { }
}
static id DY778REQuietPopupCreate(id self, SEL _cmd, id config, id context, id url, id completion) {
    id result = nil;
    DY778RecordRouteText(url, &DY778BDXSeen, &DY778BDXLastURL, &DY778BDXLastLotteryURL);
    if (DY778REOriginalQuietPopupCreate) result = ((id (*)(id, SEL, id, id, id, id))DY778REOriginalQuietPopupCreate)(self, _cmd, config, context, url, completion);
    @try {
        if (DY778RedEnvelopeEnabled() && (DY778REObjectLooksLikeBox(config) || DY778REObjectLooksLikeBox(url))) {
            NSArray *models = DY778REListModels(DY778REModelValue(config, @"dataArray"));
            if (models.count) [[DY778RECoordinator shared] receiveList:models store:nil room:DY778LiveContextRoomID(config) account:DY778CurrentAccountID() session:nil];
        }
    } @catch (__unused NSException *exception) { }
    return result;
}
static void DY778REQuietPopupShowContainer(id self, SEL _cmd, id context, id config, id vc, id completion) {
    if (DY778REOriginalQuietPopupShowContainer) ((void (*)(id, SEL, id, id, id, id))DY778REOriginalQuietPopupShowContainer)(self, _cmd, context, config, vc, completion);
    @try {
        if (DY778RedEnvelopeEnabled() && DY778REObjectLooksLikeBox(config)) {
            [DY778RECoordinator shared].officialVisible = YES;
        }
    } @catch (__unused NSException *exception) { }
    (void)context; (void)vc;
}
static void DY778REQuietPopupShowContainerVc(id self, SEL _cmd) {
    if (DY778REOriginalQuietPopupShowContainerVc) ((void (*)(id, SEL))DY778REOriginalQuietPopupShowContainerVc)(self, _cmd);
    @try {
        if (DY778RedEnvelopeEnabled() && DY778REObjectLooksLikeBox(self)) [DY778RECoordinator shared].officialVisible = YES;
    } @catch (__unused NSException *exception) { }
}
static void DY778REQuietPopupDismiss(id self, SEL _cmd, BOOL animated, id completion) {
    // 不拦截关闭：拦截 dismiss 会把容器卡在屏幕上；只透传。
    if (DY778REOriginalQuietPopupDismiss) ((void (*)(id, SEL, BOOL, id))DY778REOriginalQuietPopupDismiss)(self, _cmd, animated, completion);
}
static void DY778REQuietRouterTransition(id self, SEL _cmd, id schema, id controller, id fromVC, id context, id completion, NSError **error) {
    DY778RecordRouteText(schema, &DY778AnnieSeen, &DY778AnnieLastSchema, &DY778AnnieLastLotterySchema);
    if (DY778REOriginalQuietRouterTransition) ((void (*)(id, SEL, id, id, id, id, id, NSError **))DY778REOriginalQuietRouterTransition)(self, _cmd, schema, controller, fromVC, context, completion, error);
    @try {
        if (DY778RedEnvelopeEnabled() && DY778REStringLooksLikeBox(DY778REText(schema))) {
            // 路由层只做观测，不拦截跳转本身（见 attach: 说明）。
            // schema 疑似红包路由时记一次发现（不建 session，避免无主对象）。
            (void)controller;
        }
    } @catch (__unused NSException *exception) { }
    (void)fromVC; (void)context; (void)completion;
}
static id DY778REQuietOpenHybridDialog(id self, SEL _cmd, id dialog) {
    id result = nil;
    if (DY778REOriginalQuietOpenHybridDialog) result = ((id (*)(id, SEL, id))DY778REOriginalQuietOpenHybridDialog)(self, _cmd, dialog);
    @try {
        if (DY778RedEnvelopeEnabled() && DY778REObjectLooksLikeBox(dialog)) [DY778RECoordinator shared].officialVisible = YES;
    } @catch (__unused NSException *exception) { }
    return result;
}
static void DY778REQuietResolveRedirectScheme(id self, SEL _cmd, id scheme, id completion) {
    if (DY778REOriginalQuietResolveRedirectScheme) ((void (*)(id, SEL, id, id))DY778REOriginalQuietResolveRedirectScheme)(self, _cmd, scheme, completion);
    // 观测点：重定向解析透传，不拦截。
}
static void DY778REQuietOpenGrabLuckyBoxView(id self, SEL _cmd) {
    // 双重 hook 的内层（静默安装体 Q9）：orig 是抖音原实现。
    // DYxs 侧不拦截官方领取视图（见本节头注），调原 IMP 后驱动一次。
    @try { if (DY778RedEnvelopeEnabled()) [[DY778RECoordinator shared] registerManager:self reset:NO]; } @catch (__unused NSException *exception) { }
    if (DY778REOriginalQuietOpenGrabLuckyBoxView) ((void (*)(id, SEL))DY778REOriginalQuietOpenGrabLuckyBoxView)(self, _cmd);
    @try { if (DY778RedEnvelopeEnabled()) [[DY778RECoordinator shared] drive]; } @catch (__unused NSException *exception) { }
}

// ---------- 安装 ----------
static void DY778InstallREQuietHooks(void) {
    // Q1–Q3 是 BDXPopupViewController 的元类方法（object_getClass 取元类）。
    DY778REInstallMeta(@"BDXPopupViewController", @"openWithConfiguration:context:completion:", "@", "@@@",
                       (IMP)DY778REQuietPopupOpen, &DY778REOriginalQuietPopupOpen);
    DY778REInstallMeta(@"BDXPopupViewController", @"createWithConfiguration:context:url:completion:", "@", "@@@@",
                       (IMP)DY778REQuietPopupCreate, &DY778REOriginalQuietPopupCreate);
    DY778REInstallMeta(@"BDXPopupViewController", @"showContainerWithContext:config:vc:completion:", "v", "@@@@",
                       (IMP)DY778REQuietPopupShowContainer, &DY778REOriginalQuietPopupShowContainer);
    DY778REInstall(@"BDXPopupViewController", @"showContainerVc", "v", "",
                   (IMP)DY778REQuietPopupShowContainerVc, &DY778REOriginalQuietPopupShowContainerVc, YES);
    DY778REInstall(@"BDXPopupViewController", @"dismissWithAnimated:completion:", "v", "B@",
                   (IMP)DY778REQuietPopupDismiss, &DY778REOriginalQuietPopupDismiss, YES);
    DY778REInstall(@"AnnieLiveBizRouter", @"makeTransitionForSchema:controller:fromVC:context:completion:error:", "v", "@@@@@^",
                   (IMP)DY778REQuietRouterTransition, &DY778REOriginalQuietRouterTransition, YES);
    DY778REInstall(@"IESLiveAioLinkRouterImpl", @"openHybridDialog:", "@", "@",
                   (IMP)DY778REQuietOpenHybridDialog, &DY778REOriginalQuietOpenHybridDialog, YES);
    DY778REInstall(@"IESLiveSchemeRedirectManager", @"resolveRedirectSchemeWith:completion:", "v", "@@",
                   (IMP)DY778REQuietResolveRedirectScheme, &DY778REOriginalQuietResolveRedirectScheme, YES);
    DY778REInstall(@"IESLiveLuckyBoxServiceManager", @"openGrabLuckyBoxView", "v", "",
                   (IMP)DY778REQuietOpenGrabLuckyBoxView, &DY778REOriginalQuietOpenGrabLuckyBoxView, YES);
}

void DY778InstallRedEnvelopeHooks(void) {
    // RE 安装必须在主线程调用：quiet 安装无 dispatch 重试（规格 §1.2），
    // 非主线程直接返回；入口已在主队列调用，延迟重试会再次调用。
    if (!NSThread.isMainThread) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // 先静默抢，后主安装体：Q9 与 W5 是同一个方法 openGrabLuckyBoxView
        // 的双重 hook，后者的 orig 链上是前者；顺序反了链就断。
        DY778InstallREQuietHooks();
        // D1：规格表作 `Bc / @`，按正文「返回 B 参数 c」取 arg c；
        // 若 40.8.0 上实为对象参数，c 不匹配再试 @。
        DY778REInstall(@"LynxEventEmitter", @"dispatchTouchEvent:", "B", "c",
                       (IMP)DY778REDispatchTouchEvent, &DY778REOriginalDispatchTouchEvent, NO);
        if (!DY778REOriginalDispatchTouchEvent) {
            DY778REInstall(@"LynxEventEmitter", @"dispatchTouchEvent:", "B", "@",
                           (IMP)DY778REDispatchTouchEvent, &DY778REOriginalDispatchTouchEvent, NO);
        }
        DY778REInstall(@"IESLiveRedEnvelopeFragment", @"getLynxRedenvelopViwParms:isShowResult:", "@", "@B",
                       (IMP)DY778REGetLynxRedEnvelopeParams, &DY778REOriginalGetLynxRedEnvelopeParams, NO);
        DY778REInstall(@"IESLiveRevenuePlayRedEnvelopeAPIImpl", @"fetchAllRedEnvelopesWithRoomId:", "@", "@",
                       (IMP)DY778REFetchAllRedEnvelopes, &DY778REOriginalFetchAllRedEnvelopes, NO);
        DY778REInstall(@"IESLiveInternalRouterImpl", @"openHybridWithScheme:eventParams:customGlobalProps:playCompleteWithStats:", "@", "@@@@",
                       (IMP)DY778REOpenHybridWithScheme, &DY778REOriginalOpenHybridWithScheme, NO);
        // W1–W31（全部 void 返回；参数串为除 self/_cmd 外的参数类型）。
        DY778REInstall(@"IESLiveRedEnvelopeLynxBaseView", @"onTapped", "v", "",
                       (IMP)DY778RELynxBaseViewTapped, &DY778REOriginalLynxBaseViewTapped, NO);
        DY778REInstall(@"IESLiveLuckyBoxServiceManager", @"createLuckyBoxShortTouchItem:aniViewData:isShowEntranceAnimation:", "v", "@@B",
                       (IMP)DY778RECreateShortTouchItem, &DY778REOriginalCreateShortTouchItem, NO);
        DY778REInstall(@"IESLiveLuckyBoxServiceManager", @"shortTouchIsReady", "v", "",
                       (IMP)DY778REShortTouchIsReady, &DY778REOriginalShortTouchIsReady, NO);
        DY778REInstall(@"IESLiveLuckyBoxServiceManager", @"messageReceived:", "v", "@",
                       (IMP)DY778RELuckyBoxMessageReceived, &DY778REOriginalLuckyBoxMessageReceived, NO);
        DY778REInstall(@"IESLiveLuckyBoxServiceManager", @"openGrabLuckyBoxView", "v", "",
                       (IMP)DY778REOpenGrabLuckyBoxView, &DY778REOriginalOpenGrabLuckyBoxView, NO);
        DY778REInstall(@"IESLiveLuckyBoxServiceManager", @"removeLuckyBoxShortTouchItem", "v", "",
                       (IMP)DY778RERemoveShortTouchItem, &DY778REOriginalRemoveShortTouchItem, NO);
        DY778REInstall(@"IESLiveLuckyBoxServiceManager", @"bindService", "v", "",
                       (IMP)DY778RELuckyBoxBindService, &DY778REOriginalLuckyBoxBindService, NO);
        DY778REInstall(@"IESLiveLuckyBoxServiceManager", @"setRoomModel:", "v", "@",
                       (IMP)DY778RELuckyBoxSetRoomModel, &DY778REOriginalLuckyBoxSetRoomModel, NO);
        DY778REInstall(@"IESLiveLuckyBoxServiceManager", @"subscribeBackend", "v", "",
                       (IMP)DY778RELuckyBoxSubscribeBackend, &DY778REOriginalLuckyBoxSubscribeBackend, NO);
        DY778REInstall(@"IESLiveRedEnvelopeBackendServiceImpl", @"requestRedEnvelopeBackEndData:", "v", "@",
                       (IMP)DY778RERequestBackendData, &DY778REOriginalRequestBackendData, NO);
        DY778REInstall(@"IESLiveAudienceViewController", @"viewDidLayoutSubviews", "v", "",
                       (IMP)DY778REAudienceViewDidLayout, &DY778REOriginalAudienceViewDidLayout, NO);
        DY778REInstall(@"IESLiveAudienceViewController", @"viewDidAppear:", "v", "B",
                       (IMP)DY778REAudienceViewDidAppear, &DY778REOriginalAudienceViewDidAppear, NO);
        DY778REInstall(@"IESLiveAudienceViewController", @"didEnterRoom:", "v", "@",
                       (IMP)DY778REAudienceDidEnterRoom, &DY778REOriginalAudienceDidEnterRoom, NO);
        DY778REInstall(@"IESLiveAudienceViewController", @"didCloseRoom:closeType:", "v", "@q",
                       (IMP)DY778REAudienceDidCloseRoom, &DY778REOriginalAudienceDidCloseRoom, NO);
        DY778REInstall(@"IESLiveAudienceViewController", @"onStartLeaveRoomAnimation", "v", "",
                       (IMP)DY778REAudienceStartLeaveRoom, &DY778REOriginalAudienceStartLeaveRoom, NO);
        DY778REInstall(@"IESLiveAudienceViewController", @"roomWillResignActive:", "v", "@",
                       (IMP)DY778REAudienceRoomWillResign, &DY778REOriginalAudienceRoomWillResign, NO);
        DY778REInstall(@"IESLiveAudienceViewController", @"roomDidBecomeActive:", "v", "@",
                       (IMP)DY778REAudienceRoomDidBecomeActive, &DY778REOriginalAudienceRoomDidBecomeActive, NO);
        DY778REInstall(@"HTSRedEnvelopeStore", @"componentMount", "v", "",
                       (IMP)DY778REStoreComponentMount, &DY778REOriginalStoreComponentMount, NO);
        DY778REInstall(@"HTSRedEnvelopeStore", @"didUpdateRoom:", "v", "@",
                       (IMP)DY778REStoreDidUpdateRoom, &DY778REOriginalStoreDidUpdateRoom, NO);
        DY778REInstall(@"HTSRedEnvelopeStore", @"setRedEnvelopeQueue:", "v", "@",
                       (IMP)DY778REStoreSetRedEnvelopeQueue, &DY778REOriginalStoreSetRedEnvelopeQueue, NO);
        DY778REInstall(@"HTSRedEnvelopeStore", @"fetchAllRedEnvelopesInRoom", "v", "",
                       (IMP)DY778REStoreFetchAllInRoom, &DY778REOriginalStoreFetchAllInRoom, NO);
        DY778REInstall(@"HTSRedEnvelopeStore", @"setResultArray:", "v", "@",
                       (IMP)DY778REStoreSetResultArray, &DY778REOriginalStoreSetResultArray, NO);
        DY778REInstall(@"IESLiveRedEnvelopeFragment", @"setRoom:componentContext:trackContext:", "v", "@@@",
                       (IMP)DY778REFragmentSetRoom, &DY778REOriginalFragmentSetRoom, NO);
        DY778REInstall(@"IESLiveRedEnvelopeFragment", @"remoteRoomDataReady:", "v", "@",
                       (IMP)DY778REFragmentRemoteRoomDataReady, &DY778REOriginalFragmentRemoteRoomDataReady, NO);
        DY778REInstall(@"IESLiveRedEnvelopeFragment", @"componentMount", "v", "",
                       (IMP)DY778REFragmentComponentMount, &DY778REOriginalFragmentComponentMount, NO);
        DY778REInstall(@"IESLiveRedEnvelopeFragment", @"componentBindService", "v", "",
                       (IMP)DY778REFragmentComponentBindService, &DY778REOriginalFragmentComponentBindService, NO);
        DY778REInstall(@"IESLiveRedEnvelopeFragment", @"componentUnmount", "v", "",
                       (IMP)DY778REFragmentComponentUnmount, &DY778REOriginalFragmentComponentUnmount, NO);
        DY778REInstall(@"IESLiveRedEnvelopeFragment", @"setStore:", "v", "@",
                       (IMP)DY778REFragmentSetStore, &DY778REOriginalFragmentSetStore, NO);
        DY778REInstall(@"IESLiveRedEnvelopeFragment", @"showRedEnvelopeViewWith:", "v", "@",
                       (IMP)DY778REFragmentShowViewWith, &DY778REOriginalFragmentShowViewWith, NO);
        DY778REInstall(@"IESLiveRedEnvelopeFragment", @"showRedEnvelopeView", "v", "",
                       (IMP)DY778REFragmentShowView, &DY778REOriginalFragmentShowView, NO);
        DY778REInstall(@"IESLiveRedEnvelopeFragment", @"showLynxRedEnvelopeView:", "v", "@",
                       (IMP)DY778REFragmentShowLynxView, &DY778REOriginalFragmentShowLynxView, NO);
        // 偏好变更观察：redEnvelope.* 键变化时刷新入口与 coordinator。
        [NSNotificationCenter.defaultCenter addObserverForName:DY778PreferencesChangedNotification object:nil
            queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
                NSString *key = notification.userInfo[@"key"];
                if (!key.length || [key hasPrefix:@"redEnvelope."]) {
                    [[DY778RECoordinator shared] tick];
                    [[DY778REEntry shared] refresh];
                }
            }];
        // 尾部取 coordinator 做 host 初始化（原版同款）。
        (void)[DY778RECoordinator shared];
    });
}

// ---------- 未安装的 hook（规格 §11.6，须在汇报里说明） ----------
// 1 个静默直接 hook（安装函数 0x244040 内的 0x244354，类/方法动态算出，
// 未解析）：DYxs 侧不安装、不猜测。若将来以 hooks.py 重跑安装函数
// 解析出类名/方法名/签名，再按 Q1–Q9 同款补装。
// 4 段 XOR 串（0x3cc2b0–0x3cc350）与记录键格式串（0x3c2570 / 0x3c2e10 /
// 0x3cb450）静态不可读：DYxs 侧不猜 URL/签名字段/记录键，记录键自拟
// redEnvelope.* 前缀（见 DY778REInstall）。
