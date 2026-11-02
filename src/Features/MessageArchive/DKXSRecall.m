//  DKXSRecall.m（上半：存储层 + 观测层）
//  DY778 第 1 批 staging：对应上游 DY778Recall.m 的存储与观测部分。
//  删繁说明：上游的 VM 恢复重试循环（VMRestoredState 多次尝试）本批简化为
//  “装配时挂接快照 + 发 DKXSRecallChangedNotification 触发 cell 重绘”；
//  cell 本来就会在 willDisplay 时重新绑定，重复重试的收益小于复杂度。
//  sqlite 表结构与上游一致（含 forgotten / recall_targets / profiles 与三列迁移），
//  但数据库文件与目录已改为 DYxs 名下，见 DKXSArchiveStorage。

#import "DKXSRecall.h"
#import "DKXSRecallContent.h"
#import "DKXSRecallMediaView.h"
#import "DKXSRecallNotifications.h"
#import "DKXSArchiveStorage.h"
#import "DKXSArchiveCore.h"
#import "DKXSMessageArchivePolicy.h"
#import <sqlite3.h>
#import <CommonCrypto/CommonDigest.h>
#import <objc/runtime.h>

NSNotificationName const DKXSRecallChangedNotification = @"DKXSRecallChangedNotification";
NSNotificationName const DKXSRecallDetectedNotification = @"DKXSRecallDetectedNotification";
NSString *const DKXSRecallChatItemIdentifier = @"com.dyxs.recalled-messages";

static char kDKXSMessageSnapshot, kDKXSMessageRecalled, kDKXSMessageAccount, kDKXSRecallState, kDKXSMessageGuard;
static _Thread_local DKXSRecallFrame *DKXSRecallFrames;
static _Thread_local unsigned int DKXSObservationDepth;

static NSString *DKXSRecordKey(NSString *account, NSString *conversation, NSString *identifier) {
    return [NSString stringWithFormat:@"%@|%@|%@", account ?: @"", conversation ?: @"", identifier ?: @""];
}
static BOOL DKXSContentAvailable(id content) {
    if (![content isKindOfClass:NSDictionary.class] || ![content count]) return NO;
    NSString *text = [content[@"text"] isKindOfClass:NSString.class] ? content[@"text"] : nil;
    return ![text isEqualToString:@"Recall Content Hided"];
}
static NSString *DKXSMessageAccountID(id message) {
    NSString *bound = objc_getAssociatedObject(message, &kDKXSMessageAccount);
    if (bound.length) return bound;
    Ivar rootIvar = class_getInstanceVariable(NSClassFromString(@"TIMXOModel"), "_r");
    const char *encoding = rootIvar ? ivar_getTypeEncoding(rootIvar) : NULL;
    id root = encoding && encoding[0] == '@' && [message isKindOfClass:NSClassFromString(@"TIMXOModel")] ? object_getIvar(message, rootIvar) : nil;
    NSString *account = DKXSArchiveIdentifier(DKXSArchiveRead(DKXSArchiveRead(root, @"config"), @"uid"));
    if (!account.length || [account isEqualToString:@"0"]) {
        if (root) return nil; // 有 SDK 实例却无 UID 时，绝不能继承另一个前台账号。
        account = DKXSArchiveCurrentAccountID();
    }
    if (!account.length || [account isEqualToString:@"0"]) return nil;
    return account;
}
static NSString *DKXSConversationPreferenceKey(NSString *account, NSString *conversation) {
    if (!account.length || !conversation.length) return nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[account, conversation] options:0 error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}
static BOOL DKXSRecallEnabledForAccountConversation(NSString *account, NSString *conversation) {
    if (!DKXSArchiveBool(@"DKXSRecallEnabled")) return NO;
    NSString *key = DKXSConversationPreferenceKey(account, conversation);
    if (!key) return NO;
    id disabled = [NSUserDefaults.standardUserDefaults objectForKey:@"DKXSRecallDisabledConversations"];
    return !([disabled isKindOfClass:NSDictionary.class] && [disabled[key] boolValue]);
}
BOOL DKXSRecallEnabledForConversation(NSString *conversationID) {
    return DKXSRecallEnabledForAccountConversation(DKXSArchiveCurrentAccountID(), conversationID);
}
void DKXSSetConversationRecallEnabled(NSString *conversationID, BOOL enabled) {
    NSString *key = DKXSConversationPreferenceKey(DKXSArchiveCurrentAccountID(), conversationID);
    if (!key.length) return;
    NSMutableDictionary *disabled = [[NSUserDefaults.standardUserDefaults objectForKey:@"DKXSRecallDisabledConversations"] isKindOfClass:NSDictionary.class]
        ? [[[NSUserDefaults.standardUserDefaults objectForKey:@"DKXSRecallDisabledConversations"] mutableCopy] autorelease] : [NSMutableDictionary dictionary];
    if (enabled) [disabled removeObjectForKey:key]; else disabled[key] = @YES;
    DKXSArchiveSet(@"DKXSRecallDisabledConversations", disabled);
}

