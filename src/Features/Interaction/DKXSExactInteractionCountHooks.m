//
//  DKXSExactInteractionCountHooks.m
//  DYxs 全量合并第 2 批 staging（尚未并入 DYxs 源码）
//  移植来源：Wtrwx/DYYY 的 DYYYExactInteractionCountHooks.m；改名 + 抖音类全部动态取（不声明 AWE 类），日志前缀改为 [DKXS]。
//
#import "DKXSExactInteractionCountHooks.h"

#import "DKXSRuntimeHookInstaller.h"

#import <objc/message.h>

// 与第 1 批一致：开关直接读 NSUserDefaults，不 import 上游常量头。
#define DKXSGetBool(key) [[NSUserDefaults standardUserDefaults] boolForKey:key]
#import <objc/runtime.h>
#import <stdatomic.h>
#import <string.h>

static const char *const kDKXSObjectNumberEncodings[] = {"@24@0:8@16"};
static const char *const kDKXSVoidNoArgumentEncodings[] = {"v16@0:8"};
static const char *const kDKXSVoidObjectEncodings[] = {"v24@0:8@16"};

typedef id (*DKXSExactCountFormatterIMP)(id self, SEL _cmd, NSNumber *number);
typedef void (*DKXSLikeUpdateDiggCountIMP)(id self, SEL _cmd);
typedef void (*DKXSSetLabelStringIMP)(id self, SEL _cmd, NSString *labelString);

static DKXSExactCountFormatterIMP gDKXSOriginalCommentShowString;
static DKXSExactCountFormatterIMP gDKXSOriginalStandardCommentShowString;
static DKXSExactCountFormatterIMP gDKXSOriginalFavoriteShowString;
static DKXSExactCountFormatterIMP gDKXSOriginalShareShowString;
static DKXSLikeUpdateDiggCountIMP gDKXSOriginalLikeUpdateDiggCount;
static atomic_bool gDKXSExactInteractionCountHooksStarted = false;

static BOOL DKXSExactInteractionCountsEnabled(void) {
    return DKXSGetBool(@"DKXSShowExactInteractionCounts");
}

static NSString *DKXSExactInteractionIntegerString(NSNumber *rawValue) {
    if (![rawValue isKindOfClass:[NSNumber class]]) {
        return nil;
    }

    long long count = rawValue.longLongValue;
    if (count < 10000) {
        return nil;
    }
    return [NSString stringWithFormat:@"%lld", count];
}

static id DKXSExactCountFormatterResult(DKXSExactCountFormatterIMP original,
                                        id self,
                                        SEL _cmd,
                                        NSNumber *number) {
    id hostResult = original ? original(self, _cmd, number) : nil;
    if (!DKXSExactInteractionCountsEnabled()) {
        return hostResult;
    }

    NSString *exactString = DKXSExactInteractionIntegerString(number);
    return exactString ?: hostResult;
}

static id DKXSCommentShowStringFromNumber(id self, SEL _cmd, NSNumber *number) {
    return DKXSExactCountFormatterResult(gDKXSOriginalCommentShowString, self, _cmd, number);
}

static id DKXSStandardCommentShowStringFromNumber(id self, SEL _cmd, NSNumber *number) {
    return DKXSExactCountFormatterResult(gDKXSOriginalStandardCommentShowString, self, _cmd, number);
}

static id DKXSFavoriteShowStringFromNumber(id self, SEL _cmd, NSNumber *number) {
    return DKXSExactCountFormatterResult(gDKXSOriginalFavoriteShowString, self, _cmd, number);
}

static id DKXSShareShowStringFromNumber(id self, SEL _cmd, NSNumber *number) {
    return DKXSExactCountFormatterResult(gDKXSOriginalShareShowString, self, _cmd, number);
}

