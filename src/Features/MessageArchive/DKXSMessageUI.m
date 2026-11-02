//  DKXSMessageUI.m
//  DY778 第 1 批 staging：见头文件注释。
//  与上游的差异（均已在 REPORT 标注）：
//  · 气泡发现用启发式（类名含 Bubble 的子视图，否则 contentView 内最大子视图），
//    40.8.0 若气泡结构变化，标记仍可显示（布局退回 cell  bounds 内），只是着色可能不生效；
//  · 设置页的时间样式预览控件（DY778TimePreview）不移植，样式直接由开关控制；
//  · 官方时间隐藏只处理 header 内的 UILabel 子视图，不动 header 自身布局。

#import "DKXSMessageUI.h"
#import "DKXSRecall.h"
#import "DKXSEditHistory.h"
#import "DKXSArchiveCore.h"
#import "DKXSArchiveNative.h"
#import "DKXSMessageLayout.h"
#import <objc/runtime.h>

static char kDKXSCellDecoration;

// ---- 时间格式化 ----
NSString *DKXSFormatMessageTime(NSTimeInterval timestamp) {
    if (timestamp > 1e12) timestamp /= 1000;
    if (!timestamp) return @"";
    NSString *pattern = DKXSArchiveString(@"DKXSTimeFormat");
    if (!pattern.length || pattern.length > 80) pattern = @"HH:mm:ss";
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:timestamp];
    NSDate *now = NSDate.date;
    NSMutableDictionary *thread = NSThread.currentThread.threadDictionary;
    NSDateFormatter *formatter = thread[@"DKXS.MessageDateFormatter"];
    if (!formatter) { formatter = [NSDateFormatter new]; thread[@"DKXS.MessageDateFormatter"] = formatter; }
    formatter.locale = NSLocale.autoupdatingCurrentLocale;
    formatter.calendar = NSCalendar.autoupdatingCurrentCalendar;
    formatter.timeZone = NSTimeZone.localTimeZone;
    formatter.dateFormat = pattern;
    NSString *value = nil;
    @try { value = [formatter stringFromDate:date]; } @catch (__unused NSException *e) { }
    if (!value.length) { formatter.dateFormat = @"HH:mm:ss"; value = [formatter stringFromDate:date]; }
    NSMutableString *tokens = [NSMutableString string];
    BOOL inLiteral = NO;
    for (NSUInteger index = 0; index < pattern.length; index++) {
        unichar character = [pattern characterAtIndex:index];
        if (character == '\'') { inLiteral = !inLiteral; continue; }
        if (!inLiteral) [tokens appendFormat:@"%C", character];
    }
    BOOL includesDate = [tokens rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"yYuUrQqMLwWdDFgEec"]].location != NSNotFound;
    if (!DKXSArchiveBool(@"DKXSTimeSmartDate") || includesDate) return value ?: @"";
    NSCalendar *calendar = NSCalendar.autoupdatingCurrentCalendar;
    if ([calendar isDate:date inSameDayAsDate:now]) return value ?: @"";
    NSDate *yesterday = [calendar dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:now options:0];
    if (yesterday && [calendar isDate:date inSameDayAsDate:yesterday]) return [@"昨天 " stringByAppendingString:value ?: @""];
    formatter.dateFormat = [calendar component:NSCalendarUnitYear fromDate:date] == [calendar component:NSCalendarUnitYear fromDate:now] ? @"MM-dd" : @"yyyy-MM-dd";
    return [NSString stringWithFormat:@"%@ %@", [formatter stringFromDate:date] ?: @"", value ?: @""];
}
static UIFont *DKXSTimeFont(void) {
    double value = DKXSArchiveNumber(@"DKXSTimeFontSize");
    CGFloat size = isfinite(value) && value > 0 ? MIN(18, MAX(9, value)) : 11;
    return [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption2] scaledFontForFont:[UIFont monospacedDigitSystemFontOfSize:size weight:UIFontWeightMedium] maximumPointSize:22];
}
static UIFont *DKXSMarkFont(void) {
    return [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption1] scaledFontForFont:[UIFont systemFontOfSize:11 weight:UIFontWeightSemibold] maximumPointSize:18];
}
static UIColor *DKXSReadableTimeColor(void) {
    UIColor *chosen = DKXSArchiveColorFromHex(DKXSArchiveString(@"DKXSTimeColor"), UIColor.systemTealColor);
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        UIColor *resolved = [chosen resolvedColorWithTraitCollection:traits];
        CGFloat red = 0, green = 0, blue = 0, alpha = 1;
        if (![resolved getRed:&red green:&green blue:&blue alpha:&alpha]) return resolved;
        CGFloat luminance = red * .2126 + green * .7152 + blue * .0722;
        if (traits.userInterfaceStyle != UIUserInterfaceStyleDark && luminance > .55) {
            CGFloat scale = .42 / luminance;
            return [UIColor colorWithRed:red * scale green:green * scale blue:blue * scale alpha:1];
        }
        if (traits.userInterfaceStyle == UIUserInterfaceStyleDark && luminance < .3)
            return [UIColor colorWithRed:.55 + red * .45 green:.55 + green * .45 blue:.55 + blue * .45 alpha:1];
        return resolved;
    }];
}
static DKXSLayoutPosition DKXSPreferredPosition(NSString *key) {
    switch (DKXSArchivePositionIndex(key)) {
        case 1: return DKXSLayoutAbove;
        case 2: return DKXSLayoutBelow;
        default: return DKXSLayoutRight;
    }
}

