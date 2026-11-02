//  DKXSEditContent.h
//  DY778 第 1 批 staging：编辑元数据快照。
//  对应上游 DY778EditContent.h/.m（上游头文件只有前置声明，实现在 .m 内），
//  本批把快照函数显式导出，供 hooks 与编辑存储共用。
//  字段名保持上游原样（isEdited / content_is_edited / editTime / content_edit_time /
//  editCount / content_edit_count / editUid / content_editor），因为 40.8.0 的
//  editInfo 结构未知，读取时多路兼容，不改名。

#import <Foundation/Foundation.h>

// editInfo 原始对象 → {edited, editTime(秒), editCount, editor}；info 为空返回 nil。
FOUNDATION_EXPORT NSDictionary *DKXSEditInfoSnapshot(id info);
