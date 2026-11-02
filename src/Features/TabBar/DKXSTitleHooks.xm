//
//  DKXSTitleHooks.xm
//  DYxs（优先小批 staging，尚未并入 DYxs 源码）
//
//  移植来源：Wtrwx/DYYY 的 DYYY.xm 三段标题 hook（逻辑原样移植，仅改名）：
//  1. AWEHPTopTabItemTextContentView layoutSubviews + 顶栏标题映射函数
//     （键 DKXSModifyTopTabText，格式“原标题=新标题”，多组用 # 分隔，
//     上游 DYYYSettings.xm 的 detail 即“标题=修改#标题=修改”）。
//  2. AWENormalModeTabBarTextView layoutSubviews（键 DKXSIndexTitle、
//     DKXSFriendsTitle、DKXSMsgTitle、DKXSSelfTitle，匹配“首页/朋友/消息/我”）。
//  3. AWENormalModeTabBarFeedView layoutSubviews（仅首页标题部分；
//     上游同函数前半段是“隐藏双列入口”键的逻辑，那部分属于隐藏批，
//     本文件刻意不带，见 REPORT）。
//  不 import 上游 AwemeHeaders 与 DouyinHeaders；Logos %hook 不需要类声明。
//  冲突核查：第 1、3 段在 DYxs 里零冲突；第 2 段与 DYxs 现有
//  DKGlassTabBar、DKTabBarAppearance 的同类 layoutSubviews 同方法，
//  沿用 DYxs 已有的 Logos %orig 链做法（第 1 批评论容器已有此先例），
//  三处均调 %orig，不吞现有玻璃/外观效果。
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 最小接口声明：以下被 hook 的类在本文件内读写 UIView/NSObject 成员（hidden、alpha、superview、subviews、tag、window 等）或调用同文件 %new 方法，
// 原先只有 Logos 前置声明，编译器找不到这些成员；基类按视图身份声明为 UIView（模型类为 NSObject），不 import DouyinHeaders。
@interface AWENormalModeTabBarFeedView : UIView
@end
@interface AWENormalModeTabBarTextView : UIView
@end
@interface AWEHPTopTabItemTextContentView : UIView
- (void)setContentText:(id)contentText;
@end

static NSDictionary<NSString *, NSString *> *DKXSTopTabTitleMapping(void) {
    static NSString *cachedRawValue = nil;
    static NSDictionary<NSString *, NSString *> *cachedMapping = nil;

    NSString *currentValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSModifyTopTabText"];
    BOOL rawValueChanged = (cachedRawValue != currentValue) && ![cachedRawValue isEqualToString:currentValue];

    if (!rawValueChanged) {
        return cachedMapping;
    }

    cachedRawValue = [currentValue copy];

    if (currentValue.length == 0) {
        cachedMapping = nil;
        return nil;
    }

    NSMutableDictionary<NSString *, NSString *> *mapping = [NSMutableDictionary dictionary];
    NSArray<NSString *> *titlePairs = [currentValue componentsSeparatedByString:@"#"];
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];

    for (NSString *pair in titlePairs) {
        NSArray<NSString *> *components = [pair componentsSeparatedByString:@"="];
        if (components.count != 2) {
            continue;
        }

        NSString *originalTitle = [components[0] stringByTrimmingCharactersInSet:whitespace];
        NSString *newTitle = [components[1] stringByTrimmingCharactersInSet:whitespace];

        if (originalTitle.length == 0 || newTitle.length == 0) {
            continue;
        }
        mapping[originalTitle] = newTitle;
    }

    cachedMapping = [mapping copy];
    return cachedMapping;
}

%hook AWEHPTopTabItemTextContentView

- (void)layoutSubviews {
    %orig;
    NSDictionary<NSString *, NSString *> *titleMapping = DKXSTopTabTitleMapping();
    if (titleMapping.count == 0) {
        return;
    }

    NSString *accessibilityLabel = nil;
    if ([self.superview respondsToSelector:@selector(accessibilityLabel)]) {
        accessibilityLabel = self.superview.accessibilityLabel;
    }
    if (accessibilityLabel.length == 0) {
        return;
    }

    NSString *newTitle = titleMapping[accessibilityLabel];
    if (newTitle.length == 0) {
        return;
    }

    if ([self respondsToSelector:@selector(setContentText:)]) {
        [self setContentText:newTitle];
    } else {
        [self setValue:newTitle forKey:@"contentText"];
    }
}

%end

