// 移植自 Si-yi/DYads- f07ddb5（DYYYMessageListCardView.m）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
#import "DKXSMessageListCardView.h"
#import <QuartzCore/QuartzCore.h>
@implementation DKXSMessageListCardView
+ (Class)layerClass { return CAShapeLayer.class; }
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super initWithFrame:frame])) { self.userInteractionEnabled=NO; self.accessibilityElementsHidden=YES; self.backgroundColor=UIColor.clearColor; self.opaque=NO; }
    return self;
}
- (void)setSegment:(NSDictionary *)segment {
    if ([_segment isEqual:segment]) return;
    _segment=[segment copy]; [self updateDrawing];
}
- (void)setFillColor:(UIColor *)fillColor { if([_fillColor isEqual:fillColor])return; _fillColor=fillColor; [self updateDrawing]; }
- (void)layoutSubviews { [super layoutSubviews]; [self updateDrawing]; }
- (void)traitCollectionDidChange:(UITraitCollection *)previous { [super traitCollectionDidChange:previous]; [self updateDrawing]; }
- (void)updateDrawing {
    if (!self.segment.count) return;
    CGRect rect=CGRectMake([self.segment[@"x"] doubleValue],[self.segment[@"y"] doubleValue],[self.segment[@"width"] doubleValue],[self.segment[@"height"] doubleValue]);
    UIRectCorner corners=0;
    if ([self.segment[@"first"] boolValue]) corners|=UIRectCornerTopLeft|UIRectCornerTopRight;
    if ([self.segment[@"last"] boolValue]) corners|=UIRectCornerBottomLeft|UIRectCornerBottomRight;
    CGFloat radius=[self.segment[@"radius"] doubleValue];
    CGPathRef path=[UIBezierPath bezierPathWithRoundedRect:rect byRoundingCorners:corners cornerRadii:CGSizeMake(radius,radius)].CGPath;
    CAShapeLayer *shape=(id)self.layer;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    if (!shape.path || !CGPathEqualToPath(shape.path,path)) shape.path=path;
    CGColorRef color=[self.fillColor resolvedColorWithTraitCollection:self.traitCollection].CGColor;
    if (color && (!shape.fillColor || !CGColorEqualToColor(shape.fillColor,color))) shape.fillColor=color;
    [CATransaction commit];
}
@end
