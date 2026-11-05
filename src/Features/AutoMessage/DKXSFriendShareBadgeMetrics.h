// 移植自 Si-yi/DYads- 5e9a5c0（DYYYFriendShareBadgeMetrics.h）：改名一律 DYYY -> DKXS。
#import <Foundation/Foundation.h>

@interface DKXSFriendShareBadgeMetrics : NSObject
/// 使用交互层同一坐标系的实际可见标签矩形，分享提示不占用原生标签位置。
+ (double)topForCaptionTop:(double)captionTop badgeX:(double)x width:(double)width height:(double)height
           occupiedFrames:(NSArray<NSDictionary<NSString *, NSNumber *> *> *)frames;
@end
