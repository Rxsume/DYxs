// 移植自 Si-yi/DYads- cbc2d5a（DYYYMessageListMetrics.h）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
#import <Foundation/Foundation.h>
@interface DKXSMessageListMetrics : NSObject
+ (NSString *)kindForNotice:(BOOL)notice pinned:(BOOL)pinned;
+ (NSDictionary *)segmentForKind:(NSString *)kind previous:(NSString *)previous next:(NSString *)next width:(double)width height:(double)height;
+ (NSDictionary *)contentTransformForX:(double)x y:(double)y width:(double)width height:(double)height rowWidth:(double)rowWidth rowHeight:(double)rowHeight;
+ (NSDictionary *)nativeFrameForRequest:(NSDictionary *)request previousNative:(NSDictionary *)native previousDisplayed:(NSDictionary *)displayed;
+ (NSDictionary *)paddingForKind:(NSString *)kind previous:(NSString *)previous next:(NSString *)next nativeHeight:(double)height;
+ (NSDictionary *)viewportForListTop:(double)listTop headerBottom:(double)headerBottom tableY:(double)y width:(double)width height:(double)height rootHeight:(double)rootHeight;
+ (NSDictionary *)noticeHeaderShiftForBackRight:(double)backRight titleLeft:(double)titleLeft selectedCenter:(double)center glassWidth:(double)glassWidth actionsLeft:(double)actionsLeft width:(double)width;
+ (BOOL)showRefreshIndicator:(BOOL)refreshing dragging:(BOOL)dragging offsetY:(double)offset insetTop:(double)inset;
@end
