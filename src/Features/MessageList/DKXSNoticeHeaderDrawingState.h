// 移植自 Si-yi/DYads- b97c05e（DYYYNoticeHeaderDrawingState.h）：改名一律 DYYY -> DKXS，逻辑原样。
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

// 只调整子层绘制；原生 frame/bounds/position 和 UIKit 布局保持原样。
@interface DKXSNoticeHeaderDrawingState : NSObject
- (instancetype)initWithLayer:(CALayer *)layer;
- (BOOL)applyShift:(CGFloat)shift;
- (BOOL)applyScale:(CGFloat)scale;
+ (BOOL)pinBackgroundLayer:(CALayer *)background inLayer:(CALayer *)host reorder:(void (^)(void))reorder;
- (void)restore;
@property (nonatomic, readonly) BOOL active;
@end
