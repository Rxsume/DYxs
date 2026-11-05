// 移植自 Si-yi/DYads- 5e9a5c0（DYYYChatEnhancements.m）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样。
// 设置项不在本模块登记，见 DKXSBatch8Settings.xm；开关变化时由设置登记的 onChange 调 installHooks。
#import "DKXSChatEnhancements.h"
#import "DKXSChatEnhancementPolicy.h"
#import "DKXSIMService.h"
#import "DKXSUtils.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <math.h>

@interface DKXSChatEnhancementState : NSObject
@property (nonatomic, weak) UIViewController *controller;
@property (nonatomic, strong) NSHashTable<UIView *> *pending;
@property (nonatomic, strong) DKXSChatTranslationLedger *ledger;
@property (nonatomic, assign) BOOL scheduled;
@end
@implementation DKXSChatEnhancementState
- (instancetype)init {
    if ((self = [super init])) { _pending = [NSHashTable weakObjectsHashTable]; _ledger = [DKXSChatTranslationLedger new]; }
    return self;
}
@end

@interface DKXSChatQuoteGesture : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIView *cell;
@property (nonatomic, strong) UIPanGestureRecognizer *pan;
- (void)handle:(UIPanGestureRecognizer *)pan;
@end

@implementation DKXSChatEnhancements
#pragma mark - 偏好与原生接口
+ (BOOL)enabled:(NSString *)key { return [NSUserDefaults.standardUserDefaults boolForKey:key]; }
+ (NSMutableDictionary *)capabilities {
    static NSMutableDictionary *values; static dispatch_once_t once;
    dispatch_once(&once, ^{ values = [NSMutableDictionary dictionary]; }); return values;
}
+ (NSMutableDictionary *)events {
    static NSMutableDictionary *values; static dispatch_once_t once;
    dispatch_once(&once, ^{ values = [NSMutableDictionary dictionary]; }); return values;
}
+ (void)recordCapability:(NSString *)name available:(BOOL)available {
    if (NSThread.isMainThread && name.length && [self capabilities].count < 32) [self capabilities][name] = @(available);
}
+ (void)recordEvent:(NSString *)name {
    if (!NSThread.isMainThread || !name.length) return;
    NSMutableDictionary *events = [self events];
    if (events[name] || events.count < 32) events[name] = @(MIN([events[name] unsignedIntegerValue] + 1, 1000000));
}
+ (id)object:(id)owner selector:(NSString *)name {
    SEL selector = NSSelectorFromString(name);
    if (!owner || ![DKXSChatEnhancementPolicy class:object_getClass(owner) selector:selector result:'@' arguments:@""]) return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(owner, selector); }
    @catch (__unused NSException *exception) { return nil; }
}
+ (id)messageForCell:(UIView *)cell {
    return [self object:[self object:cell selector:@"currentContext"] selector:@"message"];
}
+ (UIViewController *)controllerForCell:(UIView *)cell {
    UIResponder *responder = cell;
    Class cls = NSClassFromString(@"AWEIMMessageListViewController");
    for (NSUInteger i = 0; responder && i < 32; i++, responder = responder.nextResponder)
        if (cls && [responder isKindOfClass:cls]) return (UIViewController *)responder;
    return nil;
}
+ (BOOL)visibleCell:(UIView *)cell controller:(UIViewController *)controller {
    if (!cell.window || cell.hidden || cell.alpha < 0.01 || !controller.isViewLoaded || !controller.view.window ||
        ![cell isDescendantOfView:controller.view] || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return NO;
    UITableView *table = [self object:controller selector:@"tableView"];
    return [table isKindOfClass:UITableView.class] && [table.visibleCells containsObject:cell];
}
+ (DKXSChatEnhancementState *)state:(UIViewController *)controller {
    const void *key = @selector(controllerAppeared:);
    DKXSChatEnhancementState *state = objc_getAssociatedObject(controller, key);
    if (!state && controller) {
        state = [DKXSChatEnhancementState new]; state.controller = controller;
        objc_setAssociatedObject(controller, key, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}
#pragma mark - 语音按可见消息合并触发
+ (void)enqueueCell:(UIView *)cell controller:(UIViewController *)controller {
    if (![self enabled:@"DKXSAutoTranslateAudio"] || !controller) return;
    DKXSChatEnhancementState *state = [self state:controller];
    if (state.pending.count < 48) [state.pending addObject:cell];
    if (state.scheduled) return;
    state.scheduled = YES;
    __weak DKXSChatEnhancementState *weakState = state;
    dispatch_async(dispatch_get_main_queue(), ^{
        DKXSChatEnhancementState *current = weakState;
        if (!current) return;
        current.scheduled = NO;
        NSArray *pending = current.pending.allObjects; [current.pending removeAllObjects];
        [self translateCells:pending state:current];
    });
}
+ (void)translateCells:(NSArray<UIView *> *)cells state:(DKXSChatEnhancementState *)state {
    UIViewController *controller = state.controller;
    if (![self enabled:@"DKXSAutoTranslateAudio"] || !controller) return;
    NSString *account = [DKXSIMService capturedAccountID];
    if (!account.length) { [self recordEvent:@"audio_account_not_ready"]; return; }
    id shortID = [self object:controller selector:@"msg_conversationShortID"];
    NSString *cid = [self object:controller selector:@"msg_conversationID"];
    if (![cid isKindOfClass:NSString.class] || !cid.length ||
        !(([shortID isKindOfClass:NSString.class] && [shortID length]) || [shortID isKindOfClass:NSNumber.class])) return;
    Class managerClass = NSClassFromString(@"AWEIMAudioMessageTranslateManager");
    BOOL two = [DKXSChatEnhancementPolicy class:managerClass selector:NSSelectorFromString(@"translateAudioMessageList:convShortID:") result:'v' arguments:@"@@"];
    BOOL three = [DKXSChatEnhancementPolicy class:managerClass selector:NSSelectorFromString(@"translateAudioMessageList:convShortID:convType:") result:'v' arguments:@"@@q"];
    [self recordCapability:@"audioTranslation" available:two || three];
    if (!two && !three) return;
    // 所有上下文与接口先验证，再占去重名额。
    id manager = [self object:managerClass selector:@"sharedInstance"];
    if (!manager) { [self recordEvent:@"audio_manager_unavailable"]; return; }
    long long conversationType = 0;
    if (!two) {
        id conversation = [self object:controller selector:@"conversation"];
        id type = [self object:conversation selector:@"type"];
        if (![type isKindOfClass:NSNumber.class]) { [self recordEvent:@"audio_conversation_type_unknown"]; return; }
        conversationType = [type longLongValue];
    }
    NSMutableArray *messages = [NSMutableArray array];
    for (UIView *cell in cells) {
        if (![self visibleCell:cell controller:controller]) continue;
        id message = [self messageForCell:cell];
        Class audio = NSClassFromString(@"AWEIMAudioMessage"), encrypted = NSClassFromString(@"AWEIMEncryptAudioMessageV2");
        if (!((audio && [message isKindOfClass:audio]) || (encrypted && [message isKindOfClass:encrypted]))) continue;
        id text = [self object:message selector:@"audioText"];
        if ([text respondsToSelector:@selector(length)] && [text length]) continue;
        NSString *sender = [self object:message selector:@"fromUid"];
        NSString *messageCID = [self object:message selector:@"conversationID"];
        NSString *identifier = [self object:message selector:@"messageID"];
        if (![sender isKindOfClass:NSString.class] || !sender.length || [sender isEqual:account] || ![messageCID isEqual:cid]) continue;
        if (messages.count >= 8) { [self enqueueCell:cell controller:controller]; continue; }
        // 验证可调用方式后才占去重槽；同一消息不会因复用或转写失败反复请求。
        if ([state.ledger reserveAccount:account conversation:cid message:identifier]) [messages addObject:message];
    }
    if (!messages.count) return;
    @try {
        if (two) {
            ((void (*)(id, SEL, id, id))objc_msgSend)(manager, NSSelectorFromString(@"translateAudioMessageList:convShortID:"), messages, shortID);
        } else {
            ((void (*)(id, SEL, id, id, long long))objc_msgSend)(manager, NSSelectorFromString(@"translateAudioMessageList:convShortID:convType:"), messages, shortID, conversationType);
        }
        [self recordEvent:@"audio_batch_requested"];
    } @catch (__unused NSException *exception) { [self recordEvent:@"audio_request_exception"]; }
}
#pragma mark - Cell 与手势生命周期
+ (void)cellChanged:(UIView *)cell {
    if (!NSThread.isMainThread) {
        __weak UIView *weakCell = cell;
        dispatch_async(dispatch_get_main_queue(), ^{ [self cellChanged:weakCell]; }); return;
    }
    if (!cell) return;
    const void *key = @selector(cellChanged:);
    DKXSChatQuoteGesture *gesture = objc_getAssociatedObject(cell, key);
    BOOL enabled = [self enabled:@"DKXSSwipeToQuote"] && cell.window;
    if (enabled && !gesture) {
        gesture = [DKXSChatQuoteGesture new]; gesture.cell = cell;
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:gesture action:@selector(handle:)];
        pan.maximumNumberOfTouches = 1; pan.delegate = gesture;
        pan.cancelsTouchesInView = NO; gesture.pan = pan;
        [cell addGestureRecognizer:pan];
        objc_setAssociatedObject(cell, key, gesture, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    gesture.pan.enabled = enabled;
    [self enqueueCell:cell controller:[self controllerForCell:cell]];
}
+ (void)controllerAppeared:(UIViewController *)controller {
    if (!NSThread.isMainThread) return;
    UITableView *table = [self object:controller selector:@"tableView"];
    if (![table isKindOfClass:UITableView.class]) return;
    NSArray *cells = table.visibleCells;
    for (NSUInteger i = 0; i < MIN(cells.count, 48); i++) [self cellChanged:cells[i]];
}
+ (BOOL)quoteCell:(UIView *)cell {
    UIViewController *controller = [self controllerForCell:cell];
    id message = [self messageForCell:cell];
    if (![self visibleCell:cell controller:controller] || !message) return NO;
    id input = [self object:controller selector:@"getInputViewController"];
    if (!input) return NO;
    NSArray *options = @[@[@"quoteReplyMessage:keyboardShow:scene:", @"@B@"],
        @[@"quoteReplyMessage:keyboardShow:shoudAt:", @"@BB"],
        @[@"quoteReplyMessage:keyboardShow:", @"@B"], @[@"configQuoteReplyWithMessage:keyboardShow:", @"@B"], @[@"quoteReplyMessage:", @"@"]];
    for (NSArray *option in options) {
        SEL selector = NSSelectorFromString(option[0]); NSString *args = option[1];
        if (![DKXSChatEnhancementPolicy class:object_getClass(input) selector:selector result:'v' arguments:args]) continue;
        @try {
            if ([args isEqual:@"@B@"]) ((void (*)(id, SEL, id, BOOL, id))objc_msgSend)(input, selector, message, YES, @"swipe");
            else if ([args isEqual:@"@BB"]) ((void (*)(id, SEL, id, BOOL, BOOL))objc_msgSend)(input, selector, message, YES, NO);
            else if ([args isEqual:@"@B"]) ((void (*)(id, SEL, id, BOOL))objc_msgSend)(input, selector, message, YES);
            else ((void (*)(id, SEL, id))objc_msgSend)(input, selector, message);
            [self recordEvent:@"quote_requested"]; return YES;
        } @catch (__unused NSException *exception) { [self recordEvent:@"quote_exception"]; return NO; }
    }
    [self recordEvent:@"quote_interface_unavailable"]; return NO;
}
#pragma mark - 诊断
+ (NSDictionary *)diagnostics {
    if (!NSThread.isMainThread) return @{};
    NSMutableDictionary *enabled = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"DKXSAutoTranslateAudio", @"DKXSSwipeToQuote", @"DKXSDisableInputStateReport", @"DKXSDisableOnlineUpload", @"DKXSPreventWatchOnceDestroy"]) enabled[key] = @([self enabled:key]);
    return @{ @"enabled":enabled, @"capabilities":[[self capabilities] copy], @"events":[[self events] copy],
        @"readReceiptHook":@NO, @"unreadMutation":@NO, @"historyScan":@NO, @"audioLimitPerController":@256,
        @"watchOncePolicy":@"native_local_flags_only_callbacks_unchanged" };
}
@end

@implementation DKXSChatQuoteGesture
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if (![DKXSChatEnhancements enabled:@"DKXSSwipeToQuote"] || !self.cell.window) return NO;
    CGPoint velocity = [self.pan velocityInView:self.cell];
    return velocity.x < -120 && fabs(velocity.x) > fabs(velocity.y) * 1.6;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    for (UIView *view = touch.view; view && view != self.cell; view = view.superview)
        if ([view isKindOfClass:UIControl.class] || [view isKindOfClass:UITextView.class] || [view isKindOfClass:UIScrollView.class]) return NO;
    return YES;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    // 表格保留纵向滚动；其他内容自己的手势继续由 UIKit 仲裁。
    return [other.view isKindOfClass:UITableView.class] && other == ((UITableView *)other.view).panGestureRecognizer;
}
- (void)handle:(UIPanGestureRecognizer *)pan {
    if (pan.state != UIGestureRecognizerStateEnded || ![DKXSChatEnhancements enabled:@"DKXSSwipeToQuote"]) return;
    CGPoint offset = [pan translationInView:self.cell];
    if (offset.x > -64 || fabs(offset.x) < fabs(offset.y) * 1.6) return;
    if ([DKXSChatEnhancements quoteCell:self.cell]) {
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight]; [feedback impactOccurred];
    } else [DKXSUtils showToast:@"此消息暂不支持快速引用，请使用原生长按菜单"];
}
@end
