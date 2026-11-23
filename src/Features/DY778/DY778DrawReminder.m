#import "DY778DrawReminder.h"
#import "DY778Core.h"
#import "DY778Avatar.h"
#import "DY778MiscPolicy.h"
#import <mach/mach_time.h>

// DY778 1.0-8 模块 4：抽奖提醒（规格 §4）。
// DY778DrawCenter 计时/弹窗/跳房；DY778DrawCard 倒计时卡片。

static NSString *const DY778DrawRecordsKey = @"drawReminders.records";

static double DY778DrawMonotonic(void) {
    static mach_timebase_info_data_t info;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ mach_timebase_info(&info); });
    return (double)mach_continuous_time() * (double)info.numer / (double)info.denom / 1e9;
}

NSString *DY778DrawReminderKey(NSString *account, NSString *kind, NSString *room, NSString *activity) {
    return [NSString stringWithFormat:@"%@/%@/%@/%@", account ?: @"", kind ?: @"", room ?: @"", activity ?: @""];
}

NSDictionary *DY778DrawReminderRecord(NSDictionary *raw) {
    if (![raw isKindOfClass:NSDictionary.class]) return @{};
    NSMutableDictionary *record = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"account", @"kind", @"name", @"avatar", @"room", @"lucky", @"handle",
                            @"prize", @"ownerID", @"activity", @"confirmed", @"superLucky", @"group"]) {
        id value = raw[key];
        if (value) record[key] = value;
    }
    id deadline = raw[@"deadline"];
    if ([deadline respondsToSelector:@selector(doubleValue)]) record[@"deadline"] = @([deadline doubleValue]);
    else record[@"deadline"] = @0;
    record[@"shown"] = @([raw[@"shown"] boolValue]);
    return record;
}

NSDictionary *DY778DrawReminderOwner(id context) {
    if (!context) return @{};
    // 字段（规格 §4.1）：name、uid、userID、nickname、avatarMedium、
    // avatar、avatarThumb、handle、idStr、id_p、ownerID、uniqueID、
    // uniqueId、unique_id、displayID、displayId、shortID。
    NSMutableDictionary *owner = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"name", @"uid", @"userID", @"nickname", @"avatarMedium", @"avatar",
                            @"avatarThumb", @"handle", @"idStr", @"id_p", @"ownerID", @"uniqueID",
                            @"uniqueId", @"unique_id", @"displayID", @"displayId", @"shortID"]) {
        id value = DY778Read(context, key);
        if (!value) value = DY778Read(DY778Read(context, @"owner"), key);
        if (!value) value = DY778Read(DY778Read(context, @"user"), key);
        if (value) owner[key] = value;
    }
    NSString *avatar = DY778AvatarURL(owner[@"avatarMedium"] ?: owner[@"avatar"] ?: owner[@"avatarThumb"]);
    if (avatar.length) owner[@"avatar"] = avatar;
    return owner;
}

