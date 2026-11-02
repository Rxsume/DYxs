// 移植来源：Wtrwx/DYYY 的 DYYYRuntimeHookInstaller.m；按计划供本批/第 2 批复用。
#import "DKXSRuntimeHookInstaller.h"

#import <os/lock.h>

static os_unfair_lock gDKXSRuntimeHookRegistryLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSString *, NSDictionary<NSString *, NSValue *> *> *gDKXSRuntimeHookRegistry;

static BOOL DKXSClassOwnsSelector(Class cls, SEL selector) {
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(cls, &methodCount);
    BOOL ownsSelector = NO;
    for (unsigned int index = 0; index < methodCount; index++) {
        if (method_getName(methods[index]) == selector) {
            ownsSelector = YES;
            break;
        }
    }
    free(methods);
    return ownsSelector;
}

static BOOL DKXSTypeEncodingAllowed(const char *actualEncoding,
                                    const char *const *allowedEncodings,
                                    NSUInteger allowedEncodingCount) {
    if (!actualEncoding || !allowedEncodings || allowedEncodingCount == 0) {
        return NO;
    }
    for (NSUInteger index = 0; index < allowedEncodingCount; index++) {
        const char *candidate = allowedEncodings[index];
        if (candidate && strcmp(actualEncoding, candidate) == 0) {
            return YES;
        }
    }
    return NO;
}

static NSString *DKXSRuntimeHookRegistryKey(DKXSRuntimeHookRequest request) {
    return [NSString stringWithFormat:@"%s|%@|%@",
                                      class_getName(request.targetClass) ?: "<missing>",
                                      request.classMethod ? @"+" : @"-",
                                      NSStringFromSelector(request.selector)];
}

DKXSRuntimeHookInstallResult DKXSInstallRuntimeHook(DKXSRuntimeHookRequest request) {
    DKXSRuntimeHookInstallResult result = {
        .status = DKXSRuntimeHookInstallStatusTargetClassMissing,
        .previousImplementation = NULL,
        .actualTypeEncoding = NULL,
        .methodWasInherited = NO,
    };
    if (!request.targetClass) {
        return result;
    }
    if (!request.replacement) {
        result.status = DKXSRuntimeHookInstallStatusReplacementMissing;
        return result;
    }

    Class installationClass = request.classMethod ? object_getClass(request.targetClass) : request.targetClass;
    Method method = class_getInstanceMethod(installationClass, request.selector);
    if (!method) {
        result.status = DKXSRuntimeHookInstallStatusTargetMethodMissing;
        return result;
    }

    const char *typeEncoding = method_getTypeEncoding(method);
    result.actualTypeEncoding = typeEncoding;
    if (!DKXSTypeEncodingAllowed(typeEncoding, request.allowedTypeEncodings, request.allowedTypeEncodingCount)) {
        result.status = DKXSRuntimeHookInstallStatusTypeEncodingMismatch;
        return result;
    }

    IMP currentImplementation = method_getImplementation(method);
    NSString *registryKey = DKXSRuntimeHookRegistryKey(request);
    os_unfair_lock_lock(&gDKXSRuntimeHookRegistryLock);
    if (!gDKXSRuntimeHookRegistry) {
        gDKXSRuntimeHookRegistry = [NSMutableDictionary dictionary];
    }
    NSDictionary<NSString *, NSValue *> *existing = gDKXSRuntimeHookRegistry[registryKey];
    if (existing) {
        IMP installedReplacement = [existing[@"replacement"] pointerValue];
        IMP previousImplementation = [existing[@"previous"] pointerValue];
        result.previousImplementation = previousImplementation;
        if (installedReplacement == request.replacement) {
            if (request.originalImplementation) {
                *request.originalImplementation = previousImplementation;
            }
            result.status = DKXSRuntimeHookInstallStatusAlreadyInstalled;
        } else {
            result.status = DKXSRuntimeHookInstallStatusConflict;
        }
        os_unfair_lock_unlock(&gDKXSRuntimeHookRegistryLock);
        return result;
    }
    if (currentImplementation == request.replacement) {
        result.status = DKXSRuntimeHookInstallStatusReplacementSelfReference;
        os_unfair_lock_unlock(&gDKXSRuntimeHookRegistryLock);
        return result;
    }

    BOOL ownsSelector = DKXSClassOwnsSelector(installationClass, request.selector);
    result.methodWasInherited = !ownsSelector;
    BOOL installed = NO;
    if (!ownsSelector) {
        installed = class_addMethod(installationClass, request.selector, request.replacement, typeEncoding);
    } else {
        method_setImplementation(method, request.replacement);
        installed = YES;
    }
    if (!installed) {
        result.status = DKXSRuntimeHookInstallStatusConflict;
        os_unfair_lock_unlock(&gDKXSRuntimeHookRegistryLock);
        return result;
    }

    result.previousImplementation = currentImplementation;
    if (request.originalImplementation) {
        *request.originalImplementation = currentImplementation;
    }
    gDKXSRuntimeHookRegistry[registryKey] = @{
        @"replacement" : [NSValue valueWithPointer:request.replacement],
        @"previous" : [NSValue valueWithPointer:currentImplementation],
    };
    result.status = DKXSRuntimeHookInstallStatusInstalled;
    os_unfair_lock_unlock(&gDKXSRuntimeHookRegistryLock);
    return result;
}

NSString *DKXSRuntimeHookInstallStatusName(DKXSRuntimeHookInstallStatus status) {
    switch (status) {
        case DKXSRuntimeHookInstallStatusInstalled: return @"installed";
        case DKXSRuntimeHookInstallStatusAlreadyInstalled: return @"already-installed";
        case DKXSRuntimeHookInstallStatusTargetClassMissing: return @"class-missing";
        case DKXSRuntimeHookInstallStatusTargetMethodMissing: return @"method-missing";
        case DKXSRuntimeHookInstallStatusTypeEncodingMismatch: return @"encoding-mismatch";
        case DKXSRuntimeHookInstallStatusReplacementMissing: return @"replacement-missing";
        case DKXSRuntimeHookInstallStatusReplacementSelfReference: return @"replacement-self-reference";
        case DKXSRuntimeHookInstallStatusConflict: return @"conflict";
    }
    return @"unknown";
}
