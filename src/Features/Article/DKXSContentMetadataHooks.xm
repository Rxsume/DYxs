// 移植自 Si-yi/DYads- 3819b4c（DYYYContentMetadataHooks.xm）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样。
// 上游 0ee4792 把 DKXSHideContentCreationInfo 的默认值登记从已删的 DoubleColumnDetailHooks 移到本文件
// %ctor（上游 @YES）；DYxs 移植惯例全部默认关，此处登记 @NO（未登记时 boolForKey 本就取 NO，登记只为显式）。
// 须先 import UIKit：下方的最小接口声明以 UICollectionViewCell 为父类，
// 未引入 UIKit 时编译器找不到父类接口（0.6.9.20 CI run #121 的教训，PR #32 已修）。
#import <UIKit/UIKit.h>
#import "DKXSContentMetadata.h"
#import "DKXSChatEnhancementPolicy.h"


// 最小接口声明：原生 Swift 类 AWEKnowledgeRichContentImpl.FullPageFeedCreationInfoCell
// 的占位类（%init 绑定真实类；hook 的 layoutSubviews/didMoveToWindow 为 UIView 方法）。
@interface DKXSRichCreationInfoCell : UICollectionViewCell
@end

%group DKXSContentMetadataHooks
%hook DKXSRichCreationInfoCell
- (void)layoutSubviews { %orig; [DKXSContentMetadata synchronize:self]; }
- (void)didMoveToWindow { %orig; [DKXSContentMetadata synchronize:self]; }
%end
%end

@implementation DKXSContentMetadata (Hooks)
+ (void)installHooks {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self installHooks]; }); return; }
    static BOOL installed;
    Class cell = NSClassFromString(@"AWEKnowledgeRichContentImpl.FullPageFeedCreationInfoCell");
    if (!installed && [cell isSubclassOfClass:UICollectionViewCell.class] &&
        [DKXSChatEnhancementPolicy class:cell selector:@selector(layoutSubviews) result:'v' arguments:@""] &&
        [DKXSChatEnhancementPolicy class:cell selector:@selector(didMoveToWindow) result:'v' arguments:@""]) {
        %init(DKXSContentMetadataHooks, DKXSRichCreationInfoCell = cell); installed = YES;
    }
}
@end
%ctor {
    [NSUserDefaults.standardUserDefaults registerDefaults:@{ @"DKXSHideContentCreationInfo":@NO }];
    [DKXSContentMetadata installHooks];
}
