#import "DY778LiveAnalysis.h"
#import "DY778Core.h"
#import "DY778LiveInfo.h"
#import "DY778LiveAnalysisPolicy.h"
#import "DY778LiveToolsPolicy.h"
#import <QuartzCore/QuartzCore.h>
#import <Security/Security.h>
#import <WebKit/WebKit.h>
#import <zlib.h>

// DY778 1.0-8 模块 2 移植：直播数据分析（观众/礼物/PK/人气，只读观测）。
// 规格：~/workspace/plugin-merge/DY778/spec-module2-liveanalysis.md
// hook 常驻装载，行为全部由开关在调用时控制，默认全部关闭：
//   liveAnalysis.enabled        总开关（关则一个 hook 都不装）
//   liveAnalysis.compact        紧凑模式（入口/面板布局）
//   liveAnalysis.entryPosition  入口位置（.portrait/.landscape 两个子键，
//                               同值：bottom-right/bottom-left/top-right/top-left）
//   liveAnalysis.audienceNotice 观众通知开关（默认关）
//   liveAnalysis.giftNotice     礼物通知开关（默认关）
//   liveAnalysis.audience       观众榜弹层开关（默认关）
//   liveAnalysis.audienceValues 观众数值展示（默认开，未证实，见 Policy）
//   liveAnalysis.credentials    凭证配置（不设 UI 行）
//   liveAnalysis.getVisitor / clearVisitor / resetPosition / info
//                               三个按钮动作 + 一条说明（见设置页）
// TODO（需真机验证，规格 §10）：
//   - protobuf 字段号→键映射表未静态还原：解析器只做通用解码，
//     字段号须运行时抓包反推后补进 DY778LAProtoFieldNames。
//   - setContentOffset: 的 CGPoint 校验用了混淆 XOR 常量：先按
//     {CGPoint=dd} 校验，失败再放宽为只比参数个数。
//   - 5 个安装后校验键缺 LynxListContainerView.didMoveToWindow：
//     按 24 个 hook 全装、校验列表照原样 5 个复刻，不自补第 6 个。
//   - _DY778LANativeObserve 疑似空实现：留空实现，不调它做任何事。
//   - WebSocket host 三选一逻辑未拆：先 hl → lf → lq 轮询。
//   - 入口的 LiveTools owner/遮罩门控：DYxs 没有对应 helper，只按
//     liveAnalysis.enabled + 房间上下文门控（见本文件末尾说明）。

static NSString *const DY778LAChannel = @"liveAnalysis";

// ---------- 签名校验（照 DY778LiveLike.m / DY778LiveTools.m 的做法） ----------
static const char *DY778LAType(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type ?: "";
}
static BOOL DY778LAMatches(const char *result, const char *arguments, NSMethodSignature *signature) {
    if (!signature) return NO;
    if (!strchr(result, *DY778LAType(signature.methodReturnType))) return NO;
    if (signature.numberOfArguments != strlen(arguments) + 2) return NO;
    for (NSUInteger i = 0; i < strlen(arguments); i++) {
        const char *actual = DY778LAType([signature getArgumentTypeAtIndex:i + 2]);
        char expected = arguments[i];
        if (expected == 'B' ? !(actual[0] == 'B' || actual[0] == 'c') :
            expected == 'q' ? !(actual[0] == 'q' || actual[0] == 'Q') :
            expected == 'P' ? strcmp(actual, @encode(CGPoint)) != 0 :
            expected == '^' ? !(actual[0] == '^' || actual[0] == '@') : actual[0] != expected) return NO;
    }
    return YES;
}
static BOOL DY778LASignature(Class cls, SEL selector, const char *result, const char *arguments) {
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!method) return NO;
    return DY778LAMatches(result, arguments, [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)]);
}
// 只比参数个数与返回类型首字符（setContentOffset: 的放宽校验，规格 §10.2）。
static BOOL DY778LASignatureLoose(Class cls, SEL selector, const char *result, NSUInteger argumentCount) {
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!method) return NO;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    return signature && strchr(result, *DY778LAType(signature.methodReturnType)) && signature.numberOfArguments == argumentCount + 2;
}
// 逐 hook 开关门控（规格 §1.1、§10.5）：启用集合来源未证实，先实现为
// “总开关开则全装”；liveAnalysis.disabledHooks（字符串数组）留作单 key
// 门控接口，默认空即全部启用，运行时验证后再填。
static BOOL DY778LAHookDisabled(NSString *className, NSString *selector) {
    id disabled = [DY778Preferences() objectForKey:@"liveAnalysis.disabledHooks"];
    if (![disabled isKindOfClass:NSArray.class]) return NO;
    return [disabled containsObject:[NSString stringWithFormat:@"%@.%@", className, selector]];
}
static void DY778LAInstall(NSString *className, NSString *selector, const char *result, const char *arguments, IMP replacement, IMP *original) {
    if (*original) return;
    Class cls = NSClassFromString(className); SEL sel = NSSelectorFromString(selector);
    NSString *recordKey = [NSString stringWithFormat:@"liveAnalysis.audience.%@.%@", className, selector];
    if (DY778LAHookDisabled(className, selector)) { DY778RecordHook(recordKey, NO); return; }
    BOOL installed = DY778LASignature(cls, sel, result, arguments) && DY778Hook(cls, sel, replacement, original);
    DY778RecordHook(recordKey, installed);
}
static void DY778LAInstallCGPoint(NSString *className, NSString *selector, IMP replacement, IMP *original) {
    if (*original) return;
    Class cls = NSClassFromString(className); SEL sel = NSSelectorFromString(selector);
    NSString *recordKey = [NSString stringWithFormat:@"liveAnalysis.audience.%@.%@", className, selector];
    BOOL installed = (DY778LASignature(cls, sel, "v", "P") || DY778LASignatureLoose(cls, sel, "v", 1)) &&
        DY778Hook(cls, sel, replacement, original);
    DY778RecordHook(recordKey, installed);
}
static void DY778LAMain(dispatch_block_t block) {
    if (NSThread.isMainThread) block(); else dispatch_async(dispatch_get_main_queue(), block);
}

BOOL DY778LiveAnalysisEnabled(void) { return DY778Bool(@"liveAnalysis.enabled"); }

// ---------- 通用取值 helper（规格 §2.2、§4.1，两模块共用） ----------
NSString *DY778LAIdentifierValue(id value) {
    NSString *identifier = DY778Identifier(value);
    if (identifier.length) return identifier;
    if ([value respondsToSelector:@selector(stringValue)]) {
        NSString *text = [value stringValue];
        if ([text isKindOfClass:NSString.class] && text.length) return text;
    }
    return nil;
}
NSString *DY778LATextValue(id value) {
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) return [value stringValue];
    return nil;
}
NSArray *DY778LAArrayValue(id value) {
    if ([value isKindOfClass:NSArray.class]) return value;
    if (value) return @[value];
    return @[];
}
long long DY778LAIntegerValue(id value) {
    if ([value respondsToSelector:@selector(longLongValue)]) return [value longLongValue];
    NSString *text = DY778LATextValue(value);
    return text.length ? [text longLongValue] : 0;
}

