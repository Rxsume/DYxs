//
//  DKXSBatch3bSidebarMessageSearch.xm
//  DYxs — 第 3 批 staging（尚未并入 DYxs 源码）
//  移植自上游 Wtrwx/DYYY（head 49867e1，2026-10-25）DYYY.xm，类/函数前缀 DYYY -> DKXS，
//  设置键 DYYY* -> DKXS*。抖音类名、ivar 名、accessibilityLabel 文案保持原样。
//  本文件不 import 上游 AwemeHeaders.h；只用 UIKit + objc/runtime + 最小前置声明。
//  详见同目录 REPORT.md（冲突核查、删减说明、布局建议）。
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#define DKXSGetBool(key) [[NSUserDefaults standardUserDefaults] boolForKey:key]

%hook AFDSkylightCellBubble
- (void)layoutSubviews {
    if (DKXSGetBool(@"DKXSHideAvatarBubble")) {
        [self removeFromSuperview];
    }
    %orig;
}
%end

%hook AWEIMMessageTabOptPushBannerView

- (instancetype)initWithFrame:(CGRect)frame {
    if (DKXSGetBool(@"DKXSHidePushBanner")) {
        return %orig(CGRectMake(frame.origin.x, frame.origin.y, 0, 0));
    }
    return %orig;
}

%end

%hook AWEIMMessageTabSideBarView
- (void)layoutSubviews {
    %orig;

    if (!DKXSGetBool(@"DKXSHideMessageTabRedPacket")) {
        return;
    }

    UIView *parentView = self.superview;
    if (!parentView) {
        return;
    }

    NSArray<UIView *> *siblings = [parentView.subviews copy];
    if (siblings.count <= 1) {
        return;
    }

    for (UIView *subview in siblings) {
        if (subview != self) {
            [subview removeFromSuperview];
        }
    }
}
%end

%hook AWEProfileNavigationButton
- (void)setupUI {

    if (DKXSGetBool(@"DKXSHideButton")) {
        return;
    }
    %orig;
}
%end

