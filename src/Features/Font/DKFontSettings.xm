//
//  DKFontSettings.xm
//  字体：设置入口 —— 导入字体文件（.ttf/.otf/.ttc）与恢复默认字体。
//  文件选择器沿用图标导入的 UIDocumentPicker 形态；导入后新打开的页面生效。
//

#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKFontStore.h"
#import "DKSettings.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>

static char kDKFontPickerRelay;
static BOOL gDKFontPickerBusy;

static void DKFontShowAlert(UIViewController *presenter, NSString *title, NSString *message) {
    if (!presenter.view.window) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

@interface DKFontPickerRelay : NSObject <UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate>
@property (nonatomic, weak) UIViewController *presenter;
@end

@implementation DKFontPickerRelay

- (void)importURL:(NSURL *)url {
    BOOL access = [url startAccessingSecurityScopedResource];
    NSNumber *length = nil;
    [url getResourceValue:&length forKey:NSURLFileSizeKey error:NULL];
    NSData *data = url && length && length.unsignedLongLongValue <= 32 * 1024 * 1024
        ? [NSData dataWithContentsOfURL:url options:0 error:NULL] : nil;
    if (access) [url stopAccessingSecurityScopedResource];
    NSString *fileName = url.lastPathComponent ?: @"";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *reason = nil;
        BOOL ok = DKFontStoreData(data, fileName, &reason);
        dispatch_async(dispatch_get_main_queue(), ^{
            gDKFontPickerBusy = NO;
            DKFontShowAlert(self.presenter, ok ? @"字体已导入" : @"无法导入字体",
                            ok ? @"新导入的字体会在新打开的页面生效，正在显示的页面重新打开后生效。"
                               : (reason ?: @"无法读取字体文件"));
        });
    });
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    [controller dismissViewControllerAnimated:YES completion:^{
        [self importURL:url];
    }];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    gDKFontPickerBusy = NO;
}

- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
    gDKFontPickerBusy = NO;
}

@end

static void DKFontPresentPicker(UIViewController *presenter) {
    if (!presenter.view.window || presenter.presentedViewController || gDKFontPickerBusy) return;
    gDKFontPickerBusy = YES;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[ UTTypeFont ] asCopy:YES];
    DKFontPickerRelay *relay = [[DKFontPickerRelay alloc] init];
    relay.presenter = presenter;
    picker.delegate = relay;
    objc_setAssociatedObject(picker, &kDKFontPickerRelay, relay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [presenter presentViewController:picker animated:YES completion:nil];
    picker.presentationController.delegate = relay;
}

static void DKFontConfirmRestore(UIViewController *presenter) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"恢复默认字体"
                                                                   message:@"移除已导入的字体文件，恢复抖音默认字体？"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        DKFontRestoreDefault();
        DKFontShowAlert(presenter, @"已恢复默认字体", @"正在显示的页面重新打开后生效。");
    }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

static void DKOpenFontPage(UIViewController *presenter) {
    NSString *current = DKFontCurrentDisplayName();
    AWESettingItemModel *currentRow = DKSettingsWithInfo(
        DKMakeAction(DKKeyFont, @"当前字体", current ?: @"未导入（系统默认）",
                     ^(__unused AWESettingItemModel *it, __unused UIViewController *p) {}),
        @"导入的字体会替换抖音界面里的系统字体（图标字体不受影响）。");

    AWESettingItemModel *importRow = DKMakeAction(DKKeyFontImport, @"导入字体文件", @"选择 .ttf / .otf / .ttc 文件",
        ^(__unused AWESettingItemModel *it, UIViewController *p) { DKFontPresentPicker(p); });
    AWESettingItemModel *restoreRow = DKMakeAction(DKKeyFontRestore, @"恢复默认字体", @"移除已导入的字体文件",
        ^(__unused AWESettingItemModel *it, UIViewController *p) { DKFontConfirmRestore(p); });

    NSMutableArray<AWESettingSectionModel *> *sections = [NSMutableArray array];
    [sections addObject:DKSettingsMakeSection(@"字体", nil, @[ currentRow, importRow, restoreRow ])];
    DKSettingsPushNotedSections(presenter, @"字体", @"导入字体文件替换界面字体，或恢复默认字体。", sections);
}

%ctor {
    DKSettingsRegister(DKKeyFont, ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeAction(DKKeyFont, @"字体", nil,
            ^(__unused AWESettingItemModel *it, UIViewController *presenter) { DKOpenFontPage(presenter); });
        return DKSettingsWithInfo(item, @"导入字体文件替换界面字体，或恢复默认字体。");
    });
}
