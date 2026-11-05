// 移植自 Si-yi/DYads- 5e9a5c0（DYYYFeedCardPolicy.h）：改名一律 DYYY -> DKXS，设置键同步改名。
#import <Foundation/Foundation.h>

@interface DKXSFeedCardPolicy : NSObject
+ (BOOL)isPromotionalCard:(id)model;
+ (BOOL)bindFeed:(id)feed controller:(id)controller;
+ (BOOL)isEnabledForController:(id)controller;
+ (NSArray *)filterArray:(id)array controller:(id)controller;
// 几何纯计算：按原生常量增减，重复布局不累加。
+ (double)bottomConstant:(double)native inset:(double)inset reversed:(BOOL)reversed;
@end