NSTimeInterval DY778DrawReminderParseSeconds(id value) {
    // 秒数字符串格式未证实（规格 §4.2）：可能是 "90" 或 "90s"，
    // DYxs 侧两者都接受（去尾部 's' 再 integerValue）。
    if ([value isKindOfClass:NSString.class]) {
        NSString *text = [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if ([text hasSuffix:@"s"] || [text hasSuffix:@"S"]) text = [text substringToIndex:text.length - 1];
        return [text integerValue];
    }
    if ([value respondsToSelector:@selector(doubleValue)]) return [value doubleValue];
    return 0;
}

NSTimeInterval DY778DrawReminderSeconds(NSString *kind) {
    NSString *key = [NSString stringWithFormat:@"%@.drawReminderSeconds", kind ?: @"lucky"];
    id value = [DY778Preferences() objectForKey:key];
    NSTimeInterval seconds = DY778DrawReminderParseSeconds(value);
    return seconds > 0 ? seconds : 60;
}

BOOL DY778DrawReminderDueWithLead(NSDictionary *record, NSTimeInterval lead) {
    if (![record isKindOfClass:NSDictionary.class]) return NO;
    if ([record[@"shown"] boolValue]) return NO;
    double deadline = [record[@"deadline"] doubleValue];
    if (deadline <= 0) return NO;
    return (deadline - lead) <= DY778DrawMonotonic();
}

BOOL DY778DrawReminderDue(NSDictionary *record) {
    // lead=0 的包装（规格 §4.1）：0 个直接调用点，疑似死代码或经
    // 函数指针调用。DYxs 侧实现它但不调用。
    return DY778DrawReminderDueWithLead(record, 0);
}

NSString *DY778DrawReminderRoute(NSString *roomID, NSString *userID) {
    NSString *room = roomID ?: @"", *user = userID ?: @"";
    return [NSString stringWithFormat:@"sslocal://webcast_room?room_id=%@&user_id=%@&enter_from_merge=live_merge&enter_method=live_cover", room, user];
}

static BOOL DY778DrawLiveRoomRouteAvailable(void) {
    Class router = NSClassFromString(@"AWERouter");
    SEL selector = NSSelectorFromString(@"transferToURLString:");
    Method method = router ? class_getClassMethod(router, selector) : NULL;
    if (!method) return NO;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (signature.numberOfArguments != 3 || signature.methodReturnType[0] != 'v') return NO;
    const char *argument = [signature getArgumentTypeAtIndex:2];
    return argument[0] == '@';
}

void DY778NavigateToLiveRoom(NSString *roomID, NSString *userID) {
    if (!DY778DrawLiveRoomRouteAvailable()) { DY778Toast(@"当前版本暂不支持跳房"); return; }
    Class router = NSClassFromString(@"AWERouter");
    SEL selector = NSSelectorFromString(@"transferToURLString:");
    NSString *route = DY778DrawReminderRoute(roomID, userID);
    @try {
        ((void (*)(id, SEL, id))objc_msgSend)(router, selector, route);
    } @catch (__unused NSException *exception) {
        DY778Toast(@"跳房失败");
    }
}

void DY778DrawReminderRemember(NSDictionary *rawRecord) {
    [[DY778DrawCenter shared] remember:rawRecord];
}

// ---------- DY778DrawCenter ----------

@implementation DY778DrawCenter

+ (instancetype)shared {
    static DY778DrawCenter *value; static dispatch_once_t once;
    dispatch_once(&once, ^{ value = [self new]; }); return value;
}

- (instancetype)init {
    if ((self = [super init])) {
        NSDictionary *saved = [DY778Preferences() objectForKey:DY778DrawRecordsKey];
        _records = [saved isKindOfClass:NSDictionary.class] ? [saved mutableCopy] : [NSMutableDictionary dictionary];
        _monotonic = DY778DrawMonotonic();
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserver:self selector:@selector(keyboard:) name:UIKeyboardWillShowNotification object:nil];
        [center addObserver:self selector:@selector(keyboard:) name:UIKeyboardWillHideNotification object:nil];
        [center addObserver:self selector:@selector(changed:) name:DY778PreferencesChangedNotification object:nil];
        [self armTimer];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self.timer invalidate];
}

- (void)armTimer {
    if (self.timer) return;
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer timerWithTimeInterval:1 repeats:YES block:^(__unused NSTimer *timer) { [weakSelf tick]; }];
    self.timer.tolerance = DY778DrawReminderTimerToleranceSeconds;
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)save {
    [DY778Preferences() setObject:[self.records copy] forKey:DY778DrawRecordsKey];
}

- (BOOL)enabled:(NSString *)kind {
    NSString *key = [NSString stringWithFormat:@"%@.drawReminder", kind ?: @"lucky"];
    return DY778Bool(key);
}

- (NSTimeInterval)remaining:(NSDictionary *)record {
    return [record[@"deadline"] doubleValue] - DY778DrawMonotonic();
}

- (void)keyboard:(NSNotification *)notification {
    self.keyboardVisible = [notification.name isEqualToString:UIKeyboardWillShowNotification];
}

- (void)changed:(NSNotification *)notification {
    NSString *key = notification.userInfo[@"key"];
    if (!key.length || [key hasSuffix:@".drawReminder"] || [key hasSuffix:@".drawReminderSeconds"]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self tick]; });
    }
}

- (void)remember:(NSDictionary *)rawRecord {
    NSDictionary *record = DY778DrawReminderRecord(rawRecord);
    NSString *key = DY778DrawReminderKey(record[@"account"], record[@"kind"], record[@"room"], record[@"activity"]);
    if (!key.length || [key isEqualToString:@"///"]) return;
    if (self.records.count >= DY778DrawReminderMaximumRecords) {
        // 超上限时删最早过期的已展示记录，再记。
        for (NSString *oldKey in self.records.allKeys) {
            if ([self.records[oldKey][@"shown"] boolValue]) { [self.records removeObjectForKey:oldKey]; break; }
        }
    }
    self.records[key] = record;
    [self save];
}

- (BOOL)canPresent:(UIViewController *)presenter {
    if (self.keyboardVisible || self.dismissing) return NO;
    if (!presenter || presenter.isBeingDismissed || presenter.isBeingPresented) return NO;
    if (!presenter.viewIfLoaded) return NO;
    NSString *className = NSStringFromClass(presenter.class).lowercaseString;
    for (size_t i = 0; i < DY778DrawReminderBlockedControllerSubstringCount; i++) {
        NSString *blocked = [NSString stringWithUTF8String:DY778DrawReminderBlockedControllerSubstrings[i]];
        if ([className containsString:blocked]) return NO;
    }
    UIViewController *presenting = presenter.presentingViewController;
    if (presenting && presenting.presentedViewController == presenter) return NO;
    return YES;
}

