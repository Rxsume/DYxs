#import "DY778Backup.h"
#import "DY778Core.h"
#import "DY778MiscPolicy.h"
#import <CommonCrypto/CommonDigest.h>
#import <sqlite3.h>
#import <zlib.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// DY778 1.0-8 模块 4：备份恢复（规格 §3）。
// 手写 ZIP（stored + deflate 读）、manifest 校验、偏好黑名单过滤、
// sqlite 快照与合并、operation.plist 两阶段恢复。见 DY778Backup.h
// 头注的 DYxs 侧偏离。

static NSString *const DY778BackupErrorDomain = @"DY778.Backup.Policy";
static NSString *const DY778BackupPreferencesDomain = @"com.dy778.douyin";
static NSString *const DY778BackupJokerDomain = @"com.dy778.joker";

NSURL *DY778BackupDirectoryURL(void) {
    NSArray<NSURL *> *dirs = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
    return [dirs.firstObject URLByAppendingPathComponent:[NSString stringWithUTF8String:DY778BackupDirectoryName] isDirectory:YES];
}

NSDictionary *DY778BackupStatus(void) {
    NSURL *url = [[DY778BackupDirectoryURL() URLByAppendingPathComponent:@"status.plist" isDirectory:NO] standardizedURL];
    NSDictionary *status = [NSDictionary dictionaryWithContentsOfURL:url];
    return status ?: @{};
}

BOOL DY778BackupPreferenceAllowed(NSString *key) {
    if (!key.length) return NO;
    NSString *lower = key.lowercaseString;
    if ([lower hasPrefix:[NSString stringWithUTF8String:DY778BackupBlockedPrefix]]) return NO;
    for (size_t i = 0; i < DY778BackupBlockedSubstringCount; i++) {
        if ([lower containsString:[NSString stringWithUTF8String:DY778BackupBlockedSubstrings[i]]]) return NO;
    }
    return YES;
}

NSDictionary *DY778BackupFilteredPreferences(void) {
    NSDictionary *domain = [[NSUserDefaults standardUserDefaults] persistentDomainForName:DY778BackupPreferencesDomain] ?: @{};
    NSMutableDictionary *filtered = [NSMutableDictionary dictionary];
    for (NSString *key in domain) {
        if (!DY778BackupPreferenceAllowed(key)) continue;
        if ([key isEqualToString:@"joker"]) continue;
        filtered[key] = domain[key];
    }
    return filtered;
}

NSDictionary *DY778BackupJokerPreferences(void) {
    NSDictionary *domain = [[NSUserDefaults standardUserDefaults] persistentDomainForName:DY778BackupJokerDomain] ?: @{};
    NSMutableDictionary *joker = [NSMutableDictionary dictionary];
    for (size_t i = 0; i < DY778BackupJokerKeyCount; i++) {
        NSString *key = [NSString stringWithUTF8String:DY778BackupJokerKeys[i]];
        if (domain[key]) joker[key] = domain[key];
    }
    return joker;
}

NSString *DY778BackupDigest(NSData *data) {
    if (!data) return @"";
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (size_t i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", hash[i]];
    return hex;
}

BOOL DY778BackupEntryAllowed(NSString *relativePath) {
    if (!relativePath.length) return NO;
    // 防路径穿越（规格 §3.3）：拒绝 ..、\、: 与控制字符。
    if ([relativePath containsString:@".."] || [relativePath containsString:@"\\"] || [relativePath containsString:@":"]) return NO;
    for (NSUInteger i = 0; i < relativePath.length; i++) {
        if ([relativePath characterAtIndex:i] < 0x20) return NO;
    }
    for (size_t i = 0; i < DY778BackupAllowedEntryCount; i++) {
        NSString *allowed = [NSString stringWithUTF8String:DY778BackupAllowedEntries[i]];
        if ([allowed hasSuffix:@"/"]) {
            if ([relativePath hasPrefix:allowed]) return YES;
        } else if ([relativePath isEqualToString:allowed]) return YES;
    }
    NSString *radar = [NSString stringWithUTF8String:DY778BackupRadarAccountPrefix];
    if ([relativePath hasPrefix:radar] && [relativePath.pathExtension isEqualToString:@"json"]) return YES;
    return NO;
}

static BOOL DY778BackupAccountIDValid(NSString *accountID) {
    if (!accountID.length) return NO;
    // 纯数字校验（规格 §3.3，_DY778BackupAccountID）；首字符 '0' 的
    // 特殊处理未全拆——DYxs 侧仍接受，校验信息里注明。
    NSCharacterSet *digits = NSCharacterSet.decimalDigitCharacterSet;
    for (NSUInteger i = 0; i < accountID.length; i++) {
        if (![digits characterIsMember:[accountID characterAtIndex:i]]) return NO;
    }
    return YES;
}

BOOL DY778BackupValidatePreferences(NSDictionary *preferences, NSError **error) {
    if (![preferences isKindOfClass:NSDictionary.class]) {
        if (error) *error = [NSError errorWithDomain:DY778BackupErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"偏好不是字典"}];
        return NO;
    }
    for (NSString *key in preferences) {
        if (!DY778BackupPreferenceAllowed(key)) {
            if (error) *error = [NSError errorWithDomain:DY778BackupErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"偏好键 %@ 在黑名单内", key]}];
            return NO;
        }
    }
    return YES;
}

