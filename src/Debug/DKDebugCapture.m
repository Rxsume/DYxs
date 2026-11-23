//
//  DKDebugCapture.m
//  DYxs
//
//  只读地遍历 UIKit/CoreAnimation 安全字段 + 收集本页类，产出 DKDebugExportContext。
//  不递归读任意对象的 ivar 值。
//

#import "DKDebugCapture.h"
#import "DKKeys.h"
#import "DKClassDump.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

@implementation DKDebugExportContext
@end

#pragma mark - 小型格式化工具

static NSString *DKStringFromPointer(const void *pointer) {
    return [NSString stringWithFormat:@"%p", pointer];
}

static NSString *DKClassName(id object) {
    return object ? NSStringFromClass([object class]) : @"";
}

static NSString *DKObjectDesc(id object) {
    if (!object) return @"";
    @try {
        return [object description] ?: @"";
    } @catch (__unused NSException *exception) {
        return @"<description threw>";
    }
}

static NSNumber *DKNum(double value) {
    return @(isfinite(value) ? value : 0);
}

static NSString *DKStringFromColor(UIColor *color) {
    if (!color) return @"";
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if ([color getRed:&r green:&g blue:&b alpha:&a]) {
        return [NSString stringWithFormat:@"rgba(%.4f, %.4f, %.4f, %.4f)", r, g, b, a];
    }
    return DKObjectDesc(color);
}

static NSDictionary *DKRectDict(CGRect rect) {
    return @{
        @"x": DKNum(rect.origin.x),
        @"y": DKNum(rect.origin.y),
        @"width": DKNum(rect.size.width),
        @"height": DKNum(rect.size.height),
        @"string": NSStringFromCGRect(rect)
    };
}

static NSDictionary *DKPointDict(CGPoint point) {
    return @{ @"x": DKNum(point.x), @"y": DKNum(point.y), @"string": NSStringFromCGPoint(point) };
}

static NSDictionary *DKSizeDict(CGSize size) {
    return @{ @"width": DKNum(size.width), @"height": DKNum(size.height), @"string": NSStringFromCGSize(size) };
}

static NSDictionary *DKAffineDict(CGAffineTransform t) {
    return @{
        @"a": DKNum(t.a), @"b": DKNum(t.b), @"c": DKNum(t.c),
        @"d": DKNum(t.d), @"tx": DKNum(t.tx), @"ty": DKNum(t.ty)
    };
}

static NSDictionary *DKTransform3DDict(CATransform3D t) {
    return @{
        @"m11": DKNum(t.m11), @"m12": DKNum(t.m12), @"m13": DKNum(t.m13), @"m14": DKNum(t.m14),
        @"m21": DKNum(t.m21), @"m22": DKNum(t.m22), @"m23": DKNum(t.m23), @"m24": DKNum(t.m24),
        @"m31": DKNum(t.m31), @"m32": DKNum(t.m32), @"m33": DKNum(t.m33), @"m34": DKNum(t.m34),
        @"m41": DKNum(t.m41), @"m42": DKNum(t.m42), @"m43": DKNum(t.m43), @"m44": DKNum(t.m44)
    };
}

#pragma mark - 窗口与控制器工具

static BOOL DKIsDebugWindow(UIWindow *window) {
    NSString *cls = DKClassName(window);
    return [cls hasPrefix:@"DKDebug"] || [cls hasPrefix:@"FLEX"];
}

NSArray<UIWindow *> *DKDebugActiveWindows(void) {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (!window || DKIsDebugWindow(window)) continue;
                if (window.hidden || window.alpha <= 0.01) continue;
                [windows addObject:window];
            }
        }
    }
    if (windows.count == 0) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            if (!window || DKIsDebugWindow(window)) continue;
            if (window.hidden || window.alpha <= 0.01) continue;
            [windows addObject:window];
        }
#pragma clang diagnostic pop
    }
    return windows;
}

UIWindow *DKDebugTargetWindow(void) {
    NSArray<UIWindow *> *windows = DKDebugActiveWindows();
    for (UIWindow *window in windows) if (window.isKeyWindow) return window;
    return windows.firstObject;
}

static UIViewController *DKViewControllerForView(UIView *view) {
    UIResponder *responder = view;
    for (NSUInteger i = 0; responder && i < 80; i++) {
        responder = responder.nextResponder;
        if ([responder isKindOfClass:[UIViewController class]]) return (UIViewController *)responder;
    }
    return nil;
}