// 抖音类一律动态取，不声明 AWEAwemeModel / AWEFeedVideoButton：
// 上游 AwemeHeaders 与 DYxs DouyinHeaders 体系冲突（ABTest 移植已因此出过错），
// 且本文件所有访问点都已有 respondsToSelector 校验。
static id DKXSLikeElementModel(id self) {
    if (!self || ![self respondsToSelector:@selector(model)]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(self, @selector(model));
}

static id DKXSLikeElementButton(id self) {
    if (!self) {
        return nil;
    }
    id button = nil;
    if ([self respondsToSelector:@selector(likeButton)]) {
        button = ((id (*)(id, SEL))objc_msgSend)(self, @selector(likeButton));
    }
    if (!button && [self respondsToSelector:@selector(button)]) {
        button = ((id (*)(id, SEL))objc_msgSend)(self, @selector(button));
    }
    return button;
}

static void DKXSLikeUpdateDiggCount(id self, SEL _cmd) {
    if (gDKXSOriginalLikeUpdateDiggCount) {
        gDKXSOriginalLikeUpdateDiggCount(self, _cmd);
    }
    if (!DKXSExactInteractionCountsEnabled()) {
        return;
    }

    id model = DKXSLikeElementModel(self);
    id statistics = [model respondsToSelector:@selector(statistics)] ? ((id (*)(id, SEL))objc_msgSend)(model, @selector(statistics)) : nil;
    NSNumber *diggCount = [statistics respondsToSelector:@selector(diggCount)] ? ((NSNumber *(*)(id, SEL))objc_msgSend)(statistics, @selector(diggCount)) : nil;
    NSString *exactString = DKXSExactInteractionIntegerString(diggCount);
    if (exactString.length == 0) {
        return;
    }

    id button = DKXSLikeElementButton(self);
    if (!button || ![button respondsToSelector:@selector(setLabelString:)]) {
        return;
    }

    Method setter = class_getInstanceMethod([button class], @selector(setLabelString:));
    const char *setterEncoding = setter ? method_getTypeEncoding(setter) : NULL;
    if (!setterEncoding || strcmp(setterEncoding, kDKXSVoidObjectEncodings[0]) != 0) {
        return;
    }

    ((DKXSSetLabelStringIMP)objc_msgSend)(button, @selector(setLabelString:), exactString);
}

static void DKXSInstallExactInteractionHook(const char *identifier,
                                             NSString *className,
                                             SEL selector,
                                             IMP replacement,
                                             IMP *original,
                                             const char *const *allowedEncodings,
                                             NSUInteger allowedEncodingCount) {
    Class targetClass = objc_lookUpClass(className.UTF8String);
    DKXSRuntimeHookInstallResult result = DKXSInstallRuntimeHook((DKXSRuntimeHookRequest){
        .identifier = identifier,
        .targetClass = targetClass,
        .selector = selector,
        .classMethod = NO,
        .replacement = replacement,
        .allowedTypeEncodings = allowedEncodings,
        .allowedTypeEncodingCount = allowedEncodingCount,
        .originalImplementation = original,
    });

    if (result.status != DKXSRuntimeHookInstallStatusInstalled &&
        result.status != DKXSRuntimeHookInstallStatusAlreadyInstalled) {
        NSLog(@"[DKXS][RuntimeHook][ExactInteractionCounts] skip=%s class=%@ selector=%@ status=%@ encoding=%s",
              identifier,
              className,
              NSStringFromSelector(selector),
              DKXSRuntimeHookInstallStatusName(result.status),
              result.actualTypeEncoding ?: "(null)");
    }
}

void DKXSStartExactInteractionCountHooks(void) {
    bool expected = false;
    if (!atomic_compare_exchange_strong_explicit(&gDKXSExactInteractionCountHooksStarted,
                                                  &expected,
                                                  true,
                                                  memory_order_acq_rel,
                                                  memory_order_acquire)) {
        return;
    }

    SEL formatterSelector = @selector(showStringFromNumber:);
    DKXSInstallExactInteractionHook("interaction-counts.comment",
                                    @"AWEPlayInteractionCommentElement",
                                    formatterSelector,
                                    (IMP)DKXSCommentShowStringFromNumber,
                                    (IMP *)&gDKXSOriginalCommentShowString,
                                    kDKXSObjectNumberEncodings,
                                    sizeof(kDKXSObjectNumberEncodings) / sizeof(kDKXSObjectNumberEncodings[0]));
    DKXSInstallExactInteractionHook("interaction-counts.standard-comment",
                                    @"AWEPlayInteractionStandardCommentElement",
                                    formatterSelector,
                                    (IMP)DKXSStandardCommentShowStringFromNumber,
                                    (IMP *)&gDKXSOriginalStandardCommentShowString,
                                    kDKXSObjectNumberEncodings,
                                    sizeof(kDKXSObjectNumberEncodings) / sizeof(kDKXSObjectNumberEncodings[0]));
    DKXSInstallExactInteractionHook("interaction-counts.favorite",
                                    @"AWEPlayInteractionFavoriteElement",
                                    formatterSelector,
                                    (IMP)DKXSFavoriteShowStringFromNumber,
                                    (IMP *)&gDKXSOriginalFavoriteShowString,
                                    kDKXSObjectNumberEncodings,
                                    sizeof(kDKXSObjectNumberEncodings) / sizeof(kDKXSObjectNumberEncodings[0]));
    DKXSInstallExactInteractionHook("interaction-counts.share",
                                    @"AWEPlayInteractionShareElement",
                                    formatterSelector,
                                    (IMP)DKXSShareShowStringFromNumber,
                                    (IMP *)&gDKXSOriginalShareShowString,
                                    kDKXSObjectNumberEncodings,
                                    sizeof(kDKXSObjectNumberEncodings) / sizeof(kDKXSObjectNumberEncodings[0]));
    DKXSInstallExactInteractionHook("interaction-counts.like-update",
                                    @"AWEPlayInteractionLikeViewSubElement",
                                    @selector(updateDiggCount),
                                    (IMP)DKXSLikeUpdateDiggCount,
                                    (IMP *)&gDKXSOriginalLikeUpdateDiggCount,
                                    kDKXSVoidNoArgumentEncodings,
                                    sizeof(kDKXSVoidNoArgumentEncodings) / sizeof(kDKXSVoidNoArgumentEncodings[0]));
}
