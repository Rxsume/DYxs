// 移植自 Si-yi/DYads- b97c05e（DYYYNoticeHeaderDrawingState.m）：改名一律 DYYY -> DKXS，逻辑原样。
#import "DKXSNoticeHeaderDrawingState.h"
#include <math.h>

@interface DKXSNoticeHeaderDrawingState ()
@property (nonatomic, weak) CALayer *layer;
@property (nonatomic) CATransform3D applied;
@property (nonatomic) BOOL installed;
- (BOOL)applyTransform:(CATransform3D)transform;
@end

@implementation DKXSNoticeHeaderDrawingState
- (instancetype)initWithLayer:(CALayer *)layer {
    if(!layer || !CATransform3DIsIdentity(layer.sublayerTransform))return nil;
    if((self=[super init]))_layer=layer;
    return self;
}
- (BOOL)applyShift:(CGFloat)shift {
    if(!isfinite(shift) || fabs(shift)>24){[self restore];return NO;}
    return [self applyTransform:CATransform3DMakeTranslation(shift,0,0)];
}
- (BOOL)applyScale:(CGFloat)scale {
    if(!isfinite(scale) || scale<0.5 || scale>1){[self restore];return NO;}
    return [self applyTransform:CATransform3DMakeScale(scale,scale,1)];
}
- (BOOL)applyTransform:(CATransform3D)target {
    CALayer *layer=self.layer;
    if(!layer || CGRectIsEmpty(layer.bounds)){[self restore];return NO;}
    CATransform3D current=layer.sublayerTransform;
    if(!CATransform3DIsIdentity(current) && !(self.installed && CATransform3DEqualToTransform(current,self.applied))){self.installed=NO;return NO;}
    [CATransaction begin];[CATransaction setDisableActions:YES];
    if(!CATransform3DEqualToTransform(current,target))layer.sublayerTransform=target;
    self.applied=target;self.installed=YES;
    [CATransaction commit];return self.active;
}
+ (BOOL)pinBackgroundLayer:(CALayer *)background inLayer:(CALayer *)host reorder:(void (^)(void))reorder {
    if(!background || !host || background.superlayer!=host)return NO;
    if(reorder)reorder();
    if(background.superlayer!=host)return NO;
    CGFloat floor=0;
    for(CALayer *layer in host.sublayers)if(layer!=background){if(!isfinite(layer.zPosition))return NO;floor=MIN(floor,layer.zPosition);}
    CGFloat position=floor-1;if(!isfinite(position) || !(position<floor))return NO;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    if(background.zPosition!=position)background.zPosition=position;
    [CATransaction commit];return background.zPosition<floor;
}
- (BOOL)active {return self.layer && self.installed && CATransform3DEqualToTransform(self.layer.sublayerTransform,self.applied);}
- (void)restore {
    if(self.active){[CATransaction begin];[CATransaction setDisableActions:YES];self.layer.sublayerTransform=CATransform3DIdentity;[CATransaction commit];}
    self.installed=NO;
}
@end
