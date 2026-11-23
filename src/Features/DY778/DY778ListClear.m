#import "DY778ListClear.h"
#import "DY778Core.h"
#import "DY778MiscPolicy.h"
#import "DY778Avatar.h"

// DY778 1.0-8 模块 4：清理关注（规格 §6）。
// 双引擎 + 原生拦截 + 三个控制器 + 隐私徽章。
// 红线见 DY778ListClear.h 头注：取关提交在未证实前不执行。

// ---------- 签名校验（照 DY778LiveLike.m 的做法） ----------

static const char *DY778LCType(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type ?: "";
}
static BOOL DY778LCMatchesSignature(NSMethodSignature *s, const char *result, NSArray<NSString *> *arguments) {
    if (!s || strcmp(DY778LCType(s.methodReturnType), result) || s.numberOfArguments != arguments.count + 2) return NO;
    for (NSUInteger i = 0; i < arguments.count; i++) {
        const char *actual = DY778LCType([s getArgumentTypeAtIndex:i + 2]), *expected = arguments[i].UTF8String;
        if (!strcmp(expected, "B")) { if (strcmp(actual, "B") && strcmp(actual, "c")) return NO; }
        else if (!strcmp(expected, "@")) { if (actual[0] != '@') return NO; }
        else if (!strcmp(expected, "#")) { if (strcmp(actual, "#")) return NO; }
        else if (strcmp(actual, expected)) return NO;
    }
    return YES;
}
static BOOL DY778LCSignature(Class cls, SEL selector, const char *result, NSArray<NSString *> *arguments) {
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    return method && DY778LCMatchesSignature([NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)], result, arguments);
}

BOOL DY778ListMethod(id object, SEL selector, const char *result, NSArray<NSString *> *arguments) {
    if (!object || !selector) return NO;
    Class cls = object_getClass(object);
    if (DY778LCSignature(cls, selector, result, arguments)) return YES;
    @try {
        return DY778LCMatchesSignature([object methodSignatureForSelector:selector], result, arguments);
    } @catch (__unused NSException *exception) { return NO; }
}

NSString *DY778ListID(id value) {
    // _DY778ListID（0xa0a70）：_DY778Identifier + 纯数字校验
    // （decimalDigitCharacterSet，'0' 特殊处理）。
    NSString *identifier = DY778Identifier(value);
    if (!identifier.length) return nil;
    NSCharacterSet *digits = NSCharacterSet.decimalDigitCharacterSet;
    for (NSUInteger i = 0; i < identifier.length; i++) {
        if (![digits characterIsMember:[identifier characterAtIndex:i]]) return nil;
    }
    return identifier;
}

NSString *DY778ListCurrentUser(void) {
    // _DY778ListCurrentUser（0xa0b58）：AWEUserService sharedService
    // currentLoginUser → userID（经 _DY778ListID）。
    return DY778ListID(DY778CurrentAccountID()) ?: @"";
}

id DY778ListAcquire(void) {
    // _DY778ListAcquire（0xa0e50）：建 DY778ListNativeRequest 作用域/
    // 请求（isMainThread + applicationState + DY778ActiveWindow 检查；
    // 错误域构造）。调用点 3 处：FollowJob startRemoval、
    // ListClearJob startKind、_DY778ListStartCollectionClear。
    if (!NSThread.isMainThread) return nil;
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return nil;
    if (!DY778ActiveWindow()) return nil;
    return [DY778ListNativeRequest account:DY778ListCurrentUser() target:nil model:nil invoke:nil completion:nil];
}

BOOL DY778ListMore(id object) {
    // _DY778ListMore（0xa0c7c）：hasMore / loadmoreHasMore 判定
    // （经 _DY778ListMethod）。
    if (!object) return NO;
    if (DY778ListMethod(object, NSSelectorFromString(@"hasMore"), "B", @[])) {
        @try { return ((BOOL (*)(id, SEL))objc_msgSend)(object, NSSelectorFromString(@"hasMore")); }
        @catch (__unused NSException *exception) { return NO; }
    }
    if (DY778ListMethod(object, NSSelectorFromString(@"loadmoreHasMore"), "B", @[])) {
        @try { return ((BOOL (*)(id, SEL))objc_msgSend)(object, NSSelectorFromString(@"loadmoreHasMore")); }
        @catch (__unused NSException *exception) { return NO; }
    }
    id value = DY778Read(object, @"hasMore") ?: DY778Read(object, @"loadmoreHasMore");
    return [value boolValue];
}

void DY778ListRelease(id object) {
    // _DY778ListRelease（0xa0ef8）：弱引用释放 helper
    // （objc_loadWeakRetained，仅 0x60 字节）。DYxs 侧用 ARC 弱引用
    // 读一次达到同等效果（不直接调未声明的 runtime 函数）。
    if (!object) return;
    __weak id weak = object;
    (void)weak;
}

BOOL DY778ListVerificationVisible(void) {
    // _DY778ListVerificationVisible（0xa0f58）：验证码可见判断：
    // NSClassFromString(@"BDTuringVerifyView") + isShow。
    Class cls = NSClassFromString([NSString stringWithUTF8String:DY778ListClearVerificationViewClass]);
    if (!cls) return NO;
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        for (UIView *view in window.subviews) {
            if (![view isKindOfClass:cls]) continue;
            if (DY778ListMethod(view, NSSelectorFromString(@"isShow"), "B", @[])) {
                @try {
                    if (((BOOL (*)(id, SEL))objc_msgSend)(view, NSSelectorFromString(@"isShow"))) return YES;
                } @catch (__unused NSException *exception) { continue; }
            }
            if (view.window && !view.hidden) return YES;
        }
    }
    return NO;
}

BOOL DY778ListClearCanSubmit(void) {
    // 取关是否走服务端接口、是否立即生效、是否可逆，一律未证实
    // （规格 §6.8）。在运行时证实前恒为 NO：取关提交不执行。
    return NO;
}

// ---------- DY778ListNativeRequest ----------

@implementation DY778ListNativeRequest
+ (instancetype)account:(NSString *)account target:(id)target model:(Class)model
                 invoke:(id)invoke completion:(id)completion {
    DY778ListNativeRequest *request = [self new];
    request.account = account;
    request.target = target;
    request.responseClass = model;
    request.completion = completion;
    (void)invoke;
    return request;
}
- (void)invoke {
    if (self.cancel || self.cancelled) return;
    self.submitted = YES;
}
- (void)cancelRequest {
    self.cancel = YES;
    self.cancelled = YES;
}
@end

