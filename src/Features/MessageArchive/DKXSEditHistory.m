//  DKXSEditHistory.m
//  DY778 第 1 批 staging：对应上游 DY778EditHistory.m 的存储、观测与历史页。
//  判定直接复用 DKXSMessageArchivePolicy.h 的 DKXSDecideEdit；
//  版本合并规则（与上游 DY778MergeEditRecord 一致）：
//  · 基线（首见未编辑）只记原文；已编辑首见记“未取得原文”占位版本；
//  · 后续编辑按 (editTime, editCount) 单调追加，正文相同不追加（元数据先到时不配对旧正文）；
//  · 正文超过 1MB 不入库（防分享体撑爆数据库）。

#import "DKXSEditHistory.h"
#import "DKXSEditContent.h"
#import "DKXSRecall.h"
#import "DKXSRecallNotifications.h"
#import "DKXSArchiveStorage.h"
#import "DKXSArchiveCore.h"
#import "DKXSMessageArchivePolicy.h"
#import <sqlite3.h>
#import <objc/runtime.h>

NSNotificationName const DKXSEditHistoryChangedNotification = @"DKXSEditHistoryChangedNotification";
NSNotificationName const DKXSEditDetectedNotification = @"DKXSEditDetectedNotification";

static char kDKXSEditBinding;
static void DKXSEditNotify(void) {
    static BOOL queued;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (queued) return; queued = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            queued = NO; [NSNotificationCenter.defaultCenter postNotificationName:DKXSEditHistoryChangedNotification object:nil];
        });
    });
}
static NSString *DKXSEditScope(NSString *account, NSString *conversation) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[account ?: @"", conversation ?: @""] options:0 error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}
BOOL DKXSEditCaptureEnabled(void) { return DKXSArchiveBool(@"DKXSEditEnabled"); }
BOOL DKXSEditEnabledForConversation(NSString *conversation) {
    if (!DKXSEditCaptureEnabled()) return NO;
    NSString *key = DKXSEditScope(DKXSArchiveCurrentAccountID(), conversation);
    id disabled = [NSUserDefaults.standardUserDefaults objectForKey:@"DKXSEditDisabledConversations"];
    return !([disabled isKindOfClass:NSDictionary.class] && [disabled[key] boolValue]);
}
void DKXSSetConversationEditEnabled(NSString *conversation, BOOL enabled) {
    NSString *key = DKXSEditScope(DKXSArchiveCurrentAccountID(), conversation);
    if (!key.length) return;
    NSMutableDictionary *disabled = [[NSUserDefaults.standardUserDefaults objectForKey:@"DKXSEditDisabledConversations"] isKindOfClass:NSDictionary.class]
        ? [[NSUserDefaults.standardUserDefaults objectForKey:@"DKXSEditDisabledConversations"] mutableCopy] : [NSMutableDictionary dictionary];
    if (enabled) [disabled removeObjectForKey:key]; else disabled[key] = @YES;
    DKXSArchiveSet(@"DKXSEditDisabledConversations", disabled);
}

