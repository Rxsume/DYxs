#import "DKXSSettingsHelper.h"
#import "DKXSAwemeHeaders.h"
#import "DKXSUtils.h"
#import <objc/runtime.h>

static char kDKXSViewModelKey;

@implementation DKXSSettingsHelper

+ (BOOL)getUserDefaults:(NSString *)key {
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

+ (void)setUserDefaults:(id)object forKey:(NSString *)key {
    if (!key) return;
    if (object) [[NSUserDefaults standardUserDefaults] setObject:object forKey:key];
    else [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
}

+ (UIViewController *)topViewController {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class]) {
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) { window = w; break; }
            }
        }
        if (window) break;
    }
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

+ (void)showTextInputAlert:(NSString *)title
               defaultText:(NSString *)defaultText
               placeholder:(NSString *)placeholder
                 onConfirm:(void (^)(NSString *text))onConfirm
                  onCancel:(void (^)(void))onCancel {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.text = defaultText ?: @"";
            field.placeholder = placeholder ?: @"";
        }];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *a) { if (onCancel) onCancel(); }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            if (onConfirm) onConfirm(alert.textFields.firstObject.text ?: @"");
        }]];
        UIViewController *top = [self topViewController];
        if (top) [top presentViewController:alert animated:YES completion:nil];
    });
}

+ (id)createSettingItem:(NSDictionary *)dict {
    AWESettingItemModel *item = [[NSClassFromString(@"AWESettingItemModel") alloc] init];
    item.identifier = dict[@"identifier"];
    item.title = dict[@"title"];
    item.subTitle = dict[@"subTitle"];
    id saved = [[NSUserDefaults standardUserDefaults] objectForKey:item.identifier];
    item.detail = [saved isKindOfClass:NSString.class] ? saved : @"";
    item.svgIconImageName = dict[@"imageName"];
    item.cellType = [dict[@"cellType"] integerValue];
    item.colorStyle = 0;
    item.isEnable = YES;
    item.isSwitchOn = [self getUserDefaults:item.identifier];
    if (item.cellType == 6 || item.cellType == 37) {
        __weak AWESettingItemModel *weakItem = item;
        item.switchChangedBlock = ^{
            __strong AWESettingItemModel *strongItem = weakItem;
            if (!strongItem || !strongItem.isEnable) return;
            BOOL isSwitchOn = !strongItem.isSwitchOn;
            strongItem.isSwitchOn = isSwitchOn;
            [self setUserDefaults:@(isSwitchOn) forKey:strongItem.identifier];
        };
    }
    return item;
}

+ (id)createSectionWithTitle:(NSString *)title items:(NSArray *)items {
    return [self createSectionWithTitle:title footerTitle:nil items:items];
}

+ (id)createSectionWithTitle:(NSString *)title footerTitle:(NSString *)footerTitle items:(NSArray *)items {
    AWESettingSectionModel *section = [[NSClassFromString(@"AWESettingSectionModel") alloc] init];
    section.sectionHeaderTitle = title;
    section.sectionHeaderHeight = 40;
    section.sectionFooterTitle = footerTitle;
    section.useNewFooterLayout = YES;
    section.type = 0;
    section.itemArray = items;
    return section;
}

+ (UIViewController *)createSubSettingsViewController:(NSString *)title sections:(NSArray *)sectionsArray {
    AWESettingBaseViewController *settingsVC = [[NSClassFromString(@"AWESettingBaseViewController") alloc] init];
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([settingsVC.view isKindOfClass:UIView.class]) {
            Class navBarClass = NSClassFromString(@"AWENavigationBar");
            for (UIView *subview in settingsVC.view.subviews) {
                if (navBarClass && [subview isKindOfClass:navBarClass]) {
                    id navigationBar = subview;
                    if ([navigationBar respondsToSelector:@selector(titleLabel)]) {
                        UILabel *label = [navigationBar valueForKey:@"titleLabel"];
                        label.text = title;
                    }
                    break;
                }
            }
        }
    });
    AWESettingsViewModel *viewModel = [[NSClassFromString(@"AWESettingsViewModel") alloc] init];
    viewModel.colorStyle = 0;
    viewModel.sectionDataArray = sectionsArray;
    objc_setAssociatedObject(settingsVC, &kDKXSViewModelKey, viewModel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return settingsVC;
}

+ (UIViewController *)findViewController:(UIResponder *)responder {
    while (responder) {
        if ([responder isKindOfClass:UIViewController.class]) return (UIViewController *)responder;
        responder = responder.nextResponder;
    }
    return nil;
}

@end
