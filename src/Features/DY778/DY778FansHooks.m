#import "DY778FansUI.h"
// DYxs：不 import 上游 DY778Enhancements.h（总入口，含未并入的 Radar/Confirm/Spark）；
// 本文件用到的符号均由 DY778FansUI.h 的引入链（DY778Core.h）提供。
#import <QuartzCore/QuartzCore.h>
static char DY778FansProfileButtonKeyStorage;
static const void *DY778FansProfileButtonKey = &DY778FansProfileButtonKeyStorage;
static NSHashTable *DY778FansProfileOwners;
static BOOL DY778FansMatch(Method method, const char *returns, const char *arguments) {
    if (!method) return NO;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (signature.methodReturnType[0] != returns[0] || signature.numberOfArguments != strlen(arguments)+2) return NO;
    for (NSUInteger i=0; arguments[i]; i++) if ([signature getArgumentTypeAtIndex:i+2][0] != arguments[i]) return NO;
    return YES;
}
@interface DY778FansProfileButton : UIButton
@property(nonatomic, weak) id owner;
@end
@implementation DY778FansProfileButton
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        [self setImage:[UIImage systemImageNamed:@"star.circle"] forState:UIControlStateNormal];
        [self setTitle:@" 星牌" forState:UIControlStateNormal]; self.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        [self setTitleColor:UIColor.whiteColor forState:UIControlStateNormal]; self.tintColor = UIColor.whiteColor;
        self.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.28]; self.layer.cornerRadius = 18;
        self.accessibilityLabel = @"查询此用户的消费等级与粉丝灯牌";
        [self addTarget:self action:@selector(open) forControlEvents:UIControlEventTouchUpInside];
    } return self;
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event { return CGRectContainsPoint(CGRectInset(self.bounds, 0, -4), point); }
- (void)open {
    if (!DY778FansEnabled(@"DY778FansC.Profile")) return;
    NSDictionary *person = DY778FansPerson(DY778FansCall(self.owner, @"userModel", @[]));
    if (person) DY778FansOpenQuery(person);
}
@end