static UIViewController *DKTopViewControllerFrom(UIViewController *vc) {
    for (NSUInteger i = 0; vc && i < 80; i++) {
        if (vc.presentedViewController) {
            vc = vc.presentedViewController;
        } else if ([vc isKindOfClass:[UINavigationController class]]) {
            UIViewController *visible = ((UINavigationController *)vc).visibleViewController;
            if (!visible || visible == vc) break;
            vc = visible;
        } else if ([vc isKindOfClass:[UITabBarController class]]) {
            UIViewController *selected = ((UITabBarController *)vc).selectedViewController;
            if (!selected || selected == vc) break;
            vc = selected;
        } else {
            break;
        }
    }
    return vc;
}

UIViewController *DKDebugTopPresenter(UIWindow *window) {
    return DKTopViewControllerFrom(window.rootViewController);
}

#pragma mark - 页面快照

static NSDictionary *DKLayerInfo(CALayer *layer) {
    if (!layer) return @{};
    return @{
        @"class": DKClassName(layer),
        @"address": DKStringFromPointer((__bridge const void *)layer),
        @"bounds": DKRectDict(layer.bounds),
        @"position": DKPointDict(layer.position),
        @"anchorPoint": DKPointDict(layer.anchorPoint),
        @"zPosition": DKNum(layer.zPosition),
        @"opacity": DKNum(layer.opacity),
        @"hidden": @(layer.hidden),
        @"masksToBounds": @(layer.masksToBounds),
        @"cornerRadius": DKNum(layer.cornerRadius),
        @"sublayerCount": @(layer.sublayers.count),
        @"transform": DKTransform3DDict(layer.transform),
        @"mask": layer.mask ? @{
            @"class": DKClassName(layer.mask),
            @"address": DKStringFromPointer((__bridge const void *)layer.mask),
            @"bounds": DKRectDict(layer.mask.bounds)
        } : @{}
    };
}

static NSMutableDictionary *DKBaseViewInfo(UIView *view, NSUInteger depth) {
    UIViewController *nearestVC = DKViewControllerForView(view);
    NSMutableDictionary *info = [@{
        @"class": DKClassName(view),
        @"address": DKStringFromPointer((__bridge const void *)view),
        @"depth": @(depth),
        @"frame": DKRectDict(view.frame),
        @"bounds": DKRectDict(view.bounds),
        @"center": DKPointDict(view.center),
        @"alpha": DKNum(view.alpha),
        @"hidden": @(view.hidden),
        @"opaque": @(view.opaque),
        @"clipsToBounds": @(view.clipsToBounds),
        @"userInteractionEnabled": @(view.userInteractionEnabled),
        @"multipleTouchEnabled": @(view.multipleTouchEnabled),
        @"contentMode": @(view.contentMode),
        @"tag": @(view.tag),
        @"autoresizingMask": @(view.autoresizingMask),
        @"autoresizesSubviews": @(view.autoresizesSubviews),
        @"transform": DKAffineDict(view.transform),
        @"backgroundColor": DKStringFromColor(view.backgroundColor),
        @"tintColor": DKStringFromColor(view.tintColor),
        @"accessibilityIdentifier": view.accessibilityIdentifier ?: @"",
        @"accessibilityLabel": view.accessibilityLabel ?: @"",
        @"nearestViewController": nearestVC ? @{
            @"class": DKClassName(nearestVC),
            @"address": DKStringFromPointer((__bridge const void *)nearestVC)
        } : @{},
        @"layer": DKLayerInfo(view.layer),
        @"subviewCount": @(view.subviews.count)
    } mutableCopy];

    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        info[@"label"] = @{
            @"text": label.text ?: @"",
            @"attributedText": label.attributedText.string ?: @"",
            @"font": DKObjectDesc(label.font),
            @"textColor": DKStringFromColor(label.textColor),
            @"numberOfLines": @(label.numberOfLines),
            @"textAlignment": @(label.textAlignment)
        };
    }
    if ([view isKindOfClass:[UIButton class]]) {
        UIButton *button = (UIButton *)view;
        info[@"button"] = @{
            @"currentTitle": [button titleForState:UIControlStateNormal] ?: (button.currentTitle ?: @""),
            @"currentAttributedTitle": button.currentAttributedTitle.string ?: @"",
            @"enabled": @(button.enabled),
            @"selected": @(button.selected),
            @"highlighted": @(button.highlighted)
        };
    }
    if ([view isKindOfClass:[UIImageView class]]) {
        UIImageView *imageView = (UIImageView *)view;
        info[@"imageView"] = @{
            @"imageSize": imageView.image ? DKSizeDict(imageView.image.size) : @{},
            @"highlighted": @(imageView.highlighted)
        };
    }
    if ([view isKindOfClass:[UIControl class]]) {
        UIControl *control = (UIControl *)view;
        info[@"control"] = @{
            @"enabled": @(control.enabled),
            @"selected": @(control.selected),
            @"highlighted": @(control.highlighted),
            @"state": @(control.state)
        };
    }
    if ([view isKindOfClass:[UIScrollView class]]) {
        UIScrollView *scroll = (UIScrollView *)view;
        info[@"scrollView"] = @{
            @"contentOffset": DKPointDict(scroll.contentOffset),
            @"contentSize": DKSizeDict(scroll.contentSize),
            @"contentInset": NSStringFromUIEdgeInsets(scroll.contentInset),
            @"adjustedContentInset": NSStringFromUIEdgeInsets(scroll.adjustedContentInset),
            @"zoomScale": DKNum(scroll.zoomScale),
            @"minimumZoomScale": DKNum(scroll.minimumZoomScale),
            @"maximumZoomScale": DKNum(scroll.maximumZoomScale),
            @"pagingEnabled": @(scroll.pagingEnabled),
            @"scrollEnabled": @(scroll.scrollEnabled),
            @"dragging": @(scroll.dragging),
            @"tracking": @(scroll.tracking),
            @"decelerating": @(scroll.decelerating)
        };
    }
    if ([view isKindOfClass:[UIVisualEffectView class]]) {
        info[@"visualEffectView"] = @{ @"effect": DKObjectDesc(((UIVisualEffectView *)view).effect) };
    }
    return info;
}

