// 移植自 Si-yi/DYads- f07ddb5（DYYYRecallHooks.xm）：改名一律 DYYY -> DKXS，设置键同步改名，逻辑原样；
// 适配见各文件内注释（DYxs 已有实现复用 / 上游已删模块不移植）。
// 最小接口声明（只声明本文件 hook 到的类与方法，不 import DKXSAwemeHeaders / DouyinHeaders，沿用第 8 批写法）。
@interface TIMXOMessage : NSObject
- (id)initWithRootObject:(id)root model:(id)model;
- (id)initWithRootObject:(id)root identifier:(id)identifier;
- (id)initEmptyNoCacheInstanceWithRootObject:(id)root;
+ (id)cachedInstanceWithRootObject:(id)root identifier:(id)identifier;
+ (id)instanceWithRootObject:(id)root identifier:(id)identifier inConversation:(id)conversation;
- (void)setContent:(id)content;
- (id)content;
- (void)setRecalled:(BOOL)recalled;
- (BOOL)recalled;
- (void)setRecalledContent:(id)content;
- (void)setFileDownloadProgressPercentage:(int)percentage;
@end
@interface AWEIMMessage : NSObject
+ (id)messageWithContext:(id)context;
+ (id)createMessageWithContext:(id)context;
- (id)filePath;
- (id)awe_filePathDictionary;
@end
@interface AWEIMReusableCommonCell : UITableViewCell
@end
@interface AWEIMMessageListViewController : UIViewController
@end
#import <objc/runtime.h>
#import "DKXSRecallCoordinator.h"
#import "DKXSChatEnhancementPolicy.h"

%group DKXSRecallInitHooks
%hook TIMXOMessage
- (id)initWithRootObject:(id)root model:(id)model {
    id result=%orig(root,model);
    [DKXSRecallCoordinator bindModel:result root:root];
    return result;
}
%end
%end
%group DKXSRecallIdentityInitHooks
%hook TIMXOMessage
- (id)initWithRootObject:(id)root identifier:(id)identifier { id result=%orig(root,identifier);[DKXSRecallCoordinator bindModel:result root:root];return result; }
%end
%end
%group DKXSRecallEmptyInitHooks
%hook TIMXOMessage
- (id)initEmptyNoCacheInstanceWithRootObject:(id)root { id result=%orig(root);[DKXSRecallCoordinator bindModel:result root:root];return result; }
%end
%end
%group DKXSRecallCacheFactoryHooks
%hook TIMXOMessage
+ (id)cachedInstanceWithRootObject:(id)root identifier:(id)identifier { id result=%orig(root,identifier);[DKXSRecallCoordinator bindModel:result root:root];return result; }
%end
%end
%group DKXSRecallFactoryHooks
%hook TIMXOMessage
+ (id)instanceWithRootObject:(id)root identifier:(id)identifier inConversation:(id)conversation { id result=%orig(root,identifier,conversation);[DKXSRecallCoordinator bindModel:result root:root];return result; }
%end
%end
%group DKXSRecallContentHooks
%hook TIMXOMessage
- (void)setContent:(id)content {
    [DKXSRecallCoordinator captureContent:content model:self];
    NSDictionary *retained=[DKXSRecallCoordinator protectedContentForModel:self];
    %orig(retained?:content);
}
- (id)content {
    NSDictionary *retained=[DKXSRecallCoordinator protectedContentForModel:self];
    return retained?:%orig;
}
%end
%end
%group DKXSRecallFlagHooks
%hook TIMXOMessage
- (void)setRecalled:(BOOL)recalled {
    [DKXSRecallCoordinator observeRecalled:recalled model:self];
    %orig(recalled && ![DKXSRecallCoordinator protectModel:self]);
}
- (BOOL)recalled {
    if([DKXSRecallCoordinator protectModel:self])return NO;
    BOOL result=%orig;
    if(result)[DKXSRecallCoordinator observeRecalled:YES model:self];
    return result;
}
%end
%end
%group DKXSRecallOriginalContentHooks
%hook TIMXOMessage
- (void)setRecalledContent:(id)content {
    [DKXSRecallCoordinator captureOriginalContent:content model:self];
    %orig(content);
}
%end
%end
%group DKXSRecallDownloadHooks
%hook TIMXOMessage
- (void)setFileDownloadProgressPercentage:(int)percentage {
    %orig(percentage);
    if(percentage==100)[DKXSRecallCoordinator mediaDownloadCompleted:self];
}
%end
%end
%group DKXSRecallUIFactoryHooks
%hook AWEIMMessage
+ (id)messageWithContext:(id)context { return [DKXSRecallCoordinator replacementForUIMessage:%orig(context)]; }
+ (id)createMessageWithContext:(id)context { return [DKXSRecallCoordinator replacementForUIMessage:%orig(context)]; }
%end
%end
%group DKXSRecallUIFileHooks
%hook AWEIMMessage
- (id)filePath { return [DKXSRecallCoordinator mediaPathForUIMessage:self original:%orig]; }
- (id)awe_filePathDictionary { return [DKXSRecallCoordinator mediaPathsForUIMessage:self original:%orig]; }
%end
%end
%group DKXSRecallCellHooks
%hook AWEIMReusableCommonCell
- (void)setCurrentContext:(id)context { [DKXSRecallCoordinator resetCell:self]; %orig(context); [DKXSRecallCoordinator captureCell:self]; }
- (void)didMoveToWindow { %orig; [DKXSRecallCoordinator captureCell:self]; }
- (void)layoutSubviews { %orig; [DKXSRecallCoordinator captureCell:self]; }
- (void)prepareForReuse { [DKXSRecallCoordinator resetCell:self]; %orig; }
%end
%end
%group DKXSRecallListHooks
%hook AWEIMMessageListViewController
- (void)viewDidAppear:(BOOL)animated { %orig(animated); [DKXSRecallCoordinator controllerAppeared:self]; }
%end
%end