BOOL DY778BackupValidateManifest(NSDictionary *manifest, NSError **error) {
    if (![manifest isKindOfClass:NSDictionary.class]) {
        if (error) *error = [NSError errorWithDomain:DY778BackupErrorDomain code:10 userInfo:@{NSLocalizedDescriptionKey: @"manifest 不是字典"}];
        return NO;
    }
    NSString *version = manifest[@"version"], *schema = manifest[@"schema"];
    if (![version isEqualToString:[NSString stringWithUTF8String:DY778BackupManifestVersion]] ||
        ![schema isEqualToString:[NSString stringWithUTF8String:DY778BackupManifestSchema]]) {
        if (error) *error = [NSError errorWithDomain:DY778BackupErrorDomain code:11 userInfo:@{NSLocalizedDescriptionKey: @"manifest 的 version/schema 不匹配"}];
        return NO;
    }
    NSArray *accounts = manifest[@"accounts"];
    if ([accounts isKindOfClass:NSArray.class]) {
        for (id account in accounts) {
            if (!DY778BackupAccountIDValid(DY778Identifier(account))) {
                if (error) *error = [NSError errorWithDomain:DY778BackupErrorDomain code:12 userInfo:@{NSLocalizedDescriptionKey: @"manifest 的 accounts 含非法账号 ID"}];
                return NO;
            }
        }
    }
    NSArray *files = manifest[@"files"];
    if (![files isKindOfClass:NSArray.class]) {
        if (error) *error = [NSError errorWithDomain:DY778BackupErrorDomain code:13 userInfo:@{NSLocalizedDescriptionKey: @"manifest 缺 files 列表"}];
        return NO;
    }
    for (id entry in files) {
        if (![entry isKindOfClass:NSDictionary.class]) {
            if (error) *error = [NSError errorWithDomain:DY778BackupErrorDomain code:14 userInfo:@{NSLocalizedDescriptionKey: @"manifest 的 files 条目不是字典"}];
            return NO;
        }
        NSString *name = entry[@"name"] ?: entry[@"path"];
        if (![name isKindOfClass:NSString.class] || !DY778BackupEntryAllowed(name)) {
            if (error) *error = [NSError errorWithDomain:DY778BackupErrorDomain code:15 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"manifest 条目 %@ 不在白名单内", name ?: @"?"]}];
            return NO;
        }
        if (![entry[@"size"] respondsToSelector:@selector(unsignedLongLongValue)] || ![entry[@"sha256"] isKindOfClass:NSString.class]) {
            if (error) *error = [NSError errorWithDomain:DY778BackupErrorDomain code:16 userInfo:@{NSLocalizedDescriptionKey: @"manifest 条目缺 size/sha256"}];
            return NO;
        }
    }
    id preferences = manifest[@"preferences"];
    if (preferences && !DY778BackupValidatePreferences(preferences, error)) return NO;
    return YES;
}

// ---------- 手写 ZIP ----------
// 写：stored（method 0），条目按名排序，CRC32 用 zlib crc32。
// 读：method 0 直接取，method 8 用 inflate 解压（zlib 1.2.11）。

static void DY778BackupZipAppendU16(NSMutableData *data, uint16_t value) {
    uint8_t bytes[2] = {value & 0xff, (value >> 8) & 0xff};
    [data appendBytes:bytes length:2];
}
static void DY778BackupZipAppendU32(NSMutableData *data, uint32_t value) {
    uint8_t bytes[4] = {value & 0xff, (value >> 8) & 0xff, (value >> 16) & 0xff, (value >> 24) & 0xff};
    [data appendBytes:bytes length:4];
}

static NSData *DY778BackupZipWrite(NSDictionary<NSString *, NSData *> *entries, NSError **error) {
    NSArray<NSString *> *names = [[entries allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableData *zip = [NSMutableData data];
    NSMutableArray<NSDictionary *> *central = [NSMutableArray array];
    for (NSString *name in names) {
        NSData *content = entries[name];
        uLong crc = crc32(0L, Z_NULL, 0);
        crc = crc32(crc, content.bytes, (uInt)content.length);
        // MS-DOS 时间：用当前时间（UTC+8 的本地时间）。
        NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
        calendar.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
        NSDateComponents *parts = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond fromDate:NSDate.date];
        uint16_t dosTime = (uint16_t)(((parts.hour & 0x1f) << 11) | ((parts.minute & 0x3f) << 5) | ((parts.second / 2) & 0x1f));
        uint16_t dosDate = (uint16_t)((((parts.year - 1980) & 0x7f) << 9) | ((parts.month & 0xf) << 5) | (parts.day & 0x1f));
        NSData *nameBytes = [name dataUsingEncoding:NSUTF8StringEncoding];
        uint32_t offset = (uint32_t)zip.length;
        [zip appendBytes:"PK\x03\x04" length:4];
        DY778BackupZipAppendU16(zip, 20);      // version needed
        DY778BackupZipAppendU16(zip, 0x0800);  // flags: UTF-8
        DY778BackupZipAppendU16(zip, 0);       // method: stored
        DY778BackupZipAppendU16(zip, dosTime);
        DY778BackupZipAppendU16(zip, dosDate);
        DY778BackupZipAppendU32(zip, (uint32_t)crc);
        DY778BackupZipAppendU32(zip, (uint32_t)content.length);
        DY778BackupZipAppendU32(zip, (uint32_t)content.length);
        DY778BackupZipAppendU16(zip, (uint16_t)nameBytes.length);
        DY778BackupZipAppendU16(zip, 0);
        [zip appendData:nameBytes];
        [zip appendData:content];
        [central addObject:@{@"name": name, @"crc": @(crc), @"size": @(content.length),
                             @"time": @(dosTime), @"date": @(dosDate), @"offset": @(offset)}];
    }
    uint32_t centralOffset = (uint32_t)zip.length;
    for (NSDictionary *entry in central) {
        NSData *nameBytes = [entry[@"name"] dataUsingEncoding:NSUTF8StringEncoding];
        [zip appendBytes:"PK\x01\x02" length:4];
        DY778BackupZipAppendU16(zip, 20);      // version made by
        DY778BackupZipAppendU16(zip, 20);      // version needed
        DY778BackupZipAppendU16(zip, 0x0800);
        DY778BackupZipAppendU16(zip, 0);
        DY778BackupZipAppendU16(zip, [entry[@"time"] unsignedShortValue]);
        DY778BackupZipAppendU16(zip, [entry[@"date"] unsignedShortValue]);
        DY778BackupZipAppendU32(zip, [entry[@"crc"] unsignedIntValue]);
        DY778BackupZipAppendU32(zip, [entry[@"size"] unsignedIntValue]);
        DY778BackupZipAppendU32(zip, [entry[@"size"] unsignedIntValue]);
        DY778BackupZipAppendU16(zip, (uint16_t)nameBytes.length);
        DY778BackupZipAppendU16(zip, 0);
        DY778BackupZipAppendU16(zip, 0);
        DY778BackupZipAppendU16(zip, 0);
        DY778BackupZipAppendU16(zip, 0);
        DY778BackupZipAppendU32(zip, 0);
        DY778BackupZipAppendU32(zip, [entry[@"offset"] unsignedIntValue]);
        [zip appendData:nameBytes];
    }
    uint32_t centralSize = (uint32_t)zip.length - centralOffset;
    [zip appendBytes:"PK\x05\x06" length:4];
    DY778BackupZipAppendU16(zip, 0);
    DY778BackupZipAppendU16(zip, 0);
    DY778BackupZipAppendU16(zip, (uint16_t)central.count);
    DY778BackupZipAppendU16(zip, (uint16_t)central.count);
    DY778BackupZipAppendU32(zip, centralSize);
    DY778BackupZipAppendU32(zip, centralOffset);
    DY778BackupZipAppendU16(zip, 0);
    if (error) *error = nil;
    return zip;
}

static uint16_t DY778BackupZipReadU16(const uint8_t *bytes, NSUInteger offset) {
    return (uint16_t)(bytes[offset] | (bytes[offset + 1] << 8));
}
static uint32_t DY778BackupZipReadU32(const uint8_t *bytes, NSUInteger offset) {
    return (uint32_t)(bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24));
}

