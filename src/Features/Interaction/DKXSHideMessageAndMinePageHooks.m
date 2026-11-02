// 移植来源：Wtrwx/DYYY 的 DYYYHideMessageAndMinePageHooks.m（原名见 REPORT.md）。
// 本文件不 import 上游 AwemeHeaders：运行时 hook 全部用 objc_getClass + 字符串类名
// 定位目标，不依赖任何抖音类声明；安装/校验/跳过逻辑与上游完全一致（见 REPORT.md）。
// 注意：上游本文件自带一套安装器，没有用 DYYYRuntimeHookInstaller；本移植保持原样，
// DKXSRuntimeHookInstaller 是按计划另行移植、供第 2 批复用的共享基础设施。
#import "DKXSHideMessageAndMinePageHooks.h"

#define DKXSGetBool(key) [[NSUserDefaults standardUserDefaults] boolForKey:key]

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <stdatomic.h>

static NSString *const kDKXSHideMessageTabStarMallKey = @"DKXSHideMessageTabStarMall";
static NSString *const kDKXSHideMineAvatarPlusKey = @"DKXSHideMineAvatarPlus";
static NSString *const kDKXSHideMineAICreationKey = @"DKXSHideMineAICreation";

typedef BOOL (*DKXSBoolIMP)(id, SEL);
typedef BOOL (*DKXSBoolContextIMP)(id, SEL, id);
typedef CGSize (*DKXSSizeIMP)(id, SEL);
typedef void (*DKXSVoidUpdateUIIMP)(id, SEL, UIView *, UIView *);
typedef void (*DKXSVoidLayoutIMP)(id, SEL);
typedef id (*DKXSIdDataIMP)(id, SEL, id);
typedef void (*DKXSVoidDataIMP)(id, SEL, id);

static atomic_bool gDKXSHideMessageAndMinePageHooksStarted = false;

static DKXSBoolIMP gOrigMessageTabResourceSlotCanShow = NULL;
static DKXSBoolIMP gOrigMessageTabResourceSlotV2CanShow = NULL;
static DKXSBoolIMP gOrigProfileStoryPublishCanShow = NULL;
static DKXSIdDataIMP gOrigGenericOperationBuildVirtualView = NULL;
static DKXSVoidDataIMP gOrigGenericOperationUpdateComponentData = NULL;
static DKXSVoidUpdateUIIMP gOrigProfileStoryPublishUpdateUI = NULL;

static BOOL DKXSHideMessageTabStarMallEnabled(void) {
    return DKXSGetBool(kDKXSHideMessageTabStarMallKey);
}

static BOOL DKXSHideMineAvatarPlusEnabled(void) {
    return DKXSGetBool(kDKXSHideMineAvatarPlusKey);
}

static BOOL DKXSHideMineAICreationEnabled(void) {
    return DKXSGetBool(kDKXSHideMineAICreationKey);
}

static void DKXSHideChromeView(UIView *view) {
    if (![view isKindOfClass:[UIView class]]) {
        return;
    }
    view.hidden = YES;
    view.alpha = 0.0;
    view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
}

static void DKXSHideProfileStoryPublishButton(id owner) {
    if (!owner) {
        return;
    }
    UIButton *publishButton = nil;
    @try {
        id value = [owner valueForKey:@"story25PublishButton"];
        if ([value isKindOfClass:[UIButton class]]) {
            publishButton = value;
        }
    } @catch (__unused NSException *exception) {
    }
    if (publishButton) {
        DKXSHideChromeView(publishButton);
    }
}

static void DKXSHideGenericOperationComponentChrome(id owner) {
    if (!owner) {
        return;
    }
    @try {
        id containerNode = [owner valueForKey:@"containerNode"];
        if ([containerNode isKindOfClass:[UIView class]]) {
            DKXSHideChromeView((UIView *)containerNode);
        } else if (containerNode && [containerNode respondsToSelector:@selector(setHidden:)]) {
            [containerNode setValue:@YES forKey:@"hidden"];
        }
    } @catch (__unused NSException *exception) {
    }
}

#pragma mark - Replacements

