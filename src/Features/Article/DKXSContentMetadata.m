// 移植自 Si-yi/DYads- 3819b4c（DYYYContentMetadata.m）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
#import "DKXSContentMetadata.h"
#import "DKXSContentBarAdapter.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

static char kDKXSContentMetadataKey;
@interface DKXSContentMetadataState : NSObject
@property (nonatomic, strong) CALayer *nativeMask;
@property (nonatomic, strong) CALayer *mask;
@property (nonatomic, assign) BOOL nativeInteraction;
@property (nonatomic, assign) BOOL applied;
@end
@implementation DKXSContentMetadataState
@end

@implementation DKXSContentMetadata
+ (NSHashTable *)cells {
    static NSHashTable *cells; static dispatch_once_t once;
    dispatch_once(&once, ^{ cells = [NSHashTable weakObjectsHashTable]; }); return cells;
}
+ (DKXSContentMetadataState *)state:(UICollectionViewCell *)cell {
    DKXSContentMetadataState *state = objc_getAssociatedObject(cell, &kDKXSContentMetadataKey);
    if (!state) {
        state = [DKXSContentMetadataState new];
        objc_setAssociatedObject(cell, &kDKXSContentMetadataKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [[self cells] addObject:cell];
    }
    return state;
}
+ (void)synchronize:(UICollectionViewCell *)cell {
    if (!NSThread.isMainThread || !cell) return;
    DKXSContentMetadataState *state = [self state:cell];
    if (![NSUserDefaults.standardUserDefaults boolForKey:@"DKXSHideContentCreationInfo"]) {
        if (!state.applied) return;
        if (cell.layer.mask == state.mask) cell.layer.mask = state.nativeMask;
        if (!cell.userInteractionEnabled) cell.userInteractionEnabled = state.nativeInteraction;
        state.applied = NO; state.nativeMask = nil; state.mask = nil;
        return;
    }
    // 空绘制遮罩隐藏整栏；保留原生hidden/布局/复用状态，避免把自有隐藏反馈给列表。
    if (!state.applied || cell.layer.mask != state.mask) state.nativeMask = cell.layer.mask;
    if (!state.applied || cell.userInteractionEnabled) state.nativeInteraction = cell.userInteractionEnabled;
    if (!state.mask) state.mask = [CALayer layer];
    if (cell.layer.mask != state.mask) cell.layer.mask = state.mask;
    if (cell.userInteractionEnabled) cell.userInteractionEnabled = NO;
    state.applied = YES;
}
+ (void)synchronizeInHost:(UIViewController *)host {
    if (!NSThread.isMainThread || ![DKXSContentBarAdapter isRichHost:host]) return;
    // 首个Swift Cell此时已实例化，再补确认安装；不依赖框架加载时的类注册时机。
    [self installHooks];
    UIScrollView *outer = [DKXSContentBarAdapter viewportInHost:host];
    for (UIView *header in outer.subviews) {
        if (header.class != UIView.class) continue;
        for (UIView *view in header.subviews) {
            if (![view isKindOfClass:UICollectionView.class]) continue;
            for (UICollectionViewCell *cell in [(UICollectionView *)view visibleCells])
                if ([NSStringFromClass(cell.class) isEqual:@"AWEKnowledgeRichContentImpl.FullPageFeedCreationInfoCell"]) [self synchronize:cell];
        }
    }
}
+ (void)refresh {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self refresh]; }); return; }
    for (UICollectionViewCell *cell in [self cells].allObjects) [self synchronize:cell];
}
+ (NSDictionary *)diagnostics {
    if (!NSThread.isMainThread) return @{};
    NSUInteger mounted = 0, hidden = 0;
    for (UICollectionViewCell *cell in [self cells].allObjects) {
        if (!cell.window) continue;
        mounted++;
        DKXSContentMetadataState *state = objc_getAssociatedObject(cell, &kDKXSContentMetadataKey);
        if (state.applied && cell.layer.mask == state.mask) hidden++;
    }
    return @{ @"enabled":@([NSUserDefaults.standardUserDefaults boolForKey:@"DKXSHideContentCreationInfo"]),
        @"mountedRows":@(mounted), @"hiddenRows":@(hidden) };
}
@end
