// 移植自 Si-yi/DYads- b97c05e（DYYYFeedTopTabStyle.h）：改名一律 DYYY -> DKXS，逻辑原样。
#import <UIKit/UIKit.h>

@interface DKXSFeedTopTabStyle : NSObject
+ (void)preparePreferences;
+ (void)applyToTextView:(UIView *)view;
+ (void)refreshVisibleTitles;
@end