static BOOL DKXSMessageTabResourceSlotCanShowInNaviBar(id self, SEL _cmd) {
    if (DKXSHideMessageTabStarMallEnabled()) {
        return NO;
    }
    if (gOrigMessageTabResourceSlotCanShow) {
        return gOrigMessageTabResourceSlotCanShow(self, _cmd);
    }
    return YES;
}

static BOOL DKXSMessageTabResourceSlotV2CanShowInNaviBar(id self, SEL _cmd) {
    if (DKXSHideMessageTabStarMallEnabled()) {
        return NO;
    }
    if (gOrigMessageTabResourceSlotV2CanShow) {
        return gOrigMessageTabResourceSlotV2CanShow(self, _cmd);
    }
    return YES;
}

static BOOL DKXSProfileStoryPublishCanShow(id self, SEL _cmd) {
    if (DKXSHideMineAvatarPlusEnabled()) {
        return NO;
    }
    if (gOrigProfileStoryPublishCanShow) {
        return gOrigProfileStoryPublishCanShow(self, _cmd);
    }
    return YES;
}

static void DKXSProfileStoryPublishUpdateUI(id self, SEL _cmd, UIView *containerView, UIView *anchorView) {
    if (gOrigProfileStoryPublishUpdateUI) {
        gOrigProfileStoryPublishUpdateUI(self, _cmd, containerView, anchorView);
    }
    if (DKXSHideMineAvatarPlusEnabled()) {
        DKXSHideProfileStoryPublishButton(self);
    }
}

static id DKXSGenericOperationBuildVirtualView(id self, SEL _cmd, id data) {
    if (DKXSHideMineAICreationEnabled()) {
        return nil;
    }
    if (gOrigGenericOperationBuildVirtualView) {
        return gOrigGenericOperationBuildVirtualView(self, _cmd, data);
    }
    return nil;
}

static void DKXSGenericOperationUpdateComponentData(id self, SEL _cmd, id data) {
    if (gOrigGenericOperationUpdateComponentData) {
        gOrigGenericOperationUpdateComponentData(self, _cmd, data);
    }
    if (DKXSHideMineAICreationEnabled()) {
        DKXSHideGenericOperationComponentChrome(self);
    }
}

#pragma mark - Install

static BOOL DKXSInstallInstanceBOOLHook(Class cls,
                                         SEL selector,
                                         IMP replacement,
                                         DKXSBoolIMP *originalSlot,
                                         BOOL required,
                                         const char *logLabel) {
    if (!cls || !replacement || !originalSlot) {
        return NO;
    }

    Method existing = class_getInstanceMethod(cls, selector);
    if (!existing) {
        if (required) {
            NSLog(@"[DKXS][RuntimeHook][HideMessageAndMinePage] %@ 缺少 %@：%@",
                  logLabel,
                  NSStringFromSelector(selector),
                  NSStringFromClass(cls));
        }
        return NO;
    }

    const char *typeEncoding = method_getTypeEncoding(existing);
    IMP existingIMP = method_getImplementation(existing);
    if (existingIMP == replacement) {
        return *originalSlot != NULL;
    }

    BOOL methodDefinedOnClass = NO;
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(cls, &methodCount);
    for (unsigned int i = 0; i < methodCount; i++) {
        if (method_getName(methods[i]) == selector) {
            methodDefinedOnClass = YES;
            break;
        }
    }
    free(methods);

    if (!methodDefinedOnClass) {
        IMP superIMP = existingIMP;
        if (!class_addMethod(cls, selector, replacement, typeEncoding)) {
            if (required) {
                NSLog(@"[DKXS][RuntimeHook][HideMessageAndMinePage] %@ class_addMethod 失败：%@",
                      logLabel,
                      NSStringFromClass(cls));
            }
            return NO;
        }
        *originalSlot = (DKXSBoolIMP)superIMP;
        return YES;
    }

    IMP previous = method_setImplementation(existing, replacement);
    if (!previous || previous == replacement) {
        NSLog(@"[DKXS][RuntimeHook][HideMessageAndMinePage] %@ 无法保存原 IMP：%@",
              logLabel,
              NSStringFromClass(cls));
        return NO;
    }
    *originalSlot = (DKXSBoolIMP)previous;
    return YES;
}