// ---------- 房间上下文（规格 §6、§9：与模块 1 同一批属性名） ----------
NSString *DY778LiveAnalysisRoomID(id object) {
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
static NSString *DY778LAContextRoomID(id object) {
    NSString *roomID = DY778LiveAnalysisRoomID(object);
    if (roomID.length) return roomID;
    id model = DY778Read(object, @"roomModel");
    if (model && model != object) return DY778LiveAnalysisRoomID(model);
    return nil;
}

// ---------- Protobuf 通用解析器（规格 §3.4：只解码，不写死字段号） ----------
NSDictionary<NSString *, NSString *> *DY778LAProtoFieldNames(void) {
    // 字段号→键名的完整映射表未静态还原（规格 §10.1）。运行时抓包反推
    // （WebSocket 帧 + 已知 uid/rank/score 值反推 tag）后补齐本表；
    // 在此之前不要凭猜测往里写字段号。
    return @{};
}
static BOOL DY778LAProtoVarint(const uint8_t *bytes, NSUInteger length, NSUInteger *offset, uint64_t *value) {
    uint64_t result = 0; NSUInteger shift = 0;
    while (*offset < length) {
        uint8_t byte = bytes[(*offset)++];
        result |= (uint64_t)(byte & 0x7f) << shift;
        if (!(byte & 0x80)) { *value = result; return YES; }
        shift += 7;
        if (shift >= 64) return NO;
    }
    return NO;
}
NSDictionary<NSString *, id> *DY778LAProtoDecodeData(NSData *data) {
    if (!data.length || data.length > DY778LiveAnalysisProtoMaxBytes) return @{};
    const uint8_t *bytes = data.bytes; NSUInteger length = data.length, offset = 0;
    NSMutableDictionary<NSString *, id> *fields = [NSMutableDictionary dictionary];
    NSUInteger count = 0;
    while (offset < length && count < DY778LiveAnalysisProtoMaxFields) {
        uint64_t tag = 0;
        if (!DY778LAProtoVarint(bytes, length, &offset, &tag)) break;
        NSUInteger field = (NSUInteger)(tag >> 3); NSUInteger wire = (NSUInteger)(tag & 0x7);
        count++;
        if (field == 0) break;
        NSString *key = [NSString stringWithFormat:@"%lu", (unsigned long)field];
        if (wire == 0) {
            uint64_t value = 0;
            if (!DY778LAProtoVarint(bytes, length, &offset, &value)) break;
            fields[key] = @(value);
        } else if (wire == 2) {
            uint64_t size = 0;
            if (!DY778LAProtoVarint(bytes, length, &offset, &size) || size > length - offset) break;
            NSData *chunk = [NSData dataWithBytes:bytes + offset length:(NSUInteger)size];
            offset += (NSUInteger)size;
            NSString *text = [[NSString alloc] initWithData:chunk encoding:NSUTF8StringEncoding];
            fields[key] = text ?: chunk;
        } else if (wire == 1) {
            if (8 > length - offset) break;
            fields[key] = [NSData dataWithBytes:bytes + offset length:8]; offset += 8;
        } else if (wire == 5) {
            if (4 > length - offset) break;
            fields[key] = [NSData dataWithBytes:bytes + offset length:4]; offset += 4;
        } else break;
    }
    return [fields copy];
}
NSData *DY778LAProtoInflateData(NSData *data) {
    if (!data.length || data.length > DY778LiveAnalysisProtoMaxBytes) return nil;
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    if (inflateInit2_(&stream, 47, ZLIB_VERSION, (int)sizeof(stream)) != Z_OK) return nil;
    NSMutableData *output = [NSMutableData dataWithLength:DY778LiveAnalysisProtoMaxBytes];
    stream.next_in = (Bytef *)data.bytes; stream.avail_in = (uInt)data.length;
    stream.next_out = output.mutableBytes; stream.avail_out = (uInt)output.length;
    int result = inflate(&stream, Z_FINISH);
    NSUInteger produced = output.length - stream.avail_out;
    inflateEnd(&stream);
    if (result != Z_STREAM_END && result != Z_OK && result != Z_BUF_ERROR) return nil;
    return [output subdataWithRange:NSMakeRange(0, produced)];
}
NSString *DY778LAProtoText(NSDictionary<NSString *, id> *decoded, NSUInteger field) {
    id value = decoded[[NSString stringWithFormat:@"%lu", (unsigned long)field]];
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSData.class]) return [[NSString alloc] initWithData:value encoding:NSUTF8StringEncoding];
    if ([value isKindOfClass:NSNumber.class]) return [value stringValue];
    return nil;
}
long long DY778LAProtoInteger(NSDictionary<NSString *, id> *decoded, NSUInteger field) {
    id value = decoded[[NSString stringWithFormat:@"%lu", (unsigned long)field]];
    if ([value respondsToSelector:@selector(longLongValue)]) return [value longLongValue];
    return 0;
}
NSData *DY778LAProtoBytes(NSDictionary<NSString *, id> *decoded, NSUInteger field) {
    id value = decoded[[NSString stringWithFormat:@"%lu", (unsigned long)field]];
    if ([value isKindOfClass:NSData.class]) return value;
    if ([value isKindOfClass:NSString.class]) return [value dataUsingEncoding:NSUTF8StringEncoding];
    return nil;
}
NSDictionary *DY778LAProtoUser(NSDictionary *record) {
    if (![record isKindOfClass:NSDictionary.class]) return nil;
    NSMutableDictionary *user = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"uid", @"id", @"name", @"avatarURLs", @"avatar_thumb", @"url_list",
                            @"hidden", @"score", @"contribution"]) {
        id value = record[key];
        if (!value) continue;
        if ([key isEqualToString:@"uid"] || [key isEqualToString:@"id"]) {
            NSString *identifier = DY778LAIdentifierValue(value);
            if (identifier.length) user[@"uid"] = identifier;
        } else if ([key isEqualToString:@"avatarURLs"] || [key isEqualToString:@"url_list"]) {
            user[@"avatarURLs"] = DY778LAArrayValue(value);
        } else if ([key isEqualToString:@"score"] || [key isEqualToString:@"contribution"]) {
            user[@"score"] = @(DY778LAIntegerValue(value));
            if ([key isEqualToString:@"contribution"]) user[@"contribution"] = @(DY778LAIntegerValue(value));
        } else user[key] = value;
    }
    return [user copy];
}

// ---------- 共享上下文 ----------
@implementation DY778LAContext
+ (instancetype)shared {
    static DY778LAContext *value; static dispatch_once_t once;
    dispatch_once(&once, ^{ value = [self new]; }); return value;
}
- (void)noteRoomID:(NSString *)roomID {
    if (!roomID.length) return;
    if (![roomID isEqualToString:self.roomID]) { self.roomID = roomID; self.finishLoad = NO; self.showRank = NO; }
}
- (void)noteFinishLoad:(BOOL)finishLoad { self.finishLoad = finishLoad; }
- (void)noteShowRank:(BOOL)showRank { self.showRank = showRank; }
- (void)noteAudienceDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:NSDictionary.class]) return;
    NSArray *members = DY778LAArrayValue(dictionary[@"members"]);
    if (!members.count) members = DY778LAArrayValue(dictionary[@"ranks"]);
    if (!members.count) return;
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
    for (id member in members) {
        if (![member isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *user = DY778LAProtoUser(member);
        if (user) [rows addObject:user];
        if (rows.count >= DY778LiveAnalysisMaximumRows) break;
    }
    if (rows.count) self.audienceRows = rows;
}
- (void)noteLynxView:(UIView *)view {
    if (![view isKindOfClass:UIView.class]) return;
    for (UIView *cursor = view; cursor; cursor = cursor.superview) {
        for (NSString *key in @[@"uiHolder", @"view", @"me", @"itemKey", @"LynxView"]) {
            id holder = DY778Read(cursor, key);
            if (!holder) continue;
            for (NSString *urlKey in @[@"url", @"bdx_URL", @"absoluteString"]) {
                NSString *text = DY778LATextValue(DY778Read(holder, urlKey));
                if (text.length) { [self noteRoomID:DY778LAIdentifierValue(DY778Read(holder, @"roomID"))]; return; }
            }
        }
    }
}
- (void)clear { self.roomID = nil; self.finishLoad = NO; self.showRank = NO; self.audienceRows = nil; }
@end

BOOL DY778LiveAnalysisEntryVisible(void) {
    return DY778LiveAnalysisEnabled() && DY778LAContext.shared.roomID.length > 0;
}

// ---------- 凭证与会话（规格 §5） ----------
static NSString *DY778LAKeychainService(void) {
    return [NSString stringWithUTF8String:DY778LiveAnalysisKeychainService];
}
static NSString *DY778LAStoredVisitorTTWID(void) {
    NSDictionary *query = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: DY778LAKeychainService(), (__bridge id)kSecAttrAccount: @"visitor",
        (__bridge id)kSecReturnData: @YES, (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne};
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) != errSecSuccess || !result) return nil;
    NSData *data = (__bridge_transfer NSData *)result;
    NSString *ttwid = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return DY778LiveToolsValidTTWID(ttwid.UTF8String) ? ttwid : nil;
}
static void DY778LAStoreVisitorTTWID(NSString *ttwid) {
    if (!DY778LiveToolsValidTTWID(ttwid.UTF8String)) return;
    NSDictionary *query = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: DY778LAKeychainService(), (__bridge id)kSecAttrAccount: @"visitor"};
    SecItemDelete((__bridge CFDictionaryRef)query);
    NSMutableDictionary *item = [query mutableCopy];
    item[(__bridge id)kSecValueData] = [ttwid dataUsingEncoding:NSUTF8StringEncoding];
    SecItemAdd((__bridge CFDictionaryRef)item, NULL);
}
static void DY778LAClearStoredVisitor(void) {
    NSDictionary *query = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: DY778LAKeychainService(), (__bridge id)kSecAttrAccount: @"visitor"};
    SecItemDelete((__bridge CFDictionaryRef)query);
}
void DY778LiveAnalysisRegisterVisitor(void (^completion)(NSString *ttwid)) {
    NSString *stored = DY778LAStoredVisitorTTWID();
    if (stored.length) { if (completion) completion(stored); return; }
    NSString *configured = [DY778String(@"liveTools.ttwid") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (DY778LiveToolsValidTTWID(configured.UTF8String)) {
        DY778LAStoreVisitorTTWID(configured);
        if (completion) completion(configured);
        return;
    }
    NSURL *url = [NSURL URLWithString:[NSString stringWithUTF8String:DY778LiveAnalysisVisitorRegisterURL]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:[NSString stringWithUTF8String:DY778LiveAnalysisUserAgent] forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSDictionary *body = @{@"region": @"cn", @"aid": @6383, @"needFid": @YES, @"service": @"www.ixigua.com",
        @"migrate_info": @"", @"ticket": @"", @"source": @"", @"node": @"", @"cbUrlProtocol": @"https"};
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSString *ttwid = nil;
        if (data.length && !error) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json isKindOfClass:NSDictionary.class]) {
                ttwid = DY778LAIdentifierValue(json[@"ttwid"] ?: json[@"visitor_id"] ?: json[@"data"][@"ttwid"]);
            }
        }
        if (DY778LiveToolsValidTTWID(ttwid.UTF8String)) DY778LAStoreVisitorTTWID(ttwid);
        else ttwid = nil;
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(ttwid); });
    }] resume];
}
void DY778LiveAnalysisClearCredential(void) {
    DY778LAClearStoredVisitor();
    DY778LAMain(^{ DY778ShowToast(DY778LAChannel, @"已清除直播数据分析的游客凭证", NO, YES); });
}
BOOL DY778LiveAnalysisHasLogin(void) {
    for (NSHTTPCookie *cookie in NSHTTPCookieStorage.sharedHTTPCookieStorage.cookies) {
        if (([cookie.name isEqualToString:@"sessionid"] || [cookie.name isEqualToString:@"sessionid_ss"]) && cookie.value.length) return YES;
    }
    return NO;
}
// 网页登录抓 Cookie（规格 §5）：WKWebView 加载 live.douyin.com，走网页登录后
// 读 Cookie；内含的 JS 在 6 秒超时内 fetch account/info 取 user_id_str。
// 混淆字符串段（__cstring 乱码）是编译期 XOR、静态不可读，按明文接口实现。
@interface DY778LACredentialViewController : UIViewController <WKNavigationDelegate>
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, copy) void (^completion)(BOOL success);
@end
@implementation DY778LACredentialViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = DY778Background();
    WKWebViewConfiguration *config = [WKWebViewConfiguration new];
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    self.webView.navigationDelegate = self;
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.webView];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
        target:self action:@selector(close)];
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://live.douyin.com/"]];
    [self.webView loadRequest:request];
}
- (void)close {
    void (^completion)(BOOL) = self.completion; self.completion = nil;
    [self dismissViewControllerAnimated:YES completion:^{ if (completion) completion(DY778LiveAnalysisHasLogin()); }];
}
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    (void)navigation;
    NSString *script = @"fetch('/passport/web/account/info/?aid=6383').then(r=>r.text()).then(t=>t).catch(()=> '')";
    [webView evaluateJavaScript:script completionHandler:^(__unused id result, __unused NSError *error) {
        if (DY778LiveAnalysisHasLogin()) {
            void (^completion)(BOOL) = self.completion; self.completion = nil;
            [self dismissViewControllerAnimated:YES completion:^{ if (completion) completion(YES); }];
        }
    }];
}
@end
void DY778LiveAnalysisAcquireCredential(void (^completion)(BOOL success)) {
    DY778LAMain(^{
        DY778LACredentialViewController *controller = [DY778LACredentialViewController new];
        controller.completion = completion;
        UIViewController *top = DY778TopController();
        if (top) DY778PresentController(top, [[UINavigationController alloc] initWithRootViewController:controller]);
        else if (completion) completion(NO);
    });
}