// ---- sqlite 存储 ----
@interface DKXSEditStore : NSObject
@property(nonatomic) sqlite3 *database;
@property(atomic, copy) NSString *status;
+ (instancetype)shared;
- (NSDictionary *)recordForKey:(NSString *)key account:(NSString *)account;
- (void)saveRecord:(NSDictionary *)record;
- (NSArray<NSDictionary *> *)recordsForAccount:(NSString *)account conversation:(NSString *)conversation;
- (void)removeKey:(NSString *)key account:(NSString *)account;
- (void)removeConversation:(NSString *)conversation account:(NSString *)account;
- (void)removeAllForAccount:(NSString *)account;
- (void)maintenance;
@end
@implementation DKXSEditStore
+ (instancetype)shared { static DKXSEditStore *store; static dispatch_once_t once; dispatch_once(&once, ^{ store = [self new]; [store open]; }); return store; }
- (void)open {
    NSURL *root = DKXSArchiveDirectory(@"EditHistory");
    if (!root) { self.status = @"编辑历史目录不可写"; return; }
    NSString *path = [root URLByAppendingPathComponent:@"history.sqlite"].path;
    sqlite3 *db = NULL;
    if (sqlite3_open_v2(path.UTF8String, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, NULL) != SQLITE_OK) {
        if (db) sqlite3_close(db); self.status = @"编辑历史数据库暂不可用"; return;
    }
    sqlite3_busy_timeout(db, 1500);
    const char *schema = "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA secure_delete=ON;"
        "CREATE TABLE IF NOT EXISTS edits(key TEXT PRIMARY KEY,account TEXT NOT NULL,conversation TEXT NOT NULL,server_id TEXT NOT NULL,created REAL NOT NULL,seen REAL NOT NULL,edited_at REAL NOT NULL,changes INTEGER NOT NULL,payload BLOB NOT NULL);"
        "CREATE INDEX IF NOT EXISTS edit_conversation ON edits(account,conversation,edited_at);"
        "CREATE INDEX IF NOT EXISTS edit_server ON edits(account,conversation,server_id);"
        "CREATE TABLE IF NOT EXISTS forgotten(key TEXT PRIMARY KEY,account TEXT NOT NULL);"
        "CREATE TRIGGER IF NOT EXISTS reject_deleted_edit BEFORE INSERT ON edits WHEN EXISTS(SELECT 1 FROM forgotten WHERE key=NEW.key) BEGIN SELECT RAISE(IGNORE); END;";
    if (sqlite3_exec(db, schema, NULL, NULL, NULL) != SQLITE_OK) { sqlite3_close(db); self.status = @"编辑历史初始化失败"; return; }
    self.database = db;
    [NSFileManager.defaultManager setAttributes:@{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:path error:nil];
    self.status = @"本机保存 · 按账号与会话隔离";
}
static void DKXSEditBind(sqlite3_stmt *statement, int index, NSString *value) {
    sqlite3_bind_text(statement, index, (value ?: @"").UTF8String, -1, SQLITE_TRANSIENT);
}
- (NSDictionary *)recordForKey:(NSString *)key account:(NSString *)account {
    sqlite3_stmt *statement = NULL; NSDictionary *record = nil;
    if (self.database && sqlite3_prepare_v2(self.database, "SELECT payload FROM edits WHERE key=? AND account=?", -1, &statement, NULL) == SQLITE_OK) {
        DKXSEditBind(statement, 1, key); DKXSEditBind(statement, 2, account);
        if (sqlite3_step(statement) == SQLITE_ROW) {
            const void *bytes = sqlite3_column_blob(statement, 0); int size = sqlite3_column_bytes(statement, 0);
            if (bytes && size > 0) record = DKXSArchiveDecodeJSON([NSData dataWithBytes:bytes length:(NSUInteger)size]);
        }
    }
    sqlite3_finalize(statement); return record;
}
- (void)saveRecord:(NSDictionary *)record {
    NSData *data = DKXSArchiveEncodeJSON(record);
    if (!self.database || !data) return;
    sqlite3_stmt *statement = NULL;
    const char *sql = "INSERT INTO edits(key,account,conversation,server_id,created,seen,edited_at,changes,payload) VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(key) DO UPDATE SET server_id=excluded.server_id,seen=excluded.seen,edited_at=excluded.edited_at,changes=excluded.changes,payload=excluded.payload";
    if (sqlite3_prepare_v2(self.database, sql, -1, &statement, NULL) != SQLITE_OK) return;
    DKXSEditBind(statement, 1, record[@"key"]); DKXSEditBind(statement, 2, record[@"account"]); DKXSEditBind(statement, 3, record[@"conversation"]);
    DKXSEditBind(statement, 4, record[@"serverID"]);
    sqlite3_bind_double(statement, 5, [record[@"created"] doubleValue]); sqlite3_bind_double(statement, 6, [record[@"seen"] doubleValue]);
    sqlite3_bind_double(statement, 7, [record[@"editedAt"] doubleValue]); sqlite3_bind_int(statement, 8, (int)[record[@"changes"] integerValue]);
    sqlite3_bind_blob(statement, 9, data.bytes, (int)data.length, SQLITE_TRANSIENT);
    sqlite3_step(statement); sqlite3_finalize(statement);
}
- (NSArray<NSDictionary *> *)recordsForAccount:(NSString *)account conversation:(NSString *)conversation {
    NSMutableArray *results = [NSMutableArray array];
    sqlite3_stmt *statement = NULL;
    NSString *sql = conversation.length
        ? @"SELECT payload FROM edits WHERE account=? AND conversation=? ORDER BY edited_at DESC"
        : @"SELECT payload FROM edits WHERE account=? ORDER BY edited_at DESC LIMIT 500";
    if (self.database && sqlite3_prepare_v2(self.database, sql.UTF8String, -1, &statement, NULL) == SQLITE_OK) {
        DKXSEditBind(statement, 1, account);
        if (conversation.length) DKXSEditBind(statement, 2, conversation);
        while (sqlite3_step(statement) == SQLITE_ROW) {
            const void *bytes = sqlite3_column_blob(statement, 0); int size = sqlite3_column_bytes(statement, 0);
            if (bytes && size > 0) { NSDictionary *record = DKXSArchiveDecodeJSON([NSData dataWithBytes:bytes length:(NSUInteger)size]); if (record) [results addObject:record]; }
        }
    }
    sqlite3_finalize(statement); return results;
}
- (void)removeKey:(NSString *)key account:(NSString *)account {
    if (!self.database) return;
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(self.database, "DELETE FROM edits WHERE key=? AND account=?", -1, &statement, NULL) == SQLITE_OK) {
        DKXSEditBind(statement, 1, key); DKXSEditBind(statement, 2, account); sqlite3_step(statement);
    }
    sqlite3_finalize(statement);
    if (sqlite3_prepare_v2(self.database, "INSERT OR REPLACE INTO forgotten(key,account) VALUES(?,?)", -1, &statement, NULL) == SQLITE_OK) {
        DKXSEditBind(statement, 1, key); DKXSEditBind(statement, 2, account); sqlite3_step(statement);
    }
    sqlite3_finalize(statement);
}
- (void)removeConversation:(NSString *)conversation account:(NSString *)account {
    for (NSDictionary *record in [self recordsForAccount:account conversation:conversation]) [self removeKey:record[@"key"] account:account];
}
- (void)removeAllForAccount:(NSString *)account {
    sqlite3_stmt *statement = NULL;
    if (self.database && sqlite3_prepare_v2(self.database, "SELECT DISTINCT conversation FROM edits WHERE account=?", -1, &statement, NULL) == SQLITE_OK) {
        DKXSEditBind(statement, 1, account);
        NSMutableArray *conversations = [NSMutableArray array];
        while (sqlite3_step(statement) == SQLITE_ROW) { const char *c = (const char *)sqlite3_column_text(statement, 0); if (c) [conversations addObject:[NSString stringWithUTF8String:c]]; }
        sqlite3_finalize(statement);
        for (NSString *conversation in conversations) [self removeConversation:conversation account:account];
        return;
    }
    sqlite3_finalize(statement);
}
- (void)maintenance {
    if (!self.database) return;
    double days = DKXSArchiveNumber(@"DKXSEditRetentionDays");
    if (days > 0) {
        sqlite3_stmt *statement = NULL;
        if (sqlite3_prepare_v2(self.database, "DELETE FROM edits WHERE seen < ?", -1, &statement, NULL) == SQLITE_OK) {
            sqlite3_bind_double(statement, 1, NSDate.date.timeIntervalSince1970 - days * 86400); sqlite3_step(statement);
        }
        sqlite3_finalize(statement);
    }
    double maxRecords = DKXSArchiveNumber(@"DKXSEditMaxRecords");
    if (maxRecords > 0) {
        sqlite3_stmt *statement = NULL;
        if (sqlite3_prepare_v2(self.database, "DELETE FROM edits WHERE key NOT IN (SELECT key FROM edits ORDER BY seen DESC LIMIT ?)", -1, &statement, NULL) == SQLITE_OK) {
            sqlite3_bind_int(statement, 1, (int)maxRecords); sqlite3_step(statement);
        }
        sqlite3_finalize(statement);
    }
}
@end

