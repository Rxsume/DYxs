// 移植自 Si-yi/DYads- 7083bae（DYYYNativeGridRoute.m）：改名一律 DYYY -> DKXS，逻辑原样。
// 本地最小接口声明：39.5 头文件未声明 AWEDCFeed* 路由类，只声明本文件直接取用的属性与方法；
// 运行时真实性由 DKXSChatEnhancementPolicy 逐项核对，缺失时拒绝并走原生，不会走到直接调用。
// 开关 DKXSEnableNativeGridFullscreen 默认关（DYxs 移植惯例；上游默认开，不跟随）。
// 0.6.9.23 修复：补 AWEDCFeedDetailVCRouter 的 initWithBuilder: 声明（上游 AwemeHeaders.h 在
// AWEDCFeedBaseRouter 上声明，DYxs 39.5 头文件里没有；缺声明时 CI 报 no known instance method）。
#import "DKXSNativeGridRoute.h"
#import "DKXSGridRouterBridge.h"
#import "DKXSChatEnhancementPolicy.h"
#import "DKXSSettingsHelper.h"
#import "DKXSUtils.h"
#import "DKXSAwemeHeaders.h"

@interface AWEDCFeedRouterTargetModel : NSObject
@property (nonatomic, strong) AWEAwemeModel *model;
@property (nonatomic, strong) NSIndexPath *indexPath;
@property (nonatomic, strong) UICollectionViewCell *cell;
@end
@interface AWEDCFeedListViewController : UIViewController
@property (nonatomic, strong) UICollectionView *collectionView;
@end
@interface AWEDCFeedBaseCell : UICollectionViewCell
@property (nonatomic, strong) AWEAwemeModel *awemeModel;
@end
@interface AWEDCFeedDetailVCRouter : NSObject
- (instancetype)initWithBuilder:(id)builder;
@end

@interface DKXSGridRouteObservation : NSObject
@property (nonatomic, weak) UINavigationController *navigation;
@property (nonatomic, weak) UIViewController *source;
@property (nonatomic, copy) NSString *decision;
@property (nonatomic, copy) NSString *scopeDecision;
@property (nonatomic, copy) NSString *sourceClass;
@end
@implementation DKXSGridRouteObservation
@end