static BOOL DKXSInstallClassBOOLHook(Class cls,
                                     SEL selector,
                                     IMP replacement,
                                     DKXSBoolContextIMP *originalSlot,
                                     BOOL required,
                                     const char *logLabel) {
    if (!cls || !replacement || !originalSlot) {
        return NO;
    }

    Method existing = class_getClassMethod(cls, selector);
    if (!existing) {
        if (required) {
            NSLog(@"[DKXS][RuntimeHook][HideMessageAndMinePage] %@ 缺少类方法 %@：%@",
                  logLabel,
                  NSStringFromSelector(selector),
                  NSStringFromClass(cls));
        }
        return NO;
    }

    const char *typeEncoding = method_getTypeEncoding(existing);
    IMP existingIMP = method_getImplementation(existing);
    if (existingIMP == replacement) {
        return *originalSlot != NULL;
    }

    IMP previous = method_setImplementation(existing, replacement);
    if (!previous || previous == replacement) {
        NSLog(@"[DKXS][RuntimeHook][HideMessageAndMinePage] %@ 无法保存原类方法 IMP：%@",
              logLabel,
              NSStringFromClass(cls));
        return NO;
    }
    *originalSlot = (DKXSBoolContextIMP)previous;
    return YES;
}

static BOOL DKXSInstallInstanceSizeHook(Class cls,
                                          SEL selector,
                                          IMP replacement,
                                          DKXSSizeIMP *originalSlot,
                                          BOOL required,
                                          const char *logLabel) {
    if (!cls || !replacement || !originalSlot) {
        return NO;
    }

    Method existing = class_getInstanceMethod(cls, selector);
    if (!existing) {
        if (required) {
            NSLog(@"[DKXS][RuntimeHook][HideMessageAndMinePage] %@ 缺少 %@：%@",
                  logLabel,
                  NSStringFromSelector(selector),
                  NSStringFromClass(cls));
        }
        return NO;
    }

    const char *typeEncoding = method_getTypeEncoding(existing);
    IMP existingIMP = method_getImplementation(existing);
    if (existingIMP == replacement) {
        return *originalSlot != NULL;
    }

    BOOL methodDefinedOnClass = NO;
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(cls, &methodCount);
    for (unsigned int i = 0; i < methodCount; i++) {
        if (method_getName(methods[i]) == selector) {
            methodDefinedOnClass = YES;
            break;
        }
    }
    free(methods);

    if (!methodDefinedOnClass) {
        IMP superIMP = existingIMP;
        if (!class_addMethod(cls, selector, replacement, typeEncoding)) {
            if (required) {
                NSLog(@"[DKXS][RuntimeHook][HideMessageAndMinePage] %@ class_addMethod 失败：%@",
                      logLabel,
                      NSStringFromClass(cls));
            }
            return NO;
        }
        *originalSlot = (DKXSSizeIMP)superIMP;
        return YES;
    }

    IMP previous = method_setImplementation(existing, replacement);
    if (!previous || previous == replacement) {
        NSLog(@"[DKXS][RuntimeHook][HideMessageAndMinePage] %@ 无法保存原 IMP：%@",
              logLabel,
              NSStringFromClass(cls));
        return NO;
    }
    *originalSlot = (DKXSSizeIMP)previous;
    return YES;
}

