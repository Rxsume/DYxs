//
//  DKFontStore.m
//  字体文件的保存、校验、注册与恢复默认。
//

#import "DKFontStore.h"
#import "DKKeys.h"
#import <CoreText/CoreText.h>

static NSURL *gDKFontRegisteredURL;

static NSURL *DKFontDirectory(void) {
    NSArray<NSURL *> *roots = [NSFileManager.defaultManager URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask];
    NSURL *dir = [[roots.firstObject URLByAppendingPathComponent:@"Application Support" isDirectory:YES]
                  URLByAppendingPathComponent:@"DKXSFonts" isDirectory:YES];
    return dir;
}

static NSString *DKFontStoredExtension(NSString *fileName) {
    NSString *ext = [[fileName pathExtension] lowercaseString];
    if ([ext isEqualToString:@"ttf"] || [ext isEqualToString:@"otf"] || [ext isEqualToString:@"ttc"]) return ext;
    return nil;
}

static NSString *DKFontPostScriptNameForData(NSData *data) {
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    if (!provider) return nil;
    CGFontRef font = CGFontCreateWithDataProvider(provider);
    CGDataProviderRelease(provider);
    if (!font) return nil;
    CFStringRef psName = CGFontCopyPostScriptName(font);
    CGFontRelease(font);
    if (!psName) return nil;
    NSString *name = (__bridge_transfer NSString *)psName;
    return name.length ? name : nil;
}

NSURL *DKFontFileURL(void) {
    NSString *ext = DKFontStoredExtension([NSUserDefaults.standardUserDefaults stringForKey:DKKeyFontFileName]);
    NSString *file = [NSString stringWithFormat:@"imported.%@", ext ?: @"ttf"];
    return [DKFontDirectory() URLByAppendingPathComponent:file isDirectory:NO];
}

NSString *DKFontCurrentDisplayName(void) {
    NSString *name = [NSUserDefaults.standardUserDefaults stringForKey:DKKeyFontFileName];
    return name.length ? name : nil;
}

NSString *DKFontRegisteredPostScriptName(void) {
    NSString *name = [NSUserDefaults.standardUserDefaults stringForKey:DKKeyFontPostScript];
    return name.length ? name : nil;
}

static BOOL DKFontRegisterURL(NSURL *url) {
    if (!url) return NO;
    if (gDKFontRegisteredURL && [gDKFontRegisteredURL isEqual:url]) return YES;
    CFErrorRef error = NULL;
    BOOL ok = CTFontManagerRegisterFontsWithURL((__bridge CFURLRef)url, kCTFontManagerScopeProcess, &error);
    if (ok) gDKFontRegisteredURL = url;
    return ok;
}

BOOL DKFontStoreData(NSData *data, NSString *fileName, NSString **reason) {
    if (!data.length || data.length > 32 * 1024 * 1024) {
        if (reason) *reason = @"字体文件为空或超过 32MB";
        return NO;
    }
    NSString *ext = DKFontStoredExtension(fileName);
    if (!ext) {
        if (reason) *reason = @"只支持 .ttf / .otf / .ttc 字体文件";
        return NO;
    }
    NSString *psName = DKFontPostScriptNameForData(data);
    if (!psName) {
        if (reason) *reason = @"不是有效的字体文件";
        return NO;
    }
    NSURL *dir = DKFontDirectory();
    NSError *error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:&error]) {
        if (reason) *reason = @"无法创建字体存储目录";
        return NO;
    }
    // 先注销旧字体、删除旧文件，再写新文件，避免新旧混用。
    DKFontRestoreDefault();
    NSURL *url = [dir URLByAppendingPathComponent:[NSString stringWithFormat:@"imported.%@", ext] isDirectory:NO];
    if (![data writeToURL:url options:NSDataWritingAtomic error:&error]) {
        if (reason) *reason = @"字体文件保存失败";
        return NO;
    }
    if (!DKFontRegisterURL(url)) {
        [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
        if (reason) *reason = @"字体注册失败";
        return NO;
    }
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:fileName.lastPathComponent forKey:DKKeyFontFileName];
    [defaults setObject:psName forKey:DKKeyFontPostScript];
    return YES;
}

void DKFontRegisterStoredFont(void) {
    if (!DKFontRegisteredPostScriptName().length) return;
    NSURL *url = DKFontFileURL();
    if (![NSFileManager.defaultManager fileExistsAtPath:url.path]) return;
    DKFontRegisterURL(url);
}

void DKFontRestoreDefault(void) {
    if (gDKFontRegisteredURL) {
        CTFontManagerUnregisterFontsWithURL((__bridge CFURLRef)gDKFontRegisteredURL, kCTFontManagerScopeProcess, NULL);
        gDKFontRegisteredURL = nil;
    }
    NSURL *url = DKFontFileURL();
    [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
    // 旧扩展名残留的文件一并清理。
    for (NSString *ext in @[@"ttf", @"otf", @"ttc"]) {
        NSURL *candidate = [DKFontDirectory() URLByAppendingPathComponent:[NSString stringWithFormat:@"imported.%@", ext] isDirectory:NO];
        if (![candidate isEqual:url]) [NSFileManager.defaultManager removeItemAtURL:candidate error:NULL];
    }
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults removeObjectForKey:DKKeyFontFileName];
    [defaults removeObjectForKey:DKKeyFontPostScript];
}
