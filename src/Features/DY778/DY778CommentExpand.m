#import "DY778CommentExpand.h"
#import "DY778Core.h"
#import "DY778MiscPolicy.h"

// DY778 1.0-8 模块 4：评论展开（规格 §5）。
// 24 个 hook + 会话/绑定/触摸模型 + 扫描记录。
// 红线：展开的具体 UI 动作未静态还原，DYxs 侧只做 hook 与扫描记录，
// 展开动作留空（DY778CommentExpansionApply 为显式空实现）。

static char DY778CEIdentityKey, DY778CESessionKey, DY778CERecordKey, DY778CEBindingKey;
static NSMutableSet<NSString *> *DY778CEInstalledSelectors;

@implementation DY778CommentExpansionSession
- (instancetype)init {
    if ((self = [super init])) { _records = [NSMutableArray array]; }
    return self;
}
@end
@implementation DY778CommentExpansionBinding
@end
@implementation DY778CommentExpansionTouch
- (void)userAction:(id)sender {
    (void)sender;
    // 触摸动作的展开行为未静态还原（规格 §5.4），只记观测。
    if (self.session) [self.session.records addObject:@{@"event": @"userAction", @"at": @(CACurrentMediaTime())}];
}
@end
@implementation DY778CommentExpansion
@end

void DY778CommentExpansionApply(DY778CommentExpansionSession *session, id cell) {
    // “展开”的具体 UI 动作未静态还原（规格 §5.4），不得按猜测实现。
    // 这里只记一次观测；须在抖音 40.8.0 上运行时验证长评论的展开入口
    // 与点后行为（改 label 行数？改 calculateHeight 返回值？刷新？）
    // 后再实现。
    (void)cell;
    if (session) [session.records addObject:@{@"event": @"expandRequested", @"at": @(CACurrentMediaTime())}];
}

// ---------- 签名校验（照 DY778LiveLike.m 的做法） ----------

static const char *DY778CEType(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type ?: "";
}
static BOOL DY778CEMatchesSignature(NSMethodSignature *s, const char *result, NSArray<NSString *> *arguments) {
    if (!s || strcmp(DY778CEType(s.methodReturnType), result) || s.numberOfArguments != arguments.count + 2) return NO;
    for (NSUInteger i = 0; i < arguments.count; i++) {
        const char *actual = DY778CEType([s getArgumentTypeAtIndex:i + 2]), *expected = arguments[i].UTF8String;
        if (!strcmp(expected, "B")) { if (strcmp(actual, "B") && strcmp(actual, "c")) return NO; }
        else if (!strcmp(expected, "@")) { if (actual[0] != '@') return NO; }
        else if (!strcmp(expected, "q")) { if (strcmp(actual, "q") && strcmp(actual, "l")) return NO; }
        else if (strcmp(actual, expected)) return NO;
    }
    return YES;
}
static BOOL DY778CESignature(Class cls, SEL selector, const char *result, NSArray<NSString *> *arguments) {
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    return method && DY778CEMatchesSignature([NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)], result, arguments);
}

// 类名解析（规格 §1.3）：先试短名，再试 Swift 混淆名
// _TtC<模块长><模块><类长><类>，模块为 AWECommentPanelListSwiftImpl。
static Class DY778CEClassForName(NSString *name) {
    Class cls = NSClassFromString(name);
    if (cls) return cls;
    NSString *module = @"AWECommentPanelListSwiftImpl";
    NSString *mangled = [NSString stringWithFormat:@"_TtC%lu%@%lu%@", (unsigned long)module.length, module, (unsigned long)name.length, name];
    return NSClassFromString(mangled);
}

static BOOL DY778CEVisible(UIView *view) {
    if (!view || !view.window || view.hidden || view.alpha < .01) return NO;
    for (UIView *v = view; v; v = v.superview) if (v.hidden || v.alpha < .01) return NO;
    return CGRectIntersectsRect([view convertRect:view.bounds toView:nil], view.window.bounds);
}

static UIViewController *DY778CECommentController(id object) {
    UIResponder *responder = [object isKindOfClass:UIResponder.class] ? object : nil;
    for (UIResponder *r = responder; r; r = r.nextResponder) {
        if ([r isKindOfClass:UIViewController.class] &&
            [NSStringFromClass(r.class) containsString:@"CommentViewController"]) return (UIViewController *)r;
        if ([r isKindOfClass:UIViewController.class]) {
            UIViewController *vc = (UIViewController *)r;
            UIViewController *parent = vc.parentViewController;
            if ([NSStringFromClass(parent.class) containsString:@"CommentViewController"]) return parent;
        }
    }
    return nil;
}