static NSDictionary *DKViewTreeJSON(UIView *view, NSUInteger depth, NSMutableArray *layers) {
    NSMutableDictionary *info = DKBaseViewInfo(view, depth);
    [layers addObject:@{
        @"viewClass": info[@"class"],
        @"viewAddress": info[@"address"],
        @"nearestViewController": info[@"nearestViewController"],
        @"layer": info[@"layer"]
    }];

    NSMutableArray *children = [NSMutableArray arrayWithCapacity:view.subviews.count];
    for (UIView *subview in view.subviews) {
        [children addObject:DKViewTreeJSON(subview, depth + 1, layers)];
    }
    info[@"children"] = children;
    return info;
}

static void DKAppendViewTreeText(UIView *view, NSUInteger depth, NSMutableString *out) {
    NSMutableString *indent = [NSMutableString string];
    for (NSUInteger i = 0; i < depth; i++) [indent appendString:@"  "];
    UIViewController *vc = DKViewControllerForView(view);
    [out appendFormat:@"%@%@ %@ frame=%@ bounds=%@ vc=%@ %@ hidden=%d alpha=%.3f clips=%d user=%d layer=%@\n",
     indent,
     DKClassName(view),
     DKStringFromPointer((__bridge const void *)view),
     NSStringFromCGRect(view.frame),
     NSStringFromCGRect(view.bounds),
     vc ? DKClassName(vc) : @"",
     vc ? DKStringFromPointer((__bridge const void *)vc) : @"",
     view.hidden,
     view.alpha,
     view.clipsToBounds,
     view.userInteractionEnabled,
     DKClassName(view.layer)];
    for (UIView *subview in view.subviews) DKAppendViewTreeText(subview, depth + 1, out);
}

#pragma mark - 紧凑视图树（摇一摇导出）

// huami DYYY 3.0.1 的 describeViewTree 与 3.0.2 的运行时探针，按本模块口径改写。
// 与 DKAppendViewTreeText 的区别：单行更紧凑（类名 + 帧 + 颜色 + 显隐 + tag，
// 不带指针地址），且 UITableView / 详情页 VC 后附只读探针行（# …），
// 供真机上核对行高类问题（如详情页 873/956 混排）。
// 探针只读：先 respondsToSelector 再按方法签名调无参方法，绝不写状态；
// 整段探针调用包在 @try/@catch 里，异常只记一行，不中断整棵树。
// 注意：[vc:] 与探针只看 view 的直接 nextResponder 是不是 VC——
// 用 DKViewControllerForView 沿链上溯会在每层子 view 上重复探同一个 VC。

// 只读地调一个无参方法，按返回类型格式化；调不到返回 @"-"，签名不对返回 @"?"。
static NSString *DKRuntimeProbeValue(id object, NSString *selName) {
    SEL sel = NSSelectorFromString(selName);
    if (!object || ![object respondsToSelector:sel]) return @"-";
    NSMethodSignature *sig = [object methodSignatureForSelector:sel];
    if (!sig || sig.numberOfArguments != 2) return @"?";
    const char *rt = sig.methodReturnType;
    switch (rt[0]) {
        case 'd': return [NSString stringWithFormat:@"%.1f", ((double (*)(id, SEL))objc_msgSend)(object, sel)];
        case 'f': return [NSString stringWithFormat:@"%.1f", ((float (*)(id, SEL))objc_msgSend)(object, sel)];
        case 'B': case 'c': return ((BOOL (*)(id, SEL))objc_msgSend)(object, sel) ? @"YES" : @"NO";
        case 'q': case 'Q': case 'i': case 'I': case 'l': case 'L':
            return [NSString stringWithFormat:@"%ld", (long)((NSInteger (*)(id, SEL))objc_msgSend)(object, sel)];
        case '@': {
            id result = ((id (*)(id, SEL))objc_msgSend)(object, sel);
            if (!result) return @"nil";
            if ([result isKindOfClass:[NSString class]]) return [NSString stringWithFormat:@"\"%@\"", result];
            return NSStringFromClass([result class]);
        }
        default: return [NSString stringWithFormat:@"<%s>", rt];
    }
}