// ---- 观测与版本合并 ----
static NSDictionary *DKXSMergeEditRecord(NSDictionary *prior, NSDictionary *event) {
    NSDictionary *info = event[@"info"];
    BOOL edited = [info[@"edited"] boolValue];
    NSString *text = event[@"content"][@"text"];
    if (![text isKindOfClass:NSString.class]) text = @"";
    double editTime = [info[@"editTime"] doubleValue];
    long long editCount = [info[@"editCount"] longLongValue];
    double previousTime = [prior[@"lastEditTime"] doubleValue];
    long long previousCount = [prior[@"changes"] longLongValue];
    BOOL same = [prior[@"lastText"] isEqualToString:text] && previousTime == editTime && previousCount == editCount;
    DKXSEditDecision decision = DKXSDecideEdit(YES, prior != nil, edited, same, previousTime, editTime, previousCount, editCount);
    if (decision == DKXSEditIgnore) return prior;
    NSMutableDictionary *merged = prior ? [prior mutableCopy] : [NSMutableDictionary dictionary];
    merged[@"key"] = event[@"key"]; merged[@"account"] = event[@"account"]; merged[@"conversation"] = event[@"conversation"];
    merged[@"serverID"] = event[@"serverID"]; merged[@"messageID"] = event[@"messageID"];
    merged[@"sender"] = event[@"sender"]; merged[@"senderName"] = event[@"senderName"] ?: @"";
    if (!merged[@"created"]) merged[@"created"] = @(event[@"observedAt"]);
    merged[@"seen"] = @(event[@"observedAt"]);
    NSMutableArray *versions = [merged[@"versions"] isKindOfClass:NSArray.class] ? [merged[@"versions"] mutableCopy] : [NSMutableArray array];
    if (decision == DKXSEditBaseline) {
        if (!versions.count) [versions addObject:@{@"text": text, @"at": @(event[@"observedAt"]), @"kind": @"original"}];
        merged[@"lastText"] = text; merged[@"changes"] = @0;
    } else if (decision == DKXSEditFirstSeenEdited) {
        [versions addObject:@{@"text": @"", @"at": @(event[@"observedAt"]), @"kind": @"unknown-original"}];
        [versions addObject:@{@"text": text, @"at": editTime > 0 ? @(editTime) : @(event[@"observedAt"]), @"kind": @"edited"}];
        merged[@"lastText"] = text; merged[@"lastEditTime"] = @(editTime); merged[@"changes"] = @1;
    } else if (decision == DKXSEditAppend) {
        [versions addObject:@{@"text": text, @"at": editTime > 0 ? @(editTime) : @(event[@"observedAt"]), @"kind": @"edited"}];
        merged[@"lastText"] = text; merged[@"lastEditTime"] = @(editTime);
        merged[@"changes"] = @([merged[@"changes"] longLongValue] + 1);
    }
    merged[@"versions"] = versions;
    merged[@"editedAt"] = @(editTime > 0 ? editTime : event[@"observedAt"]);
    return merged;
}
void DKXSEditObserveMessage(id message, NSDictionary *content, NSDictionary *editInfo) {
    if (!message || !DKXSEditCaptureEnabled()) return;
    NSDictionary *identity = DKXSMessageIdentity(message);
    if (!identity) return;
    NSString *account = identity[@"account"], *conversation = identity[@"conversation"];
    if (![account isEqual:DKXSArchiveCurrentAccountID()] || !DKXSEditEnabledForConversation(conversation)) return;
    NSString *sender = DKXSArchiveIdentifier(DKXSArchiveRead(message, @"sender"));
    if (!sender.length || [sender isEqualToString:@"0"] || [sender isEqualToString:account]) return; // 只记对方编辑
    if (!content) {
        id raw = DKXSArchiveRead(message, @"content");
        content = [raw isKindOfClass:NSDictionary.class] ? (DKXSArchiveImmutableJSON(raw) ?: @{}) : @{};
    }
    if (!editInfo) {
        editInfo = DKXSEditInfoSnapshot(DKXSArchiveRead(message, @"editInfo"));
        if (!editInfo) {
            id synced = DKXSArchiveRead(message, @"syncedExt");
            id encoded = [synced isKindOfClass:NSDictionary.class] ? synced[@"s:edit_info"] : nil;
            if ([encoded isKindOfClass:NSString.class]) encoded = [NSJSONSerialization JSONObjectWithData:[encoded dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
            editInfo = DKXSEditInfoSnapshot(encoded);
        }
    }
    if (!editInfo) return;
    NSData *probe = [NSJSONSerialization dataWithJSONObject:content options:0 error:nil];
    if (probe.length > 1024 * 1024) return; // 超大正文不入库
    NSTimeInterval observedAt = NSDate.date.timeIntervalSince1970;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        DKXSEditStore *store = DKXSEditStore.shared;
        NSDictionary *prior = [store recordForKey:identity[@"key"] account:account];
        if (!prior && [identity[@"serverID"] length]) {
            NSArray *candidates = [store recordsForAccount:account conversation:conversation];
            for (NSDictionary *candidate in candidates) {
                if ([candidate[@"serverID"] isEqual:identity[@"serverID"]]) { prior = candidate; break; }
            }
        }
        NSMutableDictionary *event = [identity mutableCopy];
        event[@"info"] = editInfo; event[@"content"] = content; event[@"observedAt"] = @(observedAt);
        event[@"sender"] = sender;
        event[@"senderName"] = DKXSArchiveIdentifier(DKXSArchiveRead(DKXSArchiveRead(message, @"senderProfile"), @"nickname")) ?: @"";
        NSDictionary *merged = DKXSMergeEditRecord(prior, event);
        if (!merged || merged == prior || [merged isEqual:prior]) return;
        BOOL hadPrevious = prior != nil;
        BOOL hadCapturedVersion = [prior[@"versions"] count] > 0;
        long long previousChanges = [prior[@"changes"] longLongValue];
        [store saveRecord:merged];
        objc_setAssociatedObject(message, &kDKXSEditBinding, merged, OBJC_ASSOCIATION_RETAIN);
        dispatch_async(dispatch_get_main_queue(), ^{
            DKXSEditNotify();
            if (DKXSEditShouldNotify(hadPrevious, hadCapturedVersion, previousChanges, [merged[@"changes"] longLongValue])) {
                [NSNotificationCenter.defaultCenter postNotificationName:DKXSEditDetectedNotification object:nil userInfo:@{@"record": merged}];
                DKXSEditNotifyDetected(merged);
            }
        });
    });
}
void DKXSEditObserveContext(id viewModel) {
    id message = DKXSArchiveRead(viewModel, @"iesMessage") ?: DKXSArchiveRead(viewModel, @"message");
    if (message) DKXSEditObserveMessage(message, nil, nil);
}
NSDictionary *DKXSEditRecordForMessage(id message) {
    NSDictionary *bound = objc_getAssociatedObject(message, &kDKXSEditBinding);
    if (bound) return bound;
    NSDictionary *identity = DKXSMessageIdentity(message);
    if (!identity) return nil;
    return [DKXSEditStore.shared recordForKey:identity[@"key"] account:identity[@"account"]];
}
void DKXSEditClearHistory(void) {
    NSString *account = DKXSArchiveCurrentAccountID();
    if (!account.length) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [DKXSEditStore.shared removeAllForAccount:account];
        dispatch_async(dispatch_get_main_queue(), ^{ DKXSEditNotify(); });
    });
}
void DKXSEditHistoryMaintenance(void) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ [DKXSEditStore.shared maintenance]; });
}
NSString *DKXSEditHistoryStatus(void) { return DKXSEditStore.shared.status ?: @""; }

