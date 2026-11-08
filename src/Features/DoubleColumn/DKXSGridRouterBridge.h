// 移植自 Si-yi/DYads- 7083bae（DYYYGridRouterBridge.h）：改名一律 DYYY -> DKXS，逻辑原样。
#import <Foundation/Foundation.h>

/// 9F48908D：沿用原生 Target/Builder，只替换处理它的路由器。
/// YES 仅表示已调用入口；不代表页面已经打开，也不自动重试另一条入口。
@interface DKXSGridRouterBridge : NSObject
@property (nonatomic, readonly, copy) NSString *lastDecision;
@property (nonatomic, readonly, copy) NSString *exceptionName;
@property (nonatomic, readonly) BOOL sessionDisabled;
@property (nonatomic, readonly) NSUInteger dispatchCount;
- (BOOL)routeTarget:(id)target fromAlbum:(id)album
       eligibility:(BOOL (^)(id container, id navigation, id target))eligibility
           factory:(id (^)(id builder))factory;
- (void)resetFailure;
@end
