//  DKXSArchiveNative.h
//  DY778 第 1 批 staging：留存记录与原生聊天之间的桥。
//  对应上游 DY778ArchiveNative.h，改名前缀；机制保留：
//  · 定位只在当前账号、会话与消息标识三者一致时进行，找不到时静默失败（只提示）；
//  · 本地媒体只读沙盒内已存在的常规文件，路径必须落在 Home 目录下；
//  · cell 复用时清掉装饰残留（时间标签与标记是装饰层挂接的，复用必须重置）。

#import <UIKit/UIKit.h>

FOUNDATION_EXPORT BOOL DKXSArchiveCanLocate(NSDictionary *record);
FOUNDATION_EXPORT NSArray<NSDictionary *> *DKXSArchiveLocalMedia(NSDictionary *record);
FOUNDATION_EXPORT UIImage *DKXSArchivePreviewImage(NSDictionary *record);
FOUNDATION_EXPORT void DKXSArchiveLocateMessage(UIViewController *source, NSDictionary *record);
FOUNDATION_EXPORT void DKXSArchiveCellWillReuse(UITableViewCell *cell);