// ---------- DY778ListClearReceipt ----------

@implementation DY778ListClearReceipt
- (instancetype)init {
    if ((self = [super init])) { _failedIDs = [NSMutableSet set]; }
    return self;
}
@end

// ---------- DY778FollowJob ----------

@implementation DY778FollowJob

+ (instancetype)shared {
    static DY778FollowJob *value; static dispatch_once_t once;
    dispatch_once(&once, ^{
        value = [self new];
        [NSNotificationCenter.defaultCenter addObserver:value selector:@selector(settingsChanged)
                                                   name:DY778PreferencesChangedNotification object:nil];
    });
    return value;
}

- (instancetype)init {
    if ((self = [super init])) {
        _users = [NSMutableArray array]; _seen = [NSMutableSet set]; _cursors = [NSMutableDictionary dictionary];
        _selected = [NSMutableArray array]; _excluded = [NSMutableSet set]; _uncertain = [NSMutableSet set];
        _queue = [NSMutableArray array];
        _excludeMutual = YES; _excludeSpecial = YES; _excludeRemark = YES;
        _account = DY778ListCurrentUser();
        NSArray *excluded = [DY778Preferences() objectForKey:self.exclusionKey];
        if ([excluded isKindOfClass:NSArray.class]) [_excluded addObjectsFromArray:excluded];
        NSArray *uncertain = [DY778Preferences() objectForKey:self.uncertainKey];
        if ([uncertain isKindOfClass:NSArray.class]) [_uncertain addObjectsFromArray:uncertain];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self.timer invalidate];
}

- (NSString *)exclusionKey {
    return [NSString stringWithFormat:@"listClear.followExcluded.%@", self.account ?: DY778ListCurrentUser()];
}
- (NSString *)uncertainKey {
    return [NSString stringWithFormat:@"listClear.followUncertain.%@", self.account ?: DY778ListCurrentUser()];
}
- (void)saveExcluded {
    DY778Set(self.exclusionKey, self.excluded.allObjects);
}
- (void)saveUncertain {
    DY778Set(self.uncertainKey, self.uncertain.allObjects);
}
- (void)settingsChanged {
    if (!DY778Bool(@"listClear.enabled") && self.removing) [self stop];
}

- (BOOL)protectedUser:(id)user {
    // 保护判断（规格 §6.6）：查 excluded / uncertain 集合 + 三个开关
    // excludeMutual / excludeSpecial / excludeRemark；字段 userID、
    // alias、followStatus、followerStatus、closeFriendsStatus
    // （互关/密友）、specialFollowStatus（特别关注）、remarkName。
    NSString *userID = DY778ListID(DY778Read(user, @"userID") ?: DY778Read(user, @"userId"));
    if (!userID.length) return YES;
    if ([self.excluded containsObject:userID] || [self.uncertain containsObject:userID]) return YES;
    if (self.excludeRemark) {
        NSString *remark = DY778Read(user, @"remarkName");
        if ([remark isKindOfClass:NSString.class] && remark.length) return YES;
    }
    if (self.excludeSpecial && [DY778Read(user, @"specialFollowStatus") boolValue]) return YES;
    if (self.excludeMutual) {
        if ([DY778Read(user, @"closeFriendsStatus") boolValue]) return YES;
        BOOL following = [DY778Read(user, @"followStatus") boolValue];
        BOOL follower = [DY778Read(user, @"followerStatus") boolValue];
        if (following && follower) return YES;
    }
    return NO;
}

- (void)resume {
    if (!DY778Bool(@"listClear.enabled")) return;
    Class managerClass = NSClassFromString(@"AWEUserFollowingManager");
    if (!managerClass) { self.failed = YES; self.message = @"当前版本暂不支持关注清理"; return; }
    self.manager = [managerClass new];
    self.account = DY778ListCurrentUser();
    self.reading = YES;
    self.generation += 1;
    [self.timer invalidate];
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer timerWithTimeInterval:1 repeats:YES block:^(__unused NSTimer *timer) { [weakSelf tick]; }];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
    [self readPage];
}

- (void)readPage {
    // 调 AWEUserFollowingManager 读一页关注列表（规格 §6.2）。
    // 原生读列表的方法名未在规格里给出，DYxs 侧不猜：只通过 DY778Read
    // 读 manager 上已知的列表属性；读不到即标记失败并停止。
    if (!self.manager) { self.failed = YES; return; }
    NSArray *page = DY778Read(self.manager, @"users");
    if (![page isKindOfClass:NSArray.class]) page = DY778Read(self.manager, @"followingUsers");
    if (![page isKindOfClass:NSArray.class]) page = DY778Read(self.manager, @"list");
    if (![page isKindOfClass:NSArray.class]) {
        self.failed = YES;
        self.message = @"当前版本读不到关注列表（原生接口未证实）";
        [self stop];
        return;
    }
    self.pages += 1;
    self.generation += 1;
    for (id user in page) {
        NSString *userID = DY778ListID(DY778Read(user, @"userID") ?: DY778Read(user, @"userId"));
        if (!userID.length || [self.seen containsObject:userID]) continue;
        [self.seen addObject:userID];
        [self.users addObject:user];
        if ([self protectedUser:user]) [self.uncertain addObject:userID];
    }
    [self saveUncertain];
    self.more = DY778ListMore(self.manager);
    self.nextAt = CACurrentMediaTime() + DY778ListClearPageIntervalSeconds;
    self.waiting = NO;
    [self render];
    if (!self.more) { self.reading = NO; }
}

- (void)tick {
    if (!NSThread.isMainThread) return;
    // 门控三件套（规格 §6.2）：listClear.enabled、applicationState、
    // 验证码可见。
    if (!DY778Bool(@"listClear.enabled")) { [self stop]; return; }
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    if (DY778ListVerificationVisible()) { self.waiting = YES; return; }
    double now = CACurrentMediaTime();
    if (now < self.nextAt) return;
    if (self.reading) { [self readPage]; return; }
    if (self.removing) { [self removeNext]; return; }
    [self render];
    if (self.failed) [self stop];
}