@implementation DKXSNativeGridRoute
+ (DKXSGridRouterBridge *)bridge {
    static DKXSGridRouterBridge *bridge; static dispatch_once_t once;
    dispatch_once(&once, ^{ bridge = [DKXSGridRouterBridge new]; }); return bridge;
}
+ (NSMutableArray<DKXSGridRouteObservation *> *)observations {
    static NSMutableArray *records; static dispatch_once_t once;
    dispatch_once(&once, ^{ records = [NSMutableArray array]; }); return records;
}
+ (NSMutableDictionary *)hookState {
    static NSMutableDictionary *state; static dispatch_once_t once;
    dispatch_once(&once, ^{ state = [@{ @"albumEntryInstalled":@NO } mutableCopy]; }); return state;
}
+ (void)setHookInstalled:(BOOL)installed { [self hookState][@"albumEntryInstalled"] = @(installed); }
+ (void)resetFailure {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self resetFailure]; }); return; }
    [[self bridge] resetFailure];
}
+ (NSString *)scopeRejectionForContainer:(id)object navigation:(id)navigation target:(AWEDCFeedRouterTargetModel *)target {
    Class listClass = NSClassFromString(@"AWEDCFeedListViewController");
    if (![object isKindOfClass:listClass] || ![navigation isKindOfClass:UINavigationController.class] ||
        ![DKXSChatEnhancementPolicy class:[object class] selector:@selector(collectionView) result:'@' arguments:@""])
        return @"source_ui_contract_unavailable";
    AWEDCFeedListViewController *list = object;
    UIViewController *home = nil; BOOL doubleColumn = NO;
    UIViewController *parent = list;
    for (NSUInteger depth = 0; parent && depth < 20; depth++, parent = parent.parentViewController) {
        if ([parent isKindOfClass:NSClassFromString(@"AWEFeedNewDoubleColumnViewController")]) doubleColumn = YES;
        if ([parent isKindOfClass:NSClassFromString(@"AWEFeedRootViewController")]) { home = parent; break; }
    }
    UINavigationController *nav = navigation;
    if (!doubleColumn || !home || nav.topViewController != home || nav.presentedViewController ||
        home.isBeingDismissed || !list.viewIfLoaded.window) return @"home_grid_not_current";
    UICollectionView *collection = list.collectionView;
    UICollectionViewCell *cell = target.cell;
    NSIndexPath *path = target.indexPath;
    if (![collection isKindOfClass:UICollectionView.class] || ![cell isKindOfClass:UICollectionViewCell.class] ||
        ![path isKindOfClass:NSIndexPath.class] || path.length != 2 || !cell.window ||
        cell.window != list.viewIfLoaded.window || collection.hidden || collection.alpha < 0.01 ||
        ![collection.visibleCells containsObject:cell] || ![[collection indexPathForCell:cell] isEqual:path] ||
        ![DKXSChatEnhancementPolicy class:cell.class selector:@selector(awemeModel) result:'@' arguments:@""])
        return @"selected_cell_not_visible_or_contract_changed";
    return [(AWEDCFeedBaseCell *)cell awemeModel] == target.model ? nil : @"selected_model_identity_mismatch";
}
+ (BOOL)routeTarget:(id)target fromAlbum:(id)album {
    if (!NSThread.isMainThread || ![DKXSSettingsHelper getUserDefaults:@"DKXSEnableNativeGridFullscreen"]) return NO;
    DKXSGridRouteObservation *record = [DKXSGridRouteObservation new];
    DKXSGridRouterBridge *bridge = [self bridge];
    BOOL dispatched = [bridge routeTarget:target fromAlbum:album eligibility:^BOOL(id container, id navigation, id nativeTarget) {
        if (![navigation isKindOfClass:UINavigationController.class]) return NO;
        record.navigation = navigation;
        record.source = [navigation topViewController];
        record.sourceClass = record.source ? NSStringFromClass(record.source.class) : @"none";
        record.scopeDecision = [self scopeRejectionForContainer:container navigation:navigation target:nativeTarget] ?: @"eligible";
        return [record.scopeDecision isEqualToString:@"eligible"];
    } factory:^id(id builder) {
        return [[NSClassFromString(@"AWEDCFeedDetailVCRouter") alloc] initWithBuilder:builder];
    }];
    record.decision = bridge.lastDecision;
    NSMutableArray *records = [self observations];
    if (records.count >= 32) [records removeObjectAtIndex:0];
    [records addObject:record];
    if ([record.decision isEqualToString:@"entry_exception_no_retry"] || [record.decision isEqualToString:@"preflight_exception_native"])
        [DKXSUtils showToast:@"全屏入口异常，已恢复默认打开方式"];
    return dispatched;
}
+ (BOOL)containsStandardFeed:(UIViewController *)controller {
    Class cls = NSClassFromString(@"AWEAwemeDetailTableViewController");
    NSMutableArray *pending = [NSMutableArray array];
    if (controller) [pending addObject:controller];
    for (NSUInteger index = 0; index < pending.count && index < 48; index++) {
        UIViewController *candidate = pending[index];
        if ([candidate isKindOfClass:cls]) return YES;
        for (UIViewController *child in candidate.childViewControllers)
            if (pending.count < 48 && ![pending containsObject:child]) [pending addObject:child];
    }
    return NO;
}
+ (NSDictionary *)diagnostics {
    if (!NSThread.isMainThread) return @{};
    NSMutableArray *records = [NSMutableArray array];
    for (DKXSGridRouteObservation *record in [self observations]) {
        UIViewController *destination = record.navigation.topViewController;
        [records addObject:@{ @"decision":record.decision ?: @"unknown",
            @"scopeDecision":record.scopeDecision ?: @"not_reached", @"sourceClass":record.sourceClass ?: @"not_reached",
            @"currentDestination":destination ? NSStringFromClass(destination.class) : @"released",
            @"sourceStillOnTop":@(destination && destination == record.source),
            @"destinationHasStandardFeed":@([self containsStandardFeed:destination]) }];
    }
    BOOL enabled = [DKXSSettingsHelper getUserDefaults:@"DKXSEnableNativeGridFullscreen"];
    BOOL active = enabled && ![self bridge].sessionDisabled && [[self hookState][@"albumEntryInstalled"] boolValue];
    return @{ @"enabled":@(enabled), @"active":@(active), @"mode":active ? @"native_router_target" : @"native_only",
        @"routingHooksRemoved":@YES, @"removedHooks":@"legacy_collection_takeover",
        @"strategy":@"album_to_detail_shared_target", @"hooks":[[self hookState] copy],
        @"dispatchCount":@([self bridge].dispatchCount), @"sessionDisabled":@([self bridge].sessionDisabled),
        @"lastDecision":[self bridge].lastDecision, @"exceptionName":[self bridge].exceptionName ?: @"", @"observations":records };
}
@end