static BOOL DKXSInstallInstanceVoidUpdateUIHook(Class cls,
                                                SEL selector,
                                                IMP replacement,
                                                DKXSVoidUpdateUIIMP *originalSlot,
                                                BOOL required,
                                                const char *logLabel) {
    if (!cls || !replacement || !originalSlot) {
        return NO;
    }

    Method existing = class_getInstanceMethod(cls, selector);
    if (!existing) {
        if (required) {
            NSLog(@"[DKXS][RuntimeHook][HideMessageAndMinePage] %@ 缺少 %@：%@",
                  logLabel,
                  NSStringFromSelector(selector),
                  NSStringFromClass(cls));
        }
        return NO;
    }

    const char *typeEncoding = method_getTypeEncoding(existing);
    IMP existingIMP = method_getImplementation(existing);
    if (existingIMP == replacement) {
        return *originalSlot != NULL;
    }

    BOOL methodDefinedOnClass = NO;
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(cls, &methodCount);
    for (unsigned int i = 0; i < methodCount; i++) {
        if (method_getName(methods[i]) == selector) {
            methodDefinedOnClass = YES;
            break;
        }
    }
    free(methods);

    if (!methodDefinedOnClass) {
        IMP superIMP = existingIMP;
        if (!class_addMethod(cls, selector, replacement, typeEncoding)) {
            if (required) {
                NSLog(@"[DKXS][RuntimeHook][HideMessageAndMinePage] %@ class_addMethod 失败：%@",
                      logLabel,
                      NSStringFromClass(cls));
            }
            return NO;
        }
        *originalSlot = (DKXSVoidUpdateUIIMP)superIMP;
        return YES;
    }

    IMP previous = method_setImplementation(existing, replacement);
    if (!previous || previous == replacement) {
        NSLog(@"[DKXS][RuntimeHook][HideMessageAndMinePage] %@ 无法保存原 IMP：%@",
              logLabel,
              NSStringFromClass(cls));
        return NO;
    }
    *originalSlot = (DKXSVoidUpdateUIIMP)previous;
    return YES;
}

static BOOL DKXSInstallInstanceIMPHook(Class cls,
                                       SEL selector,
                                       IMP replacement,
                                       IMP *originalSlot,
                                       BOOL required,
                                       const char *logLabel) {
    if (!cls || !replacement || !originalSlot) {
        return NO;
    }

    Method existing = class_getInstanceMethod(cls, selector);
    if (!existing) {
        if (required) {
            NSLog(@"[DKXS][RuntimeHook][HideMessageAndMinePage] %@ 缺少 %@：%@",
                  logLabel,
                  NSStringFromSelector(selector),
                  NSStringFromClass(cls));
        }
        return NO;
    }

    const char *typeEncoding = method_getTypeEncoding(existing);
    IMP existingIMP = method_getImplementation(existing);
    if (existingIMP == replacement) {
        return *originalSlot != NULL;
    }

    BOOL methodDefinedOnClass = NO;
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(cls, &methodCount);
    for (unsigned int i = 0; i < methodCount; i++) {
        if (method_getName(methods[i]) == selector) {
            methodDefinedOnClass = YES;
            break;
        }
    }
    free(methods);

    if (!methodDefinedOnClass) {
        IMP superIMP = existingIMP;
        if (!class_addMethod(cls, selector, replacement, typeEncoding)) {
            if (required) {
                NSLog(@"[DKXS][RuntimeHook][HideMessageAndMinePage] %@ class_addMethod 失败：%@",
                      logLabel,
                      NSStringFromClass(cls));
            }
            return NO;
        }
        *originalSlot = superIMP;
        return YES;
    }

    IMP previous = method_setImplementation(existing, replacement);
    if (!previous || previous == replacement) {
        NSLog(@"[DKXS][RuntimeHook][HideMessageAndMinePage] %@ 无法保存原 IMP：%@",
              logLabel,
              NSStringFromClass(cls));
        return NO;
    }
    *originalSlot = previous;
    return YES;
}

static BOOL DKXSInstallLayoutSubviewsHook(Class cls,
                                          DKXSVoidLayoutIMP replacement,
                                          DKXSVoidLayoutIMP *originalSlot,
                                          BOOL required,
                                          const char *logLabel) {
    if (!cls || !replacement || !originalSlot) {
        return NO;
    }

    SEL selector = @selector(layoutSubviews);
    Method existing = class_getInstanceMethod(cls, selector);
    if (!existing) {
        if (required) {
            NSLog(@"[DKXS][RuntimeHook][HideMessageAndMinePage] %@ 缺少 layoutSubviews：%@",
                  logLabel,
                  NSStringFromClass(cls));
        }
        return NO;
    }

    const char *typeEncoding = method_getTypeEncoding(existing);
    IMP existingIMP = method_getImplementation(existing);
    if (existingIMP == (IMP)replacement) {
        return *originalSlot != NULL;
    }

    BOOL methodDefinedOnClass = NO;
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(cls, &methodCount);
    for (unsigned int i = 0; i < methodCount; i++) {
        if (method_getName(methods[i]) == selector) {
            methodDefinedOnClass = YES;
            break;
        }
    }
    free(methods);

    if (!methodDefinedOnClass) {
        IMP superIMP = existingIMP;
        if (!class_addMethod(cls, selector, (IMP)replacement, typeEncoding)) {
            if (required) {
                NSLog(@"[DKXS][RuntimeHook][HideMessageAndMinePage] %@ class_addMethod 失败：%@",
                      logLabel,
                      NSStringFromClass(cls));
            }
            return NO;
        }
        *originalSlot = (DKXSVoidLayoutIMP)superIMP;
        return YES;
    }

    IMP previous = method_setImplementation(existing, (IMP)replacement);
    if (!previous || previous == (IMP)replacement) {
        NSLog(@"[DKXS][RuntimeHook][HideMessageAndMinePage] %@ 无法保存原 IMP：%@",
              logLabel,
              NSStringFromClass(cls));
        return NO;
    }
    *originalSlot = (DKXSVoidLayoutIMP)previous;
    return YES;
}