// ---- 消息关联状态 ----
@interface DKXSRecallMessageState : NSObject
@property(atomic) BOOL allowed;
@property(atomic) BOOL invalidated;
@property(atomic) BOOL recalled;
@property(atomic, copy) NSDictionary *snapshot;
@property(atomic, copy) NSString *account;
@property(atomic, copy) NSString *conversation;
@property(atomic, copy) NSString *key;
@property(atomic, copy) NSString *serverID;
@property(atomic, weak) id message;
@property(atomic) NSUInteger displayRevision;
@end
@implementation DKXSRecallMessageState
@end
static DKXSRecallMessageState *DKXSRecallState(id message, BOOL create) {
    DKXSRecallMessageState *state = objc_getAssociatedObject(message, &kDKXSRecallState);
    if (!state && create && message) {
        state = [DKXSRecallMessageState new];
        objc_setAssociatedObject(message, &kDKXSRecallState, state, OBJC_ASSOCIATION_RETAIN);
    }
    return state;
}
static dispatch_queue_t DKXSRecallObservationQueue(void) {
    static dispatch_queue_t queue; static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.dyxs.message-observation", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

// ---- sqlite 存储 ----
@interface DKXSRecallStore : NSObject
@property(nonatomic) sqlite3 *database;
@property(atomic, copy) NSString *status;
+ (instancetype)shared;
- (NSDictionary *)loadRecordForKey:(NSString *)key account:(NSString *)account;
- (NSDictionary *)loadRecordForAccount:(NSString *)account conversation:(NSString *)conversation serverID:(NSString *)serverID;
- (void)saveRecord:(NSDictionary *)record;
- (NSArray<NSDictionary *> *)recordsForAccount:(NSString *)account conversation:(NSString *)conversation limit:(NSInteger)limit;
- (NSArray<NSDictionary *> *)conversationsForAccount:(NSString *)account;
- (void)removeKey:(NSString *)key account:(NSString *)account;
- (void)removeConversation:(NSString *)conversation account:(NSString *)account;
- (void)removeAllForAccount:(NSString *)account;
- (NSUInteger)countForAccount:(NSString *)account;
- (void)maintenance;
@end
@implementation DKXSRecallStore
+ (instancetype)shared { static DKXSRecallStore *store; static dispatch_once_t once; dispatch_once(&once, ^{ store = [self new]; [store open]; }); return store; }
- (void)open {
    NSURL *root = DKXSArchiveDirectory(@"Recall");
    if (!root) { self.status = @"本地记录目录不可写"; return; }
    NSString *path = [root URLByAppendingPathComponent:@"recall.sqlite"].path;
    sqlite3 *database = NULL;
    if (sqlite3_open_v2(path.UTF8String, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, NULL) != SQLITE_OK) {
        if (database) sqlite3_close(database);
        self.status = @"本地记录数据库暂不可用"; return;
    }
    sqlite3_busy_timeout(database, 1500);
    const char *schema = "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA secure_delete=ON;"
        "CREATE TABLE IF NOT EXISTS messages (key TEXT PRIMARY KEY, account TEXT NOT NULL, conversation TEXT NOT NULL,"
        "message TEXT NOT NULL, created REAL NOT NULL, seen REAL NOT NULL, recalled INTEGER NOT NULL DEFAULT 0,"
        "recalled_at REAL NOT NULL DEFAULT 0, available INTEGER NOT NULL DEFAULT 0, payload BLOB NOT NULL);"
        "CREATE INDEX IF NOT EXISTS account_recall ON messages(account,recalled,recalled_at);"
        "CREATE INDEX IF NOT EXISTS account_conversation ON messages(account,conversation,recalled);"
        "CREATE TABLE IF NOT EXISTS forgotten (key TEXT PRIMARY KEY, account TEXT NOT NULL, deleted REAL NOT NULL);"
        "CREATE TABLE IF NOT EXISTS recall_targets (account TEXT NOT NULL, conversation TEXT NOT NULL, message TEXT NOT NULL, recalled_at REAL NOT NULL, PRIMARY KEY(account,conversation,message));"
        "CREATE TABLE IF NOT EXISTS profiles (key TEXT PRIMARY KEY, account TEXT NOT NULL, conversation TEXT NOT NULL, payload BLOB NOT NULL);"
        "CREATE TRIGGER IF NOT EXISTS reject_forgotten_message BEFORE INSERT ON messages "
        "WHEN EXISTS(SELECT 1 FROM forgotten WHERE key=NEW.key) BEGIN SELECT RAISE(IGNORE); END;";
    if (sqlite3_exec(database, schema, NULL, NULL, NULL) != SQLITE_OK) {
        sqlite3_close(database); self.status = @"本地记录初始化失败"; return;
    }
    NSMutableSet *columns = [NSMutableSet set]; sqlite3_stmt *columnQuery = NULL;
    if (sqlite3_prepare_v2(database, "PRAGMA table_info(messages)", -1, &columnQuery, NULL) == SQLITE_OK)
        while (sqlite3_step(columnQuery) == SQLITE_ROW) [columns addObject:[NSString stringWithUTF8String:(const char *)sqlite3_column_text(columnQuery, 1)]];
    sqlite3_finalize(columnQuery);
    if (![columns containsObject:@"server_id"]) sqlite3_exec(database, "ALTER TABLE messages ADD COLUMN server_id TEXT NOT NULL DEFAULT ''", NULL, NULL, NULL);
    sqlite3_exec(database, "CREATE INDEX IF NOT EXISTS message_server_id ON messages(account,conversation,server_id)", NULL, NULL, NULL);
    if (![columns containsObject:@"hidden_notice"]) sqlite3_exec(database, "ALTER TABLE messages ADD COLUMN hidden_notice INTEGER NOT NULL DEFAULT 0", NULL, NULL, NULL);
    sqlite3_exec(database, "CREATE INDEX IF NOT EXISTS message_hidden ON messages(account,hidden_notice)", NULL, NULL, NULL);
    if (![columns containsObject:@"has_media"]) sqlite3_exec(database, "ALTER TABLE messages ADD COLUMN has_media INTEGER NOT NULL DEFAULT 0", NULL, NULL, NULL);
    self.database = database;
    self.status = @"本机保存 · 按账号与会话隔离";
    dispatch_async(DKXSRecallObservationQueue(), ^{ [self maintenance]; });
}
static void DKXSBindText(sqlite3_stmt *statement, int index, NSString *value) {
    sqlite3_bind_text(statement, index, (value ?: @"").UTF8String, -1, SQLITE_TRANSIENT);
}
static NSDictionary *DKXSDecodeRow(sqlite3_stmt *statement, int payloadIndex) {
    const void *bytes = sqlite3_column_blob(statement, payloadIndex); int size = sqlite3_column_bytes(statement, payloadIndex);
    if (!bytes || size <= 0) return nil;
    return DKXSArchiveDecodeJSON([NSData dataWithBytes:bytes length:(NSUInteger)size]);
}
- (NSDictionary *)loadRecordForKey:(NSString *)key account:(NSString *)account {
    sqlite3_stmt *statement = NULL; NSDictionary *record = nil;
    if (self.database && sqlite3_prepare_v2(self.database, "SELECT payload FROM messages WHERE key=? AND account=?", -1, &statement, NULL) == SQLITE_OK) {
        DKXSBindText(statement, 1, key); DKXSBindText(statement, 2, account);
        if (sqlite3_step(statement) == SQLITE_ROW) record = DKXSDecodeRow(statement, 0);
    }
    sqlite3_finalize(statement); return record;
}
- (NSDictionary *)loadRecordForAccount:(NSString *)account conversation:(NSString *)conversation serverID:(NSString *)serverID {
    if (!serverID.length || [serverID isEqualToString:@"0"]) return nil;
    sqlite3_stmt *statement = NULL; NSDictionary *record = nil;
    if (self.database && sqlite3_prepare_v2(self.database, "SELECT payload FROM messages WHERE account=? AND conversation=? AND server_id=? LIMIT 1", -1, &statement, NULL) == SQLITE_OK) {
        DKXSBindText(statement, 1, account); DKXSBindText(statement, 2, conversation); DKXSBindText(statement, 3, serverID);
        if (sqlite3_step(statement) == SQLITE_ROW) record = DKXSDecodeRow(statement, 0);
    }
    sqlite3_finalize(statement); return record;
}
- (void)saveRecord:(NSDictionary *)record {
    NSData *data = DKXSArchiveEncodeJSON(record);
    if (!self.database || !data) return;
    sqlite3_stmt *statement = NULL;
    const char *sql = "INSERT INTO messages(key,account,conversation,message,created,seen,recalled,recalled_at,available,server_id,hidden_notice,has_media,payload) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?) "
        "ON CONFLICT(key) DO UPDATE SET seen=excluded.seen,recalled=excluded.recalled,recalled_at=excluded.recalled_at,available=excluded.available,server_id=excluded.server_id,hidden_notice=excluded.hidden_notice,has_media=excluded.has_media,payload=excluded.payload";
    if (sqlite3_prepare_v2(self.database, sql, -1, &statement, NULL) != SQLITE_OK) return;
    DKXSBindText(statement, 1, record[@"key"]); DKXSBindText(statement, 2, record[@"account"]); DKXSBindText(statement, 3, record[@"conversation"]);
    DKXSBindText(statement, 4, record[@"messageID"]);
    sqlite3_bind_double(statement, 5, [record[@"created"] doubleValue]); sqlite3_bind_double(statement, 6, [record[@"seen"] doubleValue]);
    sqlite3_bind_int(statement, 7, [record[@"recalled"] boolValue]); sqlite3_bind_double(statement, 8, [record[@"recalledAt"] doubleValue]);
    sqlite3_bind_int(statement, 9, [record[@"available"] boolValue]); DKXSBindText(statement, 10, record[@"serverID"]);
    sqlite3_bind_int(statement, 11, [record[@"hiddenNotice"] boolValue]); sqlite3_bind_int(statement, 12, [record[@"hasMedia"] boolValue]);
    sqlite3_bind_blob(statement, 13, data.bytes, (int)data.length, SQLITE_TRANSIENT);
    sqlite3_step(statement); sqlite3_finalize(statement);
}
- (NSArray<NSDictionary *> *)recordsForAccount:(NSString *)account conversation:(NSString *)conversation limit:(NSInteger)limit {
    NSMutableArray *results = [NSMutableArray array];
    sqlite3_stmt *statement = NULL;
    NSString *sql = conversation.length
        ? @"SELECT payload FROM messages WHERE account=? AND conversation=? ORDER BY seen DESC LIMIT ?"
        : @"SELECT payload FROM messages WHERE account=? ORDER BY seen DESC LIMIT ?";
    if (self.database && sqlite3_prepare_v2(self.database, sql.UTF8String, -1, &statement, NULL) == SQLITE_OK) {
        DKXSBindText(statement, 1, account);
        if (conversation.length) { DKXSBindText(statement, 2, conversation); sqlite3_bind_int(statement, 3, (int)(limit > 0 ? limit : 500)); }
        else sqlite3_bind_int(statement, 2, (int)(limit > 0 ? limit : 500));
        while (sqlite3_step(statement) == SQLITE_ROW) { NSDictionary *record = DKXSDecodeRow(statement, 0); if (record) [results addObject:record]; }
    }
    sqlite3_finalize(statement); return results;
}
- (NSArray<NSDictionary *> *)conversationsForAccount:(NSString *)account {
    NSMutableArray *results = [NSMutableArray array];
    sqlite3_stmt *statement = NULL;
    if (self.database && sqlite3_prepare_v2(self.database, "SELECT conversation, COUNT(*), MAX(seen) FROM messages WHERE account=? GROUP BY conversation ORDER BY MAX(seen) DESC", -1, &statement, NULL) == SQLITE_OK) {
        DKXSBindText(statement, 1, account);
        while (sqlite3_step(statement) == SQLITE_ROW) {
            const char *conversation = (const char *)sqlite3_column_text(statement, 0);
            [results addObject:@{@"conversation": conversation ? [NSString stringWithUTF8String:conversation] : @"", @"count": @(sqlite3_column_int(statement, 1)), @"seen": @(sqlite3_column_double(statement, 2))}];
        }
    }
    sqlite3_finalize(statement); return results;
}
- (void)removeKey:(NSString *)key account:(NSString *)account {
    if (!self.database) return;
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(self.database, "DELETE FROM messages WHERE key=? AND account=?", -1, &statement, NULL) == SQLITE_OK) {
        DKXSBindText(statement, 1, key); DKXSBindText(statement, 2, account); sqlite3_step(statement);
    }
    sqlite3_finalize(statement);
    if (sqlite3_prepare_v2(self.database, "INSERT OR REPLACE INTO forgotten(key,account,deleted) VALUES(?,?,?)", -1, &statement, NULL) == SQLITE_OK) {
        DKXSBindText(statement, 1, key); DKXSBindText(statement, 2, account); sqlite3_bind_double(statement, 3, NSDate.date.timeIntervalSince1970); sqlite3_step(statement);
    }
    sqlite3_finalize(statement);
}
- (void)removeConversation:(NSString *)conversation account:(NSString *)account {
    NSArray *records = [self recordsForAccount:account conversation:conversation limit:100000];
    for (NSDictionary *record in records) [self removeKey:record[@"key"] account:account];
}
- (void)removeAllForAccount:(NSString *)account {
    NSArray *conversations = [self conversationsForAccount:account];
    for (NSDictionary *row in conversations) [self removeConversation:row[@"conversation"] account:account];
}
- (NSUInteger)countForAccount:(NSString *)account {
    sqlite3_stmt *statement = NULL; NSUInteger count = 0;
    if (self.database && sqlite3_prepare_v2(self.database, "SELECT COUNT(*) FROM messages WHERE account=?", -1, &statement, NULL) == SQLITE_OK) {
        DKXSBindText(statement, 1, account);
        if (sqlite3_step(statement) == SQLITE_ROW) count = (NSUInteger)sqlite3_column_int64(statement, 0);
    }
    sqlite3_finalize(statement); return count;
}
- (void)maintenance {
    // 0 = 不限；超过保留天数或条数上限时删最旧的（先删未撤回的普通快照，撤回记录后删）。
    if (!self.database) return;
    double days = DKXSArchiveNumber(@"DKXSRecallRetentionDays");
    if (days > 0) {
        NSTimeInterval cutoff = NSDate.date.timeIntervalSince1970 - days * 86400;
        sqlite3_stmt *statement = NULL;
        if (sqlite3_prepare_v2(self.database, "DELETE FROM messages WHERE seen < ?", -1, &statement, NULL) == SQLITE_OK) {
            sqlite3_bind_double(statement, 1, cutoff); sqlite3_step(statement);
        }
        sqlite3_finalize(statement);
    }
    double maxRecords = DKXSArchiveNumber(@"DKXSRecallMaxRecords");
    if (maxRecords > 0) {
        sqlite3_stmt *statement = NULL;
        if (sqlite3_prepare_v2(self.database, "DELETE FROM messages WHERE key NOT IN (SELECT key FROM messages ORDER BY seen DESC LIMIT ?)", -1, &statement, NULL) == SQLITE_OK) {
            sqlite3_bind_int(statement, 1, (int)maxRecords); sqlite3_step(statement);
        }
        sqlite3_finalize(statement);
    }
}
@end