- (void)startRemoval {
    // selected 减去受保护用户 → 建 queue（UUID 作 toastToken）；
    // 调 _DY778ListAcquire；起 tick 定时器；setRemoving:。
    NSMutableArray *queue = [NSMutableArray array];
    for (id user in self.selected) {
        if ([self protectedUser:user]) continue;
        [queue addObject:user];
    }
    if (queue.count == 0) { DY778Toast(@"没有可取关的用户（已受保护或未选择）"); return; }
    self.queue = queue;
    self.toastToken = [NSUUID UUID].UUIDString;
    self.request = DY778ListAcquire();
    self.removing = YES;
    self.removeStartedAt = CACurrentMediaTime();
    [self.timer invalidate];
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer timerWithTimeInterval:1 repeats:YES block:^(__unused NSTimer *timer) { [weakSelf tick]; }];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
    DY778ShowToast(@"listClear", [NSString stringWithFormat:@"开始清理关注（共 %lu 人）", (unsigned long)queue.count], YES, NO);
}

- (void)removeNext {
    // 逐项提交取关（规格 §6.2）。提交走哪个原生接口未证实
    // （规格 §6.8）：DY778ListClearCanSubmit 恒为 NO，走到提交点
    // 即停并弹提示，绝不凭猜测调原生方法发请求。
    id user = self.queue.firstObject;
    if (!user) {
        [self.timer invalidate];
        self.timer = nil;
        [self saveUncertain];
        self.completed = YES;
        self.removing = NO;
        DY778DismissToast(@"listClear");
        DY778Toast(@"关注清理完成");
        return;
    }
    [self.queue removeObjectAtIndex:0];
    NSString *userID = DY778ListID(DY778Read(user, @"userID") ?: DY778Read(user, @"userId"));
    if (!DY778ListClearCanSubmit()) {
        self.failed = YES;
        self.message = @"取关提交的原生接口未证实，已停止（未发出任何取关请求）";
        DY778DismissToast(@"listClear");
        DY778ShowToast(@"listClear", self.message, NO, NO);
        [self stop];
        return;
    }
    (void)userID;
}

- (void)stop {
    [self.timer invalidate];
    self.timer = nil;
    self.reading = NO;
    self.removing = NO;
    DY778DismissToast(@"listClear");
    [self releaseTransient];
}
- (void)reset {
    [self stop];
    [self.users removeAllObjects];
    [self.seen removeAllObjects];
    [self.cursors removeAllObjects];
    [self.selected removeAllObjects];
    [self.queue removeAllObjects];
    self.pages = 0;
    self.generation = 0;
    self.completed = NO;
    self.failed = NO;
    self.checkpoint = nil;
    self.message = nil;
}
- (void)releaseTransient {
    self.request = nil;
    self.manager = nil;
}
- (void)background {
    [self.timer invalidate];
    self.timer = nil;
}
- (void)render {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:DY778PreferencesChangedNotification
                                                        object:nil userInfo:@{@"key": @"listClear.render"}];
    });
}

@end

// ---------- DY778ListClearJob ----------

@implementation DY778ListClearJob

+ (instancetype)shared {
    static DY778ListClearJob *value; static dispatch_once_t once;
    dispatch_once(&once, ^{
        value = [self new];
        [NSNotificationCenter.defaultCenter addObserver:value selector:@selector(settingsChanged)
                                                   name:DY778PreferencesChangedNotification object:nil];
    });
    return value;
}

- (instancetype)init {
    if ((self = [super init])) {
        _snapshot = [NSMutableArray array];
        _classifiedIDs = [NSMutableSet set];
        _disabledItemIds = [NSMutableSet set];
        _readLimit = DY778ListClearDefaultLimit;
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self.timer invalidate];
}

- (void)settingsChanged {
    if (!DY778Bool(@"listClear.enabled") && self.active) [self stop:@"开关已关闭"];
}

- (void)startKind:(DY778ListClearKind)kind user:(id)user owner:(id)owner mergedContainer:(id)container {
    (void)user; (void)container;
    self.kind = kind;
    self.owner = owner;
    self.account = DY778ListCurrentUser();
    self.toastToken = [NSUUID UUID].UUIDString;
    self.active = YES;
    self.snapshot = [NSMutableArray array];
    self.readCheckpoint = nil;
    self.folderIndex = 0;
    [self.timer invalidate];
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer timerWithTimeInterval:1 repeats:YES block:^(__unused NSTimer *timer) { [weakSelf tick]; }];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
    [self resumeReading];
}