// 只读地调一个 (NSInteger) -> double 的方法（如 cellHeightAtIndex:）。
static NSString *DKRuntimeProbeIndexedValue(id object, NSString *selName, NSInteger index) {
    SEL sel = NSSelectorFromString(selName);
    if (!object || ![object respondsToSelector:sel]) return @"-";
    NSMethodSignature *sig = [object methodSignatureForSelector:sel];
    if (!sig || sig.numberOfArguments != 3 || sig.methodReturnType[0] != 'd') return @"?";
    return [NSString stringWithFormat:@"%.1f", ((double (*)(id, SEL, NSInteger))objc_msgSend)(object, sel, index)];
}

static void DKAppendRuntimeProbeLine(NSMutableString *out, NSUInteger depth, NSString *line) {
    for (NSUInteger i = 0; i <= depth; i++) [out appendString:@"  "];
    [out appendFormat:@"# %@\n", line];
}

// UITableView 的滚动与行高状态：bounds/offset/contentSize/inset、delegate 与 dataSource 类名、
// 可见行的 delegate 行高、以及 delegate 上的 fixedCellHeight/cellHeight/originalTableViewHeight。
static void DKAppendScrollProbe(UIView *view, NSMutableString *out, NSUInteger depth) {
    if (![view isKindOfClass:[UITableView class]]) return;
    UITableView *tableView = (UITableView *)view;
    id delegate = tableView.delegate;
    DKAppendRuntimeProbeLine(out, depth, [NSString stringWithFormat:@"table bounds=%.0fx%.0f offset=%.1f contentH=%.1f inset=(%.0f,%.0f) adj=(%.0f,%.0f) paging=%d rowHeight=%.1f est=%.1f",
        tableView.bounds.size.width, tableView.bounds.size.height, tableView.contentOffset.y, tableView.contentSize.height,
        tableView.contentInset.top, tableView.contentInset.bottom, tableView.adjustedContentInset.top, tableView.adjustedContentInset.bottom,
        tableView.pagingEnabled, tableView.rowHeight, tableView.estimatedRowHeight]);
    DKAppendRuntimeProbeLine(out, depth, [NSString stringWithFormat:@"delegate=%@ dataSource=%@",
        delegate ? NSStringFromClass([delegate class]) : @"nil",
        tableView.dataSource ? NSStringFromClass([(id)tableView.dataSource class]) : @"nil"]);
    if ([delegate respondsToSelector:@selector(tableView:heightForRowAtIndexPath:)]) {
        NSMutableString *heights = [NSMutableString string];
        for (NSIndexPath *indexPath in [tableView.indexPathsForVisibleRows subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)4, tableView.indexPathsForVisibleRows.count))]) {
            [heights appendFormat:@" row%ld=%.1f(rect %.1f)", (long)indexPath.row, [delegate tableView:tableView heightForRowAtIndexPath:indexPath], [tableView rectForRowAtIndexPath:indexPath].size.height];
        }
        DKAppendRuntimeProbeLine(out, depth, [NSString stringWithFormat:@"delegate heightForRow:%@", heights]);
    } else {
        DKAppendRuntimeProbeLine(out, depth, @"delegate does NOT implement tableView:heightForRowAtIndexPath:");
    }
    for (NSString *key in @[@"fixedCellHeight", @"cellHeight", @"originalTableViewHeight"]) {
        NSString *value = DKRuntimeProbeValue(delegate, key);
        if (![value isEqualToString:@"-"]) DKAppendRuntimeProbeLine(out, depth, [NSString stringWithFormat:@"delegate.%@=%@", key, value]);
    }
}