- (void)close:(NSDictionary *)record {
    if (!record) return;
    NSString *kind = record[@"kind"] ?: @"lucky";
    if (![self enabled:kind]) return;
    NSString *key = DY778DrawReminderKey(record[@"account"], kind, record[@"room"], record[@"activity"]);
    NSMutableDictionary *updated = [record mutableCopy];
    updated[@"shown"] = @YES;
    if (key.length) { self.records[key] = updated; [self save]; }
    UIViewController *card = self.card;
    self.card = nil;
    self.dismissing = YES;
    void (^afterDismiss)(void) = ^{
        self.dismissing = NO;
        DY778NavigateToLiveRoom(record[@"room"], record[@"ownerID"]);
        DY778Toast(@"正在为你跳回开奖直播间");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self tick]; });
    };
    if (card && card.presentingViewController) {
        [card dismissViewControllerAnimated:YES completion:afterDismiss];
    } else {
        afterDismiss();
    }
}

- (void)tick {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self tick]; }); return; }
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    self.monotonic = DY778DrawMonotonic();
    UIViewController *top = DY778TopController();
    if (![self canPresent:top]) return;
    for (NSString *key in self.records.allKeys) {
        NSDictionary *record = self.records[key];
        NSString *kind = record[@"kind"] ?: @"lucky";
        if (![self enabled:kind]) continue;
        NSTimeInterval lead = DY778DrawReminderSeconds(kind);
        if (!DY778DrawReminderDueWithLead(record, lead)) continue;
        DY778DrawCard *card = [[DY778DrawCard alloc] initWithRecord:record];
        __weak typeof(self) weakSelf = self;
        card.choice = ^(BOOL jump) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (jump) [strongSelf close:record];
            else {
                NSMutableDictionary *updated = [record mutableCopy];
                updated[@"shown"] = @YES;
                strongSelf.records[key] = updated;
                [strongSelf save];
                UIViewController *presented = strongSelf.card;
                strongSelf.card = nil;
                [presented dismissViewControllerAnimated:YES completion:nil];
            }
        };
        self.card = card;
        [top presentViewController:card animated:YES completion:nil];
        return;
    }
}

@end

// ---------- DY778DrawCard ----------

@implementation DY778DrawCard

- (instancetype)initWithRecord:(NSDictionary *)record {
    if ((self = [super init])) {
        _record = record;
    }
    return self;
}

- (UILabel *)label:(NSString *)text style:(NSString *)style {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    if ([style isEqualToString:@"title"]) { label.font = [UIFont boldSystemFontOfSize:17]; }
    else if ([style isEqualToString:@"countdown"]) { label.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightMedium]; }
    else { label.font = [UIFont systemFontOfSize:14]; }
    label.textColor = UIColor.labelColor;
    return label;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    DY778StyleController(self);
    NSString *name = self.record[@"name"] ?: self.record[@"prize"] ?: @"开奖";
    NSString *kind = [self.record[@"kind"] isEqualToString:@"superLucky"] ? @"福袋" : @"红包";
    self.titleLabel = [self label:[NSString stringWithFormat:@"%@即将开奖", name] style:@"title"];
    UILabel *subtitle = [self label:[NSString stringWithFormat:@"%@ · %@", kind, self.record[@"room"] ?: @""] style:@"body"];
    self.countdownLabel = [self label:@"" style:@"countdown"];
    UIButton *jumpButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [jumpButton setTitle:@"去直播间" forState:UIControlStateNormal];
    [jumpButton addTarget:self action:@selector(jump) forControlEvents:UIControlEventTouchUpInside];
    UIButton *ignoreButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [ignoreButton setTitle:@"忽略" forState:UIControlStateNormal];
    [ignoreButton addTarget:self action:@selector(ignore) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.titleLabel, subtitle, self.countdownLabel, jumpButton, ignoreButton]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:24],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-24]]];
    [self countdown];
}

- (void)updateRemaining:(NSTimeInterval)remaining {
    NSTimeInterval value = MAX(0, remaining);
    NSInteger minutes = (NSInteger)(value / 60), seconds = (NSInteger)value % 60;
    self.countdownLabel.text = [NSString stringWithFormat:@"%02ld:%02ld 后开奖", (long)minutes, (long)seconds];
}

- (void)countdown {
    NSTimeInterval remaining = [self.record[@"deadline"] doubleValue] - DY778DrawMonotonic();
    [self updateRemaining:remaining];
}

- (void)jump {
    if (self.choice) self.choice(YES);
}

- (void)ignore {
    if (self.choice) self.choice(NO);
}

@end

// ---------- 安装 ----------
// _DY778InstallDrawReminders（0x571c4）不是 hook 安装器：本体只有
// dispatch_async(队列, block)，block 做 [[DY778DrawCenter shared] tick]。
void DY778InstallDrawReminders(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ [[DY778DrawCenter shared] tick]; });
}
