// 移植自 Si-yi/DYads- b97c05e（DYYYContentViewportMetrics.m）：改名一律 DYYY -> DKXS，逻辑原样。
#import "DKXSContentViewportMetrics.h"
#import <math.h>

@implementation DKXSContentViewportMetrics
+ (NSDictionary *)doubleColumn:(NSDictionary *)native width:(double)width height:(double)height top:(BOOL)top bottom:(BOOL)bottom {
    if (!isfinite(width) || !isfinite(height) || width < 280 || height <= width) return @{};
    for (NSString *key in @[ @"x", @"y", @"width", @"height" ])
        if (![native[key] isKindOfClass:NSNumber.class] || !isfinite([native[key] doubleValue])) return @{};
    double x = [native[@"x"] doubleValue], y = [native[@"y"] doubleValue];
    double w = [native[@"width"] doubleValue], h = [native[@"height"] doubleValue];
    double end = y + h, bottomGap = height - end;
    // 145812F1：原生{0,106,440,778}，上方106、下方72；仅接入同宽竖屏原生槽。
    if (fabs(x) > 0.5 || fabs(w - width) > 0.5 || y < 0 || y > 180 || h < height * 0.5 ||
        bottomGap < -0.5 || bottomGap > 140) return @{};
    double newY = top ? 0 : y;
    return @{ @"x":@(x), @"y":@(newY), @"width":@(w), @"height":@((bottom ? height : end) - newY) };
}
@end
