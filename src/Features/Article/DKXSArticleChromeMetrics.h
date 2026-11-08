// 移植自 Si-yi/DYads- b97c05e（DYYYArticleChromeMetrics.h）：改名一律 DYYY -> DKXS，逻辑原样。
#import <Foundation/Foundation.h>

@interface DKXSArticleChromeMetrics : NSObject
+ (NSDictionary *)topForWidth:(double)width height:(double)height back:(NSDictionary *)back
                       avatar:(NSDictionary *)avatar name:(NSDictionary *)name
                       follow:(NSDictionary *)follow search:(NSDictionary *)search;
+ (NSDictionary *)bottomForWidth:(double)width height:(double)height input:(NSDictionary *)input actions:(NSDictionary *)actions;
+ (BOOL)canRevealViewport:(NSDictionary *)viewport bottom:(NSDictionary *)bottom rootWidth:(double)width rootHeight:(double)height;
@end