static DY778CommentExpansionSession *DY778CESessionForObject(id object) {
    if (!object) return nil;
    DY778CommentExpansionSession *session = objc_getAssociatedObject(object, &DY778CESessionKey);
    if (!session) {
        session = [DY778CommentExpansionSession new];
        session.owner = object;
        objc_setAssociatedObject(object, &DY778CESessionKey, session, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return session;
}

// 扫描入口（规格 §5.3，0x22ee4）：comments.enabled 门控 +
// isMainThread + 取关联对象 identity。扫描只做记录与绑定，不改 UI。
static void DY778CEScan(id object, NSString *trigger) {
    if (!NSThread.isMainThread || !DY778Bool(@"comments.enabled")) return;
    DY778CommentExpansionSession *session = DY778CESessionForObject(object);
    if (!session || session.suspended || session.closed || session.scanning) return;
    if (session.resumeAfter > 0 && session.resumeAfter > [NSProcessInfo.processInfo systemUptime]) {
        session.scanPending = YES;
        return;
    }
    session.scanning = YES;
    session.scanPending = NO;
    @try {
        UIViewController *controller = DY778CECommentController(object);
        if (controller) session.list = controller;
        // 不可见时不扫，留待下次触发（规格 §5.3，0x26510 可见性判断）。
        if (controller.viewIfLoaded && !DY778CEVisible(controller.viewIfLoaded)) {
            session.scanPending = YES;
            return;
        }
        NSString *identity = objc_getAssociatedObject(object, &DY778CEIdentityKey);
        if (!identity.length) {
            identity = [[NSUUID UUID] UUIDString];
            objc_setAssociatedObject(object, &DY778CEIdentityKey, identity, OBJC_ASSOCIATION_COPY_NONATOMIC);
        }
        if (session.records.count < DY778CommentExpandMaximumRecords) {
            [session.records addObject:@{@"trigger": trigger ?: @"", @"at": @(CACurrentMediaTime()),
                                         @"identity": identity}];
        }
    } @finally {
        session.scanning = NO;
        session.resumeAfter = [NSProcessInfo.processInfo systemUptime] + DY778CommentExpandRescanMinimumSeconds;
    }
}

static void DY778CEAfterHook(id object, NSString *trigger) {
    if (!NSThread.isMainThread || !DY778Bool(@"comments.enabled")) return;
    DY778CommentExpansionSession *session = DY778CESessionForObject(object);
    if (!session || session.busy) return;
    session.busy = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        session.busy = NO;
        DY778CEScan(object, trigger);
    });
}

