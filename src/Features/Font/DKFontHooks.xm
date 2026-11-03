//
//  DKFontHooks.xm
//  字体：把界面里的系统字体换成用户导入的字体。图标字体与抖音自带
//  的品牌字体不受影响；没有导入字体时全部走原生逻辑。
//

#import <UIKit/UIKit.h>
#import "DKFontStore.h"

static BOOL DKFontIsSystemFontName(NSString *name) {
    if (!name.length) return NO;
    // 图标字体绝不替换。
    if ([name rangeOfString:@"icon" options:NSCaseInsensitiveSearch].location != NSNotFound) return NO;
    for (NSString *prefix in @[@"PingFang", @"Helvetica", @"Arial", @".SF", @"SFPro", @"SFCompact", @"AppleSDGothic", @"STHeiti"]) {
        if ([name hasPrefix:prefix]) return YES;
    }
    return NO;
}

static UIFont *DKFontCustomWithSize(CGFloat size) {
    NSString *psName = DKFontRegisteredPostScriptName();
    if (!psName.length || size <= 0) return nil;
    return [UIFont fontWithName:psName size:size];
}

static UIFont *DKFontSwappedFont(UIFont *font) {
    if (!font) return nil;
    if (!DKFontIsSystemFontName(font.fontName)) return nil;
    return DKFontCustomWithSize(font.pointSize);
}

%hook UIFont

+ (UIFont *)systemFontOfSize:(CGFloat)size {
    return DKFontCustomWithSize(size) ?: %orig;
}

+ (UIFont *)boldSystemFontOfSize:(CGFloat)size {
    return DKFontCustomWithSize(size) ?: %orig;
}

+ (UIFont *)italicSystemFontOfSize:(CGFloat)size {
    return DKFontCustomWithSize(size) ?: %orig;
}

+ (UIFont *)systemFontOfSize:(CGFloat)size weight:(CGFloat)weight {
    return DKFontCustomWithSize(size) ?: %orig;
}

+ (UIFont *)fontWithName:(NSString *)fontName size:(CGFloat)size {
    // 已注册的导入字体本身直接走原生，避免与系统名前缀检查互相干扰。
    if (fontName.length && [fontName isEqualToString:DKFontRegisteredPostScriptName()]) return %orig;
    if (DKFontIsSystemFontName(fontName)) {
        UIFont *custom = DKFontCustomWithSize(size);
        if (custom) return custom;
    }
    return %orig;
}

%end

%hook UILabel

- (void)setFont:(UIFont *)font {
    %orig(DKFontSwappedFont(font) ?: font);
}

%end

%hook UITextView

- (void)setFont:(UIFont *)font {
    %orig(DKFontSwappedFont(font) ?: font);
}

%end

%hook UITextField

- (void)setFont:(UIFont *)font {
    %orig(DKFontSwappedFont(font) ?: font);
}

%end

%ctor {
    DKFontRegisterStoredFont();
    %init;
}