// ---------- 原生接口（规格 §3.3：走抖音 App 内原生网络/账号服务） ----------
static NSString *DY778LANativeSecUserID(void) {
    Class serviceClass = NSClassFromString(@"AWEUserService");
    id service = nil;
    if (serviceClass && [serviceClass respondsToSelector:@selector(sharedService)]) {
        @try { service = ((id (*)(id, SEL))objc_msgSend)(serviceClass, @selector(sharedService)); } @catch (__unused NSException *e) {}
    }
    for (NSString *userKey in @[@"currentLoginUser", @"currentUser"]) {
        id user = DY778Read(service, userKey);
        for (NSString *key in @[@"secUserID", @"sec_user_id", @"userID"]) {
            NSString *identifier = DY778LAIdentifierValue(DY778Read(user, key));
            if (identifier.length) return identifier;
        }
    }
    return DY778CurrentAccountID() ?: @"";
}
static NSString *DY778LANativeAPIOrigin(void) {
    Class wrapperClass = NSClassFromString(@"IESLiveHTTPClientWrapper");
    id wrapper = nil;
    if (wrapperClass && [wrapperClass respondsToSelector:@selector(sharedInstance)]) {
        @try { wrapper = ((id (*)(id, SEL))objc_msgSend)(wrapperClass, @selector(sharedInstance)); } @catch (__unused NSException *e) {}
    }
    NSString *host = DY778LATextValue(DY778Read(wrapper, @"currentHostURL"));
    if (host.length) return host;
    return [NSString stringWithUTF8String:DY778LiveAnalysisNativeOriginFallback];
}
static NSArray<NSHTTPCookie *> *DY778LANativeCookies(NSURL *url) {
    Class cookieClass = NSClassFromString(@"TTAccountCookie");
    if (cookieClass && [cookieClass respondsToSelector:@selector(cookiesForURL:)]) {
        @try {
            id cookies = ((id (*)(id, SEL, id))objc_msgSend)(cookieClass, @selector(cookiesForURL:), url);
            if ([cookies isKindOfClass:NSArray.class]) return cookies;
        } @catch (__unused NSException *e) {}
    }
    return @[];
}
// _DY778LANativeObserve：仅 24 条指令、无任何调用，疑似空实现/占位
// （规格 §10.4）。留空实现，不调它做任何事。
// _DY778LANativeCancel（取消在途原生请求）：DYxs 侧原生请求是一次性
// 调用、无任务句柄可取消，故不设对应函数；WebSocket/HTTP 的取消走
// 各自的 close/cancel。
static void DY778LANativeObserve(void) {}

// ---------- 网络层：WebSocket 流（规格 §3.1） ----------
@interface DY778LAStream () <NSURLSessionWebSocketDelegate>
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSURLSessionWebSocketTask *task;
@property(nonatomic, strong) NSTimer *heartbeatTimer;
@property(nonatomic) NSUInteger hostIndex;
@property(nonatomic) NSUInteger retries;
@property(nonatomic, copy) NSString *roomID;
@property(nonatomic, copy) void (^onMessage)(NSDictionary *decoded);
@property(nonatomic, readwrite) BOOL socketOpen;
@property(nonatomic, readwrite) BOOL receiving;
@property(nonatomic, readwrite) BOOL connecting;
@property(nonatomic, readwrite) BOOL polling;
@property(nonatomic, readwrite) BOOL fallbackUsed;
@end
@implementation DY778LAStream
- (void)connectRoom:(NSString *)roomID {
    if (!roomID.length || !DY778LiveAnalysisEnabled()) return;
    [self close];
    self.roomID = roomID; self.connecting = YES; self.retries = 0;
    [self connectWithHostIndex:self.hostIndex];
}
- (void)connectWithHostIndex:(NSUInteger)index {
    const char *host = DY778LiveAnalysisHosts[index % DY778LiveAnalysisHostCount];
    NSString *endpoint = [NSString stringWithFormat:[NSString stringWithUTF8String:DY778LiveAnalysisWSEndpointFormat], host];
    NSString *visitor = DY778LAStoredVisitorTTWID() ?: DY778LANativeSecUserID();
    self.visitorID = visitor;
    NSString *query = [NSString stringWithFormat:
        @"live_id=1&aid=6383&version_code=180800&webcast_sdk_version=1.0.15&room_id=%@&sub_room_id=&sub_channel_id=&did_rule=3&user_unique_id=%@&device_platform=web&device_type=&ac=&identity=audience",
        self.roomID, visitor ?: @""];
    NSURL *url = [NSURL URLWithString:[endpoint stringByAppendingString:query]];
    if (!url) { self.connecting = NO; return; }
    self.session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration delegate:self delegateQueue:nil];
    self.task = [self.session webSocketTaskWithURL:url];
    [self.task resume];
    self.socketOpen = YES; self.connecting = NO; self.receiving = YES;
    [self startHeartbeat];
    [self receiveNext];
}
- (void)receiveNext {
    if (!self.task) return;
    __weak typeof(self) weakSelf = self;
    [self.task receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *message, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || error) { [strongSelf socketFailed:error retry:YES]; return; }
        if (message.type == NSURLSessionWebSocketMessageTypeData && message.data.length) [strongSelf consumeData:message.data];
        [strongSelf receiveNext];
    }];
}
- (void)socketFailed:(NSError *)error retry:(BOOL)retry {
    self.socketOpen = NO; self.receiving = NO;
    [self.heartbeatTimer invalidate]; self.heartbeatTimer = nil;
    if (!retry || !DY778LiveAnalysisEnabled() || self.retries >= DY778LiveAnalysisMaximumRetries) return;
    self.retries++;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(DY778LiveAnalysisDefaultRetrySeconds * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{ [self connectWithHostIndex:self.hostIndex + self.retries]; });
}
- (void)startHeartbeat {
    [self.heartbeatTimer invalidate];
    __weak typeof(self) weakSelf = self;
    self.heartbeatTimer = [NSTimer timerWithTimeInterval:DY778LiveAnalysisDefaultHeartbeatSeconds repeats:YES block:^(__unused NSTimer *timer) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.task) return;
        [strongSelf.task sendPingWithPongReceiveHandler:^(__unused NSError *error) {}];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.heartbeatTimer forMode:NSRunLoopCommonModes];
}
- (void)send:(NSData *)data {
    if (!self.task || !data.length) return;
    [self.task sendMessage:[[NSURLSessionWebSocketMessage alloc] initWithData:data] completionHandler:^(__unused NSError *error) {}];
}
- (void)consumeData:(NSData *)data {
    if (!data.length) return;
    NSData *inflated = DY778LAProtoInflateData(data) ?: data;
    NSDictionary<NSString *, id> *decoded = DY778LAProtoDecodeData(inflated);
    if (!decoded.count) return;
    // 字段号→键映射未还原（规格 §10.1）：此处不按猜测的字段号取
    // cursor / internal_ext / payload，只把原始字段号字典透传给
    // Board；映射表（DY778LAProtoFieldNames）补齐后再按名取值。
    // IM 响应字段名见规格 §3.4：msg / payload / cursor /
    // internal_ext / server / heartbeat / fetch_interval /
    // status_code / data。
    if (self.onMessage) self.onMessage(decoded);
}
- (void)close {
    [self.heartbeatTimer invalidate]; self.heartbeatTimer = nil;
    [self.task cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:nil];
    self.task = nil; [self.session invalidateAndCancel]; self.session = nil;
    self.socketOpen = NO; self.receiving = NO; self.connecting = NO; self.polling = NO;
}
- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(NSError *)error {
    (void)session; (void)error; self.socketOpen = NO;
}
@end

