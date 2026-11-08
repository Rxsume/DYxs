// 移植自 Si-yi/DYads- b97c05e（DYYYContentBarAdapter.m）：改名一律 DYYY -> DKXS，逻辑原样。
#import "DKXSContentBarAdapter.h"
#import <math.h>

@implementation DKXSContentBarAdapter
+ (BOOL)isRichHost:(UIViewController *)host {
    Class cls = NSClassFromString(@"AWEKnowledgeRichContentImpl.FullPageFeedTabListViewController");
    return cls && [host isKindOfClass:cls];
}
+ (BOOL)isVisible:(UIView *)view in:(UIView *)root {
    if (!view || !root || ![view isDescendantOfView:root]) return NO;
    for (UIView *parent = view; parent; parent = parent.superview) {
        if (parent.hidden || parent.alpha <= 0.01) return NO;
        if (parent == root) return YES;
    }
    return NO;
}
+ (UIView *)directClass:(NSString *)name in:(UIView *)root {
    Class cls = NSClassFromString(name);
    if (!cls) return nil;
    for (UIView *view in root.subviews) if ([view isKindOfClass:cls]) return view;
    return nil;
}
+ (UIView *)topBarInHost:(UIViewController *)host {
    return [self isRichHost:host] ? [self directClass:@"AWEKnowledgeRichContentImpl.FullPageFeedTopBarView" in:host.viewIfLoaded] : nil;
}
+ (UIView *)bottomBarInHost:(UIViewController *)host {
    return [self isRichHost:host] ? [self directClass:@"AWEKnowledgeRichContentImpl.FullPageFeedBottomBarView" in:host.viewIfLoaded] : nil;
}
+ (UIScrollView *)viewportInHost:(UIViewController *)host {
    UIView *view = [self isRichHost:host] ? [self directClass:@"AWETabListContainerScrollView" in:host.viewIfLoaded] : nil;
    return [view isKindOfClass:UIScrollView.class] ? (id)view : nil;
}
+ (CGRect)textInk:(UIView *)view in:(UIView *)root {
    CGRect rect = view ? [view convertRect:view.bounds toView:root] : CGRectZero;
    if (![view isKindOfClass:UILabel.class]) return rect;
    UILabel *label = (id)view;
    CGSize fitted = [label sizeThatFits:label.bounds.size];
    CGFloat width = MIN(CGRectGetWidth(rect), MAX(0, ceil(fitted.width)));
    if (label.textAlignment == NSTextAlignmentCenter) rect.origin.x += (rect.size.width - width) * 0.5;
    else if (label.textAlignment == NSTextAlignmentRight) rect.origin.x += rect.size.width - width;
    rect.size.width = width;
    return rect;
}
+ (NSDictionary<NSString *, UIView *> *)topRoles:(UIView *)bar {
    if (![bar isKindOfClass:NSClassFromString(@"AWEKnowledgeRichContentImpl.FullPageFeedTopBarView")]) return @{};
    UIView *container = nil;
    NSMutableArray<UIImageView *> *icons = [NSMutableArray array];
    for (UIView *view in bar.subviews) {
        if (CGRectGetHeight(view.bounds) < 28 || CGRectGetHeight(view.bounds) > 72) continue;
        [icons removeAllObjects];
        for (UIView *child in view.subviews)
            if ([child isKindOfClass:UIImageView.class] && [self isVisible:child in:bar] &&
                CGRectGetWidth(child.bounds) >= 16 && CGRectGetWidth(child.bounds) <= 32) [icons addObject:(id)child];
        if (icons.count == 2) { container = view; break; }
    }
    if (!container) return @{};
    [icons sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) { return [@(CGRectGetMinX(a.frame)) compare:@(CGRectGetMinX(b.frame))]; }];
    NSMutableDictionary *roles = [@{ @"container":container, @"back":icons.firstObject, @"search":icons.lastObject } mutableCopy];
    NSMutableArray *queue = [NSMutableArray arrayWithArray:container.subviews];
    for (NSUInteger i = 0; i < queue.count && i < 32; i++) {
        UIView *view = queue[i];
        if (![self isVisible:view in:bar]) continue;
        NSString *name = NSStringFromClass(view.class);
        if ([name isEqual:@"_TtCC27AWEKnowledgeRichContentImpl22FullPageFeedTopBarView19AuthorContainerView"]) {
            for (UIView *child in view.subviews) {
                if (![self isVisible:child in:bar]) continue;
                if ([child isKindOfClass:UIImageView.class] && CGRectGetWidth(child.bounds) >= 32 && CGRectGetWidth(child.bounds) <= 48) roles[@"avatar"] = child;
                else if ([child isKindOfClass:UILabel.class]) roles[@"name"] = child;
                else if ([NSStringFromClass(child.class) isEqual:@"AWEKnowledgeRichContentImpl.FullPageFeedRelationButton"]) roles[@"follow"] = child;
            }
            // 头像和昵称容器只读，不对其内部遍历绘制背景。
            continue;
        }
        if ([name isEqual:@"IESSegmentedControl"]) { roles[@"center"] = view; continue; }
        if (![view isKindOfClass:UIImageView.class] && ![view isKindOfClass:UILabel.class]) [queue addObjectsFromArray:view.subviews];
    }
    return roles;
}
+ (NSDictionary<NSString *, UIView *> *)bottomRoles:(UIView *)bar {
    if (![bar isKindOfClass:NSClassFromString(@"AWEKnowledgeRichContentImpl.FullPageFeedBottomBarView")]) return @{};
    for (UIView *container in bar.subviews) {
        UIView *input = [self directClass:@"_TtCC27AWEKnowledgeRichContentImpl25FullPageFeedBottomBarView16CommentInputView" in:container];
        UIView *actions = [self directClass:@"UIStackView" in:container];
        if (input && actions && [self isVisible:input in:bar] && [self isVisible:actions in:bar])
            return @{ @"container":container, @"input":input, @"actions":actions };
    }
    return @{};
}
@end