static void DY778FansUpdateProfile(id owner) {
    UIView *container = DY778FansRead(owner, @"navigationContainerView"); if (![container isKindOfClass:UIView.class]) return;
    DY778FansProfileButton *button = objc_getAssociatedObject(container, DY778FansProfileButtonKey);
    NSDictionary *person = DY778FansPerson(DY778FansCall(owner, @"userModel", @[]));
    if (!DY778FansEnabled(@"DY778FansC.Profile") || !person || container.bounds.size.width < 120) { button.hidden = YES; return; }
    if (!button) {
        button = [DY778FansProfileButton new]; button.owner = owner; [container addSubview:button]; objc_setAssociatedObject(container, DY778FansProfileButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!DY778FansProfileOwners) DY778FansProfileOwners = [NSHashTable weakObjectsHashTable]; [DY778FansProfileOwners addObject:owner];
    }
    CGFloat left = 12, right = container.bounds.size.width - 12, centerY = container.bounds.size.height / 2;
    button.owner = owner;
    button.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.28]; button.tintColor = UIColor.whiteColor;
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    id leftViews = DY778FansCall(owner, @"currentLeftShowViews", @[]), rightViews = DY778FansCall(owner, @"currentRightShowViews", @[]);
    if (![leftViews isKindOfClass:NSArray.class] || ![rightViews isKindOfClass:NSArray.class]) { button.hidden = YES; return; }
    for (id views in @[leftViews ?: @[], rightViews ?: @[]]) {
        if (![views isKindOfClass:NSArray.class]) continue;
        for (UIView *view in views) {
            if (![view isKindOfClass:UIView.class] || view.hidden || view.alpha < 0.05 || ![view isDescendantOfView:container] || view == button) continue;
            CGRect frame = [view convertRect:view.bounds toView:container];
            if (views == leftViews) { left = MAX(left, CGRectGetMaxX(frame) + 8); centerY = CGRectGetMidY(frame); }
            else right = MIN(right, CGRectGetMinX(frame) - 8);
        }
    }
    CGFloat width = DY778FansProfileButtonWidth(right - left);
    button.hidden = width == 0 || container.bounds.size.height < 36;
    [button setTitle:width > 44 ? @" 星牌" : @"" forState:UIControlStateNormal];
    button.frame = CGRectMake(left, MAX(0, MIN(container.bounds.size.height - 36, centerY - 18)), width, 36);
    [container bringSubviewToFront:button];
}
static void DY778FansInstallProfile(void) {
    static BOOL installed[4]; NSArray *selectors = @[@"viewDidLayoutSubviews", @"viewDidAppear", @"reloadData", @"viewDidDisappear"];
    Class cls = NSClassFromString(@"AWEProfileNavigationBaseComponent");
    for (NSUInteger i = 0; i < selectors.count; i++) {
        if (installed[i]) continue; SEL sel = NSSelectorFromString(selectors[i]); Method method = class_getInstanceMethod(cls, sel);
        if (!DY778FansMatch(method, "v", "")) continue;
        IMP original = method_getImplementation(method); BOOL hiding = i == 3;
        IMP replacement = imp_implementationWithBlock(^(id owner) {
            ((void (*)(id, SEL))original)(owner, sel);
            if (hiding) { UIView *view = DY778FansRead(owner, @"navigationContainerView"); UIView *button = objc_getAssociatedObject(view, DY778FansProfileButtonKey); button.hidden = YES; }
            else DY778FansUpdateProfile(owner);
        });
        class_replaceMethod(cls, sel, replacement, method_getTypeEncoding(method)); installed[i] = YES;
    }
    static BOOL hitInstalled; if (hitInstalled) return;
    Class container = NSClassFromString(@"AWEProfileNavigationContainerView"); SEL sel = @selector(hitTest:withEvent:); Method method = class_getInstanceMethod(container, sel);
    if (!method) return;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (signature.numberOfArguments != 4 || signature.methodReturnType[0] != '@' || strcmp([signature getArgumentTypeAtIndex:2], @encode(CGPoint)) != 0 || [signature getArgumentTypeAtIndex:3][0] != '@') return;
    IMP original = method_getImplementation(method);
    IMP replacement = imp_implementationWithBlock(^UIView *(UIView *owner, CGPoint point, UIEvent *event) {
        DY778FansProfileButton *button = objc_getAssociatedObject(owner, DY778FansProfileButtonKey);
        if (DY778FansEnabled(@"DY778FansC.Profile") && owner.userInteractionEnabled && !owner.hidden && owner.alpha > 0.05 && button && !button.hidden && button.alpha > 0.05) {
            CGPoint local = [button convertPoint:point fromView:owner];
            if ([button pointInside:local withEvent:event]) return button;
        }
        return ((UIView *(*)(id, SEL, CGPoint, id))original)(owner, sel, point, event);
    });
    class_replaceMethod(container, sel, replacement, method_getTypeEncoding(method)); hitInstalled = YES;
}
static void DY778FansInstallProfileLevel(void);
static void DY778FansLevelBind(UIView *cell);
static NSHashTable *DY778FansLevelCells;
void DY778InstallFansHooks(void) {
    DY778FansInstallProfile();
    DY778FansInstallProfileLevel();
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [NSNotificationCenter.defaultCenter addObserverForName:DY778PreferencesChangedNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            for (id owner in DY778FansProfileOwners.allObjects) DY778FansUpdateProfile(owner);
            for (UIView *cell in DY778FansLevelCells.allObjects) DY778FansLevelBind(cell);
        }];
    });
}

// ---------- 主页消费等级胶囊（1.1-2 DY778FansLevelLabel/ProfileLevelTarget 移植） ----------
// 单独开关 fans.profileLevel（默认关）；星牌查询 fans.enabled 未开时不显示。
// 胶囊挂在主页粉丝统计区「粉丝」标题旁；等级走 DY778FansService 查询，
// 按 person 缓存，同一人只查一次。
static char DY778FansLevelLabelKeyStorage;
static const void *DY778FansLevelLabelKey = &DY778FansLevelLabelKeyStorage;
static char DY778FansLevelPersonKeyStorage;
static const void *DY778FansLevelPersonKey = &DY778FansLevelPersonKeyStorage;
static NSHashTable *DY778FansLevelCells;
static NSMutableDictionary<NSString *, NSNumber *> *DY778FansLevelCache;
static NSMutableSet<NSString *> *DY778FansLevelInFlight;