// ---------- 网络层：HTTP 兜底（规格 §3.2） ----------
@implementation DY778LAClient
- (void)get:(NSString *)url params:(NSDictionary *)params completion:(void (^)(NSDictionary *response, NSError *error))completion {
    if (!url.length) { if (completion) completion(nil, [NSError errorWithDomain:@"DY778LA" code:-1 userInfo:nil]); return; }
    NSMutableArray<NSString *> *pairs = [NSMutableArray array];
    for (NSString *key in params) {
        NSString *value = DY778LATextValue(params[key]) ?: @"";
        [pairs addObject:[NSString stringWithFormat:@"%@=%@", key, [value stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet]]];
    }
    NSString *full = pairs.count ? [NSString stringWithFormat:@"%@?%@", url, [pairs componentsJoinedByString:@"&"]] : url;
    NSURL *requestURL = [NSURL URLWithString:full];
    if (!requestURL) { if (completion) completion(nil, [NSError errorWithDomain:@"DY778LA" code:-2 userInfo:nil]); return; }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:requestURL];
    // 原生 Cookie（TTAccountCookie）随请求带上，补齐登录态（规格 §3.3）。
    NSArray<NSHTTPCookie *> *nativeCookies = DY778LANativeCookies(requestURL);
    if (nativeCookies.count) [request setAllHTTPHeaderFields:[NSHTTPCookie requestHeaderFieldsWithCookies:nativeCookies]];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSDictionary *json = nil;
        if (data.length && !error) {
            id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([parsed isKindOfClass:NSDictionary.class]) json = parsed;
        }
        if (completion) completion(json, error ?: (json ? nil : [NSError errorWithDomain:@"DY778LA" code:-3 userInfo:nil]));
        (void)response;
    }] resume];
}
- (void)fetchAudience:(NSString *)roomID completion:(void (^)(NSDictionary *response, NSError *error))completion {
    [self get:[NSString stringWithUTF8String:DY778LiveAnalysisHTTPAudienceURL]
        params:@{@"room_id": roomID ?: @"", @"aid": @6383} completion:completion];
}
- (void)fetchHot:(NSString *)roomID completion:(void (^)(NSDictionary *response, NSError *error))completion {
    NSString *origin = DY778LANativeAPIOrigin();
    [self get:[origin stringByAppendingString:@"/webcast/ranklist/hot"]
        params:@{@"room_id": roomID ?: @"", @"sec_user_id": DY778LANativeSecUserID()} completion:completion];
}
@end

// ---------- 网络层：Push 上层封装（规格 §3.1） ----------
@interface DY778LAPush ()
@property(nonatomic, strong, readwrite) DY778LAStream *stream;
@property(nonatomic, strong, readwrite) DY778LABattle *battle;
@property(nonatomic, strong, readwrite) DY778LAGiftLedger *giftLedger;
@property(nonatomic, copy, readwrite) NSArray<NSDictionary *> *audienceScores;
@property(nonatomic, strong) DY778LABoard *board;
@property(nonatomic, copy) NSString *roomID;
@end
@implementation DY778LAPush
- (instancetype)initWithRoom:(NSString *)roomID {
    if ((self = [super init])) {
        _roomID = roomID;
        _stream = [DY778LAStream new];
        _battle = [DY778LABattle new];
        _giftLedger = [[DY778LAGiftLedger alloc] initWithRoom:roomID];
        _board = [[DY778LABoard alloc] initWithRoom:roomID seed:nil];
        __weak typeof(self) weakSelf = self;
        _stream.onMessage = ^(NSDictionary *decoded) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf.board applyRanks:decoded];
            [strongSelf.giftLedger consumePayload:decoded];
            [strongSelf.battle consumePayload:decoded room:strongSelf.roomID];
        };
    }
    return self;
}
- (void)connectRoom:(NSString *)roomID { [self.stream connectRoom:roomID]; }
- (void)connectAudienceRoom:(NSString *)roomID { [self.stream connectRoom:roomID]; }
- (void)subscribeRoom:(NSString *)roomID { [self.stream connectRoom:roomID]; }
- (void)close { [self.stream close]; }
@end

// ---------- 数据模型：礼物台账（规格 §4.2） ----------
@interface DY778LAGiftLedger ()
@property(nonatomic, strong, readwrite) NSDate *startedAt;
@property(nonatomic, strong, readwrite) NSDate *updated;
@property(nonatomic, strong, readwrite) NSArray<NSDictionary *> *cachedRows;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *rows;
@end
@implementation DY778LAGiftLedger
- (instancetype)initWithRoom:(NSString *)roomID {
    if ((self = [super init])) {
        _roomID = roomID; _startedAt = [NSDate date]; _updated = _startedAt;
        _rows = [NSMutableArray array]; _cachedRows = @[];
    }
    return self;
}
- (void)markGap { self.incomplete = YES; }
- (void)consumePayload:(NSDictionary *)payload {
    if (![payload isKindOfClass:NSDictionary.class]) return;
    NSArray *gifts = DY778LAArrayValue(payload[@"gifts"] ?: payload[@"data"] ?: payload[@"ranks"]);
    if (!gifts.count) return;
    for (id gift in gifts) {
        if (![gift isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *user = DY778LAProtoUser(gift);
        if (!user) continue;
        NSMutableDictionary *row = [user mutableCopy];
        row[@"source"] = DY778LATextValue(gift[@"source"]) ?: @"";
        row[@"sourceLabel"] = DY778LATextValue(gift[@"sourceLabel"]) ?: @"";
        row[@"room_contribution"] = @(DY778LAIntegerValue(gift[@"room_contribution"]));
        [self.rows addObject:row];
        if (self.rows.count > DY778LiveAnalysisMaximumGiftRows) [self.rows removeObjectAtIndex:0];
    }
    self.updated = [NSDate date]; self.cachedRows = [self.rows copy];
}
- (NSArray<NSDictionary *> *)mergedGiftsForKeys:(NSArray<NSString *> *)keys {
    NSMutableDictionary<NSString *, NSMutableDictionary *> *merged = [NSMutableDictionary dictionary];
    for (NSDictionary *row in self.rows) {
        NSString *key = @"";
        for (NSString *part in keys) {
            NSString *value = DY778LAIdentifierValue(row[part]);
            if (value.length) { key = value; break; }
        }
        if (!key.length) continue;
        NSMutableDictionary *entry = merged[key] ?: [NSMutableDictionary dictionary];
        entry[@"uid"] = key;
        entry[@"score"] = @([entry[@"score"] longLongValue] + DY778LAIntegerValue(row[@"score"]));
        entry[@"name"] = row[@"name"] ?: entry[@"name"];
        merged[key] = entry;
    }
    return [[merged allValues] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        long long sa = [a[@"score"] longLongValue], sb = [b[@"score"] longLongValue];
        return sa > sb ? NSOrderedAscending : sa < sb ? NSOrderedDescending : NSOrderedSame;
    }];
}
- (NSArray<NSDictionary *> *)rowsForAnchor:(NSString *)anchorID {
    if (!anchorID.length) return @[];
    return [self.rows filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"uid == %@ OR anchor == %@", anchorID, anchorID]];
}
- (NSArray<NSDictionary *> *)giftsForUser:(NSString *)userID {
    if (!userID.length) return @[];
    return [self.rows filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"uid == %@", userID]];
}
@end

