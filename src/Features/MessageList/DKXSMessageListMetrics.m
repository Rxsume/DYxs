// 移植自 Si-yi/DYads- cbc2d5a（DYYYMessageListMetrics.m）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
#import "DKXSMessageListMetrics.h"
#include <math.h>
@implementation DKXSMessageListMetrics
+ (NSString *)kindForNotice:(BOOL)notice pinned:(BOOL)pinned { return notice ? @"notice" : pinned ? @"pinned" : @"regular"; }
+ (NSDictionary *)paddingForKind:(NSString *)kind previous:(NSString *)previous next:(NSString *)next nativeHeight:(double)height {
    if(![@[@"notice",@"pinned",@"regular"] containsObject:kind?:@""] || !isfinite(height) || height<40 || height>200)return @{};
    BOOL first=[kind isEqual:@"notice"] || ![kind isEqual:previous];
    BOOL last=[kind isEqual:@"notice"] || ![kind isEqual:next];
    double edge=[kind isEqual:@"notice"]?6:12;
    double top=first?edge:0,bottom=last?edge:0;
    return @{@"top":@(top),@"bottom":@(bottom),@"nativeHeight":@(height),@"height":@(height+top+bottom)};
}
+ (NSDictionary *)segmentForKind:(NSString *)kind previous:(NSString *)previous next:(NSString *)next width:(double)width height:(double)height {
    if (![@[@"notice",@"pinned",@"regular"] containsObject:kind ?: @""] || !isfinite(width) || !isfinite(height) || width < 160 || height < 40) return @{};
    BOOL first = [kind isEqual:@"notice"] || ![kind isEqual:previous];
    BOOL last = [kind isEqual:@"notice"] || ![kind isEqual:next];
    double top = first ? 6 : 0, bottom = last ? 6 : 0;
    return @{@"x":@16,@"y":@(top),@"width":@(width-32),@"height":@(height-top-bottom),@"first":@(first),@"last":@(last),@"radius":@14};
}
+ (NSDictionary *)contentTransformForX:(double)x y:(double)y width:(double)width height:(double)height rowWidth:(double)rowWidth rowHeight:(double)rowHeight {
    if (!isfinite(x) || !isfinite(y) || !isfinite(width) || !isfinite(height) || !isfinite(rowWidth) || !isfinite(rowHeight) ||
        rowWidth<160 || rowHeight<40 || x<0 || y<0 || width<=0 || height<=0 || x+width>rowWidth+0.5 || y+height>rowHeight+0.5) return @{};
    // 全行内容使用同一个坐标映射，保持原生文案、火花、摘要和尾部角标的相对距离。
    double scale=0.92;
    double tx=(scale-1)*(x+width/2-rowWidth/2),ty=(scale-1)*(y+height/2-rowHeight/2);
    return @{@"scale":@(scale),@"translationX":@(tx),@"translationY":@(ty),
        @"x":@(rowWidth/2+(x-rowWidth/2)*scale),@"y":@(rowHeight/2+(y-rowHeight/2)*scale),@"width":@(width*scale),@"height":@(height*scale)};
}
+ (NSDictionary *)nativeFrameForRequest:(NSDictionary *)request previousNative:(NSDictionary *)native previousDisplayed:(NSDictionary *)displayed {
    for(NSDictionary *frame in @[request?:@{},native?:@{},displayed?:@{}]){
        for(NSString *key in @[@"x",@"y",@"width",@"height"])
            if(![frame[key] isKindOfClass:NSNumber.class] || !isfinite([frame[key] doubleValue]))return request;
        if([frame[@"width"] doubleValue]<=0 || [frame[@"height"] doubleValue]<=0)return request;
    }
    NSMutableDictionary *result=[request mutableCopy];
    NSArray *sizes=@[@"width",@"height"],*origins=@[@"x",@"y"];
    for(NSUInteger axis=0;axis<2;axis++){
        NSString *size=sizes[axis],*origin=origins[axis];
        if(fabs([request[size] doubleValue]-[displayed[size] doubleValue])<=0.5 && fabs([native[size] doubleValue]-[displayed[size] doubleValue])>0.5){
            result[size]=native[size];
            result[origin]=@([request[origin] doubleValue]-([displayed[origin] doubleValue]-[native[origin] doubleValue]));
        }
    }
    return result;
}
// 651F317D：原生表格起点106、高850，宿主956；只接管同宽竖屏的完整主列表。
+ (NSDictionary *)viewportForListTop:(double)listTop headerBottom:(double)headerBottom tableY:(double)y width:(double)width height:(double)height rootHeight:(double)rootHeight {
    for(NSNumber *value in @[@(listTop),@(headerBottom),@(y),@(width),@(height),@(rootHeight)])if(!isfinite(value.doubleValue))return @{};
    if(width<160 || rootHeight<=width || listTop<32 || listTop>180 || fabs(listTop-headerBottom)>1 || fabs(y)>1 || height<200 || fabs(listTop+height-rootHeight)>1)return @{};
    return @{@"extension":@(listTop),@"y":@(y-listTop),@"height":@(height+listTop)};
}
+ (NSDictionary *)noticeGlassForWidth:(double)width height:(double)height backRight:(double)backRight {
    if(!isfinite(width) || !isfinite(height) || !isfinite(backRight) || width<160 || height<32 || height>64 || backRight<0)return @{};
    // 两页都预留右侧原生88pt按钮和6pt外侧距，选中状态不参与布局。
    double x=MAX(8,backRight+8),right=width-94-8,h=MIN(44,height);
    if(right-x<200)return @{};
    return @{@"x":@(x),@"y":@((height-h)/2),@"width":@(right-x),@"height":@(h)};
}
+ (double)noticeTitleScaleForPointSize:(double)size {
    return isfinite(size) && size>=10 && size<=30?MIN(1,15/size):1;
}
+ (NSDictionary *)noticeDrawingShiftForFirst:(double)first firstInkWidth:(double)firstInk last:(double)last lastInkWidth:(double)lastInk glass:(NSDictionary *)glass {
    for(NSString *key in @[@"x",@"y",@"width",@"height"])if(![glass[key] isKindOfClass:NSNumber.class] || !isfinite([glass[key] doubleValue]))return @{};
    if(!isfinite(first) || !isfinite(last) || !isfinite(firstInk) || !isfinite(lastInk) || firstInk<20 || lastInk<20 || last-first<100 || last-first>180)return @{};
    double left=[glass[@"x"] doubleValue],right=left+[glass[@"width"] doubleValue];
    // 按两项实际文字/箭头的宽度预留空间；不能再假定返回玻璃右缘或固定96pt。
    for(NSNumber *padding in @[@20,@18,@16,@14,@12,@10,@8]){
        double firstWidth=ceil(firstInk+padding.doubleValue),lastWidth=ceil(lastInk+padding.doubleValue);
        if(firstWidth>116 || lastWidth>116)continue;
        double minimum=left+4+firstWidth/2-first,maximum=right-4-lastWidth/2-last;
        if(minimum>maximum)continue;
        double shift=MAX(minimum,MIN(0,maximum));
        if(fabs(shift)>24 || ![self noticeSelectionForCenter:first+shift width:firstWidth glass:glass].count || ![self noticeSelectionForCenter:last+shift width:lastWidth glass:glass].count)continue;
        return @{@"shift":@(shift),@"firstWidth":@(firstWidth),@"lastWidth":@(lastWidth)};
    }
    return @{};
}
+ (NSDictionary *)noticeSelectionForCenter:(double)center width:(double)width glass:(NSDictionary *)glass {
    for(NSString *key in @[@"x",@"y",@"width",@"height"])if(![glass[key] isKindOfClass:NSNumber.class] || !isfinite([glass[key] doubleValue]))return @{};
    double gx=[glass[@"x"] doubleValue],gw=[glass[@"width"] doubleValue],gh=[glass[@"height"] doubleValue],x=center-gx-width/2;
    if(!isfinite(center) || !isfinite(width) || width<28 || width>116 || gw<200 || gh<32 || gh>44 || x<4-1e-6 || x+width>gw-4+1e-6)return @{};
    double h=MIN(36,gh-8);
    return @{@"x":@(x),@"y":@((gh-h)/2),@"width":@(width),@"height":@(h)};
}
+ (BOOL)showRefreshIndicator:(BOOL)refreshing dragging:(BOOL)dragging offsetY:(double)offset insetTop:(double)inset {
    if(!isfinite(offset) || !isfinite(inset) || inset<0)return NO;
    return refreshing || (dragging && offset+inset< -0.5);
}
@end
