// 移植自 Si-yi/DYads- 3819b4c（DYYYArticleChromeMetrics.m）：改名一律 DYYY -> DKXS，逻辑原样。
#import "DKXSArticleChromeMetrics.h"
#include <math.h>

@implementation DKXSArticleChromeMetrics

+ (BOOL)valid:(NSDictionary *)rect {
    for (NSString *key in @[ @"x", @"y", @"width", @"height" ])
        if (![rect[key] isKindOfClass:NSNumber.class] || !isfinite([rect[key] doubleValue])) return NO;
    return [rect[@"width"] doubleValue] > 0 && [rect[@"height"] doubleValue] > 0;
}
+ (NSDictionary *)rectX:(double)x y:(double)y width:(double)width height:(double)height {
    return @{ @"x":@(x), @"y":@(y), @"width":@(width), @"height":@(height) };
}
+ (BOOL)fits:(NSDictionary *)rect width:(double)width height:(double)height {
    return [self valid:rect] && [rect[@"x"] doubleValue] >= -0.5 && [rect[@"y"] doubleValue] >= -0.5 &&
        [rect[@"x"] doubleValue] + [rect[@"width"] doubleValue] <= width + 0.5 &&
        [rect[@"y"] doubleValue] + [rect[@"height"] doubleValue] <= height + 0.5;
}
+ (NSDictionary *)topForWidth:(double)width height:(double)height back:(NSDictionary *)back
                       avatar:(NSDictionary *)avatar name:(NSDictionary *)name
                       follow:(NSDictionary *)follow search:(NSDictionary *)search {
    if (!isfinite(width) || !isfinite(height) || width < 280 || height < 28 || height > 64 ||
        ![self fits:back width:width height:height] || ([self valid:avatar] && ![self fits:avatar width:width height:height]) ||
        ![self fits:search width:width height:height]) return @{};
    double bx = [back[@"x"] doubleValue] + [back[@"width"] doubleValue] / 2;
    double by = [back[@"y"] doubleValue] + [back[@"height"] doubleValue] / 2;
    double diameter = MIN(40, MIN(height + 4, 2 * (bx - 6)));
    if (diameter < MAX([back[@"width"] doubleValue], [back[@"height"] doubleValue]) + 8) return @{};
    // F020EC6B：不用把返回压成30pt去迁就头像，独立作者区向右留出10pt空隙。
    double authorShift = [self valid:avatar] ? MAX(0, bx + diameter / 2 + 10 - [avatar[@"x"] doubleValue]) : 0;
    if (authorShift > 24) return @{};
    double followShift = 0, searchShift = -4;
    double searchLeft = [search[@"x"] doubleValue] + searchShift;
    double left = searchLeft, right = left + [search[@"width"] doubleValue];
    if ([self valid:follow]) {
        if (![self fits:follow width:width height:height]) return @{};
        // 7CBC3CA2：保留4pt控件间距，将关注向搜索靠近最多12pt。
        followShift = MIN(12, MAX(0, left - 4 - [follow[@"x"] doubleValue] - [follow[@"width"] doubleValue]));
        left = MIN(left, [follow[@"x"] doubleValue] + followShift);
        right = MAX(right, [follow[@"x"] doubleValue] + [follow[@"width"] doubleValue] + followShift);
    }
    double nameRight = [avatar[@"x"] doubleValue] + [avatar[@"width"] doubleValue] + authorShift;
    if ([self valid:name]) {
        if (![self fits:name width:width height:height]) return @{};
        nameRight = MAX(nameRight, [name[@"x"] doubleValue] + [name[@"width"] doubleValue] + authorShift);
    }
    if ([self valid:follow] && nameRight + 6 > [follow[@"x"] doubleValue] + followShift) return @{};
    left = MAX(left - 8, nameRight + 6);
    right = MIN(width - 8, right + 12);
    if (right - left < 36 || left > searchLeft) return @{};
    double actionHeight = MIN(40, height + 4);
    return @{ @"authorShift":@(authorShift), @"followShift":@(followShift), @"searchShift":@(searchShift), @"back":[self rectX:bx - diameter / 2 y:by - diameter / 2 width:diameter height:diameter],
              @"actions":[self rectX:left y:by - actionHeight / 2 width:right - left height:actionHeight] };
}
+ (NSDictionary *)bottomForWidth:(double)width height:(double)height input:(NSDictionary *)input actions:(NSDictionary *)actions {
    if (!isfinite(width) || !isfinite(height) || width < 280 || height < 48 || height > 140 ||
        ![self fits:input width:width height:height] || ![self fits:actions width:width height:height]) return @{};
    double actionLeft = MAX(8, [actions[@"x"] doubleValue] - 2);
    double actionRight = MIN(width - 8, [actions[@"x"] doubleValue] + [actions[@"width"] doubleValue] + 2);
    double inputLeft = MAX(8, [input[@"x"] doubleValue]);
    double nativeRight = [input[@"x"] doubleValue] + [input[@"width"] doubleValue];
    double inputRight = MIN(nativeRight, actionLeft - 8);
    if (inputRight - inputLeft < 100 || nativeRight - inputRight > 8 || actionRight - actionLeft < 120) return @{};
    double center = [actions[@"y"] doubleValue] + [actions[@"height"] doubleValue] / 2;
    double h = 44, y = center - h / 2;
    if (y < 2 || y + h > height - 2 || [input[@"height"] doubleValue] > h || [actions[@"height"] doubleValue] > h) return @{};
    // 左右各12pt、组间16pt；440样本200x44。操作图标另以原生中心等比缩至92%。
    double equalWidth = (width - 40) / 2, equalActionLeft = 28 + equalWidth;
    if (equalWidth >= 120 && equalActionLeft <= [actions[@"x"] doubleValue] + 2 &&
        12 + equalWidth >= nativeRight - 12) {
        inputLeft = 12; inputRight = inputLeft + equalWidth;
        actionLeft = equalActionLeft; actionRight = width - 12;
    }
    return @{ @"input":[self rectX:inputLeft y:y width:inputRight - inputLeft height:h],
              @"actions":[self rectX:actionLeft y:y width:actionRight - actionLeft height:h] };
}
+ (BOOL)canRevealViewport:(NSDictionary *)viewport bottom:(NSDictionary *)bottom rootWidth:(double)width rootHeight:(double)height {
    if (!isfinite(width) || !isfinite(height) || width < 280 || height <= width ||
        ![self valid:viewport] || ![self valid:bottom]) return NO;
    // D53315FA：正文视口0/0/440/873，底栏0/873/440/83。仅放开已确认外层裁切。
    return fabs([viewport[@"x"] doubleValue]) <= 0.5 && fabs([viewport[@"y"] doubleValue]) <= 0.5 &&
        fabs([viewport[@"width"] doubleValue] - width) <= 0.5 &&
        fabs([bottom[@"x"] doubleValue]) <= 0.5 && fabs([bottom[@"width"] doubleValue] - width) <= 0.5 &&
        fabs([viewport[@"height"] doubleValue] - [bottom[@"y"] doubleValue]) <= 0.5 &&
        fabs([bottom[@"y"] doubleValue] + [bottom[@"height"] doubleValue] - height) <= 0.5 &&
        [bottom[@"height"] doubleValue] >= 48 && [bottom[@"height"] doubleValue] <= 140;
}
@end