// ---- 标记按钮 ----
@interface DKXSRecallBadge : UIButton
@property(nonatomic, copy) NSString *conversationID;
@property(nonatomic, weak) UIViewController *source;
@end
@implementation DKXSRecallBadge
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.layer.cornerRadius = 7; self.layer.masksToBounds = YES; self.layer.borderWidth = .5;
        self.titleLabel.font = DKXSMarkFont(); self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        self.contentEdgeInsets = UIEdgeInsetsMake(2, 6, 2, 6);
        [self addTarget:self action:@selector(openArchive) forControlEvents:UIControlEventTouchUpInside];
        self.accessibilityHint = @"打开当前会话的撤回记录";
        self.accessibilityIdentifier = @"DKXS.RecallBadge";
    }
    return self;
}
- (void)openArchive {
    if (self.source && self.conversationID.length) DKXSRecallArchivePresentedFrom(self.source, self.conversationID);
}
@end
@interface DKXSEditBadge : UIButton
@property(nonatomic, weak) UIViewController *source;
@property(nonatomic, copy) NSDictionary *record;
@end
@implementation DKXSEditBadge
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.layer.cornerRadius = 7; self.layer.borderWidth = .5; self.clipsToBounds = YES;
        self.titleLabel.font = DKXSMarkFont(); self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        self.contentEdgeInsets = UIEdgeInsetsMake(2, 6, 2, 6);
        [self addTarget:self action:@selector(openHistory) forControlEvents:UIControlEventTouchUpInside];
        self.accessibilityHint = @"查看这条消息的原文、编辑版本和时间";
        self.accessibilityIdentifier = @"DKXS.EditBadge";
    }
    return self;
}
- (void)openHistory {
    if ([self.record[@"account"] isEqual:DKXSArchiveCurrentAccountID()])
        DKXSEditHistoryPresentedFrom(self.source, self.record[@"conversation"], self.record[@"key"]);
}
@end
static void DKXSConfigureTime(UILabel *label, NSString *text) {
    label.text = text;
    label.font = DKXSTimeFont();
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = DKXSReadableTimeColor();
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    label.layer.cornerRadius = 7; label.layer.masksToBounds = YES;
    label.backgroundColor = DKXSArchiveBool(@"DKXSTimeBackground") ? [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor colorWithRed:.13 green:.15 blue:.16 alpha:.9] : [UIColor colorWithRed:.93 green:.95 blue:.95 alpha:.95];
    }] : UIColor.clearColor;
    label.layer.borderWidth = DKXSArchiveBool(@"DKXSTimeBackground") ? .5 : 0;
    label.layer.borderColor = [[label.textColor colorWithAlphaComponent:.20] resolvedColorWithTraitCollection:label.traitCollection].CGColor;
    double opacity = DKXSArchiveNumberDefault(@"DKXSTimeOpacity", 0.94);
    label.alpha = isfinite(opacity) ? MIN(1, MAX(.35, opacity)) : .94;
    label.accessibilityLabel = [@"消息时间 " stringByAppendingString:text ?: @""];
    label.accessibilityIdentifier = @"DKXS.TimeLabel";
}
static void DKXSConfigureRecall(DKXSRecallBadge *badge, BOOL available) {
    badge.titleLabel.font = DKXSMarkFont();
    [badge setTitle:DKXSRecallMarkerText() forState:UIControlStateNormal];
    badge.titleLabel.numberOfLines = 1; badge.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    UIColor *color = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor colorWithRed:.86 green:.64 blue:.69 alpha:1] : [UIColor colorWithRed:.51 green:.28 blue:.34 alpha:1];
    }];
    [badge setTitleColor:color forState:UIControlStateNormal];
    badge.tintColor = color;
    badge.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor colorWithRed:.20 green:.16 blue:.18 alpha:.9] : [UIColor colorWithRed:.97 green:.93 blue:.94 alpha:.94];
    }];
    badge.layer.borderColor = [[color colorWithAlphaComponent:.27] resolvedColorWithTraitCollection:badge.traitCollection].CGColor;
    badge.accessibilityLabel = available ? @"对方已撤回，原始内容已保留" : @"对方已撤回，原文未取得";
}
static void DKXSConfigureEdit(UIButton *badge, NSUInteger changes) {
    badge.titleLabel.font = DKXSMarkFont(); badge.titleLabel.numberOfLines = 1;
    badge.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [badge setTitle:[NSString stringWithFormat:@"%@ · %lu", DKXSEditMarkerText(), (unsigned long)changes] forState:UIControlStateNormal];
    [badge setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
    badge.backgroundColor = [UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:.96];
    badge.layer.borderColor = [UIColor.separatorColor resolvedColorWithTraitCollection:badge.traitCollection].CGColor;
}

// ---- cell 装饰状态与协调器 ----
@interface DKXSCellDecorationState : NSObject
@property(nonatomic, weak) UIViewController *controller;
@property(nonatomic, weak) id message;
@property(nonatomic, copy) NSString *messageKey;
@property(nonatomic, copy) NSString *conversationID;
@property(nonatomic) NSTimeInterval timestamp;
@property(nonatomic) BOOL outgoing;
@property(nonatomic, strong) UILabel *timeLabel;
@property(nonatomic, strong) DKXSRecallBadge *recallBadge;
@property(nonatomic, strong) DKXSEditBadge *editBadge;
@property(nonatomic, weak) UIView *bubbleView;
@property(nonatomic, strong) UIColor *originalBubbleColor;
@property(nonatomic) BOOL bubbleTinted;
@end
@implementation DKXSCellDecorationState
@end
@interface DKXSMessageUICoordinator : NSObject
@property(nonatomic, strong) NSHashTable *controllers;
@property(nonatomic) BOOL invalidationQueued;
+ (instancetype)shared;
- (void)scheduleInvalidation:(BOOL)immediately;
@end
@implementation DKXSMessageUICoordinator
+ (instancetype)shared { static DKXSMessageUICoordinator *coordinator; static dispatch_once_t once; dispatch_once(&once, ^{ coordinator = [self new]; coordinator.controllers = [NSHashTable weakObjectsHashTable]; }); return coordinator; }
- (void)scheduleInvalidation:(BOOL)immediately {
    if (self.invalidationQueued && !immediately) return;
    self.invalidationQueued = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.invalidationQueued = NO;
        for (UIViewController *controller in self.controllers.allObjects) {
            UITableView *table = DKXSArchiveRead(controller, @"tableView");
            if (![table isKindOfClass:UITableView.class]) continue;
            for (UITableViewCell *cell in table.visibleCells) DKXSMessageUIBindCell(cell, controller);
        }
    });
}
@end
void DKXSMessageUIRegisterController(UIViewController *controller) {
    if (controller) [[DKXSMessageUICoordinator shared].controllers addObject:controller];
}
void DKXSMessageUIInvalidate(BOOL immediately) {
    [[DKXSMessageUICoordinator shared] scheduleInvalidation:immediately];
}
static id DKXSMessageForCell(UITableViewCell *cell) {
    id viewModel = DKXSArchiveRead(DKXSArchiveRead(cell, @"currentContext"), @"messageViewModel") ?: DKXSArchiveRead(cell, @"viewModel");
    return DKXSArchiveRead(viewModel, @"iesMessage") ?: DKXSArchiveRead(viewModel, @"message") ?: DKXSArchiveRead(cell, @"message");
}
static UIView *DKXSFindBubbleView(UITableViewCell *cell) {
    UIView *largest = nil; CGFloat largestArea = 0;
    for (UIView *view in cell.contentView.subviews) {
        if ([view.accessibilityIdentifier hasPrefix:@"DKXS."]) continue;
        NSString *name = NSStringFromClass([view class]);
        if ([name containsString:@"Bubble"]) return view;
        CGFloat area = view.bounds.size.width * view.bounds.size.height;
        if (area > largestArea) { largestArea = area; largest = view; }
    }
    return largest;
}
static DKXSLayoutRect DKXSRectFromCGRect(CGRect rect) { return (DKXSLayoutRect){rect.origin.x, rect.origin.y, rect.size.width, rect.size.height}; }
static CGRect DKXSCGRectFromLayoutRect(DKXSLayoutRect rect) { return CGRectMake(rect.x, rect.y, rect.width, rect.height); }