- (void)chooseKind:(id)user owner:(id)owner merged:(id)merged settings:(id)settings folder:(id)folder {
    (void)settings; (void)folder;
    UIViewController *presenter = [owner isKindOfClass:UIViewController.class] ? owner : DY778TopController();
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"清理种类" message:@"选择要清理的对象" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.keyboardType = UIKeyboardTypeNumberPad;
        textField.placeholder = [NSString stringWithFormat:@"单次上限（默认 %d）", DY778ListClearDefaultLimit];
    }];
    NSArray<NSString *> *titles = @[@"关注", @"点赞", @"推荐", @"收藏夹"];
    for (NSUInteger i = 0; i < titles.count; i++) {
        DY778ListClearKind kind = (DY778ListClearKind)i;
        [alert addAction:[UIAlertAction actionWithTitle:titles[i] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            NSUInteger limit = [alert.textFields.firstObject.text integerValue];
            [self confirmKind:kind user:user owner:owner merged:merged limit:limit > 0 ? limit : DY778ListClearDefaultLimit];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

- (void)confirmKind:(DY778ListClearKind)kind user:(id)user owner:(id)owner merged:(id)merged limit:(NSUInteger)limit {
    // confirmKind 里出现 200——疑似单次上限，未证实（规格 §6.3）。
    // DYxs 侧按用户输入的上限（默认 200）执行。
    self.readLimit = MIN(limit, DY778ListClearMaximumLimit);
    DY778Confirm([owner isKindOfClass:UIViewController.class] ? owner : DY778TopController(),
        @"确认清理", [NSString stringWithFormat:@"将清理所选种类，最多 %lu 条。取关类操作是否可逆未证实，请谨慎操作。", (unsigned long)self.readLimit],
        @"开始", YES, ^{
            [self startKind:kind user:user owner:owner mergedContainer:merged];
        });
}

- (void)showTaskFrom:(id)owner {
    UIViewController *presenter = [owner isKindOfClass:UIViewController.class] ? owner : DY778TopController();
    DY778Confirm(presenter, @"清理任务",
        self.active ? @"当前有正在进行的清理任务。" : @"当前没有正在进行的清理任务。",
        self.active ? @"继续" : @"开始", NO, ^{
            if (self.active) [self resumeReading];
            else [self chooseKind:nil owner:owner merged:nil settings:nil folder:nil];
        });
}

- (void)resumeReading {
    // 建数据控制器（三选一，规格 §6.3）：AWEFamiliarRecommendWork-
    // DataController / AWEFavoriteAwemeDataController /
    // AWEUserLikesDataManager，initWithSecUserID: 或 initWithUserID:。
    NSString *account = DY778ListCurrentUser();
    NSArray<NSString *> *controllerClasses = self.kind == DY778ListClearKindRecommend
        ? @[@"AWEFamiliarRecommendWorkDataController"]
        : self.kind == DY778ListClearKindFavorite
        ? @[@"AWEFavoriteAwemeDataController"]
        : @[@"AWEUserLikesDataManager"];
    for (NSString *className in controllerClasses) {
        Class cls = NSClassFromString(className);
        if (!cls) continue;
        id controller = nil;
        if (DY778ListMethod(cls, NSSelectorFromString(@"initWithSecUserID:"), "@", @[@"@"])) {
            @try { controller = ((id (*)(id, SEL, id))objc_msgSend)([cls alloc], NSSelectorFromString(@"initWithSecUserID:"), account); } @catch (__unused NSException *e) { controller = nil; }
        }
        if (!controller && DY778ListMethod(cls, NSSelectorFromString(@"initWithUserID:"), "@", @[@"@"])) {
            @try { controller = ((id (*)(id, SEL, id))objc_msgSend)([cls alloc], NSSelectorFromString(@"initWithUserID:"), account); } @catch (__unused NSException *e) { controller = nil; }
        }
        if (controller) { self.dataController = controller; break; }
    }
    self.reading = YES;
    [self readPage:nil];
}

- (void)readPage:(id)cursor {
    // 读一页（规格 §6.3）：DY778Read x8；cursor（maxCursor 键）；
    // snapshot 累积；调分类 helper。
    if (!self.dataController) { self.reading = NO; return; }
    NSArray *items = DY778Read(self.dataController, @"awemeList");
    if (![items isKindOfClass:NSArray.class]) items = DY778Read(self.dataController, @"items");
    if (![items isKindOfClass:NSArray.class]) items = @[];
    NSSet *disabled = DY778Read(self.dataController, @"disabledItemIds");
    if (![disabled isKindOfClass:NSSet.class]) disabled = [NSSet set];
    id nextCursor = DY778Read(self.dataController, @"maxCursor") ?: cursor;
    [self readClassificationItems:items disabled:disabled more:DY778ListMore(self.dataController) cursor:nextCursor];
    self.readCheckpoint = DY778Identifier(nextCursor);
    if (!DY778ListMore(self.dataController) || self.snapshot.count >= self.readLimit) {
        self.reading = NO;
        [self completeReadScope];
    } else {
        self.nextStepAt = CACurrentMediaTime() + DY778ListClearPageIntervalSeconds;
    }
}

- (void)readClassificationItems:(NSArray *)items disabled:(NSSet *)disabled more:(BOOL)more cursor:(id)cursor {
    // 对 AWEAwemeModel（itemID）分类；classifiedIDs 求并/差；
    // setReadCheckpoint:；completeReadScope 推进；slowed 节流。
    (void)more; (void)cursor;
    for (id item in items ?: @[]) {
        NSString *itemID = DY778ListID(DY778Read(item, @"itemID") ?: DY778Read(item, @"awemeID"));
        if (!itemID.length) continue;
        if ([disabled containsObject:itemID]) {
            [self.disabledItemIds addObject:itemID];
            self.hasUnavailableItems = YES;
            continue;
        }
        [self.classifiedIDs addObject:itemID];
        [self.snapshot addObject:item];
    }
    self.readCheckpoint = DY778Identifier(cursor);
}

- (void)prepareFolderReader {
    // 收藏夹读器（规格 §6.3）：AWEFavoriteFileVideoDataController
    // initWithCollectsId:withCollectsName:（favoriteFolderID /
    // favoriteFolderName），经 _DY778ListMethod 校验，try/catch 包裹。
    Class cls = NSClassFromString(@"AWEFavoriteFileVideoDataController");
    if (!cls) return;
    id folderID = DY778Read(self.owner, @"favoriteFolderID");
    id folderName = DY778Read(self.owner, @"favoriteFolderName");
    if (DY778ListMethod(cls, NSSelectorFromString(@"initWithCollectsId:withCollectsName:"), "@", @[@"@", @"@"])) {
        @try {
            self.dataController = ((id (*)(id, SEL, id, id))objc_msgSend)([cls alloc], NSSelectorFromString(@"initWithCollectsId:withCollectsName:"), folderID, folderName);
        } @catch (__unused NSException *exception) { self.dataController = nil; }
    }
}

- (void)completeReadScope {
    if (self.folders.count > 0 && self.folderIndex + 1 < self.folders.count) {
        self.folderIndex += 1;
        [self prepareFolderReader];
        [self readPage:nil];
        return;
    }
    if (self.snapshot.count == 0) {
        [self finish:NO uncertain:[NSSet set]];
        return;
    }
    self.classificationReady = YES;
    [self beginRemoval];
}

- (void)beginRemoval {
    if (self.reverseOrder) self.snapshot = [[[self.snapshot reverseObjectEnumerator] allObjects] mutableCopy];
    self.removing = YES;
    self.nextStepAt = CACurrentMediaTime() + DY778ListClearItemIntervalSeconds;
}

- (void)removeNextBatch {
    // 批量提交的具体接口见规格 §6.4/§6.8——未证实。DYxs 侧建
    // Receipt、置 expectedIDs/current，不发请求；走到提交点即停。
    DY778ListClearReceipt *receipt = [DY778ListClearReceipt new];
    receipt.kind = self.kind;
    NSMutableSet *expected = [NSMutableSet set];
    for (id item in self.snapshot) {
        NSString *itemID = DY778ListID(DY778Read(item, @"itemID") ?: DY778Read(item, @"awemeID") ?: DY778Read(item, @"userID"));
        if (itemID.length) [expected addObject:itemID];
    }
    receipt.expectedIDs = expected;
    receipt.current = self.snapshot.firstObject;
    receipt.intercepted = YES;
    self.receipt = receipt;
    self.requestStartedAt = CACurrentMediaTime();
    self.timeoutAt = CACurrentMediaTime() + DY778ListClearRequestTimeoutSeconds;
    if (!DY778ListClearCanSubmit()) {
        receipt.failureReason = @"批量提交的原生接口未证实，已停止（未发出任何请求）";
        [receipt.failedIDs addObjectsFromArray:expected.allObjects];
        [self finish:NO uncertain:[NSSet set]];
        DY778ShowToast(@"listClear", receipt.failureReason, NO, NO);
        return;
    }
}

- (void)tick {
    if (!NSThread.isMainThread) return;
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    if (DY778ListVerificationVisible()) {
        self.verificationVisible = YES;
        self.pauseReason = @"验证码";
        return;
    }
    self.verificationVisible = NO;
    double now = CACurrentMediaTime();
    if (now < self.nextStepAt) return;
    if (self.timeoutAt > 0 && now > self.timeoutAt) {
        self.slowed = YES;
        self.pauseReason = @"超时";
        [self stop:@"请求超时"];
        return;
    }
    if (self.reading) { [self readPage:self.readCheckpoint]; return; }
    if (self.removing) { [self removeNextBatch]; return; }
    [self updateProgress];
}

- (void)finish:(BOOL)success uncertain:(NSSet *)uncertain {
    (void)uncertain;
    [self.timer invalidate];
    self.timer = nil;
    self.active = NO;
    self.reading = NO;
    self.removing = NO;
    [NSNotificationCenter.defaultCenter postNotificationName:DY778PreferencesChangedNotification object:nil];
    DY778DismissToast(@"listClear");
    NSString *kindName = @[@"关注", @"点赞", @"推荐", @"收藏"][MIN(3, (NSUInteger)MAX(0, (NSInteger)self.kind))];
    DY778ShowToast(@"listClear", [NSString stringWithFormat:@"%@清理%@", kindName, success ? @"完成" : @"已停止"], NO, success);
}

- (void)stop:(NSString *)reason {
    self.pauseReason = reason;
    [self finish:NO uncertain:[NSSet set]];
}

- (id)cursor {
    return DY778Read(self.dataController, @"maxCursor");
}

- (void)updateProgress {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:DY778PreferencesChangedNotification
                                                        object:nil userInfo:@{@"key": @"listClear.progress"}];
    });
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    (void)gestureRecognizer;
    return DY778Bool(@"listClear.enabled");
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    (void)gestureRecognizer; (void)otherGestureRecognizer;
    return NO;
}

