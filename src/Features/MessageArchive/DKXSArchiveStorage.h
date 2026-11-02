//  DKXSArchiveStorage.h
//  DY778 第 1 批 staging：档案目录与 JSON 编解码。
//  对应上游 DY778ArchiveStorage.h/.m，改动：
//  · 目录从 Application Support/DY778/ 改为 Application Support/DYxs/MessageArchive/，
//    下分 Recall / EditHistory 两个子目录，与原版 DY778 共存时互不覆盖；
//  · 删掉旧版 ChengGuang 目录迁移与独立 suite 偏好迁移（DYxs 侧不做跨应用迁移）；
//  · 目录排除 iCloud 备份，文件保护级别与上游一致。

#import <Foundation/Foundation.h>

// component 只能是 @"Recall" 或 @"EditHistory"，否则返回 nil。
FOUNDATION_EXPORT NSURL *DKXSArchiveDirectory(NSString *component);
// 把任意 JSON 兼容对象深拷贝为不可变结构（超深层嵌套截断为占位，避免 sqlite 写入崩溃）。
FOUNDATION_EXPORT id DKXSArchiveImmutableJSON(id value);
// JSON 数据 ↔ 字典（解析失败返回 nil）。
FOUNDATION_EXPORT NSDictionary *DKXSArchiveDecodeJSON(NSData *data);
FOUNDATION_EXPORT NSData *DKXSArchiveEncodeJSON(NSDictionary *dictionary);
