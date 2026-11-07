// 移植自 Si-yi/DYads- cbc2d5a（DYYYMessageListUpdateState.m）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
#import "DKXSMessageListUpdateState.h"
@implementation DKXSMessageListUpdateState
- (NSUInteger)beginUpdate { _depth++; return _generation; }
- (BOOL)endUpdate:(NSUInteger)generation {
    if(generation!=_generation || !_depth)return NO;
    _depth--;return _depth==0;
}
- (void)invalidate { _generation++;_depth=0; }
@end