static NSDictionary<NSString *, NSData *> *DY778BackupZipRead(NSData *zipData, NSError **error) {
    const uint8_t *bytes = zipData.bytes;
    NSUInteger length = zipData.length;
    NSMutableDictionary *entries = [NSMutableDictionary dictionary];
    NSUInteger offset = 0;
    while (offset + 30 <= length && memcmp(bytes + offset, "PK\x03\x04", 4) == 0) {
        uint16_t method = DY778BackupZipReadU16(bytes, offset + 8);
        uint32_t crc = DY778BackupZipReadU32(bytes, offset + 14);
        uint32_t compressedSize = DY778BackupZipReadU32(bytes, offset + 18);
        uint32_t size = DY778BackupZipReadU32(bytes, offset + 22);
        uint16_t nameLength = DY778BackupZipReadU16(bytes, offset + 26);
        uint16_t extraLength = DY778BackupZipReadU16(bytes, offset + 28);
        NSUInteger headerEnd = offset + 30 + nameLength + extraLength;
        if (headerEnd + compressedSize > length) {
            if (error) *error = [NSError errorWithDomain:DY778BackupErrorDomain code:20 userInfo:@{NSLocalizedDescriptionKey: @"zip 条目越界"}];
            return nil;
        }
        NSString *name = [[NSString alloc] initWithBytes:bytes + offset + 30 length:nameLength encoding:NSUTF8StringEncoding];
        NSData *content = nil;
        if (method == 0) {
            content = [NSData dataWithBytes:bytes + headerEnd length:compressedSize];
        } else if (method == 8) {
            NSMutableData *inflated = [NSMutableData dataWithLength:size];
            z_stream stream; memset(&stream, 0, sizeof(stream));
            stream.next_in = (Bytef *)(bytes + headerEnd);
            stream.avail_in = compressedSize;
            stream.next_out = inflated.mutableBytes;
            stream.avail_out = (uInt)size;
            if (inflateInit2(&stream, -MAX_WBITS) != Z_OK) {
                if (error) *error = [NSError errorWithDomain:DY778BackupErrorDomain code:21 userInfo:@{NSLocalizedDescriptionKey: @"zip inflate 初始化失败"}];
                return nil;
            }
            int result = inflate(&stream, Z_FINISH);
            inflateEnd(&stream);
            if (result != Z_STREAM_END && result != Z_OK) {
                if (error) *error = [NSError errorWithDomain:DY778BackupErrorDomain code:22 userInfo:@{NSLocalizedDescriptionKey: @"zip inflate 解压失败"}];
                return nil;
            }
            content = inflated;
        } else {
            if (error) *error = [NSError errorWithDomain:DY778BackupErrorDomain code:23 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"zip 不支持的压缩方法 %u", method]}];
            return nil;
        }
        uLong actual = crc32(0L, Z_NULL, 0);
        actual = crc32(actual, content.bytes, (uInt)content.length);
        if (actual != crc || content.length != size) {
            if (error) *error = [NSError errorWithDomain:DY778BackupErrorDomain code:24 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"zip 条目 %@ 校验失败", name]}];
            return nil;
        }
        if (name.length) entries[name] = content;
        offset = headerEnd + compressedSize;
    }
    if (entries.count == 0 && error) {
        *error = [NSError errorWithDomain:DY778BackupErrorDomain code:25 userInfo:@{NSLocalizedDescriptionKey: @"zip 内无有效条目"}];
        return nil;
    }
    return entries;
}

// ---------- 数据库快照与合并（规格 §3.5） ----------
// 快照：sqlite3_backup_init/step/finish + PRAGMA trusted_schema=OFF。
// 合并：BEGIN IMMEDIATE / COMMIT / ROLLBACK；CREATE TABLE；
// INSERT OR REPLACE 逐行合并（原版为 INSERT INTO ... VALUES，
// DYxs 侧用 OR REPLACE 避免主键冲突导致整事务回滚，语义仍是合并）。
// 涉及的表（只作备份/恢复用）：messages、forgotten、recall_targets、
// profiles、edits。恢复会一并影响模块外的 Recall/编辑历史/Radar。

