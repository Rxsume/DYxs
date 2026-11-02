//  DKXSRecallMediaView.m
//  DY778 第 1 批 staging：见头文件注释。

#import "DKXSRecallMediaView.h"
#import "DKXSRecallContent.h"
#import "DKXSArchiveCore.h"
#import <QuickLook/QuickLook.h>

@interface DKXSPreviewItem : NSObject <QLPreviewItem>
@property(nonatomic, copy) NSURL *previewItemURL;
@property(nonatomic, copy) NSString *previewItemTitle;
@end
@implementation DKXSPreviewItem
@end

static void DKXSLoadImageEphemeral(UIImageView *view, NSString *urlString, NSString *identity) {
    if (!urlString.length) return;
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];
    NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) return;
        UIImage *image = [UIImage imageWithData:data];
        if (!image) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![view.accessibilityIdentifier isEqualToString:identity ?: @""]) return;
            view.image = image;
        });
    }];
    view.accessibilityIdentifier = identity ?: @"";
    [task resume];
    objc_setAssociatedObject(view, @selector(cancel), task, OBJC_ASSOCIATION_RETAIN);
}

@interface DKXSRecallMediaView () <QLPreviewControllerDataSource>
@end

@implementation DKXSRecallMediaView {
    UIImageView *_imageView;
    UIButton *_openButton;
    NSDictionary *_record;
    NSURLSessionDataTask *_task;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _imageView = [UIImageView new];
        _imageView.contentMode = UIViewContentModeScaleAspectFit;
        _imageView.clipsToBounds = YES;
        [self addSubview:_imageView];
        _openButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_openButton setTitle:@"打开媒体预览" forState:UIControlStateNormal];
        [_openButton addTarget:self action:@selector(openTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_openButton];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _imageView.frame = CGRectMake(0, 0, self.bounds.size.width, MAX(0, self.bounds.size.height - 44));
    _openButton.frame = CGRectMake(0, self.bounds.size.height - 44, self.bounds.size.width, 44);
}
- (void)cancel { [_task cancel]; _task = nil; }
- (void)configureRecord:(NSDictionary *)record {
    _record = record;
    NSDictionary *media = DKXSRecallPrimaryMedia(record);
    NSString *remoteURL = media[@"remoteURL"];
    NSString *sourcePath = media[@"sourcePath"];
    if (sourcePath.length && [NSFileManager.defaultManager fileExistsAtPath:sourcePath]) {
        _imageView.image = [UIImage imageWithContentsOfFile:sourcePath];
        [_openButton setTitle:[NSString stringWithFormat:@"打开本地媒体（%@）", media[@"kind"] ?: @""] forState:UIControlStateNormal];
    } else if (remoteURL.length) {
        DKXSLoadImageEphemeral(_imageView, remoteURL, record[@"key"]);
        [_openButton setTitle:[NSString stringWithFormat:@"打开媒体预览（%@）", media[@"kind"] ?: @""] forState:UIControlStateNormal];
    } else {
        _imageView.image = nil;
        [_openButton setTitle:@"无可用媒体" forState:UIControlStateNormal];
        _openButton.enabled = NO;
    }
    [self setNeedsLayout];
}
- (void)openTapped {
    if (self.openMedia) { self.openMedia(DKXSRecallPrimaryMedia(_record) ?: @{}); return; }
    NSDictionary *media = DKXSRecallPrimaryMedia(_record);
    NSString *sourcePath = media[@"sourcePath"];
    NSString *remoteURL = media[@"remoteURL"];
    UIViewController *top = DKXSArchiveTopController();
    if (!top) return;
    if (sourcePath.length && [NSFileManager.defaultManager fileExistsAtPath:sourcePath]) {
        DKXSPreviewItem *item = [DKXSPreviewItem new];
        item.previewItemURL = [NSURL fileURLWithPath:sourcePath];
        item.previewItemTitle = media[@"name"] ?: @"媒体";
        QLPreviewController *preview = [QLPreviewController new];
        preview.dataSource = self;
        objc_setAssociatedObject(preview, @selector(openTapped), item, OBJC_ASSOCIATION_RETAIN);
        [top presentViewController:preview animated:YES completion:nil];
        return;
    }
    if (remoteURL.length) {
        // 远程媒体先用 ephemeral 会话下载到 tmp 再预览，不进相册、不留缓存。
        NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];
        NSURLSessionDownloadTask *task = [session downloadTaskWithURL:[NSURL URLWithString:remoteURL] completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
            if (error || !location) return;
            NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"dkxs-media-%@.%@", @((NSUInteger)NSDate.date.timeIntervalSince1970), [response.URL pathExtension]]];
            [NSFileManager.defaultManager copyItemAtURL:location toURL:[NSURL fileURLWithPath:tmp] error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                DKXSPreviewItem *item = [DKXSPreviewItem new];
                item.previewItemURL = [NSURL fileURLWithPath:tmp];
                item.previewItemTitle = media[@"name"] ?: @"媒体";
                QLPreviewController *preview = [QLPreviewController new];
                preview.dataSource = self;
                objc_setAssociatedObject(preview, @selector(openTapped), item, OBJC_ASSOCIATION_RETAIN);
                [top presentViewController:preview animated:YES completion:nil];
            });
        }];
        [task resume];
    }
}
#pragma mark - QLPreviewControllerDataSource
- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller {
    return objc_getAssociatedObject(controller, @selector(openTapped)) ? 1 : 0;
}
- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index {
    return objc_getAssociatedObject(controller, @selector(openTapped));
}
@end

@implementation DKXSRecallCoverView
- (void)configureRecord:(NSDictionary *)record {
    NSDictionary *media = DKXSRecallPrimaryMedia(record);
    NSString *sourcePath = media[@"sourcePath"];
    if (sourcePath.length && [NSFileManager.defaultManager fileExistsAtPath:sourcePath]) {
        self.image = [UIImage imageWithContentsOfFile:sourcePath];
    } else if ([media[@"remoteURL"] length]) {
        DKXSLoadImageEphemeral(self, media[@"remoteURL"], record[@"key"]);
    }
}
- (void)cancel {
    NSURLSessionDataTask *task = objc_getAssociatedObject(self, @selector(cancel));
    [task cancel];
}
@end
