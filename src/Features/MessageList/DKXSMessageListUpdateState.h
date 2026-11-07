// 移植自 Si-yi/DYads- cbc2d5a（DYYYMessageListUpdateState.h）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
#import <Foundation/Foundation.h>
@interface DKXSMessageListUpdateState : NSObject
@property (nonatomic, readonly) NSUInteger depth;
@property (nonatomic, readonly) NSUInteger generation;
- (NSUInteger)beginUpdate;
- (BOOL)endUpdate:(NSUInteger)generation;
- (void)invalidate;
@end
