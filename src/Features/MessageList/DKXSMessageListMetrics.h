// 移植自 Si-yi/DYads- f07ddb5（DYYYMessageListMetrics.h）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
#import <Foundation/Foundation.h>
@interface DKXSMessageListMetrics : NSObject
+ (NSString *)kindForNotice:(BOOL)notice pinned:(BOOL)pinned;
+ (NSDictionary *)segmentForKind:(NSString *)kind previous:(NSString *)previous next:(NSString *)next width:(double)width height:(double)height;
+ (NSDictionary *)contentPlacementForX:(double)x width:(double)width rowWidth:(double)rowWidth trailing:(BOOL)trailing nativeRightLimit:(double)rightLimit;
@end
