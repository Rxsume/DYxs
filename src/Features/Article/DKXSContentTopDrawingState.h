// 移植自 Si-yi/DYads- 3819b4c（DYYYContentTopDrawingState.h）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

/// 保存原生绘制变换，重复布局只基于原值；不写bounds/position或滚动几何。
@interface DKXSContentTopDrawingState : NSObject
- (CGAffineTransform)nativeTransform:(CALayer *)layer;
- (void)applyShift:(CGFloat)shift scale:(CGFloat)scale toLayer:(CALayer *)layer;
- (void)restoreLayer:(CALayer *)layer;
- (void)restore;
@end