@implementation DKXSRecallCoordinator (Hooks)
+ (void)installHooks {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self installHooks];});return;}
    static BOOL init,identityInit,emptyInit,cacheFactory,messageFactory,content,flag,original,download,factory,files,cells,list;
    Class sdk=NSClassFromString(@"TIMXOMessage"),ui=NSClassFromString(@"AWEIMMessage"),cell=NSClassFromString(@"AWEIMReusableCommonCell");
    BOOL initReady=[DKXSChatEnhancementPolicy class:sdk selector:@selector(initWithRootObject:model:) result:'@' arguments:@"@@"];
    BOOL contentReady=[DKXSChatEnhancementPolicy class:sdk selector:@selector(setContent:) result:'v' arguments:@"@"] && [DKXSChatEnhancementPolicy class:sdk selector:@selector(content) result:'@' arguments:@""];
    BOOL flagReady=[DKXSChatEnhancementPolicy class:sdk selector:@selector(setRecalled:) result:'v' arguments:@"B"] && [DKXSChatEnhancementPolicy class:sdk selector:@selector(recalled) result:'B' arguments:@""];
    [self recordHook:@"nativeInterfacesAvailable" installed:initReady && contentReady && flagReady];
    if([self enabled]){
        if(!init && initReady){%init(DKXSRecallInitHooks);init=YES;}
        if(!identityInit && [DKXSChatEnhancementPolicy class:sdk selector:@selector(initWithRootObject:identifier:) result:'@' arguments:@"@@"]){%init(DKXSRecallIdentityInitHooks);identityInit=YES;}
        if(!emptyInit && [DKXSChatEnhancementPolicy class:sdk selector:@selector(initEmptyNoCacheInstanceWithRootObject:) result:'@' arguments:@"@"]){%init(DKXSRecallEmptyInitHooks);emptyInit=YES;}
        if(!cacheFactory && [DKXSChatEnhancementPolicy class:object_getClass(sdk) selector:@selector(cachedInstanceWithRootObject:identifier:) result:'@' arguments:@"@@"]){%init(DKXSRecallCacheFactoryHooks);cacheFactory=YES;}
        if(!messageFactory && [DKXSChatEnhancementPolicy class:object_getClass(sdk) selector:@selector(instanceWithRootObject:identifier:inConversation:) result:'@' arguments:@"@@@"]){%init(DKXSRecallFactoryHooks);messageFactory=YES;}
        if(!content && contentReady){%init(DKXSRecallContentHooks);content=YES;}
        if(!flag && flagReady){%init(DKXSRecallFlagHooks);flag=YES;}
        if(!original && [DKXSChatEnhancementPolicy class:sdk selector:@selector(setRecalledContent:) result:'v' arguments:@"@"]){%init(DKXSRecallOriginalContentHooks);original=YES;}
        if(!download && [DKXSChatEnhancementPolicy class:sdk selector:@selector(setFileDownloadProgressPercentage:) result:'v' arguments:@"i"]){%init(DKXSRecallDownloadHooks);download=YES;}
        if(!factory && [DKXSChatEnhancementPolicy class:object_getClass(ui) selector:@selector(messageWithContext:) result:'@' arguments:@"@"] && [DKXSChatEnhancementPolicy class:object_getClass(ui) selector:@selector(createMessageWithContext:) result:'@' arguments:@"@"]){%init(DKXSRecallUIFactoryHooks);factory=YES;}
        if(!files && [DKXSChatEnhancementPolicy class:ui selector:@selector(filePath) result:'@' arguments:@""] && [DKXSChatEnhancementPolicy class:ui selector:@selector(awe_filePathDictionary) result:'@' arguments:@""]){%init(DKXSRecallUIFileHooks);files=YES;}
        if(!cells && [cell isSubclassOfClass:UITableViewCell.class] && [DKXSChatEnhancementPolicy class:cell selector:@selector(setCurrentContext:) result:'v' arguments:@"@"]){%init(DKXSRecallCellHooks);cells=YES;}
        if(!list && [DKXSChatEnhancementPolicy class:NSClassFromString(@"AWEIMMessageListViewController") selector:@selector(viewDidAppear:) result:'v' arguments:@"B"]){%init(DKXSRecallListHooks);list=YES;}
    }
    [self recordHook:@"nativeInit" installed:init || identityInit || emptyInit];[self recordHook:@"nativeFactories" installed:cacheFactory && messageFactory];[self recordHook:@"content" installed:content];[self recordHook:@"recallFlag" installed:flag];[self recordHook:@"originalContent" installed:original];[self recordHook:@"uiFactory" installed:factory];[self recordHook:@"mediaPaths" installed:files];[self recordHook:@"downloadCompletion" installed:download];[self recordHook:@"cells" installed:cells];
}
@end
%ctor {
    [NSUserDefaults.standardUserDefaults registerDefaults:@{@"DKXSRecallShowMarker":@YES,@"DKXSRecallKeepMedia":@YES}];
    dispatch_async(dispatch_get_main_queue(),^{[DKXSRecallCoordinator settingsChanged];});
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note){[DKXSRecallCoordinator installHooks];}];
}
