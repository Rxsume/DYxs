// 移植自 Si-yi/DYads- 7083bae（DYYYGridRouterBridge.m）：改名一律 DYYY -> DKXS，逻辑原样。
// 只转发原生已有的 Target/Builder，不拼装数据或控制器；每一步都先经
// DKXSChatEnhancementPolicy 核对运行时契约，任一缺失即拒绝并走原生。
#import "DKXSGridRouterBridge.h"
#import "DKXSChatEnhancementPolicy.h"
#import <objc/message.h>

@interface DKXSGridRouterBridge ()
@property (nonatomic, readwrite, copy) NSString *lastDecision;
@property (nonatomic, readwrite, copy) NSString *exceptionName;
@property (nonatomic, readwrite) BOOL sessionDisabled;
@property (nonatomic, readwrite) NSUInteger dispatchCount;
@property (nonatomic, assign) BOOL forwarding;
@end

@implementation DKXSGridRouterBridge
- (instancetype)init {
    if ((self = [super init])) _lastDecision = @"not_used";
    return self;
}
+ (BOOL)object:(id)object supports:(NSString *)name result:(char)result arguments:(NSString *)arguments {
    return object && [DKXSChatEnhancementPolicy class:[object class] selector:NSSelectorFromString(name)
        result:result arguments:arguments];
}
+ (BOOL)object:(id)object kind:(NSString *)name {
    Class cls = NSClassFromString(name);
    return cls && [object isKindOfClass:cls];
}
+ (id)read:(id)object name:(NSString *)name {
    return ((id (*)(id, SEL))objc_msgSend)(object, NSSelectorFromString(name));
}
+ (BOOL)routerContract:(id)router {
    for (NSString *name in @[@"routerService", @"container", @"context", @"eventDispatcher", @"transitionService", @"navigationController"])
        if (![self object:router supports:name result:'@' arguments:@""]) return NO;
    return [self object:router supports:@"enterVCWithRouterTargetModel:" result:'v' arguments:@"@"];
}
- (BOOL)reject:(NSString *)reason { self.lastDecision = reason; return NO; }
- (void)resetFailure {
    if (!NSThread.isMainThread || self.forwarding) return;
    self.sessionDisabled = NO; self.exceptionName = nil;
}
- (BOOL)routeTarget:(id)target fromAlbum:(id)album
       eligibility:(BOOL (^)(id, id, id))eligibility factory:(id (^)(id))factory {
    if (!NSThread.isMainThread) return NO;
    if (self.sessionDisabled) return [self reject:@"session_disabled"];
    if (self.forwarding) return [self reject:@"native_reentry"];
    BOOL attempted = NO;
    @try {
        if (!eligibility || ![self.class object:album kind:@"AWEDCFeedAlbumRouter"] ||
            ![self.class object:target kind:@"AWEDCFeedRouterTargetModel"] || ![self.class routerContract:album])
            return [self reject:@"source_contract_unavailable"];
        for (NSString *name in @[@"model", @"indexPath", @"cell"])
            if (![self.class object:target supports:name result:'@' arguments:@""])
                return [self reject:@"target_contract_unavailable"];
        id model = [self.class read:target name:@"model"];
        if (![self.class object:model kind:@"AWEAwemeModel"] ||
            ![self.class object:model supports:@"isLive" result:'B' arguments:@""] ||
            ((BOOL (*)(id, SEL))objc_msgSend)(model, NSSelectorFromString(@"isLive")))
            return [self reject:@"unsupported_media"];
        id container = [self.class read:album name:@"container"];
        id context = [self.class read:album name:@"context"];
        id navigation = [self.class read:album name:@"navigationController"];
        id service = [self.class read:album name:@"routerService"];
        if (!container || !context || !navigation || ![self.class object:service kind:@"AWEDCFeedDefaultRouterService"])
            return [self reject:@"source_context_unavailable"];
        for (NSString *name in @[@"container", @"context", @"detailVCRouter", @"getRouterBuilder"])
            if (![self.class object:service supports:name result:'@' arguments:@""])
                return [self reject:@"service_contract_unavailable"];
        if ([self.class read:service name:@"container"] != container || [self.class read:service name:@"context"] != context)
            return [self reject:@"service_context_mismatch"];
        if (!eligibility(container, navigation, target)) return [self reject:@"outside_visible_home_grid"];

        self.forwarding = YES;
        // getter 可能尚未创建路由器；只用原生服务提供的完整 Builder，禁止拼装数据或控制器。
        id detail = [self.class read:service name:@"detailVCRouter"];
        BOOL created = !detail;
        if (created) {
            Class detailClass = NSClassFromString(@"AWEDCFeedDetailVCRouter");
            if (!factory || ![DKXSChatEnhancementPolicy class:detailClass selector:NSSelectorFromString(@"initWithBuilder:") result:'@' arguments:@"@"] ||
                ![self.class object:service supports:@"setDetailVCRouter:" result:'v' arguments:@"@"])
                return [self reject:@"builder_contract_unavailable"];
            id builder = [self.class read:service name:@"getRouterBuilder"];
            if (![self.class object:builder kind:@"AWEDCFeedRouterBuilder"])
                return [self reject:@"builder_unavailable"];
            for (NSString *name in @[@"routerService", @"container", @"context", @"eventDispatcher", @"transitionService"])
                if (![self.class object:builder supports:name result:'@' arguments:@""] ||
                    [self.class read:builder name:name] != [self.class read:album name:name])
                    return [self reject:[@"builder_context_mismatch_" stringByAppendingString:name]];
            detail = factory(builder);
        }
        if (![self.class object:detail kind:@"AWEDCFeedDetailVCRouter"] || ![self.class routerContract:detail])
            return [self reject:@"detail_contract_unavailable"];
        for (NSString *name in @[@"routerService", @"container", @"context", @"eventDispatcher", @"transitionService", @"navigationController"])
            if ([self.class read:detail name:name] != [self.class read:album name:name])
                return [self reject:[@"detail_context_mismatch_" stringByAppendingString:name]];
        if (created) ((void (*)(id, SEL, id))objc_msgSend)(service, NSSelectorFromString(@"setDetailVCRouter:"), detail);
        attempted = YES; self.dispatchCount++;
        ((void (*)(id, SEL, id))objc_msgSend)(detail, NSSelectorFromString(@"enterVCWithRouterTargetModel:"), target);
        self.lastDecision = @"detail_router_dispatched";
        return YES;
    } @catch (NSException *exception) {
        self.exceptionName = exception.name;
        self.sessionDisabled = YES;
        self.lastDecision = attempted ? @"entry_exception_no_retry" : @"preflight_exception_native";
        // 入口抛异常后不能再试另一条导航，避免部分完成后双 push；下次点击恢复原生。
        return attempted;
    } @finally {
        self.forwarding = NO;
    }
}
@end