%hook AWEFeedUnfollowFamiliarFollowAndDislikeView
- (void)showUnfollowFamiliarView {
    if (DKXSGetBool(@"DKXSHideFamiliar")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook AWEPlayInteractionStrongifyShareContentView

- (void)layoutSubviews {
    %orig;
    if (DKXSGetBool(@"DKXSHideShareContentView")) {
        UIView *parentView = self.superview;
        if (parentView) {
            parentView.hidden = YES;
        } else {
            self.hidden = YES;
        }
    }
}

%end

%hook AWELeftSideBarEntranceView

- (void)setRedDot:(id)redDot {
    // 偏离上游：上游此处无条件 %orig(nil)。改为仅在开关开时清零，否则开关形同虚设（见 REPORT.md）。
    if (DKXSGetBool(@"DKXSHideSidebarDot")) {
        %orig(nil);
    } else {
        %orig(redDot);
    }
}

- (void)setNumericalRedDot:(id)numericalRedDot {
    // 同上：上游无条件 %orig(nil)，改为开关门控。
    if (DKXSGetBool(@"DKXSHideSidebarDot")) {
        %orig(nil);
    } else {
        %orig(numericalRedDot);
    }
}

- (void)layoutSubviews {
    %orig;

    // 偏离上游：上游此处无条件隐藏 badge。改为仅在开关开时隐藏（见 REPORT.md）。
    if (DKXSGetBool(@"DKXSHideSidebarDot")) {
        for (UIView *subview in self.subviews) {
            if ([subview isKindOfClass:%c(DUXBadge)]) {
                subview.hidden = YES;
                break;
            }
        }
    }

    UIResponder *responder = self;
    UIViewController *parentVC = nil;
    while ((responder = [responder nextResponder])) {
        if ([responder isKindOfClass:%c(AWEFeedContainerViewController)]) {
            parentVC = (UIViewController *)responder;
            break;
        }
    }

    if (!(parentVC && [[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSHideLeftSideBar"])) {
        return;
    }

    static char kDKXSLeftSideViewCacheKey;
    NSArray *cachedViews = objc_getAssociatedObject(self, &kDKXSLeftSideViewCacheKey);
    if (!cachedViews) {
        NSMutableArray *views = [NSMutableArray array];
        for (UIView *subview in self.subviews) {
            if ([subview isKindOfClass:%c(DUXBaseImageView)]) {
                [views addObject:subview];
            }
        }
        cachedViews = [views copy];
        objc_setAssociatedObject(self, &kDKXSLeftSideViewCacheKey, cachedViews, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    for (UIView *v in cachedViews) {
        v.hidden = YES;
    }
}

%end

%hook AWEIMSkylightListView
- (void)setFrame:(CGRect)frame {
    if (DKXSGetBool(@"DKXSHideAvatarList")) {
        CGFloat scale = [UIScreen mainScreen].scale ?: 2.0;
        CGFloat minH = MAX(1.0 / scale, 0.5);
        frame.size.height = minH;
    }
    %orig(frame);
}
%end

%hook AWEHPSearchBubbleEntranceView
- (void)layoutSubviews {
    %orig;

    if (DKXSGetBool(@"DKXSHideSearchBubble")) {
        [self removeFromSuperview];
        return;
    }
}

%end

%hook AWEPlayInteractionSearchAnchorView

- (void)layoutSubviews {
    if (DKXSGetBool(@"DKXSHideInteractionSearch")) {
        [self removeFromSuperview];
        return;
    }
    %orig;
}

%end

%hook AWEDiscoverFeedEntranceView
- (id)init {
    if (DKXSGetBool(@"DKXSHideInteractionSearch")) {
        return nil;
    }
    return %orig;
}
%end

%hook AWESearchEntranceView

- (void)layoutSubviews {

    if (DKXSGetBool(@"DKXSHideSearchEntrance")) {
        self.hidden = YES;
        return;
    }
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSHideSearchEntranceIndicator"]) {
        static char kDKXSSearchIndicatorKey;
        NSArray *indicatorViews = objc_getAssociatedObject(self, &kDKXSSearchIndicatorKey);
        if (!indicatorViews) {
            NSMutableArray *tmp = [NSMutableArray array];
            for (UIView *subviews in self.subviews) {
                if ([subviews isKindOfClass:%c(UIImageView)] && [NSStringFromClass([((UIImageView *)subviews).image class]) isEqualToString:@"_UIResizableImage"]) {
                    [tmp addObject:subviews];
                }
            }
            indicatorViews = [tmp copy];
            objc_setAssociatedObject(self, &kDKXSSearchIndicatorKey, indicatorViews, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }

        for (UIImageView *imgView in indicatorViews) {
            imgView.hidden = YES;
        }
    }

    %orig;
}

%end

%hook AWEHPDiscoverFeedEntranceView

- (void)layoutSubviews {
    %orig;

    if (DKXSGetBool(@"DKXSHideDiscover")) {
        UIView *firstSubview = self.subviews.firstObject;
        if ([firstSubview isKindOfClass:[UIImageView class]]) {
            ((UIImageView *)firstSubview).image = nil;
        }
    }
}

%end

%hook ACCStickerContainerView
- (void)layoutSubviews {
    %orig;
    if (DKXSGetBool(@"DKXSHideSearchSame")) {
        [self removeFromSuperview];
    }
}
%end

%hook AWENewLiveSkylightViewController

- (void)showSkylight:(BOOL)arg0 animated:(BOOL)arg1 actionMethod:(unsigned long long)arg2 {
    if (DKXSGetBool(@"DKXSHideLiveView")) {
        return;
    }
    %orig(arg0, arg1, arg2);
}

- (void)updateIsSkylightShowing:(BOOL)arg0 {
    if (DKXSGetBool(@"DKXSHideLiveView")) {
        %orig(NO);
    } else {
        %orig(arg0);
    }
}

%end

%hook AWELiveSkylightViewModel

- (id)dataSource {
	BOOL DKXSHideConcernCapsuleView = DKXSGetBool(@"DKXSHideConcernCapsuleView");
	if (DKXSHideConcernCapsuleView) {
		return nil;
	}
	return %orig;
}

- (void)setDataSource:(id)dataSource {
	BOOL DKXSHideConcernCapsuleView = DKXSGetBool(@"DKXSHideConcernCapsuleView");
	if (DKXSHideConcernCapsuleView) {
		%orig(nil);
		return;
	}
	%orig;
}

%end

%hook AWELiveAutoEnterStyleAView

- (void)layoutSubviews {
    %orig;

    if (DKXSGetBool(@"DKXSHideLiveView")) {
        self.hidden = YES;
        return;
    }
}

%end

%hook AWENearbyFullScreenViewModel

- (void)setShowSkyLight:(id)arg1 {
    if (DKXSGetBool(@"DKXSHideMenuView")) {
        arg1 = nil;
    }
    %orig(arg1);
}

- (void)setHaveSkyLight:(id)arg1 {
    if (DKXSGetBool(@"DKXSHideMenuView")) {
        arg1 = nil;
    }
    %orig(arg1);
}

%end

%hook AWENearbySkyLightCapsuleView
- (void)layoutSubviews {
    if (DKXSGetBool(@"DKXSHideNearbyCapsuleView")) {
        [self removeFromSuperview];
        return;
    }
    %orig;
}
%end

%hook AWELiveFeedStatusLabel
- (void)layoutSubviews {
    if (DKXSGetBool(@"DKXSHideEnterLive")) {
        UIView *parentView = self.superview;
        UIView *grandparentView = parentView.superview;

        if (grandparentView) {
            grandparentView.hidden = YES;
            return;
        } else if (parentView) {
            parentView.hidden = YES;
            return;
        } else {
            self.hidden = YES;
            return;
        }
    }
    %orig;
}
%end

%hook AWELiveFeedLabelTagView
- (void)layoutSubviews {

    if (DKXSGetBool(@"DKXSHideLiveCapsuleView")) {
        UIView *parentView = self.superview;
        if (parentView) {
            parentView.hidden = YES;
            return;
        } else {
            self.hidden = YES;
            return;
        }
    }
    %orig;
}

%end

%hook AWEPlayInteractionLiveExtendGuideView
- (void)layoutSubviews {
    if (DKXSGetBool(@"DKXSHideLiveCapsuleView")) {
        [self removeFromSuperview];
        return;
    }
    %orig;
}
%end

%hook AWEHPTopTabItemBadgeContentView
- (void)layoutSubviews {
    if (DKXSGetBool(@"DKXSHideConcernCapsuleView")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook AWEIMFansGroupTopDynamicDomainTemplateView
- (void)layoutSubviews {
    if (DKXSGetBool(@"DKXSHideGroupShop")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook AWEIMCellLiveStatusContainerView

- (void)p_initUI {
    if (!DKXSGetBool(@"DKXSHideGroupLiveIndicator"))
        %orig;
}
%end

%hook AWELiveStatusIndicatorView

- (void)layoutSubviews {
    if (DKXSGetBool(@"DKXSHideGroupLiveIndicator")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook AWEIMInputActionBarInteractor

- (void)p_setupUI {
    if (DKXSGetBool(@"DKXSHideGroupInputActionBar")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook AWEProfileMixItemCollectionViewCell
- (void)layoutSubviews {
    %orig;
    if (DKXSGetBool(@"DKXSHidePostView")) {
        if ([self.accessibilityLabel isEqualToString:@"私密作品"]) {
            self.hidden = YES;
            return;
        }
    }
}
%end

%hook AWEProfilePostEmptyPublishGuideCollectionViewCell

- (void)didMoveToSuperview {
    %orig;
    if (DKXSGetBool(@"DKXSHidePostView")) {
        if ([(UIView *)self superview]) {
            [(UIView *)self setHidden:YES];
        }
    }
}

%end

%hook AWEProfileTaskCardStyleListCollectionViewCell
- (BOOL)shouldShowPublishGuide {
    if (DKXSGetBool(@"DKXSHidePostView")) {
        return NO;
    }
    return %orig;
}
%end

%hook AWEProfileRichEmptyView

- (void)setTitle:(id)title {
    if (DKXSGetBool(@"DKXSHidePostView")) {
        return;
    }
    %orig(title);
}

- (void)setDetail:(id)detail {
    if (DKXSGetBool(@"DKXSHidePostView")) {
        return;
    }
    %orig(detail);
}
%end

static NSString *const kDKXSHideRecentAppsKey = @"DKXSHideSidebarRecentApps";
static NSString *const kDKXSHideRecentUsersKey = @"DKXSHideSidebarRecentUsers";

%hook AWELeftSideBarModel

- (NSArray *)moduleModels {
    NSArray *originalModels = %orig;

    BOOL shouldHideRecentApps = DKXSGetBool(kDKXSHideRecentAppsKey);
    BOOL shouldHideRecentUsers = DKXSGetBool(kDKXSHideRecentUsersKey);

    if (!shouldHideRecentApps && !shouldHideRecentUsers) {
        return originalModels;
    }

    NSMutableArray *filteredModels = [NSMutableArray arrayWithCapacity:originalModels.count];

    for (id moduleModel in originalModels) {
        if ([moduleModel respondsToSelector:@selector(moduleID)]) {
            NSString *moduleID = [moduleModel moduleID];

            if (shouldHideRecentApps && [moduleID isEqualToString:@"recently_apps_module"]) {
                continue;
            }

            if (shouldHideRecentUsers && [moduleID isEqualToString:@"recently_users_module"]) {
                continue;
            }
        }

        id filteredModule = [self filterModuleItems:moduleModel];
        if (filteredModule) {
            [filteredModels addObject:filteredModule];
        }
    }

    return [filteredModels copy];
}

%new
- (id)filterModuleItems:(id)moduleModel {
    if (![moduleModel respondsToSelector:@selector(items)] || ![moduleModel respondsToSelector:@selector(moduleID)]) {
        return moduleModel;
    }

    NSString *moduleID = [moduleModel moduleID];
    NSArray *originalItems = [moduleModel items];

    if ([moduleID isEqualToString:@"top_area"]) {
        // 只保留天气、设置、扫一扫
        NSMutableArray *filteredItems = [NSMutableArray array];

        for (id item in originalItems) {
            if ([item respondsToSelector:@selector(businessType)]) {
                NSString *businessType = [item businessType];

                // 保留需要的组件
                if ([businessType isEqualToString:@"weather_time_tip_component"] || [businessType isEqualToString:@"setting_page_component"] ||
                    [businessType isEqualToString:@"top_area_vertical_cell"]) {
                    [filteredItems addObject:item];
                }
            }
        }

        // 创建新的模块对象，保持原有属性但更新items
        if ([moduleModel respondsToSelector:@selector(copy)]) {
            id newModule = [moduleModel copy];
            if ([newModule respondsToSelector:@selector(setItems:)]) {
                [newModule setItems:[filteredItems copy]];
            }
            return newModule;
        }
    }

    return moduleModel;
}

%end


%ctor {
    %init;
}