void DKXSMessageUIBindCell(UITableViewCell *cell, UIViewController *controller) {
    if (!cell || !NSThread.isMainThread) return;
    id message = DKXSMessageForCell(cell);
    DKXSCellDecorationState *state = objc_getAssociatedObject(cell, &kDKXSCellDecoration);
    if (!state) { state = [DKXSCellDecorationState new]; objc_setAssociatedObject(cell, &kDKXSCellDecoration, state, OBJC_ASSOCIATION_RETAIN); }
    state.controller = controller;
    state.message = message;
    if (!message) {
        state.timeLabel.hidden = YES; state.recallBadge.hidden = YES; state.editBadge.hidden = YES;
        return;
    }
    NSDictionary *identity = DKXSMessageIdentity(message);
    state.messageKey = identity[@"key"]; state.conversationID = identity[@"conversation"];
    state.timestamp = DKXSArchiveTimestamp(DKXSArchiveRead(message, @"createTime") ?: DKXSArchiveRead(message, @"timestamp") ?: DKXSArchiveRead(message, @"msgTime"));
    NSString *account = DKXSArchiveCurrentAccountID();
    NSString *sender = DKXSArchiveIdentifier(DKXSArchiveRead(message, @"sender"));
    state.outgoing = account.length && sender.length && [account isEqualToString:sender];
    NSDictionary *recallRecord = DKXSRecallRecordForMessage(message);
    NSDictionary *editRecord = DKXSEditRecordForMessage(message);
    BOOL showTime = DKXSArchiveBool(@"DKXSTimeEnabled") && state.timestamp > 0;
    BOOL showRecall = DKXSArchiveBool(@"DKXSRecallEnabled") && DKXSArchiveBool(@"DKXSRecallBadge") && [recallRecord[@"recalled"] boolValue];
    BOOL showEdit = DKXSArchiveBool(@"DKXSEditEnabled") && DKXSArchiveBool(@"DKXSEditBadge") && [editRecord[@"changes"] unsignedIntegerValue] > 0;
    if (showTime && !state.timeLabel) { state.timeLabel = [UILabel new]; state.timeLabel.accessibilityIdentifier = @"DKXS.TimeLabel"; [cell.contentView addSubview:state.timeLabel]; }
    if (showRecall && !state.recallBadge) { state.recallBadge = [DKXSRecallBadge new]; [cell.contentView addSubview:state.recallBadge]; }
    if (showEdit && !state.editBadge) { state.editBadge = [DKXSEditBadge new]; [cell.contentView addSubview:state.editBadge]; }
    state.timeLabel.hidden = !showTime;
    state.recallBadge.hidden = !showRecall;
    state.editBadge.hidden = !showEdit;
    if (showTime) DKXSConfigureTime(state.timeLabel, DKXSFormatMessageTime(state.timestamp));
    if (showRecall) {
        state.recallBadge.source = controller; state.recallBadge.conversationID = state.conversationID;
        DKXSConfigureRecall(state.recallBadge, [recallRecord[@"available"] boolValue]);
    }
    if (showEdit) {
        state.editBadge.source = controller; state.editBadge.record = editRecord;
        DKXSConfigureEdit(state.editBadge, [editRecord[@"changes"] unsignedIntegerValue]);
    }
    // 气泡着色：仅在标记显示且对应着色开关开时做；复用时由 CellReuse 恢复。
    UIView *bubble = DKXSFindBubbleView(cell);
    state.bubbleView = bubble;
    BOOL wantRecallTint = showRecall && DKXSArchiveBool(@"DKXSRecallTintBubble");
    BOOL wantEditTint = showEdit && DKXSArchiveBool(@"DKXSEditTintBubble");
    BOOL wantPlain = showRecall && DKXSArchiveBool(@"DKXSRecallPlainBubbleOnSkin");
    if (bubble && (wantRecallTint || wantEditTint || wantPlain) && !state.bubbleTinted) {
        state.originalBubbleColor = bubble.backgroundColor;
        UIColor *tint = nil;
        if (wantRecallTint) tint = [DKXSArchiveColorFromHex(DKXSArchiveString(@"DKXSRecallBubbleColor"), nil) colorWithAlphaComponent:0.35];
        else if (wantEditTint) tint = [DKXSArchiveColorFromHex(DKXSArchiveString(@"DKXSEditBubbleColor"), nil) colorWithAlphaComponent:0.35];
        else if (wantPlain) tint = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor colorWithRed:.22 green:.22 blue:.23 alpha:1] : [UIColor colorWithRed:.93 green:.93 blue:.94 alpha:1];
        }];
        if (tint) { bubble.backgroundColor = tint; state.bubbleTinted = YES; }
    }
    DKXSMessageUICellLayout(cell);
}
void DKXSMessageUICellLayout(UITableViewCell *cell) {
    DKXSCellDecorationState *state = objc_getAssociatedObject(cell, &kDKXSCellDecoration);
    if (!state) return;
    if ((!state.timeLabel || state.timeLabel.hidden) && (!state.recallBadge || state.recallBadge.hidden) && (!state.editBadge || state.editBadge.hidden)) return;
    CGRect bounds = cell.contentView.bounds;
    if (bounds.size.width <= 0 || bounds.size.height <= 0) return;
    UIView *bubble = state.bubbleView ?: DKXSFindBubbleView(cell);
    if (!bubble) return;
    CGRect bubbleFrame = [cell.contentView convertRect:bubble.frame fromView:bubble.superview];
    if (bubbleFrame.size.width <= 8 || bubbleFrame.size.height <= 8) return;
    DKXSLayoutItem timeItem = {0, 0, 0, DKXSLayoutRight};
    DKXSLayoutItem recallItem = {0, 0, 0, DKXSLayoutRight};
    DKXSLayoutItem editItem = {0, 0, 0, DKXSLayoutRight};
    if (state.timeLabel && !state.timeLabel.hidden) {
        CGSize size = [state.timeLabel.text sizeWithAttributes:@{NSFontAttributeName: state.timeLabel.font}];
        timeItem = (DKXSLayoutItem){MIN(200, ceil(size.width) + 10), ceil(state.timeLabel.font.lineHeight) + 4, 1, DKXSPreferredPosition(@"DKXSTimePosition")};
    }
    if (state.recallBadge && !state.recallBadge.hidden) {
        CGSize size = [state.recallBadge.currentTitle sizeWithAttributes:@{NSFontAttributeName: state.recallBadge.titleLabel.font}];
        recallItem = (DKXSLayoutItem){MIN(156, ceil(size.width) + 12), ceil(state.recallBadge.titleLabel.font.lineHeight) + 4, 1, DKXSPreferredPosition(@"DKXSRecallPosition")};
    }
    if (state.editBadge && !state.editBadge.hidden) {
        CGSize size = [state.editBadge.currentTitle sizeWithAttributes:@{NSFontAttributeName: state.editBadge.titleLabel.font}];
        editItem = (DKXSLayoutItem){MIN(156, ceil(size.width) + 12), ceil(state.editBadge.titleLabel.font.lineHeight) + 4, 1, DKXSPreferredPosition(@"DKXSEditPosition")};
    }
    DKXSDecorationLayoutResult layout = DKXSComputeDecorationLayout(DKXSRectFromCGRect(bounds), DKXSRectFromCGRect(bubbleFrame), timeItem, recallItem, editItem, state.outgoing, NULL, 0);
    if (layout.visible[0]) state.timeLabel.frame = DKXSCGRectFromLayoutRect(layout.frames[0]);
    if (layout.visible[1]) state.recallBadge.frame = DKXSCGRectFromLayoutRect(layout.frames[1]);
    if (layout.visible[2]) state.editBadge.frame = DKXSCGRectFromLayoutRect(layout.frames[2]);
    state.timeLabel.hidden = !layout.visible[0] || state.timeLabel.hidden;
    state.recallBadge.hidden = !layout.visible[1] || state.recallBadge.hidden;
    state.editBadge.hidden = !layout.visible[2] || state.editBadge.hidden;
}
void DKXSMessageUICellReuse(UITableViewCell *cell) {
    DKXSCellDecorationState *state = objc_getAssociatedObject(cell, &kDKXSCellDecoration);
    if (state.bubbleTinted && state.bubbleView) { state.bubbleView.backgroundColor = state.originalBubbleColor; state.bubbleTinted = NO; }
    DKXSArchiveCellWillReuse(cell);
}
static void DKXSSetLabelsHidden(UIView *view, BOOL hidden, NSMutableArray *touched) {
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:UILabel.class]) {
            if (hidden) { objc_setAssociatedObject(sub, @"DKXSOfficialHidden", @(sub.hidden), OBJC_ASSOCIATION_RETAIN); sub.hidden = YES; }
            [touched addObject:sub];
        }
        DKXSSetLabelsHidden(sub, hidden, touched);
    }
}
void DKXSMessageUIHideOfficialHeader(UIView *header) {
    if (!header) return;
    if (!DKXSArchiveBool(@"DKXSTimeEnabled") || !DKXSArchiveBool(@"DKXSTimeHideOfficial")) { DKXSMessageUIRestoreOfficialHeader(header); return; }
    NSMutableArray *touched = [NSMutableArray array];
    DKXSSetLabelsHidden(header, YES, touched);
    objc_setAssociatedObject(header, @"DKXSOfficialTouched", touched, OBJC_ASSOCIATION_RETAIN);
}
void DKXSMessageUIRestoreOfficialHeader(UIView *header) {
    NSArray *touched = objc_getAssociatedObject(header, @"DKXSOfficialTouched");
    for (UIView *view in touched) {
        NSNumber *wasHidden = objc_getAssociatedObject(view, @"DKXSOfficialHidden");
        if ([view isKindOfClass:UILabel.class]) view.hidden = wasHidden ? [wasHidden boolValue] : NO;
    }
}