// ---- 观测层 ----
NSDictionary *DKXSMessageIdentity(id message) {
    NSString *account = DKXSMessageAccountID(message);
    NSString *conversation = DKXSArchiveIdentifier(DKXSArchiveRead(message, @"belongingConversationIdentifier")) ?: DKXSArchiveIdentifier(DKXSArchiveRead(message, @"conversationID"));
    if (!account.length || !conversation.length) return nil;
    NSString *serverID = DKXSArchiveIdentifier(DKXSArchiveRead(message, @"serverMessageID"));
    NSString *identifier = serverID.length && ![serverID isEqualToString:@"0"] ? serverID : DKXSArchiveIdentifier(DKXSArchiveRead(message, @"identifier"));
    if (!identifier.length) identifier = DKXSArchiveIdentifier(DKXSArchiveRead(message, @"messageID"));
    return @{@"key": DKXSRecordKey(account, conversation, identifier), @"account": account, @"conversation": conversation,
             @"messageID": identifier, @"serverID": serverID ?: @""};
}
static BOOL DKXSIncomingMessage(id message) {
    NSString *account = DKXSMessageAccountID(message);
    NSString *sender = DKXSArchiveIdentifier(DKXSArchiveRead(message, @"sender"));
    return account.length && sender.length && ![sender isEqualToString:@"0"] && ![sender isEqualToString:account];
}
static void DKXSNotifyRecallChanged(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:DKXSRecallChangedNotification object:nil];
    });
}
static NSDictionary *DKXSBuildSnapshot(id message, NSDictionary *identity, BOOL recalled, NSTimeInterval recalledAt) {
    id content = DKXSArchiveRead(message, @"content");
    if (![content isKindOfClass:NSDictionary.class]) content = @{};
    NSDictionary *immutable = DKXSArchiveImmutableJSON(content) ?: @{};
    NSDictionary *enriched = DKXSRecallEnrichRecord(@{@"content": immutable, @"messageClass": NSStringFromClass([message class])});
    NSMutableDictionary *record = [NSMutableDictionary dictionary];
    record[@"key"] = identity[@"key"]; record[@"account"] = identity[@"account"]; record[@"conversation"] = identity[@"conversation"];
    record[@"messageID"] = identity[@"messageID"]; record[@"serverID"] = identity[@"serverID"];
    record[@"sender"] = DKXSArchiveIdentifier(DKXSArchiveRead(message, @"sender")) ?: @"";
    record[@"senderName"] = DKXSArchiveIdentifier(DKXSArchiveRead(DKXSArchiveRead(message, @"senderProfile"), @"nickname")) ?: @"";
    record[@"created"] = @(DKXSArchiveTimestamp(DKXSArchiveRead(message, @"createTime") ?: DKXSArchiveRead(message, @"timestamp")));
    record[@"seen"] = @(NSDate.date.timeIntervalSince1970);
    record[@"content"] = immutable; record[@"card"] = enriched[@"card"];
    record[@"available"] = @(DKXSContentAvailable(immutable));
    record[@"recalled"] = @(recalled); record[@"recalledAt"] = @(recalledAt);
    record[@"hiddenNotice"] = @(DKXSRecallRecordShouldHide(record));
    record[@"hasMedia"] = @([DKXSRecallPreviewCandidates(record) count] > 0);
    record[@"systemRecallNotice"] = @(DKXSRecallContentIsNotice(immutable));
    return record;
}
void DKXSObserveMessage(id message) {
    if (!message || DKXSObservationDepth > 8) return;
    NSDictionary *identity = DKXSMessageIdentity(message);
    if (!identity) return;
    DKXSRecallMessageState *state = DKXSRecallState(message, YES);
    NSString *account = identity[@"account"], *conversation = identity[@"conversation"];
    BOOL allowed = DKXSRecallEnabledForAccountConversation(account, conversation);
    state.allowed = allowed;
    state.account = account; state.conversation = conversation; state.key = identity[@"key"];
    state.serverID = identity[@"serverID"]; state.message = message;
    if (!allowed) return;
    BOOL rawRecalled = [DKXSArchiveRead(message, @"recalled") boolValue];
    id content = DKXSArchiveRead(message, @"content");
    NSDictionary *immutable = [content isKindOfClass:NSDictionary.class] ? (DKXSArchiveImmutableJSON(content) ?: @{}) : @{};
    dispatch_async(DKXSRecallObservationQueue(), ^{
        if (state.invalidated || !state.allowed) return;
        DKXSRecallStore *store = DKXSRecallStore.shared;
        NSDictionary *stored = [store loadRecordForKey:identity[@"key"] account:account];
        if (!stored && [identity[@"serverID"] length]) stored = [store loadRecordForAccount:account conversation:conversation serverID:identity[@"serverID"]];
        BOOL previousRecalled = [stored[@"recalled"] boolValue];
        BOOL previousAvailable = [stored[@"available"] boolValue];
        BOOL available = DKXSContentAvailable(immutable);
        DKXSRecallDecision decision = DKXSRecallDecide(YES, stored != nil, [stored[@"content"] isEqual:immutable], previousRecalled, rawRecalled, previousAvailable, available);
        // 只留存对方消息；自己的消息只记录撤回边（若之前已留存）。
        NSMutableDictionary *record = stored ? [stored mutableCopy] : nil;
        if (!record && DKXSIncomingMessage(message)) record = [DKXSBuildSnapshot(message, identity, rawRecalled, rawRecalled ? NSDate.date.timeIntervalSince1970 : 0) mutableCopy];
        if (!record) return;
        if (decision.persist) {
            if (DKXSIncomingMessage(message) && available) {
                NSDictionary *fresh = DKXSBuildSnapshot(message, identity, rawRecalled, [record[@"recalledAt"] doubleValue]);
                // 撤回后正文被替换为提示前，先到的原文优先：已有可用内容时不被“Recall Content Hided”覆盖。
                if (!available && previousAvailable) { fresh = record; }
                record = [fresh mutableCopy];
            }
            record[@"recalled"] = @(rawRecalled);
            if (rawRecalled && ![record[@"recalledAt"] doubleValue]) record[@"recalledAt"] = @(NSDate.date.timeIntervalSince1970);
            record[@"seen"] = @(NSDate.date.timeIntervalSince1970);
            [store saveRecord:record];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            state.recalled = rawRecalled;
            NSDictionary *old = state.snapshot;
            BOOL changed = [old[@"available"] boolValue] != [record[@"available"] boolValue] || [old[@"recalled"] boolValue] != [record[@"recalled"] boolValue] || ![old[@"content"] isEqual:record[@"content"]];
            state.snapshot = record;
            if (changed || !state.displayRevision) state.displayRevision++;
            objc_setAssociatedObject(message, &kDKXSMessageRecalled, @(rawRecalled), OBJC_ASSOCIATION_RETAIN);
            objc_setAssociatedObject(message, &kDKXSMessageSnapshot, record, OBJC_ASSOCIATION_RETAIN);
            if (decision.notify) {
                [NSNotificationCenter.defaultCenter postNotificationName:DKXSRecallDetectedNotification object:nil userInfo:@{@"record": record}];
                DKXSRecallNotifyDetected(record);
                DKXSNotifyRecallChanged();
            } else if (changed) DKXSNotifyRecallChanged();
        });
    });
}
void DKXSObserveMessageContext(id viewModel) {
    id message = DKXSArchiveRead(viewModel, @"iesMessage") ?: DKXSArchiveRead(viewModel, @"message");
    if (!message) return;
    DKXSRecallMessageState *state = DKXSRecallState(message, YES);
    NSString *conversation = DKXSArchiveIdentifier(DKXSArchiveRead(viewModel, @"conversation"));
    if (conversation.length) state.conversation = conversation;
    state.message = message;
    DKXSObserveMessage(message);
}
BOOL DKXSRecallEnabledForMessage(id message) {
    DKXSRecallMessageState *state = DKXSRecallState(message, NO);
    return state && state.allowed && DKXSArchiveBool(@"DKXSRecallEnabled");
}
id DKXSRecallContentForMessage(id message) {
    // 恢复规则：快照已撤回 + 原文可用 → 把原文还给 UI；其余一律 nil（走原生）。
    // 刻意不读 message 的 recalled：本函数会被 hooked 的 content getter 调用，
    // 而 recalled getter 同样被 hook，KVC 再读会重入；快照本身已是“撤回边已确认”的证据。
    DKXSRecallMessageState *state = DKXSRecallState(message, NO);
    NSDictionary *snapshot = state.snapshot ?: objc_getAssociatedObject(message, &kDKXSMessageSnapshot);
    if (!state.allowed || !snapshot || ![snapshot[@"recalled"] boolValue] || ![snapshot[@"available"] boolValue]) return nil;
    return snapshot[@"content"];
}
BOOL DKXSRecallRecalledDisplay(id message, BOOL original) {
    DKXSRecallMessageState *state = DKXSRecallState(message, NO);
    NSDictionary *snapshot = state.snapshot ?: objc_getAssociatedObject(message, &kDKXSMessageSnapshot);
    return DKXSRecallDisplayState(state.allowed && DKXSArchiveBool(@"DKXSRecallEnabled"), original, snapshot != nil, [snapshot[@"available"] boolValue]);
}
NSDictionary *DKXSRecallRecordForMessage(id message) {
    DKXSRecallMessageState *state = DKXSRecallState(message, NO);
    if (state.snapshot) return state.snapshot;
    NSDictionary *identity = DKXSMessageIdentity(message);
    if (!identity) return nil;
    return [DKXSRecallStore.shared loadRecordForKey:identity[@"key"] account:identity[@"account"]];
}
BOOL DKXSMessageWasRecalled(id message) {
    DKXSRecallMessageState *state = DKXSRecallState(message, NO);
    if (state) return state.recalled;
    return [objc_getAssociatedObject(message, &kDKXSMessageRecalled) boolValue];
}
BOOL DKXSRestoreRecallPresentation(id viewModel, id message) {
    if (!message) return NO;
    DKXSObserveMessageContext(viewModel);
    NSDictionary *record = DKXSRecallRecordForMessage(message);
    if (!record || ![record[@"recalled"] boolValue] || ![record[@"available"] boolValue]) return NO;
    DKXSRecallMessageState *state = DKXSRecallState(message, YES);
    state.snapshot = record; state.recalled = YES;
    objc_setAssociatedObject(message, &kDKXSMessageSnapshot, record, OBJC_ASSOCIATION_RETAIN);
    DKXSNotifyRecallChanged();
    return YES;
}
NSUInteger DKXSRecallCount(void) {
    NSString *account = DKXSArchiveCurrentAccountID();
    return account.length ? [DKXSRecallStore.shared countForAccount:account] : 0;
}
void DKXSRecallMaintenance(void) {
    dispatch_async(DKXSRecallObservationQueue(), ^{ [DKXSRecallStore.shared maintenance]; });
}
NSString *DKXSRecallStorageStatus(void) { return DKXSRecallStore.shared.status ?: @""; }
void DKXSRecallStorageStatistics(void (^completion)(NSDictionary *statistics)) {
    NSString *account = DKXSArchiveCurrentAccountID();
    dispatch_async(DKXSRecallObservationQueue(), ^{
        NSUInteger count = account.length ? [DKXSRecallStore.shared countForAccount:account] : 0;
        NSDictionary *result = @{@"count": @(count), @"status": DKXSRecallStore.shared.status ?: @"", @"directory": DKXSArchiveDirectory(@"Recall").path ?: @""};
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(result); });
    });
}
void DKXSRecallClearArchive(void) {
    NSString *account = DKXSArchiveCurrentAccountID();
    if (!account.length) return;
    dispatch_async(DKXSRecallObservationQueue(), ^{
        [DKXSRecallStore.shared removeAllForAccount:account];
        DKXSNotifyRecallChanged();
    });
}
void DKXSRecallClearConversationArchive(NSString *conversationID) {
    NSString *account = DKXSArchiveCurrentAccountID();
    if (!account.length || !conversationID.length) return;
    dispatch_async(DKXSRecallObservationQueue(), ^{
        [DKXSRecallStore.shared removeConversation:conversationID account:account];
        DKXSNotifyRecallChanged();
    });
}