@interface DY778FansLevelLabel : UILabel
- (void)configureLevel:(NSNumber *)level;
- (void)configureLoading;
@end

@implementation DY778FansLevelLabel
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.textAlignment = NSTextAlignmentCenter;
        self.clipsToBounds = YES;
        self.userInteractionEnabled = NO;
    }
    return self;
}
- (CGFloat)DY778Scale {
    id value = [DY778Preferences() objectForKey:@"fans.levelScale"];
    CGFloat scale = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 1.0;
    return MAX(0.6, MIN(1.6, scale > 0 ? scale : 1.0));
}
- (void)DY778ApplyStyle {
    id fontValue = [DY778Preferences() objectForKey:@"fans.levelFontSize"];
    CGFloat fontSize = [fontValue respondsToSelector:@selector(doubleValue)] ? [fontValue doubleValue] : 11;
    if (fontSize <= 0) fontSize = 11;
    self.font = [UIFont systemFontOfSize:fontSize * [self DY778Scale] weight:UIFontWeightSemibold];
    NSString *colorName = [DY778Preferences() objectForKey:@"fans.levelColor"];
    UIColor *background = [UIColor colorWithRed:0.98 green:0.75 blue:0.25 alpha:1]; // 金色
    if ([colorName isEqualToString:@"blue"]) background = UIColor.systemBlueColor;
    else if ([colorName isEqualToString:@"pink"]) background = UIColor.systemPinkColor;
    else if ([colorName isEqualToString:@"gray"]) background = UIColor.systemGrayColor;
    self.backgroundColor = background;
    self.textColor = UIColor.whiteColor;
}
- (void)configureLevel:(NSNumber *)level {
    [self DY778ApplyStyle];
    self.text = level ? [NSString stringWithFormat:@"Lv.%@", level] : @"Lv.?";
    [self setNeedsLayout];
}
- (void)configureLoading {
    [self DY778ApplyStyle];
    self.text = @"Lv.…";
    [self setNeedsLayout];
}
- (CGSize)intrinsicContentSize {
    CGSize size = [super intrinsicContentSize];
    CGFloat scale = [self DY778Scale];
    return CGSizeMake(size.width + 12 * scale, MAX(16 * scale, size.height + 4 * scale));
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = self.bounds.size.height / 2;
}
@end

static NSString *DY778FansLevelPersonKeyOf(NSDictionary *person) {
    NSString *uid = person[@"uid"];
    if ([uid isKindOfClass:NSString.class] && uid.length) return uid;
    NSString *sec = person[@"secUID"];
    return [sec isKindOfClass:NSString.class] ? sec : nil;
}

static NSDictionary *DY778FansLevelPersonForCell(UIView *cell) {
    for (NSString *key in @[@"userModel", @"user", @"profileUser"]) {
        NSDictionary *person = DY778FansPerson(DY778FansRead(cell, key));
        if (person) return person;
    }
    id context = DY778FansRead(cell, @"context");
    if (context) {
        NSDictionary *person = DY778FansPerson(DY778FansCall(context, @"userModel", @[]));
        if (person) return person;
    }
    for (UIResponder *responder = cell.nextResponder; responder; responder = responder.nextResponder) {
        if (![responder isKindOfClass:UIViewController.class]) continue;
        NSDictionary *person = DY778FansPerson(DY778FansCall(responder, @"userModel", @[]));
        if (person) return person;
    }
    for (id owner in DY778FansProfileOwners.allObjects) {
        NSDictionary *person = DY778FansPerson(DY778FansCall(owner, @"userModel", @[]));
        if (person) return person;
    }
    return nil;
}