@end

// ---------- 控制器 ----------

@implementation DY778FollowViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"清理关注";
    DY778StyleController(self);
    self.job = DY778FollowJob.shared;
    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.navigationItem.searchController = self.search;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"选项" style:UIBarButtonItemStylePlain target:self action:@selector(options)];
    self.clearButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.clearButton setTitle:@"开始清理" forState:UIControlStateNormal];
    [self.clearButton addTarget:self action:@selector(confirmClear) forControlEvents:UIControlEventTouchUpInside];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.clearButton];
    self.status = [[UILabel alloc] init];
    self.count = [[UILabel alloc] init];
    [self render];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.visible = YES;
    [self.job resume];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.visible = NO;
}

- (void)render {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.count.text = [NSString stringWithFormat:@"已读 %lu 人，已选 %lu 人",
                           (unsigned long)self.job.users.count, (unsigned long)self.job.selected.count];
        self.status.text = self.job.message ?: (self.job.failed ? @"读取失败" : @"");
        [self.tableView reloadData];
    });
}

- (NSArray *)visibleUsers {
    NSArray *users = self.job.users;
    NSString *query = self.search.searchBar.text;
    if (!query.length) return users;
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF CONTAINS[cd] %@", query];
    return [users filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id user, NSDictionary *bindings) {
        (void)bindings;
        NSString *userID = DY778ListID(DY778Read(user, @"userID") ?: DY778Read(user, @"userId")) ?: @"";
        NSString *alias = DY778Read(user, @"alias") ?: @"";
        return [predicate evaluateWithObject:userID] || [predicate evaluateWithObject:alias];
    }]];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return (NSInteger)self.visibleUsers.count;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"DY778FollowCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    id user = self.visibleUsers[indexPath.row];
    NSString *userID = DY778ListID(DY778Read(user, @"userID") ?: DY778Read(user, @"userId")) ?: @"";
    cell.textLabel.text = [DY778Read(user, @"alias") isKindOfClass:NSString.class] ? DY778Read(user, @"alias") : userID;
    cell.detailTextLabel.text = userID;
    BOOL selected = [self.job.selected containsObject:user];
    BOOL protected = [self.job protectedUser:user];
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.textLabel.textColor = protected ? UIColor.secondaryLabelColor : UIColor.labelColor;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    id user = self.visibleUsers[indexPath.row];
    if ([self.job protectedUser:user]) {
        DY778Toast(@"该用户受保护，不会取关");
        return;
    }
    if ([self.job.selected containsObject:user]) [self.job.selected removeObject:user];
    else [self.job.selected addObject:user];
    [self render];
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    id user = self.visibleUsers[indexPath.row];
    NSString *userID = DY778ListID(DY778Read(user, @"userID") ?: DY778Read(user, @"userId"));
    UIContextualAction *exclude = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"排除" handler:^(__unused UIContextualAction *action, __unused UIView *view, void (^completion)(BOOL)) {
        if (userID.length) {
            [self.job.excluded addObject:userID];
            [self.job saveExcluded];
        }
        [self render];
        completion(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[exclude]];
}
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    (void)searchController;
    [self.tableView reloadData];
}