// 详情页 VC 的行高与交互挂载状态：DetailCellViewController 看交互层延迟挂载的几个状态位；
// DetailTableViewController 看行高源（fixedCellHeight/cellHeightAtIndex/smartSnap）与直播卡片高度。
static void DKAppendViewControllerProbe(UIViewController *vc, NSMutableString *out, NSUInteger depth) {
    NSString *cls = NSStringFromClass([vc class]);
    if ([cls containsString:@"DetailCellViewController"]) {
        // 交互层（文案/右侧按钮）是首帧后延迟挂载的，这里只读几个状态位，看卡在哪一步。
        NSMutableString *line = [NSMutableString stringWithString:@"cellVC:"];
        for (NSString *key in @[@"interactionController", @"shouldDelayAddInteraction", @"shouldForbidInitInteraction", @"innerInteractionDelay",
                              @"shouldOptimizeInteractionDelayProcess", @"awe_isWaitingForDelayedInteractionInit", @"awe_isWaitingForDelayedInteractionUpdate",
                              @"awe_defersInteractionUpdate", @"awe_hasDeferredInteractionUpdate", @"referString"]) {
            [line appendFormat:@" %@=%@", key, DKRuntimeProbeValue(vc, key)];
        }
        id model = nil; SEL modelSel = NSSelectorFromString(@"model");
        if ([vc respondsToSelector:modelSel]) model = ((id (*)(id, SEL))objc_msgSend)(vc, modelSel);
        [line appendFormat:@" | model=%@ awemeType=%@ isAds=%@", model ? NSStringFromClass([model class]) : @"nil", DKRuntimeProbeValue(model, @"awemeType"), DKRuntimeProbeValue(model, @"isAds")];
        id interactionController = nil; SEL icSel = NSSelectorFromString(@"interactionController");
        if ([vc respondsToSelector:icSel]) interactionController = ((id (*)(id, SEL))objc_msgSend)(vc, icSel);
        if ([interactionController isKindOfClass:[UIViewController class]]) {
            UIViewController *icvc = (UIViewController *)interactionController;
            [line appendFormat:@" | interaction viewLoaded=%d superview=%@", icvc.isViewLoaded,
                            icvc.isViewLoaded ? (icvc.view.superview ? NSStringFromClass([icvc.view.superview class]) : @"-") : @"-"];
        }
        DKAppendRuntimeProbeLine(out, depth, line);
        return;
    }
    if (![cls containsString:@"DetailTableViewController"]) return;
    NSMutableString *line = [NSMutableString stringWithFormat:@"vc %@:", cls];
    for (NSString *key in @[@"referString", @"fixedCellHeight", @"cellHeight", @"canShowFixedBottomBar", @"getCanShowFixedBottomBar",
                          @"currentIndex", @"detailFeedTakeoverUIContainer", @"rootContainer", @"liveCardLayoutController", @"bottomBarCoordinator"]) {
        [line appendFormat:@" %@=%@", key, DKRuntimeProbeValue(vc, key)];
    }
    DKAppendRuntimeProbeLine(out, depth, line);
    NSMutableString *heightsLine = [NSMutableString stringWithString:@"vc cellHeightAtIndex:"];
    for (NSInteger i = 0; i < 4; i++) [heightsLine appendFormat:@" [%ld]=%@", (long)i, DKRuntimeProbeIndexedValue(vc, @"cellHeightAtIndex:", i)];
    [heightsLine appendFormat:@" | smartSnap[1]=%@", DKRuntimeProbeIndexedValue(vc, @"smartSlidePageSnapCellHeightForIndex:", 1)];
    DKAppendRuntimeProbeLine(out, depth, heightsLine);
    id live = nil;
    SEL liveSel = NSSelectorFromString(@"liveCardLayoutController");
    if ([vc respondsToSelector:liveSel]) live = ((id (*)(id, SEL))objc_msgSend)(vc, liveSel);
    if (live) DKAppendRuntimeProbeLine(out, depth, [NSString stringWithFormat:@"liveCardLayoutController %@ originalTableViewHeight=%@ normalHeight=%@",
        NSStringFromClass([live class]), DKRuntimeProbeValue(live, @"originalTableViewHeight"), DKRuntimeProbeValue(live, @"normalHeight")]);
    id ui = nil;
    SEL uiSel = NSSelectorFromString(@"detailFeedTakeoverUIContainer");
    if ([vc respondsToSelector:uiSel]) ui = ((id (*)(id, SEL))objc_msgSend)(vc, uiSel);
    if (ui) {
        id scrollDelegate = nil; SEL sdSel = NSSelectorFromString(@"scrollDelegate");
        if ([ui respondsToSelector:sdSel]) scrollDelegate = ((id (*)(id, SEL))objc_msgSend)(ui, sdSel);
        DKAppendRuntimeProbeLine(out, depth, [NSString stringWithFormat:@"takeover ui=%@ fixedCellHeight=%@ cellHeightAtIndex[1]=%@ | scrollDelegate=%@ fixed=%@ variableHeightProviders=%@",
            NSStringFromClass([ui class]), DKRuntimeProbeValue(ui, @"fixedCellHeight"), DKRuntimeProbeIndexedValue(ui, @"cellHeightAtIndex:", 1),
            scrollDelegate ? NSStringFromClass([scrollDelegate class]) : @"nil", DKRuntimeProbeValue(scrollDelegate, @"fixedCellHeight"), DKRuntimeProbeValue(scrollDelegate, @"variableHeightProviders")]);
    }
}

