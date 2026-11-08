// 移植自 Si-yi/DYads- b97c05e（DYYYContentViewportMetrics.h）：改名一律 DYYY -> DKXS，逻辑原样。
#import <Foundation/Foundation.h>

@interface DKXSContentViewportMetrics : NSObject
+ (NSDictionary *)doubleColumn:(NSDictionary *)native width:(double)width height:(double)height top:(BOOL)top bottom:(BOOL)bottom;
@end
