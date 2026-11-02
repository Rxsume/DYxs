#import <UIKit/UIKit.h>

@interface DKXSAutoMessageQuietHoursPanel : UIViewController
+ (void)showFrom:(UIViewController *)presenter onChange:(void (^)(void))onChange;
@end