static void DKAppendCompactViewTree(UIView *view, NSMutableString *out, NSUInteger depth) {
    if (!view) return;
    for (NSUInteger i = 0; i < depth; i++) [out appendString:@"  "];
    NSString *vc = @"";
    UIResponder *next = [view nextResponder];
    if ([next isKindOfClass:[UIViewController class]])
        vc = [NSString stringWithFormat:@" [vc:%@]", NSStringFromClass([next class])];
    NSString *bg = @"";
    UIColor *c = view.backgroundColor;
    if (c) {
        CGFloat r = 0, g = 0, b = 0, a = 0;
        if ([c getRed:&r green:&g blue:&b alpha:&a] && a > 0.01)
            bg = [NSString stringWithFormat:@" bg=(%.2f,%.2f,%.2f,%.2f)", r, g, b, a];
    }
    // 诊断：layer.backgroundColor（CGColor 直接上色时 view.backgroundColor 读不到）。
    NSString *lbg = @"";
    CGColorRef lc = view.layer.backgroundColor;
    if (lc && CGColorGetAlpha(lc) > 0.01) {
        UIColor *lcu = [UIColor colorWithCGColor:lc];
        CGFloat r = 0, g = 0, b = 0, a = 0;
        if ([lcu getRed:&r green:&g blue:&b alpha:&a])
            lbg = [NSString stringWithFormat:@" lbg=(%.2f,%.2f,%.2f,%.2f)", r, g, b, a];
    }
    // 诊断：UILabel 富文本背景色属性（NSBackgroundColorAttributeName）。
    NSString *abg = @"";
    if ([view isKindOfClass:[UILabel class]]) {
        NSAttributedString *att = ((UILabel *)view).attributedText;
        if (att.length > 0) {
            UIColor *ac = [att attribute:NSBackgroundColorAttributeName atIndex:0 effectiveRange:NULL];
            if (ac) {
                CGFloat r = 0, g = 0, b = 0, a = 0;
                if ([ac getRed:&r green:&g blue:&b alpha:&a] && a > 0.01)
                    abg = [NSString stringWithFormat:@" abg=(%.2f,%.2f,%.2f,%.2f)", r, g, b, a];
            }
        }
    }
    if ([view isKindOfClass:[UILabel class]] && (view.opaque || view.layer.opaque))
        abg = [abg stringByAppendingFormat:@" opq=%d/%d", view.opaque, view.layer.opaque];
    CGRect f = view.frame;
    [out appendFormat:@"%@%@ {%.0f,%.0f,%.0f,%.0f}%@%@%@%@%@%@\n",
                      NSStringFromClass([view class]), vc,
                      f.origin.x, f.origin.y, f.size.width, f.size.height, bg, lbg, abg,
                      (view.alpha < 0.99) ? [NSString stringWithFormat:@" a=%.2f", view.alpha] : @"",
                      view.hidden ? @" HIDDEN" : @"",
                      (view.tag != 0) ? [NSString stringWithFormat:@" tag=%ld", (long)view.tag] : @""];
    @try {
        if ([next isKindOfClass:[UIViewController class]])
            DKAppendViewControllerProbe((UIViewController *)next, out, depth);
        DKAppendScrollProbe(view, out, depth);
    } @catch (NSException *e) {
        DKAppendRuntimeProbeLine(out, depth, [NSString stringWithFormat:@"probe exception: %@", e.reason]);
    }
    for (UIView *sub in view.subviews)
        DKAppendCompactViewTree(sub, out, depth + 1);
}

NSString *DKDescribeViewTreeText(UIView *root) {
    NSMutableString *out = [NSMutableString string];
    DKAppendCompactViewTree(root, out, 0);
    return out;
}

static NSDictionary *DKWindowJSON(UIWindow *window) {
    return @{
        @"class": DKClassName(window),
        @"address": DKStringFromPointer((__bridge const void *)window),
        @"frame": DKRectDict(window.frame),
        @"bounds": DKRectDict(window.bounds),
        @"windowLevel": DKNum(window.windowLevel),
        @"hidden": @(window.hidden),
        @"alpha": DKNum(window.alpha),
        @"keyWindow": @(window.isKeyWindow),
        @"rootViewController": window.rootViewController ? @{
            @"class": DKClassName(window.rootViewController),
            @"address": DKStringFromPointer((__bridge const void *)window.rootViewController)
        } : @{}
    };
}

static NSArray *DKAncestorChain(UIView *view) {
    NSMutableArray *chain = [NSMutableArray array];
    UIView *v = view;
    for (NSUInteger depth = 0; v && depth < 120; depth++, v = v.superview) {
        [chain addObject:DKBaseViewInfo(v, depth)];
    }
    return chain;
}