static UILabel *DY778FansFindTitleLabel(UIView *root, NSString *title) {
    if ([root isKindOfClass:UILabel.class] && [((UILabel *)root).text isEqualToString:title]) return (UILabel *)root;
    for (UIView *sub in root.subviews) {
        UILabel *found = DY778FansFindTitleLabel(sub, title);
        if (found) return found;
    }
    return nil;
}

static void DY778FansLevelBind(UIView *cell) {
    if (![cell isKindOfClass:UIView.class]) return;
    DY778FansLevelLabel *label = objc_getAssociatedObject(cell, DY778FansLevelLabelKey);
    if (!DY778Bool(@"fans.enabled") || !DY778Bool(@"fans.profileLevel")) { label.hidden = YES; return; }
    UILabel *fansTitle = DY778FansFindTitleLabel(cell, @"粉丝");
    if (!fansTitle) { label.hidden = YES; return; }
    if (!label) {
        label = [DY778FansLevelLabel new];
        [cell addSubview:label];
        objc_setAssociatedObject(cell, DY778FansLevelLabelKey, label, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!DY778FansLevelCells) DY778FansLevelCells = [NSHashTable weakObjectsHashTable];
        [DY778FansLevelCells addObject:cell];
    }
    // 定位：粉丝标题右侧，垂直居中对齐标题。
    CGRect titleFrame = [fansTitle convertRect:fansTitle.bounds toView:cell];
    CGSize size = label.intrinsicContentSize;
    label.frame = CGRectMake(CGRectGetMaxX(titleFrame) + 4,
                             CGRectGetMidY(titleFrame) - size.height / 2,
                             size.width, size.height);
    label.hidden = NO;
    [cell bringSubviewToFront:label];
    NSDictionary *person = DY778FansLevelPersonForCell(cell);
    NSString *key = person ? DY778FansLevelPersonKeyOf(person) : nil;
    if (!key) { [label configureLoading]; return; }
    NSString *bound = objc_getAssociatedObject(cell, DY778FansLevelPersonKey);
    if ([bound isEqualToString:key]) return;
    objc_setAssociatedObject(cell, DY778FansLevelPersonKey, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (!DY778FansLevelCache) DY778FansLevelCache = [NSMutableDictionary dictionary];
    NSNumber *cached = DY778FansLevelCache[key];
    if (cached) { [label configureLevel:cached]; return; }
    [label configureLoading];
    if (!DY778FansLevelInFlight) DY778FansLevelInFlight = [NSMutableSet set];
    if ([DY778FansLevelInFlight containsObject:key]) return;
    [DY778FansLevelInFlight addObject:key];
    DY778FansService *service = [DY778FansService new];
    __weak UIView *weakCell = cell;
    [service queryInput:@"" mode:DY778FansInputAutomatic target:person anchor:nil completion:^(DY778FansResult *result, NSError *error) {
        [DY778FansLevelInFlight removeObject:key];
        UIView *strongCell = weakCell;
        if (!strongCell) return;
        NSString *current = objc_getAssociatedObject(strongCell, DY778FansLevelPersonKey);
        if (![current isEqualToString:key]) return;
        DY778FansLevelLabel *boundLabel = objc_getAssociatedObject(strongCell, DY778FansLevelLabelKey);
        if (result.level) {
            DY778FansLevelCache[key] = result.level;
            [boundLabel configureLevel:result.level];
        } else {
            [boundLabel configureLevel:nil];
        }
    }];
}

static void DY778FansInstallProfileLevel(void) {
    static BOOL installed;
    if (installed) return;
    Class cls = NSClassFromString(@"AWEProfileHeaderSocialStatisticCollectionViewCellV2");
    SEL sel = @selector(layoutSubviews);
    Method method = cls ? class_getInstanceMethod(cls, sel) : NULL;
    if (!DY778FansMatch(method, "v", "")) return;
    IMP original = method_getImplementation(method);
    IMP replacement = imp_implementationWithBlock(^(UIView *cell) {
        ((void (*)(id, SEL))original)(cell, sel);
        DY778FansLevelBind(cell);
    });
    class_replaceMethod(cls, sel, replacement, method_getTypeEncoding(method));
    installed = YES;
}