// Cell 绑定（规格 §5.3，0x24894）：新建 record、设 pendingTicket、
// 写关联对象。
static void DY778CEBindCell(id cell, id model) {
    if (!cell || !DY778Bool(@"comments.enabled")) return;
    DY778CommentExpansionSession *session = DY778CESessionForObject(cell);
    DY778CommentExpansionBinding *binding = objc_getAssociatedObject(cell, &DY778CEBindingKey);
    if (!binding) {
        binding = [DY778CommentExpansionBinding new];
        binding.identity = [[NSUUID UUID] UUIDString];
        binding.session = session;
        objc_setAssociatedObject(cell, &DY778CEBindingKey, binding, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    binding.generation += 1;
    binding.pendingTicket = binding.generation;
    binding.model = model;
    NSDictionary *record = @{@"identity": binding.identity, @"generation": @(binding.generation),
                             @"model": DY778Identifier(DY778Read(model, @"commentID")) ?: @""};
    binding.record = record;
    objc_setAssociatedObject(cell, &DY778CERecordKey, record, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (session.records.count < DY778CommentExpandMaximumRecords) [session.records addObject:record];
}

// ---------- 替换实现 ----------
// 每个替换实现先调原 IMP，再在开关开时调度扫描；calculateHeight
// 原样返回（返回值是否被篡改未证实，DYxs 侧不篡改）。

#define DY778_CE_ORIG(NAME) static IMP DY778CEOriginal##NAME;
#define DY778_CE_VOID0(NAME, TRIGGER) \
static void DY778CE##NAME(id self, SEL cmd) { \
    ((void (*)(id, SEL))DY778CEOriginal##NAME)(self, cmd); \
    DY778CEAfterHook(self, @TRIGGER); }
#define DY778_CE_VOID_B(NAME, TRIGGER) \
static void DY778CE##NAME(id self, SEL cmd, BOOL v) { \
    ((void (*)(id, SEL, BOOL))DY778CEOriginal##NAME)(self, cmd, v); \
    DY778CEAfterHook(self, @TRIGGER); }
#define DY778_CE_VOID_AT(NAME, TRIGGER) \
static void DY778CE##NAME(id self, SEL cmd, id v) { \
    ((void (*)(id, SEL, id))DY778CEOriginal##NAME)(self, cmd, v); \
    DY778CEAfterHook(self, @TRIGGER); }

DY778_CE_ORIG(ViewDidLayoutSubviews)
DY778_CE_ORIG(ViewDidAppear)
DY778_CE_ORIG(ViewWillDisappear)
DY778_CE_ORIG(ScrollViewDidScroll)
DY778_CE_ORIG(ScrollViewDidEndDecelerating)
DY778_CE_ORIG(ScrollViewDidEndScrollingAnimation)
DY778_CE_ORIG(ListDidPerformBatchUpdates)
DY778_CE_ORIG(ListDidReloadData)
DY778_CE_ORIG(CellLayoutSubviews)
DY778_CE_ORIG(CellDidMoveToWindow)
DY778_CE_ORIG(CellPrepareForReuse)
DY778_CE_ORIG(LabelLayoutSubviews)
DY778_CE_ORIG(LabelDidMoveToWindow)
DY778_CE_ORIG(RenderOn)
DY778_CE_ORIG(ViewDidDisappear)
DY778_CE_ORIG(CalculateHeight)
DY778_CE_ORIG(Build)
DY778_CE_ORIG(BuildIfNeeded)
DY778_CE_ORIG(SendAction)
DY778_CE_ORIG(ScrollViewDidEndDragging)
DY778_CE_ORIG(LabelDidAddSubview)
DY778_CE_ORIG(ConfigCell)
DY778_CE_ORIG(SectionWillDisplayCell)
DY778_CE_ORIG(MakeCommentSectionViewModel)

DY778_CE_VOID0(ViewDidLayoutSubviews, "viewDidLayoutSubviews")
DY778_CE_VOID_B(ViewDidAppear, "viewDidAppear:")
DY778_CE_VOID_B(ViewWillDisappear, "viewWillDisappear:")
DY778_CE_VOID_AT(ScrollViewDidScroll, "scrollViewDidScroll:")
DY778_CE_VOID_AT(ScrollViewDidEndDecelerating, "scrollViewDidEndDecelerating:")
DY778_CE_VOID_AT(ScrollViewDidEndScrollingAnimation, "scrollViewDidEndScrollingAnimation:")
DY778_CE_VOID_AT(ListDidPerformBatchUpdates, "listDidPerformBatchUpdatesWithCollectionView:")
DY778_CE_VOID_AT(ListDidReloadData, "listDidReloadDataWithCollectionView:")
DY778_CE_VOID0(CellLayoutSubviews, "layoutSubviews")
DY778_CE_VOID0(CellDidMoveToWindow, "didMoveToWindow")
DY778_CE_VOID0(CellPrepareForReuse, "prepareForReuse")
DY778_CE_VOID0(LabelLayoutSubviews, "layoutSubviews")
DY778_CE_VOID0(LabelDidMoveToWindow, "didMoveToWindow")
DY778_CE_VOID_AT(RenderOn, "renderOn:")
DY778_CE_VOID_B(ViewDidDisappear, "viewDidDisappear:")

static double DY778CECalculateHeight(id self, SEL cmd) {
    double height = ((double (*)(id, SEL))DY778CEOriginalCalculateHeight)(self, cmd);
    DY778CEAfterHook(self, @"calculateHeight");
    return height;
}
static id DY778CEBuild(id self, SEL cmd) {
    id value = ((id (*)(id, SEL))DY778CEOriginalBuild)(self, cmd);
    DY778CEAfterHook(self, @"build");
    return value;
}
static id DY778CEBuildIfNeeded(id self, SEL cmd, BOOL needed) {
    id value = ((id (*)(id, SEL, BOOL))DY778CEOriginalBuildIfNeeded)(self, cmd, needed);
    DY778CEAfterHook(self, @"buildIfNeeded:");
    return value;
}
static void DY778CESendAction(id self, SEL cmd, SEL action, id target, id event) {
    ((void (*)(id, SEL, SEL, id, id))DY778CEOriginalSendAction)(self, cmd, action, target, event);
    DY778CEAfterHook(self, @"sendAction:to:forEvent:");
}
static void DY778CEScrollViewDidEndDragging(id self, SEL cmd, id scrollView, BOOL decelerate) {
    ((void (*)(id, SEL, id, BOOL))DY778CEOriginalScrollViewDidEndDragging)(self, cmd, scrollView, decelerate);
    DY778CEAfterHook(self, @"scrollViewDidEndDragging:willDecelerate:");
}
static void DY778CELabelDidAddSubview(id self, SEL cmd, id subview) {
    ((void (*)(id, SEL, id))DY778CEOriginalLabelDidAddSubview)(self, cmd, subview);
    DY778CEAfterHook(self, @"didAddSubview:");
}
static void DY778CEConfigCell(id self, SEL cmd, id cell, NSInteger index, id model) {
    ((void (*)(id, SEL, id, NSInteger, id))DY778CEOriginalConfigCell)(self, cmd, cell, index, model);
    DY778CEBindCell(cell, model);
    DY778CEAfterHook(self, @"configCell:index:model:");
}
static void DY778CESectionWillDisplayCell(id self, SEL cmd, id cell, NSInteger index, id model) {
    ((void (*)(id, SEL, id, NSInteger, id))DY778CEOriginalSectionWillDisplayCell)(self, cmd, cell, index, model);
    DY778CEBindCell(cell, model);
    DY778CEAfterHook(self, @"sectionWillDisplayCell:index:model:");
}
static id DY778CEMakeCommentSectionViewModel(id self, SEL cmd, id model, id context) {
    id value = ((id (*)(id, SEL, id, id))DY778CEOriginalMakeCommentSectionViewModel)(self, cmd, model, context);
    DY778CEAfterHook(self, @"makeCommentSectionViewModelWithModel:context:");
    return value;
}

// ---------- 安装 ----------

static void DY778CEInstall(NSString *className, NSString *selector, const char *result, NSArray<NSString *> *arguments,
                           IMP replacement, IMP *original) {
    if (*original) return;
    if (!DY778CEInstalledSelectors) DY778CEInstalledSelectors = [NSMutableSet set];
    NSString *key = [NSString stringWithFormat:@"comment.expand.%@", selector];
    if ([DY778CEInstalledSelectors containsObject:key]) return;
    Class cls = DY778CEClassForName(className);
    SEL sel = NSSelectorFromString(selector);
    BOOL installed = DY778CESignature(cls, sel, result, arguments) && DY778Hook(cls, sel, replacement, original);
    if (installed) [DY778CEInstalledSelectors addObject:key];
    DY778RecordHook(key, installed);
}

void DY778InstallCommentExpandHooks(void) {
    // 入口门控 [NSThread isMainThread] + 全局 once 守卫（规格 §1.3）。
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ DY778InstallCommentExpandHooks(); }); return; }
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // 高度/构建（CommentContentViewModel）。
        DY778CEInstall(@"CommentContentViewModel", @"calculateHeight", "d", @[], (IMP)DY778CECalculateHeight, &DY778CEOriginalCalculateHeight);
        DY778CEInstall(@"CommentContentViewModel", @"build", "@", @[], (IMP)DY778CEBuild, &DY778CEOriginalBuild);
        DY778CEInstall(@"CommentContentViewModel", @"buildIfNeeded:", "@", @[@"B"], (IMP)DY778CEBuildIfNeeded, &DY778CEOriginalBuildIfNeeded);
        // sendAction:to:forEvent:：规格表写 v:@@，真实 UIControl 编码
        // 含 SEL 参数（v@::@@）。安装按真实编码校验，校验不过则不装。
        DY778CEInstall(@"CommentContentViewModel", @"sendAction:to:forEvent:", "v", @[@":", @"@", @"@"], (IMP)DY778CESendAction, &DY778CEOriginalSendAction);
        // 控制器生命周期/滚动（CommentViewController）。
        DY778CEInstall(@"CommentViewController", @"viewDidLayoutSubviews", "v", @[], (IMP)DY778CEViewDidLayoutSubviews, &DY778CEOriginalViewDidLayoutSubviews);
        DY778CEInstall(@"CommentViewController", @"viewDidAppear:", "v", @[@"B"], (IMP)DY778CEViewDidAppear, &DY778CEOriginalViewDidAppear);
        DY778CEInstall(@"CommentViewController", @"viewWillDisappear:", "v", @[@"B"], (IMP)DY778CEViewWillDisappear, &DY778CEOriginalViewWillDisappear);
        DY778CEInstall(@"CommentViewController", @"scrollViewDidScroll:", "v", @[@"@"], (IMP)DY778CEScrollViewDidScroll, &DY778CEOriginalScrollViewDidScroll);
        DY778CEInstall(@"CommentViewController", @"scrollViewDidEndDecelerating:", "v", @[@"@"], (IMP)DY778CEScrollViewDidEndDecelerating, &DY778CEOriginalScrollViewDidEndDecelerating);
        DY778CEInstall(@"CommentViewController", @"scrollViewDidEndScrollingAnimation:", "v", @[@"@"], (IMP)DY778CEScrollViewDidEndScrollingAnimation, &DY778CEOriginalScrollViewDidEndScrollingAnimation);
        DY778CEInstall(@"CommentViewController", @"listDidPerformBatchUpdatesWithCollectionView:", "v", @[@"@"], (IMP)DY778CEListDidPerformBatchUpdates, &DY778CEOriginalListDidPerformBatchUpdates);
        DY778CEInstall(@"CommentViewController", @"listDidReloadDataWithCollectionView:", "v", @[@"@"], (IMP)DY778CEListDidReloadData, &DY778CEOriginalListDidReloadData);
        DY778CEInstall(@"CommentViewController", @"scrollViewDidEndDragging:willDecelerate:", "v", @[@"@", @"B"], (IMP)DY778CEScrollViewDidEndDragging, &DY778CEOriginalScrollViewDidEndDragging);
        // Cell/Label 布局（CommentNewCell、BaseCellCommentLabel）。
        DY778CEInstall(@"CommentNewCell", @"layoutSubviews", "v", @[], (IMP)DY778CECellLayoutSubviews, &DY778CEOriginalCellLayoutSubviews);
        DY778CEInstall(@"CommentNewCell", @"didMoveToWindow", "v", @[], (IMP)DY778CECellDidMoveToWindow, &DY778CEOriginalCellDidMoveToWindow);
        DY778CEInstall(@"CommentNewCell", @"prepareForReuse", "v", @[], (IMP)DY778CECellPrepareForReuse, &DY778CEOriginalCellPrepareForReuse);
        DY778CEInstall(@"BaseCellCommentLabel", @"layoutSubviews", "v", @[], (IMP)DY778CELabelLayoutSubviews, &DY778CEOriginalLabelLayoutSubviews);
        DY778CEInstall(@"BaseCellCommentLabel", @"didMoveToWindow", "v", @[], (IMP)DY778CELabelDidMoveToWindow, &DY778CEOriginalLabelDidMoveToWindow);
        DY778CEInstall(@"BaseCellCommentLabel", @"didAddSubview:", "v", @[@"@"], (IMP)DY778CELabelDidAddSubview, &DY778CEOriginalLabelDidAddSubview);
        // Section/模型绑定。
        DY778CEInstall(@"CommentSectionController", @"configCell:index:model:", "v", @[@"@", @"q", @"@"], (IMP)DY778CEConfigCell, &DY778CEOriginalConfigCell);
        DY778CEInstall(@"CommentSectionController", @"sectionWillDisplayCell:index:model:", "v", @[@"@", @"q", @"@"], (IMP)DY778CESectionWillDisplayCell, &DY778CEOriginalSectionWillDisplayCell);
        DY778CEInstall(@"AWECommentCellViewModel", @"renderOn:", "v", @[@"@"], (IMP)DY778CERenderOn, &DY778CEOriginalRenderOn);
        DY778CEInstall(@"CommentSectionViewModelService", @"makeCommentSectionViewModelWithModel:context:", "@", @[@"@", @"@"], (IMP)DY778CEMakeCommentSectionViewModel, &DY778CEOriginalMakeCommentSectionViewModel);
        DY778CEInstall(@"CommentSectionViewModelService", @"viewDidDisappear:", "v", @[@"B"], (IMP)DY778CEViewDidDisappear, &DY778CEOriginalViewDidDisappear);
        // 注：类型串里另有 1 个裸 B（返回 BOOL 的方法）未定位到具体目标，
        // DYxs 侧不安装（规格 §2.1 注）。
    });
}