// ---------- 数据模型：PK 状态机（规格 §4.3） ----------
@implementation DY778LABattle
- (void)consumePayload:(NSDictionary *)payload room:(NSString *)roomID {
    (void)roomID;
    if (![payload isKindOfClass:NSDictionary.class]) return;
    NSDictionary *battle = payload[@"battle"] ?: payload[@"teamfight"];
    if ([battle isKindOfClass:NSDictionary.class]) [self consumeTeamfight:battle clock:[NSDate date].timeIntervalSince1970];
    if (payload[@"teams"]) self.teams = DY778LAArrayValue(payload[@"teams"]);
    if (payload[@"seats"]) self.seats = DY778LAArrayValue(payload[@"seats"]);
    if (payload[@"teamScores"]) self.teamScores = payload[@"teamScores"];
}
- (void)consumeTeamfight:(NSDictionary *)fields clock:(NSTimeInterval)clock {
    (void)clock;
    if (![fields isKindOfClass:NSDictionary.class]) return;
    self.active = YES;
    if (fields[@"teams"]) self.teams = DY778LAArrayValue(fields[@"teams"]);
    if (fields[@"status"]) self.status = DY778LATextValue(fields[@"status"]);
    if (fields[@"scores"]) self.teamScores = fields[@"scores"];
}
- (void)endBattle:(NSTimeInterval)clock {
    (void)clock;
    self.settled = YES; self.active = NO;
}
- (NSInteger)contributionIndexForAnchor:(NSString *)anchorID {
    if (!anchorID.length) return NSNotFound;
    return [self.teams indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
        (void)idx; (void)stop;
        return [DY778LAIdentifierValue([obj isKindOfClass:NSDictionary.class] ? obj[@"uid"] : nil) isEqualToString:anchorID];
    }];
}
- (void)retireBattle { self.retired = YES; self.active = NO; }
@end

// ---------- 数据模型：聚合板（规格 §4.4、§7） ----------
@interface DY778LABoard ()
@property(nonatomic, strong) DY778LABattle *battle;
@property(nonatomic, strong) DY778LAGiftLedger *giftLedger;
@property(nonatomic, strong) DY778LAClient *client;
@property(nonatomic, strong) DY778LAClient *hotClient;
@property(nonatomic) NSTimeInterval hotTimestamp;
@end
@implementation DY778LABoard
- (instancetype)initWithRoom:(NSString *)roomID seed:(NSDictionary *)seed {
    if ((self = [super init])) {
        _roomID = roomID; _status = @"idle";
        _battle = [DY778LABattle new];
        _giftLedger = [[DY778LAGiftLedger alloc] initWithRoom:roomID];
        _client = [DY778LAClient new]; _hotClient = [DY778LAClient new];
        if ([seed isKindOfClass:NSDictionary.class]) [self applyRanks:seed];
    }
    return self;
}
- (void)applyRanks:(NSDictionary *)response {
    if (![response isKindOfClass:NSDictionary.class]) return;
    NSArray *ranks = DY778LAArrayValue(response[@"ranks"] ?: response[@"data"]);
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
    for (id rank in ranks) {
        if (![rank isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *user = DY778LAProtoUser(rank);
        if (!user) continue;
        NSMutableDictionary *row = [user mutableCopy];
        row[@"rank"] = @(DY778LAIntegerValue(rank[@"rank"] ?: rank[@"index"]));
        row[@"source"] = DY778LATextValue(rank[@"source"]) ?: @"";
        [rows addObject:row];
        if (rows.count >= DY778LiveAnalysisMaximumRows) break;
    }
    if (rows.count) { self.rankRows = rows; self.status = @"ready"; }
    self.generation++;
}
- (void)applyHot:(NSDictionary *)response {
    if (![response isKindOfClass:NSDictionary.class]) return;
    self.hotTimestamp = [NSDate date].timeIntervalSince1970;
    [self applyRanks:response];
}
- (void)applyRoom:(NSDictionary *)room error:(NSError *)error sec:(NSString *)secUserID {
    (void)secUserID;
    if (error) { self.status = @"error"; self.failures++; return; }
    if ([room isKindOfClass:NSDictionary.class]) {
        NSString *roomID = DY778LAIdentifierValue(room[@"room_id_str"] ?: room[@"id_str"]);
        if (roomID.length) self.roomID = roomID;
        self.status = @"ready";
    }
}
- (void)applyPK:(NSDictionary *)battle room:(NSString *)roomID {
    if (![battle isKindOfClass:NSDictionary.class]) return;
    [self.battle consumePayload:battle room:roomID];
}
- (void)refresh {
    if (!self.roomID.length || !DY778LiveAnalysisEnabled()) return;
    __weak typeof(self) weakSelf = self;
    [self.client fetchAudience:self.roomID completion:^(NSDictionary *response, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (error) { strongSelf.failures++; return; }
        [strongSelf applyRanks:response ?: @{}];
    }];
}
- (void)refreshHot {
    if (!self.roomID.length || !DY778LiveAnalysisEnabled()) return;
    __weak typeof(self) weakSelf = self;
    [self.hotClient fetchHot:self.roomID completion:^(NSDictionary *response, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || error) return;
        [strongSelf applyHot:response ?: @{}];
    }];
}
- (void)expireHour { self.hotTimestamp = 0; }
@end

// ---------- UI 小件（规格 §6、§7：40 个方法以下的小类按需合并） ----------
@interface DY778LAStateView : UIView
- (instancetype)initCompact:(BOOL)compact;
- (void)setTitle:(NSString *)title detail:(NSString *)detail loading:(BOOL)loading;
@end
@implementation DY778LAStateView {
    UILabel *_titleLabel;
    UILabel *_detailLabel;
    UIActivityIndicatorView *_spinner;
}
- (instancetype)initCompact:(BOOL)compact {
    if ((self = [super initWithFrame:CGRectZero])) {
        self.backgroundColor = [DY778CardBackground() colorWithAlphaComponent:.9];
        self.layer.cornerRadius = compact ? 10 : 14;
        _titleLabel = [UILabel new]; _titleLabel.font = [UIFont boldSystemFontOfSize:compact ? 14 : 16];
        _titleLabel.textColor = DY778Accent(); _detailLabel = [UILabel new];
        _detailLabel.font = [UIFont systemFontOfSize:compact ? 12 : 13]; _detailLabel.numberOfLines = 0;
        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        for (UIView *v in @[_titleLabel, _detailLabel, _spinner]) { v.translatesAutoresizingMaskIntoConstraints = NO; [self addSubview:v]; }
        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:12],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
            [_detailLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:4],
            [_detailLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
            [_detailLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
            [_detailLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12],
            [_spinner.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
            [_spinner.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
        ]];
    }
    return self;
}
- (void)setTitle:(NSString *)title detail:(NSString *)detail loading:(BOOL)loading {
    _titleLabel.text = title; _detailLabel.text = detail;
    if (loading) [_spinner startAnimating]; else [_spinner stopAnimating];
}
@end

// ---------- UI：入口悬浮按钮（规格 §6，SF Symbol chart.bar.fill） ----------
@implementation DY778LAEntry {
    UIButton *_button;
}
+ (instancetype)shared {
    static DY778LAEntry *value; static dispatch_once_t once;
    dispatch_once(&once, ^{ value = [self new]; }); return value;
}
- (void)refresh {
    if (!DY778LiveAnalysisEntryVisible()) { [self hide]; return; }
    DY778LAMain(^{
        UIWindow *window = DY778ActiveWindow();
        if (!window) return;
        if (!self->_button) {
            self->_button = [UIButton buttonWithType:UIButtonTypeSystem];
            UIImage *icon = DY778MenuIcon(@"chart.bar.fill");
            [self->_button setImage:icon ?: [UIImage systemImageNamed:@"chart.bar.fill"] forState:UIControlStateNormal];
            self->_button.backgroundColor = [DY778CardBackground() colorWithAlphaComponent:.92];
            self->_button.tintColor = DY778Accent();
            self->_button.layer.cornerRadius = 22; self->_button.layer.masksToBounds = YES;
            [self->_button addTarget:self action:@selector(openPanel) forControlEvents:UIControlEventTouchUpInside];
        }
        BOOL compact = DY778Bool(@"liveAnalysis.compact");
        CGFloat side = compact ? 36 : 44;
        self->_button.frame = CGRectMake(0, 0, side, side);
        NSString *position = DY778String(@"liveAnalysis.entryPosition.portrait");
        if (!DY778LiveAnalysisValidEntryPosition(position.UTF8String)) position = @"bottom-right";
        CGFloat margin = 16, bottom = 180;
        CGRect bounds = window.bounds;
        CGFloat x = [position containsString:@"left"] ? margin : bounds.size.width - side - margin;
        CGFloat y = [position hasPrefix:@"top"] ? 120 : bounds.size.height - bottom - side;
        self->_button.frame = CGRectMake(x, y, side, side);
        if (self->_button.superview != window) [window addSubview:self->_button];
        [window bringSubviewToFront:self->_button];
    });
}
- (void)hide {
    DY778LAMain(^{ [self->_button removeFromSuperview]; self->_button = nil; });
}
- (void)openPanel {
    NSString *roomID = DY778LAContext.shared.roomID;
    if (!roomID.length) return;
    DY778LAMain(^{
        UIViewController *top = DY778TopController();
        if (top) DY778PresentController(top, [[DY778LAPanel alloc] initWithRoom:roomID]);
    });
}
@end

// ---------- UI：主面板（规格 §6、§7） ----------
@interface DY778LAPanel () <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, strong) DY778LABoard *board;
@property(nonatomic, strong) DY778LAPush *push;
@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic, strong) DY778LAStateView *stateView;
@end
@implementation DY778LAPanel
- (instancetype)initWithRoom:(NSString *)roomID {
    if ((self = [super init])) {
        _board = [[DY778LABoard alloc] initWithRoom:roomID seed:nil];
        _push = [[DY778LAPush alloc] initWithRoom:roomID];
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"直播数据分析";
    self.view.backgroundColor = DY778Background();
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
        target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
        target:self action:@selector(refreshTapped)];
    self.stateView = [[DY778LAStateView alloc] initCompact:DY778Bool(@"liveAnalysis.compact")];
    self.stateView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.stateView];
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.dataSource = self; self.tableView.delegate = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.stateView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [self.stateView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [self.stateView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [self.tableView.topAnchor constraintEqualToAnchor:self.stateView.bottomAnchor constant:8],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    [self refreshAll];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.push connectRoom:self.board.roomID];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stop];
}
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)refreshTapped { [self refreshAll]; }
- (void)refreshAll {
    [self.board refresh]; [self.board refreshHot];
    [self.stateView setTitle:self.board.roomID.length ? [@"房间 " stringByAppendingString:self.board.roomID] : @"未进入直播间"
        detail:@"观众 / 礼物 / PK / 人气只读展示，不修改直播间行为" loading:NO];
    [self.tableView reloadData];
}
- (void)stop { [self.push close]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView; return 3;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return MAX(1, (NSInteger)self.board.rankRows.count);
    if (section == 1) return MAX(1, (NSInteger)self.board.battle.teams.count);
    return 1;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return section == 0 ? @"观众榜" : section == 1 ? @"PK" : @"人气";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DY778LARow"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"DY778LARow"];
    if (indexPath.section == 0) {
        if (!self.board.rankRows.count) { cell.textLabel.text = @"暂无观众数据"; cell.detailTextLabel.text = @"请确认已进入直播间且开关已开启"; return cell; }
        NSDictionary *row = self.board.rankRows[indexPath.row];
        cell.textLabel.text = DY778LATextValue(row[@"name"]) ?: DY778LAIdentifierValue(row[@"uid"]);
        char buffer[32];
        DY778LiveAnalysisGroupedNumber(buffer, sizeof(buffer), DY778LAIntegerValue(row[@"score"]));
        cell.detailTextLabel.text = [NSString stringWithFormat:@"第 %lld 名 · %@ 分", DY778LAIntegerValue(row[@"rank"]), [NSString stringWithUTF8String:buffer]];
    } else if (indexPath.section == 1) {
        if (!self.board.battle.teams.count) { cell.textLabel.text = @"当前无 PK"; cell.detailTextLabel.text = @""; return cell; }
        id team = self.board.battle.teams[indexPath.row];
        cell.textLabel.text = [team isKindOfClass:NSDictionary.class] ? DY778LATextValue(team[@"name"]) : @"队伍";
        cell.detailTextLabel.text = @"";
    } else {
        cell.textLabel.text = @"人气热榜";
        cell.detailTextLabel.text = self.board.status ?: @"";
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1 && self.board.battle.teams.count) {
        DY778LAMain(^{
            UIViewController *top = DY778TopController();
            if (top) DY778PresentController(top, [[DY778LAPKPage alloc] initWithBattle:self.board.battle room:self.board.roomID]);
        });
    }
}
@end