static BOOL DY778BackupDatabaseSnapshot(NSString *sourcePath, NSString *destinationPath, NSError **error) {
    sqlite3 *source = NULL, *destination = NULL;
    if (sqlite3_open_v2(sourcePath.UTF8String, &source, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) {
        if (error) *error = [NSError errorWithDomain:DY778BackupErrorDomain code:30 userInfo:@{NSLocalizedDescriptionKey: @"打不开源数据库"}];
        if (source) sqlite3_close(source);
        return NO;
    }
    if (sqlite3_open(destinationPath.UTF8String, &destination) != SQLITE_OK) {
        if (error) *error = [NSError errorWithDomain:DY778BackupErrorDomain code:31 userInfo:@{NSLocalizedDescriptionKey: @"打不开目标数据库"}];
        sqlite3_close(source);
        if (destination) sqlite3_close(destination);
        return NO;
    }
    sqlite3_exec(source, "PRAGMA trusted_schema=OFF", NULL, NULL, NULL);
    sqlite3_backup *backup = sqlite3_backup_init(destination, "main", source, "main");
    BOOL ok = backup != NULL;
    if (ok) {
        while (sqlite3_backup_step(backup, -1) == SQLITE_OK) { sqlite3_sleep(10); }
        ok = sqlite3_backup_finish(backup) == SQLITE_OK;
    }
    sqlite3_close(source);
    sqlite3_close(destination);
    if (!ok && error) *error = [NSError errorWithDomain:DY778BackupErrorDomain code:32 userInfo:@{NSLocalizedDescriptionKey: @"数据库快照失败"}];
    return ok;
}

static BOOL DY778BackupDatabaseQuickCheck(NSString *path) {
    sqlite3 *db = NULL;
    if (sqlite3_open_v2(path.UTF8String, &db, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) { if (db) sqlite3_close(db); return NO; }
    sqlite3_stmt *stmt = NULL;
    BOOL ok = NO;
    if (sqlite3_prepare_v2(db, "PRAGMA quick_check(1)", -1, &stmt, NULL) == SQLITE_OK) {
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            const unsigned char *text = sqlite3_column_text(stmt, 0);
            ok = text && strcmp((const char *)text, "ok") == 0;
        }
        sqlite3_finalize(stmt);
    }
    sqlite3_close(db);
    return ok;
}

static BOOL DY778BackupDatabaseMerge(NSString *sourcePath, NSString *destinationPath, NSError **error) {
    sqlite3 *source = NULL, *destination = NULL;
    if (sqlite3_open_v2(sourcePath.UTF8String, &source, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK ||
        sqlite3_open(destinationPath.UTF8String, &destination) != SQLITE_OK) {
        if (error) *error = [NSError errorWithDomain:DY778BackupErrorDomain code:33 userInfo:@{NSLocalizedDescriptionKey: @"打不开要合并的数据库"}];
        if (source) sqlite3_close(source);
        if (destination) sqlite3_close(destination);
        return NO;
    }
    sqlite3_exec(destination, "PRAGMA trusted_schema=OFF", NULL, NULL, NULL);
    char *message = NULL;
    BOOL ok = sqlite3_exec(destination, "BEGIN IMMEDIATE", NULL, NULL, &message) == SQLITE_OK;
    if (ok) {
        // 列出源库的表与视图，逐表合并。
        sqlite3_stmt *list = NULL;
        if (sqlite3_prepare_v2(source, "SELECT name, sql FROM sqlite_master WHERE type IN ('table','view')", -1, &list, NULL) == SQLITE_OK) {
            while (sqlite3_step(list) == SQLITE_ROW) {
                const char *table = (const char *)sqlite3_column_text(list, 0);
                const char *sql = (const char *)sqlite3_column_text(list, 1);
                if (!table || !sql) continue;
                if (strncmp(table, "sqlite_", 7) == 0) continue;
                // 表结构以源库为准：按原 sql 建表（不存在时）。
                NSString *originalCreate = [NSString stringWithUTF8String:sql];
                NSString *guarded = [originalCreate stringByReplacingOccurrencesOfString:@"CREATE TABLE" withString:@"CREATE TABLE IF NOT EXISTS"];
                if (sqlite3_exec(destination, guarded.UTF8String, NULL, NULL, &message) != SQLITE_OK) { ok = NO; break; }
                // 读源表列名。
                NSString *pragma = [NSString stringWithFormat:@"PRAGMA table_info(\"%s\")", table];
                sqlite3_stmt *columns = NULL;
                NSMutableArray<NSString *> *names = [NSMutableArray array];
                if (sqlite3_prepare_v2(source, pragma.UTF8String, -1, &columns, NULL) == SQLITE_OK) {
                    while (sqlite3_step(columns) == SQLITE_ROW) {
                        const unsigned char *name = sqlite3_column_text(columns, 1);
                        if (name) [names addObject:[NSString stringWithUTF8String:(const char *)name]];
                    }
                    sqlite3_finalize(columns);
                }
                if (names.count == 0) continue;
                NSString *columnList = [names componentsJoinedByString:@", "];
                NSString *selectSQL = [NSString stringWithFormat:@"SELECT %@ FROM \"%s\"", columnList, table];
                sqlite3_stmt *read = NULL;
                if (sqlite3_prepare_v2(source, selectSQL.UTF8String, -1, &read, NULL) != SQLITE_OK) { ok = NO; break; }
                NSMutableString *placeholders = [NSMutableString string];
                for (NSUInteger i = 0; i < names.count; i++) [placeholders appendString:i ? @", ?" : @"?"];
                NSString *insertSQL = [NSString stringWithFormat:@"INSERT OR REPLACE INTO \"%s\" (%@) VALUES (%@)", table, columnList, placeholders];
                sqlite3_stmt *insert = NULL;
                if (sqlite3_prepare_v2(destination, insertSQL.UTF8String, -1, &insert, NULL) != SQLITE_OK) { sqlite3_finalize(read); ok = NO; break; }
                while (sqlite3_step(read) == SQLITE_ROW) {
                    for (int i = 0; i < (int)names.count; i++) {
                        int type = sqlite3_column_type(read, i);
                        if (type == SQLITE_INTEGER) sqlite3_bind_int64(insert, i + 1, sqlite3_column_int64(read, i));
                        else if (type == SQLITE_FLOAT) sqlite3_bind_double(insert, i + 1, sqlite3_column_double(read, i));
                        else if (type == SQLITE_BLOB) sqlite3_bind_blob(insert, i + 1, sqlite3_column_blob(read, i), sqlite3_column_bytes(read, i), SQLITE_TRANSIENT);
                        else if (type == SQLITE_NULL) sqlite3_bind_null(insert, i + 1);
                        else { const unsigned char *text = sqlite3_column_text(read, i); sqlite3_bind_text(insert, i + 1, (const char *)text, -1, SQLITE_TRANSIENT); }
                    }
                    if (sqlite3_step(insert) != SQLITE_DONE) { ok = NO; }
                    sqlite3_reset(insert);
                    sqlite3_clear_bindings(insert);
                    if (!ok) break;
                }
                sqlite3_finalize(read);
                sqlite3_finalize(insert);
                if (!ok) break;
            }
            sqlite3_finalize(list);
        }
    }
    if (ok) ok = sqlite3_exec(destination, "COMMIT", NULL, NULL, &message) == SQLITE_OK;
    if (!ok) sqlite3_exec(destination, "ROLLBACK", NULL, NULL, NULL);
    sqlite3_close(source);
    sqlite3_close(destination);
    if (!ok && error) *error = [NSError errorWithDomain:DY778BackupErrorDomain code:34 userInfo:@{NSLocalizedDescriptionKey: @"数据库合并失败，已回滚"}];
    return ok;
}

// ---------- 偏好合并（规格 §3.4） ----------
// 合并不是覆盖：mutableCopy + addEntriesFromDictionary。
// listClear.followExcluded./followUncertain. 前缀键做并集合并；
// snapshot/workCache/spark.settings/displayStats.accounts 保留备份值。
static NSDictionary *DY778BackupMergePreferences(NSDictionary *current, NSDictionary *incoming) {
    NSMutableDictionary *merged = [current mutableCopy] ?: [NSMutableDictionary dictionary];
    for (NSString *key in incoming) {
        id value = incoming[key];
        if (([key hasPrefix:@"listClear.followExcluded."] || [key hasPrefix:@"listClear.followUncertain."]) &&
            [merged[key] isKindOfClass:NSArray.class] && [value isKindOfClass:NSArray.class]) {
            NSMutableOrderedSet *unionSet = [NSMutableOrderedSet orderedSetWithArray:merged[key]];
            [unionSet addObjectsFromArray:value];
            merged[key] = unionSet.array;
        } else {
            merged[key] = value;
        }
    }
    return merged;
}

// ---------- stores 文件收集 ----------
// Recall/编辑历史/Radar 已从 DYxs 删除，stores 文件通常不存在；
// 只打包实际存在的文件，缺失不报错。
static NSDictionary<NSString *, NSData *> *DY778BackupCollectStoresFiles(void) {
    NSFileManager *manager = NSFileManager.defaultManager;
    NSMutableDictionary *collected = [NSMutableDictionary dictionary];
    NSArray<NSURL *> *roots = @[
        [[manager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"DY778" isDirectory:YES],
        [[manager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"DY778" isDirectory:YES]];
    NSArray<NSString *> *candidates = @[
        @"stores/DY778/Recall/messages.sqlite", @"stores/DY778/Recall/messages.sqlite-wal", @"stores/DY778/Recall/messages.sqlite-shm",
        @"stores/DY778/EditHistory/history.sqlite", @"stores/DY778/EditHistory/history.sqlite-wal", @"stores/DY778/EditHistory/history.sqlite-shm"];
    for (NSURL *root in roots) {
        for (NSString *relative in candidates) {
            NSURL *url = [root URLByAppendingPathComponent:relative];
            if (![manager fileExistsAtPath:url.path]) continue;
            if ([relative hasSuffix:@".sqlite"]) {
                // sqlite 主文件走 sqlite3_backup 快照，避免直接拷走
                // 写了一半的库；-wal / -shm 直接拷。
                NSString *temp = [NSTemporaryDirectory() stringByAppendingPathComponent:[relative.lastPathComponent stringByAppendingString:@".snapshot"]];
                NSError *snapshotError = nil;
                if (DY778BackupDatabaseSnapshot(url.path, temp, &snapshotError)) {
                    NSData *data = [NSData dataWithContentsOfFile:temp];
                    if (data) collected[relative] = data;
                    [manager removeItemAtPath:temp error:nil];
                    continue;
                }
            }
            NSData *data = [NSData dataWithContentsOfURL:url];
            if (data) collected[relative] = data;
        }
        NSURL *radarDir = [root URLByAppendingPathComponent:@"stores/DY778Radar"];
        NSArray<NSURL *> *radarFiles = [manager contentsOfDirectoryAtURL:radarDir includingPropertiesForKeys:nil options:0 error:nil];
        for (NSURL *file in radarFiles) {
            if (![file.lastPathComponent hasPrefix:@"account-"] || ![file.pathExtension isEqualToString:@"json"]) continue;
            NSData *data = [NSData dataWithContentsOfURL:file];
            if (data) collected[[@"stores/DY778Radar/" stringByAppendingString:file.lastPathComponent]] = data;
        }
    }
    return collected;
}

static NSString *DY778BackupTimestamp(void) {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    formatter.dateFormat = @"yyyyMMdd_HHmmss_SSS";
    return [formatter stringFromDate:NSDate.date];
}

static BOOL DY778BackupWriteStatus(NSDictionary *status) {
    NSURL *dir = DY778BackupDirectoryURL();
    [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *url = [dir URLByAppendingPathComponent:@"status.plist"];
    return [status writeToURL:url error:nil];
}

// ---------- 导出 / 导入 / 清除 / 两阶段恢复 ----------

void DY778BackupExport(UIViewController *presenter) {
    NSMutableDictionary<NSString *, NSData *> *entries = [NSMutableDictionary dictionary];
    NSDictionary *preferences = DY778BackupFilteredPreferences();
    NSDictionary *joker = DY778BackupJokerPreferences();
    NSError *error = nil;
    NSData *preferencesData = [NSPropertyListSerialization dataWithPropertyList:preferences format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
    NSData *jokerData = [NSPropertyListSerialization dataWithPropertyList:joker format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
    if (preferencesData) entries[[NSString stringWithUTF8String:DY778BackupPreferencesFile]] = preferencesData;
    if (jokerData) entries[[NSString stringWithUTF8String:DY778BackupJokerFile]] = jokerData;
    [entries addEntriesFromDictionary:DY778BackupCollectStoresFiles()];
    // manifest：version/schema/format/created/accounts/files[]（size+sha256）。
    NSMutableArray *files = [NSMutableArray array];
    for (NSString *name in [entries.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSData *data = entries[name];
        [files addObject:@{@"name": name, @"size": @(data.length), @"sha256": DY778BackupDigest(data)}];
    }
    NSString *account = DY778CurrentAccountID();
    NSDictionary *manifest = @{
        @"version": [NSString stringWithUTF8String:DY778BackupManifestVersion],
        @"schema": [NSString stringWithUTF8String:DY778BackupManifestSchema],
        @"format": @"zip",
        @"created": DY778BackupTimestamp(),
        @"accounts": account.length ? @[account] : @[],
        @"files": files};
    NSData *manifestData = [NSJSONSerialization dataWithJSONObject:manifest options:0 error:&error];
    if (manifestData) entries[[NSString stringWithUTF8String:DY778BackupManifestFile]] = manifestData;
    NSData *zip = DY778BackupZipWrite(entries, &error);
    if (!zip) { DY778Toast(@"备份导出失败"); return; }
    NSURL *dir = DY778BackupDirectoryURL();
    [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *fileName = [NSString stringWithFormat:@"%@%@.zip", [NSString stringWithUTF8String:DY778BackupFilePrefix], DY778BackupTimestamp()];
    NSURL *fileURL = [dir URLByAppendingPathComponent:fileName];
    if (![zip writeToURL:fileURL options:NSDataWritingAtomic error:&error]) { DY778Toast(@"备份导出失败"); return; }
    DY778BackupWriteStatus(@{@"lastExport": fileName, @"files": @(files.count), @"updated": DY778BackupTimestamp()});
    DY778BackupPicker *picker = [[DY778BackupPicker alloc] initForExportWithURL:fileURL];
    picker.source = fileName;
    [presenter presentViewController:[picker documentPickerForExport] animated:YES completion:nil];
    DY778Toast(@"备份已生成，请选择保存位置");
}

static BOOL DY778BackupApplyExtracted(NSURL *extractedDir, NSError **error) {
    NSFileManager *manager = NSFileManager.defaultManager;
    NSURL *manifestURL = [extractedDir URLByAppendingPathComponent:[NSString stringWithUTF8String:DY778BackupManifestFile]];
    NSData *manifestData = [NSData dataWithContentsOfURL:manifestURL];
    NSDictionary *manifest = manifestData ? [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:nil] : nil;
    if (!DY778BackupValidateManifest(manifest, error)) return NO;
    // 逐条核对 size + sha256。
    for (NSDictionary *entry in manifest[@"files"]) {
        NSString *name = entry[@"name"];
        NSURL *url = [extractedDir URLByAppendingPathComponent:name];
        NSData *data = [NSData dataWithContentsOfURL:url];
        if (!data || data.length != [entry[@"size"] unsignedLongLongValue] || ![DY778BackupDigest(data) isEqualToString:entry[@"sha256"]]) {
            if (error) *error = [NSError errorWithDomain:DY778BackupErrorDomain code:40 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"备份条目 %@ 校验失败", name]}];
            return NO;
        }
    }
    // 偏好合并：setPersistentDomain + synchronize。
    NSURL *preferencesURL = [extractedDir URLByAppendingPathComponent:[NSString stringWithUTF8String:DY778BackupPreferencesFile]];
    NSData *preferencesData = [NSData dataWithContentsOfURL:preferencesURL];
    if (preferencesData) {
        NSDictionary *incoming = [NSPropertyListSerialization propertyListWithData:preferencesData options:NSPropertyListImmutable format:NULL error:nil];
        if ([incoming isKindOfClass:NSDictionary.class] && DY778BackupValidatePreferences(incoming, error)) {
            NSDictionary *current = [[NSUserDefaults standardUserDefaults] persistentDomainForName:DY778BackupPreferencesDomain] ?: @{};
            NSDictionary *merged = DY778BackupMergePreferences(current, incoming);
            [[NSUserDefaults standardUserDefaults] setPersistentDomain:merged forName:DY778BackupPreferencesDomain];
        }
    }
    NSURL *jokerURL = [extractedDir URLByAppendingPathComponent:[NSString stringWithUTF8String:DY778BackupJokerFile]];
    NSData *jokerData = [NSData dataWithContentsOfURL:jokerURL];
    if (jokerData) {
        NSDictionary *incoming = [NSPropertyListSerialization propertyListWithData:jokerData options:NSPropertyListImmutable format:NULL error:nil];
        if ([incoming isKindOfClass:NSDictionary.class]) {
            NSDictionary *current = [[NSUserDefaults standardUserDefaults] persistentDomainForName:DY778BackupJokerDomain] ?: @{};
            NSDictionary *merged = DY778BackupMergePreferences(current, incoming);
            [[NSUserDefaults standardUserDefaults] setPersistentDomain:merged forName:DY778BackupJokerDomain];
        }
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
    // 数据库合并：Recall/EditHistory 的 sqlite 逐表合并（BEGIN IMMEDIATE）。
    // 目标路径与导出源一致；目标不存在时直接复制快照。
    NSArray<NSString *> *dbPairs = @[
        @"stores/DY778/Recall/messages.sqlite", @"stores/DY778/EditHistory/history.sqlite"];
    for (NSString *relative in dbPairs) {
        NSURL *sourceURL = [extractedDir URLByAppendingPathComponent:relative];
        if (![manager fileExistsAtPath:sourceURL.path]) continue;
        if (!DY778BackupDatabaseQuickCheck(sourceURL.path)) {
            if (error) *error = [NSError errorWithDomain:DY778BackupErrorDomain code:41 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"备份数据库 %@ 未通过 quick_check", relative]}];
            return NO;
        }
        NSURL *documentsRoot = [manager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        NSURL *targetURL = [[documentsRoot URLByAppendingPathComponent:@"DY778"] URLByAppendingPathComponent:relative];
        [manager createDirectoryAtURL:targetURL.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        if ([manager fileExistsAtPath:targetURL.path]) {
            if (!DY778BackupDatabaseMerge(sourceURL.path, targetURL.path, error)) return NO;
        } else {
            NSError *copyError = nil;
            if (![manager copyItemAtURL:sourceURL toURL:targetURL error:&copyError]) {
                if (error) *error = copyError;
                return NO;
            }
        }
        // -wal / -shm 一并处理。
        for (NSString *suffix in @[@"-wal", @"-shm"]) {
            NSURL *sideSource = [NSURL URLWithString:[sourceURL.absoluteString stringByAppendingString:suffix]];
            NSURL *sideTarget = [NSURL URLWithString:[targetURL.absoluteString stringByAppendingString:suffix]];
            if ([manager fileExistsAtPath:sideSource.path]) {
                [manager removeItemAtURL:sideTarget error:nil];
                [manager copyItemAtURL:sideSource toURL:sideTarget error:nil];
            }
        }
    }
    // Radar account-*.json 直接复制。
    NSURL *radarDir = [extractedDir URLByAppendingPathComponent:@"stores/DY778Radar"];
    NSArray<NSURL *> *radarFiles = [manager contentsOfDirectoryAtURL:radarDir includingPropertiesForKeys:nil options:0 error:nil];
    for (NSURL *file in radarFiles ?: @[]) {
        if (![file.lastPathComponent hasPrefix:@"account-"] || ![file.pathExtension isEqualToString:@"json"]) continue;
        NSURL *documentsRoot = [manager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        NSURL *target = [[[documentsRoot URLByAppendingPathComponent:@"DY778"] URLByAppendingPathComponent:@"stores/DY778Radar"] URLByAppendingPathComponent:file.lastPathComponent];
        [manager createDirectoryAtURL:target.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        [manager removeItemAtURL:target error:nil];
        [manager copyItemAtURL:file toURL:target error:nil];
    }
    return YES;
}

BOOL DY778BackupApplyPending(NSError **error) {
    NSURL *dir = DY778BackupDirectoryURL();
    NSURL *operationURL = [dir URLByAppendingPathComponent:@"operation.plist"];
    NSDictionary *operation = [NSDictionary dictionaryWithContentsOfURL:operationURL];
    if (!operation) {
        if (error) *error = [NSError errorWithDomain:DY778BackupErrorDomain code:50 userInfo:@{NSLocalizedDescriptionKey: @"没有待处理的备份操作"}];
        return NO;
    }
    NSString *action = operation[@"action"], *phase = operation[@"phase"];
    if (![phase isEqualToString:[NSString stringWithUTF8String:DY778BackupPhaseReady]]) {
        if (error) *error = [NSError errorWithDomain:DY778BackupErrorDomain code:51 userInfo:@{NSLocalizedDescriptionKey: @"备份操作不在 ready 阶段"}];
        return NO;
    }
    NSFileManager *manager = NSFileManager.defaultManager;
    // 失败可回滚到 previous-pending：先把当前 operation 拷一份。
    NSURL *previousURL = [dir URLByAppendingPathComponent:@"previous-pending"];
    [manager removeItemAtURL:previousURL error:nil];
    [manager copyItemAtURL:operationURL toURL:previousURL error:nil];
    BOOL ok = NO;
    if ([action isEqualToString:[NSString stringWithUTF8String:DY778BackupActionRestore]]) {
        NSURL *extractedDir = [dir URLByAppendingPathComponent:@"extracted"];
        // NSFileCoordinator + 安全作用域资源（规格 §3.4）。
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        __block BOOL coordinated = NO;
        __block NSError *coordinatedError = nil;
        [coordinator coordinateReadingItemAtURL:extractedDir options:0 error:&coordinatedError byAccessor:^(NSURL *url) {
            coordinated = DY778BackupApplyExtracted(url, &coordinatedError);
        }];
        if (coordinatedError && error) *error = coordinatedError;
        ok = coordinated;
    } else if ([action isEqualToString:[NSString stringWithUTF8String:DY778BackupActionClear]]) {
        NSError *removeError = nil;
        for (NSString *name in @[@"backup.zip", @"status.plist"]) {
            [manager removeItemAtURL:[dir URLByAppendingPathComponent:name] error:nil];
        }
        ok = removeError == nil;
        if (!ok && error) *error = removeError;
    } else {
        if (error) *error = [NSError errorWithDomain:DY778BackupErrorDomain code:52 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"未知的备份操作 %@", action]}];
        return NO;
    }
    if (ok) {
        NSMutableDictionary *committed = [operation mutableCopy];
        committed[@"phase"] = [NSString stringWithUTF8String:DY778BackupPhaseCommitted];
        [committed writeToURL:operationURL atomically:YES];
        DY778BackupWriteStatus(@{@"lastRestore": DY778BackupTimestamp(), @"action": action ?: @""});
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:DY778PreferencesChangedNotification object:nil];
        });
        DY778Toast(@"备份恢复完成");
    } else {
        // 回滚到 previous-pending。
        [manager removeItemAtURL:operationURL error:nil];
        [manager copyItemAtURL:previousURL toURL:operationURL error:nil];
        DY778Toast(@"备份恢复失败，已回滚");
    }
    return ok;
}

void DY778BackupImport(UIViewController *presenter) {
    DY778BackupPicker *picker = [[DY778BackupPicker alloc] initForImportWithPresenter:presenter];
    picker.importing = YES;
    UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeZIP] asCopy:YES];
    documentPicker.delegate = picker;
    documentPicker.allowsMultipleSelection = NO;
    // picker 对象需在导入完成前存活：挂在 presenter 的关联对象上。
    static char DY778BackupPickerKey;
    objc_setAssociatedObject(presenter, &DY778BackupPickerKey, picker, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [presenter presentViewController:documentPicker animated:YES completion:nil];
}

void DY778BackupClear(void) {
    // _DY778BackupClear 仅 0x30 字节，推测为写 pending clear 动作
    // （规格 §3.1，未完全解析）。DYxs 侧：写 operation.plist
    // （action=clear，phase=ready），再由 ApplyPending 执行。
    NSURL *dir = DY778BackupDirectoryURL();
    [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSDictionary *operation = @{@"pending": @YES, @"action": [NSString stringWithUTF8String:DY778BackupActionClear],
                                @"phase": [NSString stringWithUTF8String:DY778BackupPhaseReady],
                                @"journal": @[], @"info.plist": @{}};
    [operation writeToURL:[dir URLByAppendingPathComponent:@"operation.plist"] atomically:YES];
    NSError *error = nil;
    if (DY778BackupApplyPending(&error)) DY778Toast(@"备份已清除");
    else DY778Toast([NSString stringWithFormat:@"清除备份失败：%@", error.localizedDescription]);
}

id DY778BackupTakeCompletion(void) {
    // _DY778BackupTakeCompletion 仅 0x10 字节（4 条指令），推测返回
    // 完成标记/块，未解析（规格 §3.1）。DYxs 侧返回已提交的操作记录，
    // 无则 nil。
    NSDictionary *operation = [NSDictionary dictionaryWithContentsOfURL:
        [DY778BackupDirectoryURL() URLByAppendingPathComponent:@"operation.plist"]];
    if ([operation[@"phase"] isEqualToString:[NSString stringWithUTF8String:DY778BackupPhaseCommitted]]) return operation;
    return nil;
}

// ---------- DY778BackupPicker ----------

@interface DY778BackupPicker ()
@property(nonatomic, strong) NSURL *exportURL;
@property(nonatomic, weak) UIViewController *presenter;
@end

@implementation DY778BackupPicker

- (instancetype)initForExportWithURL:(NSURL *)url {
    if ((self = [super init])) { _exportURL = url; }
    return self;
}
- (instancetype)initForImportWithPresenter:(UIViewController *)presenter {
    if ((self = [super init])) { _presenter = presenter; }
    return self;
}
- (UIDocumentPickerViewController *)documentPickerForExport {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForExportingURLs:@[self.exportURL] asCopy:YES];
    picker.delegate = self;
    return picker;
}
- (void)finish {
    DY778Toast(self.importing ? @"备份导入完成" : @"备份导出完成");
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    (void)controller;
    DY778Toast(@"已取消");
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    NSURL *url = urls.firstObject;
    if (!url) return;
    if (!self.importing) { [self finish]; return; }
    BOOL accessing = [url startAccessingSecurityScopedResource];
    NSData *zipData = [NSData dataWithContentsOfURL:url];
    if (accessing) [url stopAccessingSecurityScopedResource];
    if (!zipData) { DY778Toast(@"读不到备份文件"); return; }
    NSError *error = nil;
    NSDictionary<NSString *, NSData *> *entries = DY778BackupZipRead(zipData, &error);
    if (!entries) { DY778Toast([NSString stringWithFormat:@"备份文件无效：%@", error.localizedDescription]); return; }
    NSData *manifestData = entries[[NSString stringWithUTF8String:DY778BackupManifestFile]];
    NSDictionary *manifest = manifestData ? [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:nil] : nil;
    if (!DY778BackupValidateManifest(manifest, &error)) {
        DY778Toast([NSString stringWithFormat:@"备份校验失败：%@", error.localizedDescription]);
        return;
    }
    // 解到 extracted，写 operation.plist（phase=ready），再 ApplyPending。
    NSURL *dir = DY778BackupDirectoryURL();
    NSFileManager *manager = NSFileManager.defaultManager;
    [manager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *extractedDir = [dir URLByAppendingPathComponent:@"extracted"];
    [manager removeItemAtURL:extractedDir error:nil];
    [manager createDirectoryAtURL:extractedDir withIntermediateDirectories:YES attributes:nil error:nil];
    for (NSString *name in entries) {
        if (!DY778BackupEntryAllowed(name)) continue;
        NSURL *target = [extractedDir URLByAppendingPathComponent:name];
        [manager createDirectoryAtURL:target.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        [entries[name] writeToURL:target options:NSDataWritingAtomic error:nil];
    }
    NSURL *backupZipURL = [dir URLByAppendingPathComponent:@"backup.zip"];
    [manager removeItemAtURL:backupZipURL error:nil];
    [zipData writeToURL:backupZipURL options:NSDataWritingAtomic error:nil];
    NSDictionary *operation = @{@"pending": @YES, @"action": [NSString stringWithUTF8String:DY778BackupActionRestore],
                                @"phase": [NSString stringWithUTF8String:DY778BackupPhaseReady],
                                @"journal": @[], @"info.plist": @{}};
    [operation writeToURL:[dir URLByAppendingPathComponent:@"operation.plist"] atomically:YES];
    if (DY778BackupApplyPending(&error)) [self finish];
    else DY778Toast([NSString stringWithFormat:@"备份恢复失败：%@", error.localizedDescription]);
}

@end
