// 移植来源：Wtrwx/DYYY 的 DYYYRuntimeHookInstaller.h；按计划供本批/第 2 批复用。
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, DKXSRuntimeHookInstallStatus) {
    DKXSRuntimeHookInstallStatusInstalled,
    DKXSRuntimeHookInstallStatusAlreadyInstalled,
    DKXSRuntimeHookInstallStatusTargetClassMissing,
    DKXSRuntimeHookInstallStatusTargetMethodMissing,
    DKXSRuntimeHookInstallStatusTypeEncodingMismatch,
    DKXSRuntimeHookInstallStatusReplacementMissing,
    DKXSRuntimeHookInstallStatusReplacementSelfReference,
    DKXSRuntimeHookInstallStatusConflict,
};

typedef struct {
    const char *identifier;
    Class targetClass;
    SEL selector;
    BOOL classMethod;
    IMP replacement;
    const char *_Nonnull const *_Nullable allowedTypeEncodings;
    NSUInteger allowedTypeEncodingCount;
    IMP _Nullable *_Nullable originalImplementation;
} DKXSRuntimeHookRequest;

typedef struct {
    DKXSRuntimeHookInstallStatus status;
    IMP _Nullable previousImplementation;
    const char *_Nullable actualTypeEncoding;
    BOOL methodWasInherited;
} DKXSRuntimeHookInstallResult;

FOUNDATION_EXPORT DKXSRuntimeHookInstallResult DKXSInstallRuntimeHook(DKXSRuntimeHookRequest request);
FOUNDATION_EXPORT NSString *DKXSRuntimeHookInstallStatusName(DKXSRuntimeHookInstallStatus status);

NS_ASSUME_NONNULL_END
