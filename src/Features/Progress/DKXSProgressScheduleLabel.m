//
//  DKXSProgressScheduleLabel.m
//  DYxs 全量合并第 5 批 staging（尚未并入 DYxs 源码）
//

#import "DKXSProgressScheduleLabel.h"

static id DKXSProgressDefaultsValue(NSString *key) {
    return [[NSUserDefaults standardUserDefaults] objectForKey:key];
}

BOOL DKXSProgressScheduleOn(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSShowScheduleDisplay"];
}

BOOL DKXSHideVideoProgressOn(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"DKXSHideVideoProgress"];
}

NSString *DKXSProgressScheduleStyleString(void) {
    id stored = DKXSProgressDefaultsValue(@"DKXSScheduleStyle");
    if ([stored isKindOfClass:[NSString class]]) return (NSString *)stored;
    static NSArray<NSString *> *styles = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        styles = @[ @"进度条两侧上下", @"进度条左侧剩余", @"进度条左侧完整", @"进度条右侧剩余", @"进度条右侧完整" ];
    });
    if ([stored isKindOfClass:[NSNumber class]]) {
        NSInteger index = [(NSNumber *)stored integerValue];
        if (index >= 0 && index < (NSInteger)styles.count) return styles[(NSUInteger)index];
    }
    return nil;
}

UIColor *DKXSProgressLabelColor(void) {
    id stored = DKXSProgressDefaultsValue(@"DKXSProgressLabelColor");
    if (![stored isKindOfClass:[NSString class]]) return nil;
    NSString *hex = [(NSString *)stored stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([hex hasPrefix:@"#"]) hex = [hex substringFromIndex:1];
    if (hex.length == 3) {
        unichar r = [hex characterAtIndex:0], g = [hex characterAtIndex:1], b = [hex characterAtIndex:2];
        hex = [NSString stringWithFormat:@"%C%C%C%C%C%C", r, r, g, g, b, b];
    } else if (hex.length == 8) {
        hex = [hex substringFromIndex:2];
    }
    if (hex.length != 6) return nil;
    unsigned int rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hex];
    if (![scanner scanHexInt:&rgb] || !scanner.isAtEnd) return nil;
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

CGFloat DKXSProgressVerticalOffset(void) {
    CGFloat verticalOffset = -12.5;
    id stored = DKXSProgressDefaultsValue(@"DKXSTimelineVerticalPosition");
    if ([stored isKindOfClass:[NSString class]] && [(NSString *)stored length] > 0) {
        CGFloat configuredOffset = [(NSString *)stored floatValue];
        if (configuredOffset != 0) verticalOffset = configuredOffset;
    }
    return verticalOffset;
}