- (void)options {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"清理选项" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSString *> *titles = @[@"排除互关", @"排除特别关注", @"排除有备注的用户"];
    NSArray<NSNumber *> *values = @[@(self.job.excludeMutual), @(self.job.excludeSpecial), @(self.job.excludeRemark)];
    for (NSUInteger i = 0; i < titles.count; i++) {
        [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@（%@）", titles[i], values[i].boolValue ? @"开" : @"关"]
                                                  style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            if (i == 0) self.job.excludeMutual = !self.job.excludeMutual;
            else if (i == 1) self.job.excludeSpecial = !self.job.excludeSpecial;
            else self.job.excludeRemark = !self.job.excludeRemark;
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmClear {
    if (self.job.selected.count == 0) { DY778Toast(@"请先选择要取关的用户"); return; }
    DY778Confirm(self, @"确认取关",
        [NSString stringWithFormat:@"将对 %lu 人尝试取关（受保护用户已自动排除）。取关是否可逆未证实，且提交的原生接口未证实——当前版本不会发出任何取关请求。", (unsigned long)self.job.selected.count],
        @"开始", YES, ^{ [self.job startRemoval]; });
}

@end

@implementation DY778ListClearSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"清理关注";
    DY778StyleController(self);
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"关闭" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
}
- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}
- (void)refresh {
    [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 3;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return section == 0 ? 1 : section == 1 ? 3 : 1;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return section == 0 ? @"总开关" : section == 1 ? @"清理" : @"关于";
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (section == 2) return @"取关是否走服务端接口、是否立即生效、是否可逆，一律未证实；当前版本不会发出任何取关请求。";
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"DY778ListClearSettingsCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    cell.imageView.image = DY778MenuIcon(@"list.bullet.rectangle");
    if (indexPath.section == 0) {
        cell.textLabel.text = @"启用清理关注";
        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.on = DY778Bool(@"listClear.enabled");
        [toggle addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    } else if (indexPath.section == 1) {
        cell.textLabel.text = @[@"关注清理", @"按种类清理", @"收藏夹清理"][indexPath.row];
        cell.detailTextLabel.text = @[@"读取关注列表，选择后取关", @"点赞 / 推荐 / 收藏夹", @"按收藏夹清理"][indexPath.row];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.textLabel.text = @"清理关注正在运行";
        cell.detailTextLabel.text = DY778FollowClearActive() ? @"是" : @"否";
    }
    return cell;
}
- (void)toggle:(UISwitch *)sender {
    DY778Set(@"listClear.enabled", @(sender.isOn));
    if (!sender.isOn) DY778FollowClearStop();
    [self refresh];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 1) return;
    if (indexPath.row == 0) {
        // 原版此处调 _DY778FollowClearController 两次（规格 §6.5），
        // 疑似一次取控制器、一次校验；DYxs 侧只建一次并展示一次，
        // 展示两次是 UI 错误。
        DY778PresentController(self, DY778FollowClearController());
    } else if (indexPath.row == 1) {
        NSString *currentUser = DY778ListCurrentUser();
        (void)currentUser;
        [[DY778ListClearJob shared] chooseKind:nil owner:self merged:nil settings:nil folder:nil];
    } else {
        DY778PresentController(self, DY778ListFoldersController());
    }
    if (DY778FollowClearActive()) [self refresh];
}

@end

@implementation DY778ListFolderViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"收藏夹清理";
    DY778StyleController(self);
    self.folders = [NSMutableArray array];
    self.seen = [NSMutableSet set];
    self.cursors = [NSMutableDictionary dictionary];
    self.selectedIDs = [NSMutableSet set];
    self.account = DY778ListCurrentUser();
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.status = [[UILabel alloc] init];
    self.count = [[UILabel alloc] init];
    self.clearButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.clearButton setTitle:@"开始清理" forState:UIControlStateNormal];
    [self.clearButton addTarget:self action:@selector(clearTapped) forControlEvents:UIControlEventTouchUpInside];
    self.taskButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.taskButton setTitle:@"任务" forState:UIControlStateNormal];
    [self.taskButton addTarget:self action:@selector(taskTapped) forControlEvents:UIControlEventTouchUpInside];
    self.progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    [self reloadFolders];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self resume];
}
- (void)reloadFolders {
    NSArray *folders = DY778Read(DY778TopController(), @"folders");
    if ([folders isKindOfClass:NSArray.class]) {
        for (id folder in folders) {
            NSString *folderID = DY778ListID(DY778Read(folder, @"folderID") ?: DY778Read(folder, @"collectsId"));
            if (folderID.length && ![self.seen containsObject:folderID]) {
                [self.seen addObject:folderID];
                [self.folders addObject:folder];
            }
        }
    }
    [self render];
}
- (void)render {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.count.text = [NSString stringWithFormat:@"%lu 个收藏夹，已选 %lu 个", (unsigned long)self.folders.count, (unsigned long)self.selectedIDs.count];
        self.status.text = self.message ?: @"";
        [self.tableView reloadData];
    });
}
- (void)tick {
    if (!NSThread.isMainThread) return;
    if (self.waiting) return;
    double now = CACurrentMediaTime();
    if (now < self.nextAt) return;
    [self loadPage];
}
- (void)resume {
    self.first = YES;
    [self.timer invalidate];
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer timerWithTimeInterval:1 repeats:YES block:^(__unused NSTimer *timer) { [weakSelf tick]; }];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
    [self loadPage];
}
- (void)loadPage {
    self.pages += 1;
    self.nextAt = CACurrentMediaTime() + DY778ListClearPageIntervalSeconds;
    [self reloadFolders];
}
- (void)selectAll {
    for (id folder in self.folders) {
        NSString *folderID = DY778ListID(DY778Read(folder, @"folderID") ?: DY778Read(folder, @"collectsId"));
        if (folderID.length) [self.selectedIDs addObject:folderID];
    }
    [self render];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return (NSInteger)self.folders.count;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"DY778ListFolderCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    id folder = self.folders[indexPath.row];
    NSString *folderID = DY778ListID(DY778Read(folder, @"folderID") ?: DY778Read(folder, @"collectsId")) ?: @"";
    cell.textLabel.text = [DY778Read(folder, @"name") isKindOfClass:NSString.class] ? DY778Read(folder, @"name") : folderID;
    cell.detailTextLabel.text = folderID;
    cell.accessoryType = [self.selectedIDs containsObject:folderID] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    id folder = self.folders[indexPath.row];
    NSString *folderID = DY778ListID(DY778Read(folder, @"folderID") ?: DY778Read(folder, @"collectsId"));
    if (!folderID.length) return;
    if ([self.selectedIDs containsObject:folderID]) [self.selectedIDs removeObject:folderID];
    else [self.selectedIDs addObject:folderID];
    [self render];
}
- (void)taskTapped {
    DY778ListShowClearTask(self);
}
- (void)clearTapped {
    DY778ListStopCollectionClear();
    DY778ListStartCollectionClear(self, self.folders.firstObject, nil);
}

@end

