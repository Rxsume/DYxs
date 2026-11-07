// 移植自 Si-yi/DYads- cbc2d5a（DYYYMessageListClipState.m）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
#import "DKXSMessageListClipState.h"
#import <math.h>
@interface DKXSMessageListClipState ()
@property (nonatomic, weak) CALayer *layer;
@property (nonatomic, strong) CAShapeLayer *mask;
@property (nonatomic) BOOL nativeClipping;
@end
@implementation DKXSMessageListClipState
- (instancetype)initWithLayer:(CALayer *)layer {
    if(!layer || layer.mask || !layer.masksToBounds)return nil;
    if((self=[super init])){_layer=layer;_nativeClipping=layer.masksToBounds;_mask=[CAShapeLayer layer];CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();CGFloat components[]={0,0,0,1};CGColorRef color=CGColorCreate(space,components);_mask.fillColor=color;CGColorRelease(color);CGColorSpaceRelease(space);}
    return self;
}
- (BOOL)applyExtension:(CGFloat)extension {
    CALayer *layer=self.layer;CGRect bounds=layer.bounds;
    if(!layer || (layer.mask && layer.mask!=self.mask) || !isfinite(extension) || extension<=0 || extension>180 || !isfinite(bounds.origin.x) || !isfinite(bounds.origin.y) || !isfinite(bounds.size.width) || !isfinite(bounds.size.height) || bounds.size.width<=0 || bounds.size.height<=0){[self restore];return NO;}
    CGRect frame=CGRectMake(bounds.origin.x,bounds.origin.y-extension,bounds.size.width,bounds.size.height+extension);
    CGPathRef path=CGPathCreateWithRect(CGRectMake(0,0,frame.size.width,frame.size.height),NULL);
    [CATransaction begin];[CATransaction setDisableActions:YES];
    @try {
        if(!CGRectEqualToRect(self.mask.frame,frame))self.mask.frame=frame;
        if(!self.mask.path || !CGPathEqualToPath(self.mask.path,path))self.mask.path=path;
        // 不能把尚未设置 bounds/path 的空遮罩提前交给原生容器。
        if(layer.mask!=self.mask)layer.mask=self.mask;
        if(layer.masksToBounds)layer.masksToBounds=NO;
    } @catch(NSException *exception){[self restore];} @finally {CGPathRelease(path);[CATransaction commit];}
    return self.active;
}
- (BOOL)active {
    return self.layer && self.layer.mask==self.mask && !self.layer.masksToBounds && !CGRectIsEmpty(self.mask.bounds) && self.mask.path && !CGPathIsEmpty(self.mask.path);
}
- (void)restore {
    CALayer *layer=self.layer;if(layer.mask!=self.mask)return;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    layer.mask=nil;layer.masksToBounds=self.nativeClipping;[CATransaction commit];
}
@end