// ---------- UI：PK 页面（规格 §4.3、§7） ----------
@interface DY778LAPKPage () <UITableViewDataSource>
@property(nonatomic, strong) DY778LABattle *battle;
@property(nonatomic, copy) NSString *roomID;
@property(nonatomic, strong) UITableView *tableView;
@end
@implementation DY778LAPKPage
- (instancetype)initWithBattle:(DY778LABattle *)battle room:(NSString *)roomID {
    if ((self = [super init])) { _battle = battle; _roomID = roomID; }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"PK";
    self.view.backgroundColor = DY778Background();
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
        target:self action:@selector(close)];
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.dataSource = self; self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.tableView];
}
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section; return MAX(1, (NSInteger)self.battle.teams.count);
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DY778LAPKRow"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"DY778LAPKRow"];
    if (!self.battle.teams.count) { cell.textLabel.text = @"当前无 PK 数据"; cell.detailTextLabel.text = @""; return cell; }
    id team = self.battle.teams[indexPath.row];
    cell.textLabel.text = [team isKindOfClass:NSDictionary.class] ? DY778LATextValue(team[@"name"]) : @"队伍";
    NSNumber *score = [team isKindOfClass:NSDictionary.class] ? team[@"score"] : nil;
    cell.detailTextLabel.text = [score respondsToSelector:@selector(stringValue)] ? [score stringValue] : @"";
    return cell;
}
@end

// ---------- UI：观众榜弹层（规格 §4.1、§7） ----------
@interface DY778LAAudienceSheet () <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, strong) DY778LABoard *board;
@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic) NSUInteger nextOffset;
@property(nonatomic) NSUInteger pageOffset;
@property(nonatomic) BOOL hasMore;
@property(nonatomic) BOOL loadingMore;
@property(nonatomic) BOOL inFlight;
@property(nonatomic) NSTimeInterval retryAt;
@property(nonatomic) NSTimeInterval requestDeadline;
@end
@implementation DY778LAAudienceSheet
- (instancetype)initWithRoom:(NSString *)roomID {
    if ((self = [super init])) { _board = [[DY778LABoard alloc] initWithRoom:roomID seed:nil]; }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"观众榜";
    self.view.backgroundColor = DY778Background();
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
        target:self action:@selector(close)];
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.dataSource = self; self.tableView.delegate = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.tableView];
    [self loadScores:nil];
}
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)loadScores:(id)sender {
    (void)sender;
    if (self.inFlight) return;
    self.inFlight = YES;
    [self.board refresh];
    self.inFlight = NO; self.hasMore = self.board.rankRows.count >= 20;
    self.nextOffset = self.board.rankRows.count;
    [self.tableView reloadData];
}
- (void)refreshScores { [self loadScores:nil]; }
- (void)loadMoreScores {
    if (self.loadingMore || !self.hasMore) return;
    self.loadingMore = YES; self.pageOffset = self.nextOffset;
    [self.board refresh];
    self.loadingMore = NO;
    self.nextOffset = self.board.rankRows.count;
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    if (self.contextMissing) return 1;
    return MAX(1, (NSInteger)self.board.rankRows.count);
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DY778LAAudienceRow"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"DY778LAAudienceRow"];
    if (self.contextMissing) { cell.textLabel.text = @"未取得当前直播间"; cell.detailTextLabel.text = @""; return cell; }
    if (self.authMissing) { cell.textLabel.text = @"缺少登录凭证"; cell.detailTextLabel.text = @"请先在设置里获取游客身份或登录"; return cell; }
    if (self.readFailed) { cell.textLabel.text = @"读取失败"; cell.detailTextLabel.text = @"请稍后重试"; return cell; }
    if (!self.board.rankRows.count) { cell.textLabel.text = @"暂无观众数据"; cell.detailTextLabel.text = @""; return cell; }
    NSDictionary *row = self.board.rankRows[indexPath.row];
    cell.textLabel.text = DY778LATextValue(row[@"name"]) ?: DY778LAIdentifierValue(row[@"uid"]);
    cell.detailTextLabel.text = [NSString stringWithFormat:@"第 %lld 名", DY778LAIntegerValue(row[@"rank"])];
    return cell;
}
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView; (void)cell;
    if (indexPath.row + 5 >= (NSInteger)self.board.rankRows.count) [self loadMoreScores];
}
@end

// ---------- UI：通用页与容器（规格 §6，当前主路径直接用 DY778PresentController
// 呈现面板；Overlay/Page 按规格实现完整，供跳房/嵌套流程复用） ----------
@interface DY778LAPage : UIViewController
- (void)addCloseAction;
- (void)exitCard;
@end
@implementation DY778LAPage
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = DY778Background();
    [self addCloseAction];
}
- (void)addCloseAction {
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
        target:self action:@selector(exitCard)];
}
- (void)exitCard { [self dismissViewControllerAnimated:YES completion:nil]; }
@end

@interface DY778LAOverlay : UIViewController
@property(nonatomic, strong) UIViewController *page;
- (instancetype)initWithPage:(UIViewController *)page;
- (void)closeAnimated:(BOOL)animated;
- (void)closeAnimated:(BOOL)animated completion:(void (^)(void))completion;
- (void)endWork;
- (void)exitCard;
@end
@implementation DY778LAOverlay
- (instancetype)initWithPage:(UIViewController *)page {
    if ((self = [super init])) { _page = page; }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = DY778Background();
    if (self.page) {
        [self addChildViewController:self.page];
        self.page.view.frame = self.view.bounds;
        self.page.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view addSubview:self.page.view];
        [self.page didMoveToParentViewController:self];
    }
}
- (void)exitCard { [self closeAnimated:YES]; }
- (void)endWork { [self closeAnimated:NO]; }
- (void)closeAnimated:(BOOL)animated { [self closeAnimated:animated completion:nil]; }
- (void)closeAnimated:(BOOL)animated completion:(void (^)(void))completion {
    [self dismissViewControllerAnimated:animated completion:completion];
}
@end