@implementation DY778ListFolderPrivacyBadge
- (CGSize)intrinsicContentSize {
    CGSize size = [super intrinsicContentSize];
    return CGSizeMake(size.width + 12, size.height + 4);
}
- (CGSize)sizeThatFits:(CGSize)size {
    CGSize fitted = [super sizeThatFits:size];
    return CGSizeMake(fitted.width + 12, fitted.height + 4);
}
- (void)drawTextInRect:(CGRect)rect {
    [super drawTextInRect:CGRectInset(rect, 6, 2)];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = 4;
    self.clipsToBounds = YES;
}
@end

// ---------- C 入口（规格 §6.1） ----------

UIViewController *DY778FollowClearController(void) {
    return [DY778FollowViewController new];
}
BOOL DY778FollowClearActive(void) {
    return DY778FollowJob.shared.removing;
}
void DY778FollowClearStop(void) {
    [DY778FollowJob.shared stop];
}
void DY778ResetListClear(void) {
    DY778Set(@"listClear.enabled", @NO);
    DY778FollowClearStop();
    // 原版 ResetListClear 内调 helper 0x8b404 / 0x98148（各 3 次），
    // 未拆（规格 §6.1）；DYxs 侧只做开关复位与停止。
}
void DY778ListStartCollectionClear(id owner, id folder, id context) {
    (void)context;
    id acquired = DY778ListAcquire();
    (void)acquired;
    DY778ListClearJob *job = DY778ListClearJob.shared;
    job.owner = owner;
    [job prepareFolderReader];
    [job startKind:DY778ListClearKindFavorite user:nil owner:owner mergedContainer:folder];
}
void DY778ListShowClearTask(id owner) {
    [[DY778ListClearJob shared] showTaskFrom:owner];
}
void DY778ListStopCollectionClear(void) {
    DY778ListClearJob *job = DY778ListClearJob.shared;
    if (job.active) [job stop:@"用户停止"];
}
UIViewController *DY778ListClearSettingsController(void) {
    return [DY778ListClearSettingsViewController new];
}
UIViewController *DY778ListFoldersController(void) {
    return [DY778ListFolderViewController new];
}

// ---------- 原生拦截（规格 §1.5、§6.4） ----------
// AWENetworkService 元类 get/post 各 1 个 hook，均为类方法，
// 返回 @、参数 @@#@，先经 _DY778ListMethod 签名校验，orig 槽非空
// 即跳过（幂等）。替换实现只观察并核对，不发取关请求。

typedef struct { void *isa; int flags, reserved; void *invoke; void *descriptor; } DY778LCBlockLayout;
static BOOL DY778LCCallbackCompatible(id callback) {
    if (!callback || ![callback isKindOfClass:NSClassFromString(@"NSBlock")]) return NO;
    const DY778LCBlockLayout *block = (__bridge const void *)callback;
    if (!(block->flags & (1 << 30)) || !block->descriptor) return NO;
    const uint8_t *descriptor = block->descriptor;
    descriptor += sizeof(unsigned long) * 2;
    if (block->flags & (1 << 25)) descriptor += sizeof(void *) * 2;
    const char *types = *(const char *const *)descriptor;
    if (!types) return NO;
    NSMethodSignature *s = [NSMethodSignature signatureWithObjCTypes:types];
    return !strcmp(s.methodReturnType, "v") && s.numberOfArguments == 3 &&
        [s getArgumentTypeAtIndex:1][0] == '@' && [s getArgumentTypeAtIndex:2][0] == '@';
}

static NSArray<NSString *> *DY778LCInterceptedModelNames(void) {
    // 拦截判定的模型类（规格 §6.4，字符串实锤）。
    return @[@"AWEUserFollowResponseModel", @"AWEProfileFavoriteCollectsListResponseModel", @"AFDFavoriteFolderListModel"];
}
static BOOL DY778LCShouldIntercept(Class modelClass, NSDictionary *params) {
    if (!modelClass) return NO;
    if (![DY778LCInterceptedModelNames() containsObject:NSStringFromClass(modelClass)]) return NO;
    // 参数键 to_user_id / follow_type / user_id（规格 §6.4）。
    if ([params isKindOfClass:NSDictionary.class]) {
        if (!DY778ListID(params[@"to_user_id"]) && !DY778ListID(params[@"user_id"])) return NO;
    }
    return YES;
}

static id DY778LCInvoke(id self, SEL cmd, NSString *url, NSDictionary *params, Class modelClass, id completion,
                        IMP original, BOOL isPost) {
    (void)cmd; (void)isPost;
    BOOL intercept = DY778LCShouldIntercept(modelClass, params);
    DY778ListNativeRequest *scope = nil;
    DY778ListClearReceipt *receipt = DY778ListClearJob.shared.receipt;
    if (intercept) {
        scope = [DY778ListNativeRequest account:DY778ListCurrentUser() target:self model:modelClass invoke:nil completion:completion];
        // 尾部 A（规格 §6.4）：_DY778ListID 校验 user_id；读
        // liveAnalysis.enabled（模块 2 的总开关，原因未证实，保留
        // 这次读数，见规格 §8.2）；查 applicationState；
        // threadDictionary 存取；对当前 receipt 置 submitted。
        NSString *userID = DY778ListID(params[@"user_id"] ?: params[@"to_user_id"]);
        BOOL liveAnalysisEnabled = DY778Bool(@"liveAnalysis.enabled");
        (void)liveAnalysisEnabled;
        if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive && userID.length) {
            scope.submitted = YES;
            if (receipt) receipt.submitted = YES;
            [[NSThread currentThread].threadDictionary setObject:scope forKey:@"DY778.List.NativeScope"];
        }
    }
    id wrappedCompletion = completion;
    if (intercept && DY778LCCallbackCompatible(completion)) {
        void (^originalCompletion)(id, id) = [completion copy];
        __weak DY778ListClearReceipt *weakReceipt = receipt;
        void (^wrapped)(id, id) = ^(id model, id error) {
            @try { originalCompletion(model, error); }
            @finally {
                // 尾部 B（规格 §6.4）：回包处理；对 receipt 置
                // received / finished；查 statusCode /
                // favoriteStatusCode；调 finishToast。
                dispatch_async(dispatch_get_main_queue(), ^{
                    DY778ListClearReceipt *strongReceipt = weakReceipt;
                    if (strongReceipt) {
                        strongReceipt.received = YES;
                        strongReceipt.intercepted = YES;
                        NSNumber *statusCode = DY778Read(model, @"statusCode");
                        NSNumber *favoriteStatusCode = DY778Read(model, @"favoriteStatusCode");
                        BOOL ok = error == nil && model != nil &&
                            (!statusCode || [statusCode longLongValue] == 0) &&
                            (!favoriteStatusCode || [favoriteStatusCode longLongValue] == 0);
                        // verified 的核对方式未还原（规格 §6.8）：
                        // 只在回包明确成功时置 verified，不重读列表比对。
                        strongReceipt.verified = ok;
                        DY778ShowToast(@"listClear", ok ? @"请求已核对" : @"请求回包异常", NO, ok);
                    }
                    [[NSThread currentThread].threadDictionary removeObjectForKey:@"DY778.List.NativeScope"];
                });
            }
        };
        wrappedCompletion = [wrapped copy];
    }
    id result = ((id (*)(id, SEL, id, id, Class, id))original)(self, cmd, url, params, modelClass, wrappedCompletion);
    if (scope) scope.task = result;
    return result;
}

