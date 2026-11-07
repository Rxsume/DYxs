// 移植自 Si-yi/DYads- f07ddb5（DYYYRecallMarkerMetrics.h）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
#import <Foundation/Foundation.h>

@interface DKXSRecallMarkerMetrics : NSObject
/// 输入均为Cell.contentView内实际可见矩形；不改变原生行高，找不到空位时隐藏提示。
+ (NSDictionary *)layoutForWidth:(double)width height:(double)height bubble:(NSDictionary *)bubble
                      occupied:(NSArray<NSDictionary *> *)occupied idealWidth:(double)idealWidth;
@end