%hook AWENormalModeTabBarTextView

- (void)layoutSubviews {
    @try {
        %orig;

        if (![NSThread isMainThread]) {
            dispatch_async(dispatch_get_main_queue(), ^{
              [self layoutSubviews];
            });
            return;
        }

        if (!self || !self.superview) {
            return;
        }

        NSString *indexTitle = [[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSIndexTitle"];
        NSString *friendsTitle = [[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSFriendsTitle"];
        NSString *msgTitle = [[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSMsgTitle"];
        NSString *selfTitle = [[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSSelfTitle"];

        if (!(indexTitle.length || friendsTitle.length || msgTitle.length || selfTitle.length)) {
            return;
        }

        static char kDKXSTabTextLabelCacheKey;
        NSArray *labelCache = objc_getAssociatedObject(self, &kDKXSTabTextLabelCacheKey);
        if (!labelCache) {
            NSMutableArray *tmp = [NSMutableArray array];
            if (!tmp) {
                return;
            }
            NSArray *subviews = [self subviews];
            if (!subviews) {
                return;
            }
            for (UIView *subview in subviews) {
                if (subview && [subview isKindOfClass:[UILabel class]]) {
                    [tmp addObject:subview];
                }
            }
            labelCache = [tmp copy];
            if (labelCache) {
                objc_setAssociatedObject(self, &kDKXSTabTextLabelCacheKey, labelCache, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }

        if (!labelCache) {
            return;
        }

        for (UILabel *label in labelCache) {
            if (!label || ![label isKindOfClass:[UILabel class]]) {
                continue;
            }
            NSString *labelText = label.text;
            if (!labelText) {
                continue;
            }
            if ([labelText isEqualToString:@"首页"] && indexTitle.length > 0) {
                label.text = indexTitle;
                dispatch_async(dispatch_get_main_queue(), ^{
                  [self setNeedsLayout];
                });
            } else if ([labelText isEqualToString:@"朋友"] && friendsTitle.length > 0) {
                label.text = friendsTitle;
                dispatch_async(dispatch_get_main_queue(), ^{
                  [self setNeedsLayout];
                });
            } else if ([labelText isEqualToString:@"消息"] && msgTitle.length > 0) {
                label.text = msgTitle;
                dispatch_async(dispatch_get_main_queue(), ^{
                  [self setNeedsLayout];
                });
            } else if ([labelText isEqualToString:@"我"] && selfTitle.length > 0) {
                label.text = selfTitle;
                dispatch_async(dispatch_get_main_queue(), ^{
                  [self setNeedsLayout];
                });
            }
        }
    } @catch (NSException *exception) {
        return;
    }
}

%end

%hook AWENormalModeTabBarFeedView

- (void)layoutSubviews {
    @try {
        %orig;
        if (![NSThread isMainThread]) {
            dispatch_async(dispatch_get_main_queue(), ^{
              [self layoutSubviews];
            });
            return;
        }

        if (!self || !self.superview) {
            return;
        }

        NSString *indexTitle = [[NSUserDefaults standardUserDefaults] objectForKey:@"DKXSIndexTitle"];
        if (!(indexTitle.length)) {
            return;
        }

        static char kDKXSTabFeedLabelCacheKey;
        NSArray *labelCache = objc_getAssociatedObject(self, &kDKXSTabFeedLabelCacheKey);
        if (!labelCache) {
            NSMutableArray *tmp = [NSMutableArray array];
            if (!tmp) {
                return;
            }
            NSArray *subviews = [self subviews];
            if (!subviews) {
                return;
            }
            for (UIView *subview in subviews) {
                if (subview && [subview isKindOfClass:[UILabel class]]) {
                    [tmp addObject:subview];
                }
            }
            labelCache = [tmp copy];
            if (labelCache) {
                objc_setAssociatedObject(self, &kDKXSTabFeedLabelCacheKey, labelCache, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }

        if (!labelCache) {
            return;
        }

        for (UILabel *label in labelCache) {
            if (!label || ![label isKindOfClass:[UILabel class]]) {
                continue;
            }
            NSString *labelText = label.text;
            if (!labelText) {
                continue;
            }
            if ([labelText isEqualToString:@"首页"] && indexTitle.length > 0) {
                label.text = indexTitle;
                dispatch_async(dispatch_get_main_queue(), ^{
                  [self setNeedsLayout];
                });
            }
        }
    } @catch (NSException *exception) {
        return;
    }
}

%end

%ctor {
    %init;
}
