// 移植自 Si-yi/DYads- 3819b4c（DYYYContentTopDrawingState.m）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
#import "DKXSContentTopDrawingState.h"
#import <math.h>

@interface DKXSContentTopDrawingState ()
@property (nonatomic, strong) NSMapTable<CALayer *, NSDictionary *> *moves;
@end
@implementation DKXSContentTopDrawingState
- (instancetype)init {
    if ((self = [super init])) _moves = [NSMapTable weakToStrongObjectsMapTable];
    return self;
}
+ (NSValue *)value:(CGAffineTransform)transform {
    return [NSValue valueWithBytes:&transform objCType:@encode(CGAffineTransform)];
}
+ (CGAffineTransform)transform:(NSValue *)value {
    CGAffineTransform transform = CGAffineTransformIdentity;
    if (value) [value getValue:&transform size:sizeof(transform)];
    return transform;
}
- (CGAffineTransform)nativeTransform:(CALayer *)layer {
    if (!layer) return CGAffineTransformIdentity;
    NSDictionary *record = [self.moves objectForKey:layer];
    CGAffineTransform current = layer.affineTransform;
    return record && CGAffineTransformEqualToTransform(current, [[self class] transform:record[@"applied"]]) ? [[self class] transform:record[@"base"]] : current;
}
- (void)applyShift:(CGFloat)shift scale:(CGFloat)scale toLayer:(CALayer *)layer {
    if (!layer || !isfinite(shift) || !isfinite(scale) || scale <= 0) return;
    CGAffineTransform base = [self nativeTransform:layer];
    CGAffineTransform applied = CGAffineTransformScale(base, scale, scale); applied.tx += shift;
    [self.moves setObject:@{ @"base":[[self class] value:base], @"applied":[[self class] value:applied] } forKey:layer];
    if (!CGAffineTransformEqualToTransform(layer.affineTransform, applied)) {
        [CATransaction begin]; [CATransaction setDisableActions:YES];
        layer.affineTransform = applied; [CATransaction commit];
    }
}
- (void)restoreLayer:(CALayer *)layer {
    if (!layer) return;
    NSDictionary *record = [self.moves objectForKey:layer];
    if (!record) return;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    if (CGAffineTransformEqualToTransform(layer.affineTransform, [[self class] transform:record[@"applied"]]))
        layer.affineTransform = [[self class] transform:record[@"base"]];
    [CATransaction commit]; [self.moves removeObjectForKey:layer];
}
- (void)restore {
    for (CALayer *layer in self.moves.keyEnumerator.allObjects) [self restoreLayer:layer];
}
@end