// ---------- Hook 替换函数（规格 §2：24 个） ----------
static void DY778LANoteObject(id object) {
    if (!DY778LiveAnalysisEnabled() || !object) return;
    NSString *roomID = DY778LAContextRoomID(object);
    if (roomID.length) [DY778LAContext.shared noteRoomID:roomID];
    if (!DY778LAContext.shared.roomID.length && [object isKindOfClass:UIView.class])
        [DY778LAContext.shared noteLynxView:object];
    [[DY778LAEntry shared] refresh];
}
static void DY778LANoteAudienceSource(id object, id param) {
    if ([param isKindOfClass:NSDictionary.class]) { [DY778LAContext.shared noteAudienceDictionary:param]; return; }
    for (NSString *key in @[@"audience", @"data", @"params", @"sourceParam", @"ranks"]) {
        id value = DY778Read(object, key);
        if ([value isKindOfClass:NSDictionary.class]) [DY778LAContext.shared noteAudienceDictionary:value];
    }
}

static IMP DY778LAOriginalLynxDidMove, DY778LAOriginalLynxLayout;
static IMP DY778LAOriginalListDidMove, DY778LAOriginalListLayout;
static IMP DY778LAOriginalPopupAppear, DY778LAOriginalPopupDisappear, DY778LAOriginalPopupLayout;
static IMP DY778LAOriginalPopupFinishLoad, DY778LAOriginalPopupPageReady;
static IMP DY778LAOriginalSetContentOffset;
static IMP DY778LAOriginalHYFinishLoad, DY778LAOriginalHYWillDismiss, DY778LAOriginalHYDidDismiss;
static IMP DY778LAOriginalHYPuzzleDismiss;
static IMP DY778LAOriginalOpenHybridURLObject, DY778LAOriginalOpenHybridURLBool;
static IMP DY778LAOriginalShowRankCustom, DY778LAOriginalShowLynxList;
static IMP DY778LAOriginalShowRank, DY778LAOriginalComponentUnmount;
static IMP DY778LAOriginalSetHoldingUI, DY778LAOriginalAddLynxUI;
static IMP DY778LAOriginalListReuse, DY778LAOriginalSetItemKey, DY778LAOriginalSetItemKeyReset;

#define DY778_LA_VOID2(N, ORIGINAL) \
static void DY778LA##N(id target, SEL cmd) { \
    @try { DY778LANoteObject(target); } @catch (__unused NSException *e) {} \
    ((void (*)(id, SEL))ORIGINAL)(target, cmd); }
DY778_LA_VOID2(LynxDidMove, DY778LAOriginalLynxDidMove)
DY778_LA_VOID2(LynxLayout, DY778LAOriginalLynxLayout)
DY778_LA_VOID2(ListDidMove, DY778LAOriginalListDidMove)
DY778_LA_VOID2(ListLayout, DY778LAOriginalListLayout)
DY778_LA_VOID2(PopupLayout, DY778LAOriginalPopupLayout)
#undef DY778_LA_VOID2

static void DY778LAPopupAppear(id target, SEL cmd, BOOL animated) {
    @try { DY778LANoteObject(target); } @catch (__unused NSException *e) {}
    ((void (*)(id, SEL, BOOL))DY778LAOriginalPopupAppear)(target, cmd, animated);
}
static void DY778LAPopupDisappear(id target, SEL cmd, BOOL animated) {
    @try { DY778LANoteObject(target); } @catch (__unused NSException *e) {}
    ((void (*)(id, SEL, BOOL))DY778LAOriginalPopupDisappear)(target, cmd, animated);
}
static void DY778LAPopupFinishLoad(id target, SEL cmd, id container, id url) {
    @try { DY778LANoteObject(target); DY778LANoteAudienceSource(target, url); } @catch (__unused NSException *e) {}
    ((void (*)(id, SEL, id, id))DY778LAOriginalPopupFinishLoad)(target, cmd, container, url);
}
static void DY778LAPopupPageReady(id target, SEL cmd, id container, id param) {
    @try { DY778LANoteObject(target); DY778LANoteAudienceSource(target, param); } @catch (__unused NSException *e) {}
    ((void (*)(id, SEL, id, id))DY778LAOriginalPopupPageReady)(target, cmd, container, param);
}
static void DY778LASetContentOffset(id target, SEL cmd, CGPoint offset) {
    @try {
        DY778LAContext.shared.lastScrollOffset = offset;
        DY778LANoteObject(target);
    } @catch (__unused NSException *e) {}
    ((void (*)(id, SEL, CGPoint))DY778LAOriginalSetContentOffset)(target, cmd, offset);
}
static void DY778LAHYFinishLoad(id target, SEL cmd, id controller) {
    @try { DY778LANoteObject(target); [DY778LAContext.shared noteFinishLoad:YES]; } @catch (__unused NSException *e) {}
    ((void (*)(id, SEL, id))DY778LAOriginalHYFinishLoad)(target, cmd, controller);
}
static void DY778LAHYWillDismiss(id target, SEL cmd, id controller) {
    @try { DY778LANoteObject(target); } @catch (__unused NSException *e) {}
    ((void (*)(id, SEL, id))DY778LAOriginalHYWillDismiss)(target, cmd, controller);
}
static void DY778LAHYDidDismiss(id target, SEL cmd, id controller) {
    @try { [DY778LAContext.shared noteFinishLoad:NO]; } @catch (__unused NSException *e) {}
    ((void (*)(id, SEL, id))DY778LAOriginalHYDidDismiss)(target, cmd, controller);
    DY778LiveAnalysisClosingRoom();
    DY778LiveAnalysisDidCloseRoom();
}
static void DY778LAHYPuzzleDismiss(id target, SEL cmd, id object) {
    @try { DY778LANoteObject(target); } @catch (__unused NSException *e) {}
    ((void (*)(id, SEL, id))DY778LAOriginalHYPuzzleDismiss)(target, cmd, object);
}
static id DY778LAOpenHybridURLObject(id target, SEL cmd, id url, id fromInside) {
    @try { DY778LANoteObject(target); } @catch (__unused NSException *e) {}
    return ((id (*)(id, SEL, id, id))DY778LAOriginalOpenHybridURLObject)(target, cmd, url, fromInside);
}
static id DY778LAOpenHybridURLBool(id target, SEL cmd, id url, BOOL fromInside) {
    @try { DY778LANoteObject(target); } @catch (__unused NSException *e) {}
    return ((id (*)(id, SEL, id, BOOL))DY778LAOriginalOpenHybridURLBool)(target, cmd, url, fromInside);
}
static id DY778LAShowRankCustom(id target, SEL cmd, id param) {
    @try { DY778LANoteObject(target); DY778LANoteAudienceSource(target, param); } @catch (__unused NSException *e) {}
    return ((id (*)(id, SEL, id))DY778LAOriginalShowRankCustom)(target, cmd, param);
}
static id DY778LAShowLynxList(id target, SEL cmd, long long roomID, id param, BOOL useKrossRouter) {
    @try {
        DY778LANoteObject(target);
        DY778LANoteAudienceSource(target, param);
        if (roomID > 0) [DY778LAContext.shared noteRoomID:[NSString stringWithFormat:@"%lld", roomID]];
    } @catch (__unused NSException *e) {}
    return ((id (*)(id, SEL, long long, id, BOOL))DY778LAOriginalShowLynxList)(target, cmd, roomID, param, useKrossRouter);
}
static void DY778LAShowRank(id target, SEL cmd) {
    @try { DY778LANoteObject(target); [DY778LAContext.shared noteShowRank:YES]; } @catch (__unused NSException *e) {}
    ((void (*)(id, SEL))DY778LAOriginalShowRank)(target, cmd);
}
static void DY778LAComponentUnmount(id target, SEL cmd) {
    @try { [DY778LAContext.shared noteShowRank:NO]; } @catch (__unused NSException *e) {}
    ((void (*)(id, SEL))DY778LAOriginalComponentUnmount)(target, cmd);
    DY778LiveAnalysisClosingRoom();
    DY778LiveAnalysisDidCloseRoom();
}
static void DY778LASetHoldingUI(id target, SEL cmd, id ui) {
    @try { DY778LANoteObject(target); DY778LANoteObject(ui); } @catch (__unused NSException *e) {}
    ((void (*)(id, SEL, id))DY778LAOriginalSetHoldingUI)(target, cmd, ui);
}
static void DY778LAAddLynxUI(id target, SEL cmd, id ui) {
    @try { DY778LANoteObject(target); DY778LANoteObject(ui); } @catch (__unused NSException *e) {}
    ((void (*)(id, SEL, id))DY778LAOriginalAddLynxUI)(target, cmd, ui);
}
static void DY778LAListReuse(id target, SEL cmd, id node, long long itemKey) {
    @try { DY778LANoteObject(target); (void)itemKey; } @catch (__unused NSException *e) {}
    ((void (*)(id, SEL, id, long long))DY778LAOriginalListReuse)(target, cmd, node, itemKey);
}
static void DY778LASetItemKey(id target, SEL cmd, id itemKey) {
    @try { DY778LANoteObject(target); (void)itemKey; } @catch (__unused NSException *e) {}
    ((void (*)(id, SEL, id))DY778LAOriginalSetItemKey)(target, cmd, itemKey);
}
static void DY778LASetItemKeyReset(id target, SEL cmd, id itemKey, BOOL reset) {
    @try { DY778LANoteObject(target); (void)itemKey; (void)reset; } @catch (__unused NSException *e) {}
    ((void (*)(id, SEL, id, BOOL))DY778LAOriginalSetItemKeyReset)(target, cmd, itemKey, reset);
}