// ---- 记录页（DKXSRecall.m 下半） ----
// 两个控制器：会话列表（全部会话）与消息列表（单个会话内），均带搜索与删除。
// 详情页：文字 + 媒体预览（DKXSRecallMediaView）+ 在聊天中定位（DKXSArchiveNative）+ 删除本条。

#import "DKXSArchiveNative.h"

@interface DKXSRecallDetailController : UIViewController
@property(nonatomic, copy) NSDictionary *record;
@end
@implementation DKXSRecallDetailController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.title = @"撤回记录详情";
    UITextView *textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    textView.editable = NO; textView.font = [UIFont systemFontOfSize:15];
    NSDictionary *card = self.record[@"card"];
    NSMutableString *text = [NSMutableString string];
    if ([self.record[@"senderName"] length]) [text appendFormat:@"%@\n", self.record[@"senderName"]];
    [text appendFormat:@"%@\n", DKXSRecallSummary(self.record)];
    if ([self.record[@"recalled"] boolValue]) [text appendFormat:@"\n（对方已撤回 · 原文已由本机留存）\n"];
    if ([card[@"comment"] isKindOfClass:NSDictionary.class] && [card[@"comment"][@"text"] length])
        [text appendFormat:@"\n分享评论：%@\n", card[@"comment"][@"text"]];
    textView.text = text;
    [self.view addSubview:textView];
    DKXSRecallMediaView *mediaView = [[DKXSRecallMediaView alloc] initWithFrame:CGRectMake(0, 0, 0, 0)];
    // 媒体区挂在导航栏按钮后：点“媒体”才展开，避免详情页布局与长文本冲突。
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:@"媒体" style:UIBarButtonItemStylePlain target:self action:@selector(showMedia)],
        [[UIBarButtonItem alloc] initWithTitle:@"定位" style:UIBarButtonItemStylePlain target:self action:@selector(locate)],
        [[UIBarButtonItem alloc] initWithTitle:@"删除" style:UIBarButtonItemStylePlain target:self action:@selector(deleteRecord)],
    ];
    objc_setAssociatedObject(self, @selector(showMedia), mediaView, OBJC_ASSOCIATION_RETAIN);
}
- (void)showMedia {
    DKXSRecallMediaView *mediaView = objc_getAssociatedObject(self, @selector(showMedia));
    UIViewController *holder = [UIViewController new];
    holder.title = @"媒体预览"; holder.view.backgroundColor = UIColor.systemBackgroundColor;
    mediaView.frame = holder.view.bounds; mediaView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [holder.view addSubview:mediaView];
    [mediaView configureRecord:self.record];
    [self.navigationController pushViewController:holder animated:YES];
}
- (void)locate {
    if (!DKXSArchiveCanLocate(self.record)) { DKXSArchiveToast(@"该记录缺少定位所需的会话或消息标识"); return; }
    DKXSArchiveLocateMessage((UIViewController *)self, self.record);
}
- (void)deleteRecord {
    NSString *key = self.record[@"key"], *account = self.record[@"account"];
    if (!key.length || !account.length) return;
    dispatch_async(DKXSRecallObservationQueue(), ^{
        [DKXSRecallStore.shared removeKey:key account:account];
        dispatch_async(dispatch_get_main_queue(), ^{
            DKXSArchiveToast(@"已删除本条记录");
            [self.navigationController popViewControllerAnimated:YES];
        });
    });
}
@end

