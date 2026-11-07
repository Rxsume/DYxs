// 移植自 Si-yi/DYads- cbc2d5a（DYYYMessageListClipState.h）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
// 遮罩先生成完整尺寸与路径，再挂载；拒绝空几何，失败时恢复原生裁切。
@interface DKXSMessageListClipState : NSObject
- (instancetype)initWithLayer:(CALayer *)layer;
- (BOOL)applyExtension:(CGFloat)extension;
- (void)restore;
@property (nonatomic, readonly) BOOL active;
@end
