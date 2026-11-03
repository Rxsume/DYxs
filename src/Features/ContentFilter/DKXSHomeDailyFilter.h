// 移植自 Si-yi/DYads- (fb78fd91)：改名一律 DYYY -> DKXS，设置键同步改名；逻辑原样。
#import <Foundation/Foundation.h>

@interface DKXSHomeDailyFilter : NSObject
+ (BOOL)isDailyModel:(id)model;
+ (NSArray *)filterArray:(id)array enabled:(BOOL)enabled home:(BOOL)home;
+ (BOOL)bindFeed:(id)feed controller:(id)controller;
+ (BOOL)isEnabledForController:(id)controller;
+ (NSArray *)filterArray:(id)array controller:(id)controller;
+ (NSDictionary *)diagnostics;
@end