// ---------- 安装后校验（规格 §2.6：照原样 5 个键，不自补第 6 个） ----------
static void DY778LAVerifyInstalled(void) {
    NSDictionary<NSString *, NSNumber *> *report = DY778HookReport();
    NSArray<NSString *> *keys = @[
        @"liveAnalysis.audience.LynxView.didMoveToWindow",
        @"liveAnalysis.audience.LynxView.layoutSubviews",
        @"liveAnalysis.audience.LynxListContainerView.layoutSubviews",
        @"liveAnalysis.audience.BDXPopupViewController.viewDidLayoutSubviews",
        @"liveAnalysis.audience.IESLiveAudienceRankListSwiftFragment.showAudienceRankList",
    ];
    BOOL all = YES;
    for (NSString *key in keys) all = all && [report[key] boolValue];
    DY778RecordHook(@"liveAnalysis.audience.verify", all);
}

// ---------- 生命周期（规格 §6） ----------
// 停用：遍历房间模型链取值（owner / ownerUser / roomModel / roomGuarder /
// room / currentRoom / roomConfig / rawRoom / rawHTSLiveRoomModel /
// liveRoom / roomAisle / originRoom，逐个 respondsToSelector 后取，取不到
// 则顺延）。DYxs 侧上下文只存 roomID 字符串，链的遍历由房间捕获
// （DY778LiveAnalysisRoomID）承担；停用本身只清状态、关流、撤入口。
void DY778LiveAnalysisDeactivate(void) {
    DY778LAMain(^{
        [DY778LAContext.shared clear];
        [[DY778LAEntry shared] hide];
    });
}
void DY778LiveAnalysisClosingRoom(void) {
    DY778LAMain(^{ [DY778LAContext.shared noteFinishLoad:NO]; });
}
void DY778LiveAnalysisDidCloseRoom(void) {
    DY778LiveAnalysisDeactivate();
}
void DY778LiveAnalysisRefresh(void) {
    if (!DY778LiveAnalysisEnabled()) { DY778LiveAnalysisDeactivate(); return; }
    DY778InstallLiveAnalysisHooks();
    [[DY778LAEntry shared] refresh];
}

void DY778InstallLiveAnalysisHooks(void) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ DY778InstallLiveAnalysisHooks(); }); return; }
    // 外壳门控（规格 §1）：总开关关则一个不装；开关后开由设置变更通知
    // 重新触发本函数（见末尾 dispatch_once），DY778LAInstall 本身幂等。
    if (!DY778LiveAnalysisEnabled()) return;
    // 2.1 Lynx 视图生命周期（#1–4）。
    DY778LAInstall(@"LynxView", @"didMoveToWindow", "v", "", (IMP)DY778LALynxDidMove, &DY778LAOriginalLynxDidMove);
    DY778LAInstall(@"LynxView", @"layoutSubviews", "v", "", (IMP)DY778LALynxLayout, &DY778LAOriginalLynxLayout);
    DY778LAInstall(@"LynxListContainerView", @"didMoveToWindow", "v", "", (IMP)DY778LAListDidMove, &DY778LAOriginalListDidMove);
    DY778LAInstall(@"LynxListContainerView", @"layoutSubviews", "v", "", (IMP)DY778LAListLayout, &DY778LAOriginalListLayout);
    // 2.2 混合容器 BDXPopupViewController（#5–9）。
    DY778LAInstall(@"BDXPopupViewController", @"viewDidAppear:", "v", "B", (IMP)DY778LAPopupAppear, &DY778LAOriginalPopupAppear);
    DY778LAInstall(@"BDXPopupViewController", @"viewWillDisappear:", "v", "B", (IMP)DY778LAPopupDisappear, &DY778LAOriginalPopupDisappear);
    DY778LAInstall(@"BDXPopupViewController", @"viewDidLayoutSubviews", "v", "", (IMP)DY778LAPopupLayout, &DY778LAOriginalPopupLayout);
    DY778LAInstall(@"BDXPopupViewController", @"container:didFinishLoadWithURL:", "v", "@@", (IMP)DY778LAPopupFinishLoad, &DY778LAOriginalPopupFinishLoad);
    DY778LAInstall(@"BDXPopupViewController", @"containerDidPageReady:sourceParam:", "v", "@@", (IMP)DY778LAPopupPageReady, &DY778LAOriginalPopupPageReady);
    // 2.3 滚动（#10）：先按 {CGPoint=dd} 校验，失败放宽为只比参数个数（§10.2）。
    DY778LAInstallCGPoint(@"BDXLynxSwiperCollectionView", @"setContentOffset:", (IMP)DY778LASetContentOffset, &DY778LAOriginalSetContentOffset);
    // 2.4 观众榜混合 Fragment（#11–19）。
    DY778LAInstall(@"IESLiveAudienceRankListSwiftFragment", @"iesHYControllerDidFinishLoad:", "v", "@", (IMP)DY778LAHYFinishLoad, &DY778LAOriginalHYFinishLoad);
    DY778LAInstall(@"IESLiveAudienceRankListSwiftFragment", @"iesHYControllerWillDismiss:", "v", "@", (IMP)DY778LAHYWillDismiss, &DY778LAOriginalHYWillDismiss);
    DY778LAInstall(@"IESLiveAudienceRankListSwiftFragment", @"iesHYControllerDidDismiss:", "v", "@", (IMP)DY778LAHYDidDismiss, &DY778LAOriginalHYDidDismiss);
    DY778LAInstall(@"IESLiveAudienceRankListSwiftFragment", @"puzzleHybridPopControllerDismissedWithObject:", "v", "@", (IMP)DY778LAHYPuzzleDismiss, &DY778LAOriginalHYPuzzleDismiss);
    // #15：运行时按 arg3 类型二选一，只装一条（规格 §2.4）。
    {
        Class cls = NSClassFromString(@"IESLiveAudienceRankListSwiftFragment");
        SEL sel = NSSelectorFromString(@"openHybridURL:fromInside:");
        Method method = cls ? class_getInstanceMethod(cls, sel) : NULL;
        if (method) {
            NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
            if (signature.numberOfArguments == 4) {
                const char *arg3 = DY778LAType([signature getArgumentTypeAtIndex:3]);
                if (arg3[0] == '@') DY778LAInstall(@"IESLiveAudienceRankListSwiftFragment", @"openHybridURL:fromInside:", "@", "@@", (IMP)DY778LAOpenHybridURLObject, &DY778LAOriginalOpenHybridURLObject);
                else if (arg3[0] == 'c' || arg3[0] == 'B') DY778LAInstall(@"IESLiveAudienceRankListSwiftFragment", @"openHybridURL:fromInside:", "@", "@B", (IMP)DY778LAOpenHybridURLBool, &DY778LAOriginalOpenHybridURLBool);
            }
        }
    }
    DY778LAInstall(@"IESLiveAudienceRankListSwiftFragment", @"showAudienceRankListWithCustomParam:", "@", "@", (IMP)DY778LAShowRankCustom, &DY778LAOriginalShowRankCustom);
    DY778LAInstall(@"IESLiveAudienceRankListSwiftFragment", @"showLynxAudienceListWith:customParam:useKrossRouter:", "@", "q@B", (IMP)DY778LAShowLynxList, &DY778LAOriginalShowLynxList);
    DY778LAInstall(@"IESLiveAudienceRankListSwiftFragment", @"showAudienceRankList", "v", "", (IMP)DY778LAShowRank, &DY778LAOriginalShowRank);
    DY778LAInstall(@"IESLiveAudienceRankListSwiftFragment", @"componentUnmount", "v", "", (IMP)DY778LAComponentUnmount, &DY778LAOriginalComponentUnmount);
    // 2.5 Lynx UI 节点（#20–24）。
    DY778LAInstall(@"LynxListContainerComponentWrapper", @"setHoldingUI:", "v", "@", (IMP)DY778LASetHoldingUI, &DY778LAOriginalSetHoldingUI);
    DY778LAInstall(@"LynxListViewCellLightLynxUI", @"addLynxUI:", "v", "@", (IMP)DY778LAAddLynxUI, &DY778LAOriginalAddLynxUI);
    DY778LAInstall(@"LynxUIOwner", @"listWillReuseNode:withItemKey:", "v", "@q", (IMP)DY778LAListReuse, &DY778LAOriginalListReuse);
    DY778LAInstall(@"LynxUIComponent", @"setItemKey:", "v", "@", (IMP)DY778LASetItemKey, &DY778LAOriginalSetItemKey);
    DY778LAInstall(@"LynxUIComponent", @"setItemKey:requestReset:", "v", "@B", (IMP)DY778LASetItemKeyReset, &DY778LAOriginalSetItemKeyReset);
    DY778LAVerifyInstalled();
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue
                       usingBlock:^(__unused NSNotification *note) { DY778LiveAnalysisDeactivate(); }];
        [center addObserverForName:DY778PreferencesChangedNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            NSString *key = note.userInfo[@"key"];
            if (!key.length || [key hasPrefix:@"liveAnalysis."]) DY778LiveAnalysisRefresh();
        }];
    });
}