static void DKAppendVCText(UIViewController *vc, NSUInteger depth, NSMutableString *out, NSHashTable *seen) {
    if (!vc || [seen containsObject:vc]) return;
    [seen addObject:vc];
    NSMutableString *indent = [NSMutableString string];
    for (NSUInteger i = 0; i < depth; i++) [indent appendString:@"  "];
    BOOL loaded = vc.isViewLoaded;
    UIView *view = loaded ? vc.view : nil;
    [out appendFormat:@"%@%@ %@ viewLoaded=%@ view=%@ %@ frame=%@\n",
     indent,
     DKClassName(vc),
     DKStringFromPointer((__bridge const void *)vc),
     loaded ? @"YES" : @"NO",
     DKClassName(view),
     view ? DKStringFromPointer((__bridge const void *)view) : @"",
     view ? NSStringFromCGRect(view.frame) : @"null"];

    if ([vc isKindOfClass:[UINavigationController class]]) {
        UINavigationController *nav = (UINavigationController *)vc;
        [out appendFormat:@"%@  nav.top=%@ nav.visible=%@\n", indent, DKClassName(nav.topViewController), DKClassName(nav.visibleViewController)];
    }
    if ([vc isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tab = (UITabBarController *)vc;
        [out appendFormat:@"%@  tab.selected=%@\n", indent, DKClassName(tab.selectedViewController)];
    }
    for (UIViewController *child in vc.childViewControllers) DKAppendVCText(child, depth + 1, out, seen);
    if (vc.presentedViewController) {
        [out appendFormat:@"%@  presented:\n", indent];
        DKAppendVCText(vc.presentedViewController, depth + 1, out, seen);
    }
}

// 按 windowLevel 从低到高逐个画，截图才等于用户真正看到的画面。
// 只画 key 窗口会漏掉浮层：抖音的内嵌画中画 AWEDPlayerPiPWindow 在 windowLevel 2000，
// 它铺满全屏时导出截图却一切正常，排查会整整绕一轮。
static NSData *DKScreenshotPNG(UIWindow *targetWindow) {
    if (!targetWindow) return NSData.data;

    NSArray<UIWindow *> *windows =
        [DKDebugActiveWindows() sortedArrayUsingComparator:^NSComparisonResult(UIWindow *a, UIWindow *b) {
            if (a.windowLevel == b.windowLevel) return NSOrderedSame;
            return a.windowLevel < b.windowLevel ? NSOrderedAscending : NSOrderedDescending;
        }];
    if (windows.count == 0) windows = @[ targetWindow ];

    UIGraphicsBeginImageContextWithOptions(targetWindow.bounds.size, NO, 0);
    for (UIWindow *window in windows) {
        BOOL drew = [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:NO];
        if (!drew) [window.layer renderInContext:UIGraphicsGetCurrentContext()];
    }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image ? UIImagePNGRepresentation(image) : NSData.data;
}

#pragma mark - 页面类收集

// 收集一个类及其整条继承链的类名：跳过运行时生成子类噪声，但继续上溯 → 自动收到真实基类。
static void DKCollectClassAndSupers(Class cls, NSMutableSet<NSString *> *names) {
    for (int i = 0; cls && i < 50; i++) {
        if (!DKClassIsSafe(cls)) break;
        NSString *name = NSStringFromClass(cls);
        if (name.length && !DKClassNameIsRuntimeGenerated(name)) [names addObject:name];
        cls = class_getSuperclass(cls);
    }
}

// 递归收集视图子树里每个 view 及其 layer 的类（含继承链）。
static void DKCollectPageClassesFromView(UIView *view, NSMutableSet<NSString *> *names) {
    if (!view) return;
    DKCollectClassAndSupers(object_getClass(view), names);
    DKCollectClassAndSupers(object_getClass(view.layer), names);
    for (UIView *sub in view.subviews) DKCollectPageClassesFromView(sub, names);
}

// 递归收集 VC 树（child + presented）里每个 VC 及其已加载 view 的类（含继承链）。
static void DKCollectPageClassesFromVC(UIViewController *vc, NSMutableSet<NSString *> *names, NSHashTable *seen) {
    if (!vc || [seen containsObject:vc]) return;
    [seen addObject:vc];
    DKCollectClassAndSupers(object_getClass(vc), names);
    if (vc.isViewLoaded) DKCollectClassAndSupers(object_getClass(vc.view), names);
    for (UIViewController *child in vc.childViewControllers) DKCollectPageClassesFromVC(child, names, seen);
    if (vc.presentedViewController) DKCollectPageClassesFromVC(vc.presentedViewController, names, seen);
}

static NSDictionary *DKDebugMetadata(UIWindow *targetWindow, CGPoint point) {
    return @{
        @"generatedAt": DKObjectDesc(NSDate.date),
        @"dyxsVersion": DK_VERSION,
        @"bundleIdentifier": NSBundle.mainBundle.bundleIdentifier ?: @"",
        @"bundleName": NSBundle.mainBundle.infoDictionary[@"CFBundleName"] ?: @"",
        @"appVersion": NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"",
        @"buildVersion": NSBundle.mainBundle.infoDictionary[(NSString *)kCFBundleVersionKey] ?: @"",
        @"systemName": UIDevice.currentDevice.systemName ?: @"",
        @"systemVersion": UIDevice.currentDevice.systemVersion ?: @"",
        @"deviceModel": UIDevice.currentDevice.model ?: @"",
        @"screenBounds": DKRectDict(UIScreen.mainScreen.bounds),
        @"tapPointInTargetWindow": DKPointDict(point),
        @"targetWindow": targetWindow ? DKWindowJSON(targetWindow) : @{}
    };
}

// 音频专项导出只用得上元信息和截图。整棵 view tree 有几 MB，
// 采到再丢等于让主线程白跑一趟，所以单开这条轻量路径。
DKDebugExportContext *DKDebugCaptureMetadataContext(UIWindow *targetWindow) {
    DKDebugExportContext *context = [DKDebugExportContext new];
    context.metadata = DKDebugMetadata(targetWindow, CGPointZero);
    context.screenshotPNG = DKScreenshotPNG(targetWindow);
    context.sourceView = targetWindow;
    context.presenter = DKDebugTopPresenter(targetWindow);
    return context;
}

DKDebugExportContext *DKDebugCaptureContext(UIWindow *targetWindow, CGPoint point, UIView *selectedView) {
    DKDebugExportContext *context = [DKDebugExportContext new];
    NSArray<UIWindow *> *windows = DKDebugActiveWindows();
    NSMutableArray *windowsJSON = [NSMutableArray array];
    NSMutableArray *treeJSON = [NSMutableArray array];
    NSMutableArray *layersJSON = [NSMutableArray array];
    NSMutableString *treeText = [NSMutableString string];
    NSMutableString *vcText = [NSMutableString string];
    NSHashTable *seenVCs = [NSHashTable weakObjectsHashTable];
    NSMutableSet<NSString *> *pageClasses = [NSMutableSet set];
    NSHashTable *seenClassVCs = [NSHashTable weakObjectsHashTable];

    for (UIWindow *window in windows) {
        [windowsJSON addObject:DKWindowJSON(window)];
        [treeJSON addObject:DKViewTreeJSON(window, 0, layersJSON)];
        DKAppendViewTreeText(window, 0, treeText);
        DKCollectPageClassesFromView(window, pageClasses);
        DKCollectPageClassesFromVC(window.rootViewController, pageClasses, seenClassVCs);
        if (window.rootViewController) {
            [vcText appendFormat:@"Window %@ %@\n", DKClassName(window), DKStringFromPointer((__bridge const void *)window)];
            DKAppendVCText(window.rootViewController, 1, vcText, seenVCs);
        }
    }

    UIViewController *nearestVC = DKViewControllerForView(selectedView);
    NSDictionary *selected = @{
        @"tapPointInWindow": DKPointDict(point),
        @"hitView": DKBaseViewInfo(selectedView ?: targetWindow, 0),
        @"nearestViewController": nearestVC ? @{
            @"class": DKClassName(nearestVC),
            @"address": DKStringFromPointer((__bridge const void *)nearestVC)
        } : @{},
        @"ancestorChain": selectedView ? DKAncestorChain(selectedView) : @[]
    };

    NSString *summary = [NSString stringWithFormat:
                         @"Hit: %@ %@\nFrame: %@\nBounds: %@\nNearest VC: %@ %@\nWindows: %lu\nSubviews: %lu",
                         DKClassName(selectedView),
                         DKStringFromPointer((__bridge const void *)selectedView),
                         selectedView ? NSStringFromCGRect(selectedView.frame) : @"",
                         selectedView ? NSStringFromCGRect(selectedView.bounds) : @"",
                         nearestVC ? DKClassName(nearestVC) : @"",
                         nearestVC ? DKStringFromPointer((__bridge const void *)nearestVC) : @"",
                         (unsigned long)windows.count,
                         (unsigned long)selectedView.subviews.count];

    context.metadata = DKDebugMetadata(targetWindow, point);
    context.windowsJSON = windowsJSON;
    context.viewTreeJSON = treeJSON;
    context.viewTreeText = treeText;
    context.selectedViewJSON = selected;
    context.viewControllersText = vcText;
    context.layersJSON = layersJSON;
    context.screenshotPNG = DKScreenshotPNG(targetWindow);
    context.summary = summary;
    context.pageClassNames = pageClasses.allObjects;
    context.sourceView = targetWindow;
    context.presenter = DKDebugTopPresenter(targetWindow);
    return context;
}