static IMP DY778LCOriginalGet, DY778LCOriginalPost;
static id DY778LCGet(id self, SEL cmd, id url, id params, Class modelClass, id completion) {
    return DY778LCInvoke(self, cmd, url, params, modelClass, completion, DY778LCOriginalGet, NO);
}
static id DY778LCPost(id self, SEL cmd, id url, id params, Class modelClass, id completion) {
    return DY778LCInvoke(self, cmd, url, params, modelClass, completion, DY778LCOriginalPost, YES);
}

void DY778InstallListNativeHooks(void) {
    Class service = NSClassFromString(@"AWENetworkService");
    if (!service) return;
    Class metaclass = object_getClass(service);
    SEL getSelector = NSSelectorFromString(@"getWithURLString:params:modelClass:completion:");
    SEL postSelector = NSSelectorFromString(@"postWithURLString:params:modelClass:completion:");
    BOOL getInstalled = NO, postInstalled = NO;
    if (!DY778LCOriginalGet) {
        getInstalled = DY778LCSignature(metaclass, getSelector, "@", @[@"@", @"@", @"#", @"@"]) &&
            DY778Hook(metaclass, getSelector, (IMP)DY778LCGet, &DY778LCOriginalGet);
    }
    if (!DY778LCOriginalPost) {
        postInstalled = DY778LCSignature(metaclass, postSelector, "@", @[@"@", @"@", @"#", @"@"]) &&
            DY778Hook(metaclass, postSelector, (IMP)DY778LCPost, &DY778LCOriginalPost);
    }
    DY778RecordHook(@"清理关注 / AWENetworkService.getWithURLString:params:modelClass:completion:", getInstalled);
    DY778RecordHook(@"清理关注 / AWENetworkService.postWithURLString:params:modelClass:completion:", postInstalled);
}

// ---------- UI 刷新 hook（规格 §2.3） ----------

static IMP DY778LCOriginalRefresh, DY778LCOriginalReloadItem, DY778LCOriginalReloadView;
static void DY778LCRefresh(id self, SEL cmd, id config) {
    ((void (*)(id, SEL, id))DY778LCOriginalRefresh)(self, cmd, config);
    [NSNotificationCenter.defaultCenter postNotificationName:DY778PreferencesChangedNotification
                                                    object:nil userInfo:@{@"key": @"listClear.render"}];
}
static void DY778LCReloadItem(id self, SEL cmd) {
    ((void (*)(id, SEL))DY778LCOriginalReloadItem)(self, cmd);
    [NSNotificationCenter.defaultCenter postNotificationName:DY778PreferencesChangedNotification
                                                    object:nil userInfo:@{@"key": @"listClear.render"}];
}
static void DY778LCReloadView(id self, SEL cmd) {
    ((void (*)(id, SEL))DY778LCOriginalReloadView)(self, cmd);
    [NSNotificationCenter.defaultCenter postNotificationName:DY778PreferencesChangedNotification
                                                    object:nil userInfo:@{@"key": @"listClear.render"}];
}

void DY778InstallListClearHooks(void) {
    // 入口查 isMainThread（非主线程直接返回）；先调
    // _DY778InstallListNative，再装 UI 刷新 hook（规格 §1.4）。
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ DY778InstallListClearHooks(); }); return; }
    DY778InstallListNativeHooks();
    // 已确认的 3 个（规格 §2.3）：AWEProfileBaseHeaderSegmentCell
    // refreshWithConfig:、AWERLSegmentItemView __reloadData、
    // AWERLSegmentView __reloadData。第 4 个 setTitle:forState:
    // 归属未解析（AWERLSegmentItemView / AWERLSegmentView 之一），
    // DYxs 侧不安装。
    Class headerCell = NSClassFromString(@"AWEProfileBaseHeaderSegmentCell");
    BOOL refreshInstalled = NO;
    if (!DY778LCOriginalRefresh) {
        refreshInstalled = DY778LCSignature(headerCell, NSSelectorFromString(@"refreshWithConfig:"), "v", @[@"@"]) &&
            DY778Hook(headerCell, NSSelectorFromString(@"refreshWithConfig:"), (IMP)DY778LCRefresh, &DY778LCOriginalRefresh);
    }
    Class itemView = NSClassFromString(@"AWERLSegmentItemView");
    BOOL itemInstalled = NO;
    if (!DY778LCOriginalReloadItem) {
        itemInstalled = DY778LCSignature(itemView, NSSelectorFromString(@"__reloadData"), "v", @[]) &&
            DY778Hook(itemView, NSSelectorFromString(@"__reloadData"), (IMP)DY778LCReloadItem, &DY778LCOriginalReloadItem);
    }
    Class segmentView = NSClassFromString(@"AWERLSegmentView");
    BOOL viewInstalled = NO;
    if (!DY778LCOriginalReloadView) {
        viewInstalled = DY778LCSignature(segmentView, NSSelectorFromString(@"__reloadData"), "v", @[]) &&
            DY778Hook(segmentView, NSSelectorFromString(@"__reloadData"), (IMP)DY778LCReloadView, &DY778LCOriginalReloadView);
    }
    DY778RecordHook(@"清理关注 / AWEProfileBaseHeaderSegmentCell.refreshWithConfig:", refreshInstalled);
    DY778RecordHook(@"清理关注 / AWERLSegmentItemView.__reloadData", itemInstalled);
    DY778RecordHook(@"清理关注 / AWERLSegmentView.__reloadData", viewInstalled);
}
