//  DKXSEditContent.m
//  DY778 第 1 批 staging：见头文件注释。

#import "DKXSEditContent.h"
#import "DKXSArchiveCore.h"

NSDictionary *DKXSEditInfoSnapshot(id info) {
    if (!info) return nil;
    return @{@"edited": @([DKXSArchiveRead(info, @"isEdited") boolValue] || [DKXSArchiveRead(info, @"content_is_edited") boolValue]),
        @"editTime": @(DKXSArchiveTimestamp(DKXSArchiveRead(info, @"editTime") ?: DKXSArchiveRead(info, @"content_edit_time"))),
        @"editCount": DKXSArchiveRead(info, @"editCount") ?: DKXSArchiveRead(info, @"content_edit_count") ?: @0,
        @"editor": DKXSArchiveIdentifier(DKXSArchiveRead(info, @"editUid") ?: DKXSArchiveRead(info, @"content_editor")) ?: @""};
}