// ---- 历史页 ----
static NSString *DKXSEditDate(double time) {
    if (time <= 0) return @"未知";
    NSDateFormatter *format = [NSDateFormatter new]; format.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    format.dateFormat = @"yyyy-MM-dd HH:mm:ss"; format.timeZone = NSTimeZone.localTimeZone;
    return [format stringFromDate:[NSDate dateWithTimeIntervalSince1970:time]];
}
@interface DKXSEditHistoryController : UITableViewController <UISearchResultsUpdating>
@property(nonatomic, copy) NSString *conversation;
@property(nonatomic, copy) NSString *messageKey;
@property(nonatomic, copy) NSArray *rows;
@property(nonatomic, copy) NSArray *filtered;
@property(nonatomic, strong) UISearchController *search;
@end
@implementation DKXSEditHistoryController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.messageKey.length ? @"消息编辑历史" : (self.conversation.length ? @"此会话的编辑历史" : @"编辑历史 · 会话");
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 120;
    if (!self.messageKey.length) {
        self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
        self.search.obscuresBackgroundDuringPresentation = NO;
        self.search.searchResultsUpdater = self;
        self.search.searchBar.placeholder = self.conversation.length ? @"搜索已加载的原文与编辑版本" : @"搜索会话";
        self.navigationItem.searchController = self.search; self.definesPresentationContext = YES;
    }
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:DKXSEditHistoryChangedNotification object:nil];
    [self reload];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)reload {
    NSString *account = DKXSArchiveCurrentAccountID();
    if (!account.length) { self.rows = @[]; self.filtered = @[]; [self.tableView reloadData]; return; }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSArray *rows = [DKXSEditStore.shared recordsForAccount:account conversation:self.conversation];
        if (self.messageKey.length) {
            NSMutableArray *kept = [NSMutableArray array];
            for (NSDictionary *record in rows) if ([record[@"key"] isEqual:self.messageKey]) [kept addObject:record];
            rows = kept;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.rows = rows; [self updateSearchResultsForSearchController:self.search]; [self.tableView reloadData];
        });
    });
}
- (void)updateSearchResultsForSearchController:(UISearchController *)controller {
    NSString *query = controller.searchBar.text;
    if (!query.length) { self.filtered = self.rows; }
    else {
        NSMutableArray *matched = [NSMutableArray array];
        for (NSDictionary *record in self.rows) {
            NSMutableString *haystack = [NSMutableString string];
            for (NSDictionary *version in record[@"versions"]) [haystack appendFormat:@"%@ ", version[@"text"] ?: @""];
            if ([haystack containsString:query]) [matched addObject:record];
        }
        self.filtered = matched;
    }
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.messageKey.length) return [(NSArray *)self.filtered.firstObject[@"versions"] count];
    return self.filtered.count;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DKXSEditCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"DKXSEditCell"];
    cell.textLabel.numberOfLines = 0; cell.detailTextLabel.numberOfLines = 0;
    if (self.messageKey.length) {
        NSDictionary *version = self.filtered.firstObject[@"versions"][indexPath.row];
        NSString *kind = version[@"kind"];
        if ([kind isEqualToString:@"unknown-original"]) {
            cell.textLabel.text = @"（首次收到时已经编辑，未取得原文）";
            cell.textLabel.textColor = UIColor.secondaryLabelColor;
        } else {
            cell.textLabel.text = [version[@"text"] length] ? version[@"text"] : @"（空内容）";
        }
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", [kind isEqualToString:@"original"] ? @"原文" : @"编辑版本", DKXSEditDate([version[@"at"] doubleValue])];
    } else {
        NSDictionary *record = self.filtered[indexPath.row];
        cell.textLabel.text = [NSString stringWithFormat:@"%@ · %lu 次编辑", record[@"senderName"] ?: @"对方", (unsigned long)[record[@"changes"] unsignedIntegerValue]];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"最近编辑 %@", DKXSEditDate([record[@"editedAt"] doubleValue])];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.messageKey.length) return;
    DKXSEditHistoryController *child = [DKXSEditHistoryController new];
    child.conversation = self.conversation;
    child.messageKey = self.filtered[indexPath.row][@"key"];
    [self.navigationController pushViewController:child animated:YES];
}
@end
void DKXSEditHistoryPresentedFrom(UIViewController *source, NSString *conversation, NSString *messageKey) {
    UIViewController *presenter = source ?: DKXSArchiveTopController();
    if (!presenter) return;
    DKXSEditHistoryController *controller = [DKXSEditHistoryController new];
    controller.conversation = conversation; controller.messageKey = messageKey;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:controller];
    [presenter presentViewController:nav animated:YES completion:nil];
}
