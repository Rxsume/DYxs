//  DKXSArchiveStorage.m
//  DY778 第 1 批 staging：见头文件注释。

#import "DKXSArchiveStorage.h"

NSURL *DKXSArchiveDirectory(NSString *component) {
    if (![@[@"Recall", @"EditHistory"] containsObject:component]) return nil;
    NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    if (!support) return nil;
    NSDictionary *protection = @{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication};
    NSURL *root = [[support URLByAppendingPathComponent:@"DYxs" isDirectory:YES] URLByAppendingPathComponent:@"MessageArchive" isDirectory:YES];
    NSURL *target = [root URLByAppendingPathComponent:component isDirectory:YES];
    NSError *error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtURL:target withIntermediateDirectories:YES attributes:protection error:&error]) return nil;
    [target setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
    return target;
}

static id DKXSArchiveJSONValue(id value, NSUInteger depth) {
    if (!value || value == NSNull.null) return NSNull.null;
    if (depth > 32) return @{@"_unavailable": @"Nesting exceeds 32 levels"};
    if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) return value;
    if ([value isKindOfClass:NSDate.class]) return @([(NSDate *)value timeIntervalSince1970]);
    if ([value isKindOfClass:NSURL.class]) return [value absoluteString] ?: @"";
    if ([value isKindOfClass:NSData.class]) return @{@"_encoding": @"base64", @"data": [value base64EncodedStringWithOptions:0]};
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray *result = [NSMutableArray array];
        for (id item in value) [result addObject:DKXSArchiveJSONValue(item, depth + 1)];
        return result;
    }
    if ([value isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        for (id key in value) {
            NSString *name = [key isKindOfClass:NSString.class] ? key : [key description];
            if (name) result[name] = DKXSArchiveJSONValue(value[key], depth + 1);
        }
        return result;
    }
    return @{@"_class": NSStringFromClass([value class]), @"_description": [value description] ?: @""};
}
id DKXSArchiveImmutableJSON(id value) {
    if (![value isKindOfClass:NSDictionary.class]) return nil;
    @try { return [DKXSArchiveJSONValue(value, 0) copy]; } @catch (__unused NSException *e) { return nil; }
}
NSDictionary *DKXSArchiveDecodeJSON(NSData *data) {
    if (!data.length) return nil;
    id result = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [result isKindOfClass:NSDictionary.class] ? result : nil;
}
NSData *DKXSArchiveEncodeJSON(NSDictionary *dictionary) {
    if (!dictionary || ![NSJSONSerialization isValidJSONObject:dictionary]) return nil;
    return [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:nil];
}