@interface DKXSRecallArchiveController : UITableViewController <UISearchResultsUpdating>
@property(nonatomic, copy) NSString *conversationID;
@property(nonatomic, copy) NSArray *rows;
@property(nonatomic, copy) NSArray *filtered;
@property(nonatomic, strong) UISearchController *search;
@end
@implementation DKXSRecallArchiveController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.conversationID.length ? @"撤回记录" : @"撤回记录 · 会话";
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 72;
    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchResultsUpdater = self;
    self.search.searchBar.placeholder = self.conversationID.length ? @"搜索已留存的消息" : @"搜索会话";
    self.navigationItem.searchController = self.search; self.definesPresentationContext = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"清空" style:UIBarButtonItemStylePlain target:self action:@selector(clearAll)];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:DKXSRecallChangedNotification object:nil];
    [self reload];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)clearAll {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"清空撤回记录" message:@"删除后不可恢复，确定吗？" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) {
        if (self.conversationID.length) DKXSRecallClearConversationArchive(self.conversationID); else DKXSRecallClearArchive();
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)reload {
    NSString *account = DKXSArchiveCurrentAccountID();
    if (!account.length) { self.rows = @[]; self.filtered = @[]; [self.tableView reloadData]; return; }
    dispatch_async(DKXSRecallObservationQueue(), ^{
        NSArray *rows = self.conversationID.length
            ? [DKXSRecallStore.shared recordsForAccount:account conversation:self.conversationID limit:500]
            : [DKXSRecallStore.shared conversationsForAccount:account];
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
        for (NSDictionary *row in self.rows) {
            NSString *haystack = self.conversationID.length ? DKXSRecallSummary(row) : (row[@"conversation"] ?: @"");
            if ([haystack containsString:query]) [matched addObject:row];
        }
        self.filtered = matched;
    }
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.filtered.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DKXSRecallCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"DKXSRecallCell"];
    NSDictionary *row = self.filtered[indexPath.row];
    if (self.conversationID.length) {
        cell.textLabel.text = DKXSRecallSummary(row);
        cell.detailTextLabel.text = [row[@"recalled"] boolValue] ? @"已撤回 · 原文已留存" : @"已留存";
        cell.detailTextLabel.textColor = [row[@"recalled"] boolValue] ? UIColor.systemRedColor : UIColor.secondaryLabelColor;
    } else {
        cell.textLabel.text = [NSString stringWithFormat:@"会话 %@", row[@"conversation"]];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ 条留存", row[@"count"]];
    }
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *row = self.filtered[indexPath.row];
    if (self.conversationID.length) {
        DKXSRecallDetailController *detail = [DKXSRecallDetailController new];
        detail.record = row;
        [self.navigationController pushViewController:detail animated:YES];
    } else {
        DKXSRecallArchiveController *child = [DKXSRecallArchiveController new];
        child.conversationID = row[@"conversation"];
        [self.navigationController pushViewController:child animated:YES];
    }
}
@end

void DKXSRecallArchivePresentedFrom(UIViewController *source, NSString *conversationID) {
    UIViewController *presenter = source ?: DKXSArchiveTopController();
    if (!presenter) return;
    DKXSRecallArchiveController *controller = [DKXSRecallArchiveController new];
    controller.conversationID = conversationID;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:controller];
    [presenter presentViewController:nav animated:YES completion:nil];
}
