//  DKXSArchiveNative.m
//  DY778 第 1 批 staging：见头文件注释。
//  定位机制与上游一致：先在可见 cell 里找，再用 listViewModel 的
//  indexPathOfMsgWithMsgID: / messageViewModelAtIndexPath: 查；
//  40.8.0 若这两个方法改名，定位静默失败（不崩溃），见 REPORT。

#import "DKXSArchiveNative.h"
#import "DKXSArchiveCore.h"
#import "DKXSRecallContent.h"
#import "DKXSMessageArchivePolicy.h"
#import <ImageIO/ImageIO.h>
#import <objc/message.h>

static id DKXSNativeInvoke(id target, NSString *name, NSArray *arguments) {
    SEL selector = NSSelectorFromString(name);
    if (![target respondsToSelector:selector]) return nil;
    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != arguments.count + 2) return nil;
    const char result = signature.methodReturnType[0];
    if (!strchr("@vBcqQ", result)) return nil;
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = target; invocation.selector = selector;
    for (NSUInteger index = 0; index < arguments.count; index++) {
        id value = arguments[index] == NSNull.null ? nil : arguments[index];
        const char type = [signature getArgumentTypeAtIndex:index + 2][0];
        if (type == '@' || type == '#') [invocation setArgument:&value atIndex:index + 2];
        else if (type == 'Q' || type == 'q' || type == 'B' || type == 'c') { long long number = [value longLongValue]; [invocation setArgument:&number atIndex:index + 2]; }
        else return nil;
    }
    @try {
        [invocation invoke];
        if (result == 'v') return @YES;
        if (result == '@') { __unsafe_unretained id value = nil; [invocation getReturnValue:&value]; return value; }
        if (result == 'B' || result == 'c') { BOOL value = NO; [invocation getReturnValue:&value]; return @(value); }
        long long value = 0; [invocation getReturnValue:&value]; return @(value);
    } @catch (__unused NSException *e) { return nil; }
}
static NSString *DKXSNativeString(id object, NSArray *fields) {
    for (NSString *field in fields) {
        NSString *value = DKXSArchiveIdentifier(DKXSArchiveRead(object, field));
        if (value.length && ![value isEqualToString:@"0"]) return value;
    }
    return @"";
}
BOOL DKXSArchiveCanLocate(NSDictionary *record) {
    return [record[@"account"] length] && [record[@"conversation"] length] &&
        (DKXSNativeString(record, @[@"messageID", @"serverID"]).length > 0);
}
static BOOL DKXSNativeMatches(id message, NSDictionary *record) {
    if (!message || ![record[@"account"] isEqual:DKXSArchiveCurrentAccountID()]) return NO;
    NSString *conversation = DKXSNativeString(message, @[@"belongingConversationIdentifier", @"conversationID"]);
    if (![conversation isEqual:record[@"conversation"]]) return NO;
    NSString *client = DKXSNativeString(message, @[@"identifier", @"messageID"]);
    NSString *server = DKXSNativeString(message, @[@"serverMessageID"]);
    return DKXSArchiveIdentityMatches([record[@"account"] UTF8String], DKXSArchiveCurrentAccountID().UTF8String,
        [record[@"conversation"] UTF8String], conversation.UTF8String, [DKXSArchiveIdentifier(record[@"messageID"]) UTF8String], client.UTF8String,
        [DKXSArchiveIdentifier(record[@"serverID"]) UTF8String], server.UTF8String);
}
static UIViewController *DKXSNativeList(UIViewController *controller, NSString *conversation, NSUInteger depth) {
    if (!controller || depth > 14) return nil;
    if ([controller isKindOfClass:NSClassFromString(@"AWEIMMessageListViewController")] &&
        [DKXSNativeString(DKXSArchiveRead(controller, @"conversation"), @[@"conversationID"]) isEqual:conversation]) return controller;
    for (UIViewController *child in controller.childViewControllers.reverseObjectEnumerator) {
        UIViewController *found = DKXSNativeList(child, conversation, depth + 1); if (found) return found;
    }
    return DKXSNativeList(controller.presentedViewController, conversation, depth + 1);
}
static NSString *DKXSNativePath(id value) {
    if (![value isKindOfClass:NSString.class] || ![value length]) return nil;
    NSString *path = value;
    if ([path hasPrefix:@"file://"]) path = [NSURL URLWithString:path].path;
    if (!path.isAbsolutePath) path = [NSHomeDirectory() stringByAppendingPathComponent:path];
    path = path.stringByStandardizingPath.stringByResolvingSymlinksInPath;
    if (![path hasPrefix:[NSHomeDirectory().stringByResolvingSymlinksInPath stringByAppendingString:@"/"]]) return nil;
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    return [attributes[NSFileType] isEqual:NSFileTypeRegular] && [attributes fileSize] > 0 &&
        [NSFileManager.defaultManager isReadableFileAtPath:path] ? path : nil;
}
static void DKXSNativeAddMedia(NSMutableArray *media, id value, NSString *kind) {
    if (!kind.length) return;
    NSString *path = DKXSNativePath(value); if (!path) return;
    for (NSDictionary *item in media) if ([item[@"sourcePath"] isEqual:path]) return;
    CGImageSourceRef image = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
    BOOL isImage = image && CGImageSourceGetCount(image) > 0; if (image) CFRelease(image);
    if ([kind isEqualToString:@"image"] && !isImage) return;
    NSString *actualKind = isImage ? @"image" : kind;
    [media addObject:@{@"kind": actualKind, @"sourcePath": path, @"quality": @1000, @"native": @YES,
        @"cover": @([kind isEqualToString:@"video"] && isImage), @"name": isImage ? @"本地图片" : @"本地媒体"}];
}
NSArray<NSDictionary *> *DKXSArchiveLocalMedia(NSDictionary *record) {
    if (!NSThread.isMainThread || ![record[@"account"] isEqual:DKXSArchiveCurrentAccountID()]) return @[];
    NSString *kind = DKXSRecallEnrichRecord(record)[@"card"][@"kind"];
    if (![@[@"image", @"video", @"audio"] containsObject:kind ?: @""]) return @[];
    UIViewController *list = DKXSNativeList(DKXSArchiveActiveWindow().rootViewController, record[@"conversation"], 0);
    UITableView *table = DKXSArchiveRead(list, @"tableView");
    NSMutableArray *media = [NSMutableArray array];
    if ([table isKindOfClass:UITableView.class]) for (UITableViewCell *cell in table.visibleCells) {
        id vm = DKXSArchiveRead(DKXSArchiveRead(cell, @"currentContext"), @"messageViewModel") ?: DKXSArchiveRead(cell, @"viewModel");
        id message = DKXSArchiveRead(vm, @"iesMessage") ?: DKXSArchiveRead(vm, @"message");
        if (!DKXSNativeMatches(message, record)) continue;
        DKXSNativeAddMedia(media, DKXSArchiveRead(message, @"filePath"), kind);
        DKXSNativeAddMedia(media, DKXSArchiveRead(DKXSArchiveRead(message, @"content"), @"localPath"), kind);
    }
    return media;
}
UIImage *DKXSArchivePreviewImage(NSDictionary *record) {
    NSArray *media = DKXSArchiveLocalMedia(record);
    for (NSDictionary *item in media) {
        if (![item[@"kind"] isEqualToString:@"image"]) continue;
        UIImage *image = [UIImage imageWithContentsOfFile:item[@"sourcePath"]];
        if (image) return image;
    }
    return nil;
}
void DKXSArchiveLocateMessage(UIViewController *source, NSDictionary *record) {
    if (!DKXSArchiveCanLocate(record) || ![record[@"account"] isEqual:DKXSArchiveCurrentAccountID()]) {
        DKXSArchiveToast(@"该记录暂无法定位到原会话"); return;
    }
    UIViewController *list = DKXSNativeList(DKXSArchiveActiveWindow().rootViewController, record[@"conversation"], 0);
    if (!list) {
        // 会话未打开时无法滚动定位：只提示，不擅自跳会话（避免打断用户当前操作）。
        DKXSArchiveToast(@"请先打开对应会话，再从记录页定位"); return;
    }
    UITableView *table = DKXSArchiveRead(list, @"tableView");
    id listModel = DKXSArchiveRead(list, @"listViewModel");
    for (NSString *identifier in @[DKXSNativeString(record, @[@"messageID"]), DKXSNativeString(record, @[@"serverID"])]) {
        if (!identifier.length) continue;
        id index = DKXSNativeInvoke(listModel, @"indexPathOfMsgWithMsgID:", @[identifier]);
        if (![index isKindOfClass:NSIndexPath.class]) continue;
        if ([table isKindOfClass:UITableView.class]) {
            [table scrollToRowAtIndexPath:index atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                UITableViewCell *cell = [table cellForRowAtIndexPath:index];
                if (cell) {
                    [UIView animateWithDuration:0.25 animations:^{ cell.contentView.backgroundColor = [UIColor.systemYellowColor colorWithAlphaComponent:0.35]; }
                                     completion:^(__unused BOOL finished) {
                        [UIView animateWithDuration:0.6 animations:^{ cell.contentView.backgroundColor = UIColor.clearColor; }];
                    }];
                }
            });
            return;
        }
    }
    DKXSArchiveToast(@"原消息不在当前已加载列表中");
}
void DKXSArchiveCellWillReuse(UITableViewCell *cell) {
    // 装饰层挂接的标签以 accessibilityIdentifier 标记，复用时统一摘掉，避免串行。
    for (UIView *view in [cell.contentView.subviews copy]) {
        if ([view.accessibilityIdentifier hasPrefix:@"DKXS."]) [view removeFromSuperview];
    }
}