void DKXSStartHideMessageAndMinePageHooks(void) {
    bool expected = false;
    if (!atomic_compare_exchange_strong(&gDKXSHideMessageAndMinePageHooksStarted, &expected, true)) {
        return;
    }

    NSUInteger installed = 0;

    Class resourceSlotClass = objc_getClass("AWEIMMessageTabNavBarResourceSlotComponent");
    if (resourceSlotClass &&
        DKXSInstallInstanceBOOLHook(resourceSlotClass,
                                    @selector(canShowInNaviBar),
                                    (IMP)DKXSMessageTabResourceSlotCanShowInNaviBar,
                                    &gOrigMessageTabResourceSlotCanShow,
                                    NO,
                                    "MessageTabStarMall")) {
        installed += 1;
    }

    Class resourceSlotV2Class = objc_getClass("AWEIMMessageTabNavBarResourceSlotComponentV2");
    if (resourceSlotV2Class &&
        DKXSInstallInstanceBOOLHook(resourceSlotV2Class,
                                    @selector(canShowInNaviBar),
                                    (IMP)DKXSMessageTabResourceSlotV2CanShowInNaviBar,
                                    &gOrigMessageTabResourceSlotV2CanShow,
                                    YES,
                                    "MessageTabStarMall")) {
        installed += 1;
    }

    Class storyPublishClass = objc_getClass("AWEProfileAvatarStoryPublishController");
    if (storyPublishClass) {
        if (DKXSInstallInstanceBOOLHook(storyPublishClass,
                                        @selector(canShow),
                                        (IMP)DKXSProfileStoryPublishCanShow,
                                        &gOrigProfileStoryPublishCanShow,
                                        YES,
                                        "MineAvatarPlus")) {
            installed += 1;
        }
        if (DKXSInstallInstanceVoidUpdateUIHook(storyPublishClass,
                                                @selector(updateUIWithContainerView:anchorView:),
                                                (IMP)DKXSProfileStoryPublishUpdateUI,
                                                &gOrigProfileStoryPublishUpdateUI,
                                                NO,
                                                "MineAvatarPlus")) {
            installed += 1;
        }
    }

    Class genericOperationClass = objc_getClass("AWEProfileHeaderGenericOperationComponent");
    if (genericOperationClass) {
        if (DKXSInstallInstanceIMPHook(genericOperationClass,
                                       @selector(buildVirtualView:),
                                       (IMP)DKXSGenericOperationBuildVirtualView,
                                       (IMP *)&gOrigGenericOperationBuildVirtualView,
                                       YES,
                                       "MineAICreation")) {
            installed += 1;
        }
        if (DKXSInstallInstanceIMPHook(genericOperationClass,
                                       @selector(updateComponentData:),
                                       (IMP)DKXSGenericOperationUpdateComponentData,
                                       (IMP *)&gOrigGenericOperationUpdateComponentData,
                                       NO,
                                       "MineAICreation")) {
            installed += 1;
        }
    }

    NSLog(@"[DKXS][RuntimeHook][HideMessageAndMinePage] 安装完成，成功 %lu 个目标", (unsigned long)installed);
}
