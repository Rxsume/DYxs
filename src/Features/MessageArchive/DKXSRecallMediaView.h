//  DKXSRecallMediaView.h
//  DY778 第 1 批 staging：留存记录的媒体预览。
//  对应上游 DY778RecallMediaView.h，改名前缀；行为保留：
//  · 图片直接显示（远程地址用 ephemeral 会话下载，不带 Cookie）；
//  · 视频/音频/文件点按后用 QuickLook 预览（本地文件直接预览，远程先下载到 tmp）；
//  · 封面与正片区分：封面只作占位，不当作视频播放。

#import <UIKit/UIKit.h>

@interface DKXSRecallMediaView : UIView
@property(nonatomic, copy) void (^openMedia)(NSDictionary *media);
@property(nonatomic, copy) dispatch_block_t openOriginal;
@property(nonatomic, copy) dispatch_block_t openMessage;
- (void)cancel;
- (void)configureRecord:(NSDictionary *)record;
@end

@interface DKXSRecallCoverView : UIImageView
- (void)configureRecord:(NSDictionary *)record;
- (void)cancel;
@end
