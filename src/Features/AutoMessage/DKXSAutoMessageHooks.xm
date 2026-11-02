#import "DKXSAwemeHeaders.h"
#import "DKXSAutoMessage.h"
#import "DKXSIMService.h"
#import "DKXSIMConversationStore.h"
#import "DKXSFriendShareService.h"
#import "DKXSFriendShareBadgeView.h"
#import "DKXSUtils.h"

%hook AWEPlayInteractionViewController
- (void)setModel:(AWEAwemeModel *)model {
    [DKXSFriendShareBadgeView resetForController:self];
    %orig(model);
}
- (void)viewWillLayoutSubviews {
    %orig;
}
- (void)viewDidLayoutSubviews {
    %orig;
    [DKXSFriendShareBadgeView updateForController:self];
}
- (void)viewWillAppear:(BOOL)animated {
    %orig;
}
- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    // 相邻缓存页仍使用页内最终位置；真正离开详情或离窗时由作用域检查恢复。
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
}
%end


%hook AWEElementStackView
- (void)layoutSubviews {
    %orig;
    if (![NSUserDefaults.standardUserDefaults boolForKey:@"DKXSFriendShareFeedEnabled"]) return;
    UIViewController *controller = [DKXSUtils firstAvailableViewControllerFromView:self];
    if ([controller isKindOfClass:NSClassFromString(@"AWEPlayInteractionViewController")]) [DKXSFriendShareBadgeView updateForController:controller];
}
%end

// 复用抖音创建并配置好的实例，不自己 new 消息 SDK，也不调用其他插件。
%hook AWEIMUserDBManager
- (id)init {
    id result = %orig;
    [DKXSIMService captureService:result role:@"contacts"];
    return result;
}
%end

%hook AWEFeedTableViewController
- (void)viewDidLoad {
    %orig;
    [DKXSFriendShareService bindHomeFeed:self];
}
- (void)setDataController:(id)controller {
    %orig(controller);
    __weak UIViewController *weakFeed = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [DKXSFriendShareService bindHomeFeed:weakFeed]; });
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [DKXSFriendShareService bindHomeFeed:self];
}
- (void)viewWillDisappear:(BOOL)animated {
    [DKXSFriendShareService homeDidLeave:self];
    %orig;
}
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    %orig;
    [DKXSFriendShareService homeDidEndScrolling:self scrollView:scrollView];
}
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    [DKXSFriendShareService homeWillDrag:self scrollView:scrollView];
    %orig;
}
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    %orig;
    if (!decelerate) [DKXSFriendShareService homeDidEndScrolling:self scrollView:scrollView];
}
- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    %orig;
    [DKXSFriendShareService homeDidEndScrolling:self scrollView:scrollView];
}
- (void)videoPlayer:(id)player didSingleClick:(id)event {
    [DKXSFriendShareService homePlaybackTouched:self];
    %orig(player, event);
}
- (void)videoPlayer:(id)player updatePlayTime:(double)time totalTime:(double)total {
    %orig(player, time, total);
    [DKXSFriendShareService homePlaybackAdvanced:self time:time];
}
- (void)videoControllerWillStartNextLoop:(id)controller {
    [DKXSFriendShareService homeWillLoop:self];
    %orig;
}
- (void)pi_scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    [DKXSFriendShareService homeWillDrag:self scrollView:scrollView];
    %orig;
}
- (void)pi_scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    %orig;
    if (!decelerate) [DKXSFriendShareService homeDidEndScrolling:self scrollView:scrollView];
}
%end

%hook AWEFeedCellViewController
- (void)didDisplay {
    %orig;
    [DKXSFriendShareService homeCellDidDisplay:self];
}
%end

%hook AWEPlayVideoViewController
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    [DKXSFriendShareService homePlayerWillLeave:self];
    %orig(controller, animated, completion);
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [DKXSFriendShareService homePlayerDidReturn:self];
}
%end

%hook AWEDPlayerViewController_Merge
- (void)player:(id)player updatePlayTime:(double)time canPlayTime:(double)buffered totalTime:(double)total {
    [DKXSFriendShareService playerPlaybackAdvanced:self time:time];
    %orig(player, time, buffered, total);
}
- (void)playerWillStartNextLoop:(id)player {
    [DKXSFriendShareService playerWillLoop:self];
    %orig;
}
%end

%hook AWEListDataController
- (void)setDataSource:(NSMutableArray *)data {
    NSArray *ordered = [DKXSFriendShareService arrangeData:data controller:self];
    %orig(ordered == data ? data : [ordered mutableCopy]);
}
%end

%hook AWEHotListDataController
- (id)_refreshDataSourceWithArray:(id)data cleanRefresh:(BOOL)clean requestId:(id)requestID {
    NSArray *ordered = [DKXSFriendShareService arrangeData:data controller:self];
    return %orig(ordered, clean, requestID);
}
- (void)updateAwemeList:(id)data {
    NSArray *ordered = [DKXSFriendShareService arrangeData:data controller:self];
    %orig(ordered);
}
%end

%hook TIMXOConversationManager
- (id)initWithRootObject:(id)root {
    id result = %orig;
    [DKXSIMService captureService:result role:@"conversations"];
    return result;
}
%end

%hook TIMXOConversation
+ (id)cachedInstanceWithRootObject:(id)root identifier:(id)identifier {
    id result = %orig(root, identifier);
    [DKXSIMConversationStore observeNativeConversation:result root:root identifier:identifier];
    return result;
}
+ (id)instanceWithRootObject:(id)root identifier:(id)identifier {
    id result = %orig(root, identifier);
    [DKXSIMConversationStore observeNativeConversation:result root:root identifier:identifier];
    return result;
}
+ (id)instanceWithRootObject:(id)root pbModel:(id)model {
    id result = %orig(root, model);
    [DKXSIMConversationStore observeNativeConversation:result root:root identifier:nil];
    return result;
}
+ (id)instanceWithRootObject:(id)root modelORM:(id)model {
    id result = %orig(root, model);
    [DKXSIMConversationStore observeNativeConversation:result root:root identifier:nil];
    return result;
}
+ (id)instanceWithRootObject:(id)root identifier:(id)identifier modelProtocol:(id)model coreInfo:(id)core settingsInfo:(id)settings {
    id result = %orig(root, identifier, model, core, settings);
    [DKXSIMConversationStore observeNativeConversation:result root:root identifier:identifier];
    return result;
}
- (id)sendMessage:(id)model error:(void *)error {
    [DKXSIMService observeConversationSend:model conversation:self];
    return %orig;
}
- (id)sendMessage:(id)model isSaveDB:(BOOL)saveDB error:(void *)error {
    [DKXSIMService observeConversationSend:model conversation:self];
    return %orig;
}
%end

%hook IESIMMessageSender
- (id)init {
    id result = %orig;
    [DKXSIMService captureService:result role:@"sender"];
    return result;
}
- (id)sendMessage:(id)model {
    [DKXSIMService observeTextModel:model sender:self];
    return %orig;
}
- (void)asyncSendMessage:(id)model completion:(id)completion {
    [DKXSIMService observeTextModel:model sender:self];
    %orig;
}
- (void)message:(id)message inConversation:(id)conversation didReceiveResponse:(id)response error:(id)error {
    %orig;
    [DKXSIMService observeMessage:message conversation:conversation error:error];
}
- (void)message:(id)message inConversation:(id)conversation didReceiveAsyncResponse:(id)response error:(id)error {
    %orig;
    [DKXSIMService observeMessage:message conversation:conversation error:error];
}
%end

%hook TIMXOMessageManager
- (id)initWithRootObject:(id)root {
    id result = %orig;
    [DKXSIMService captureService:result role:@"messages"];
    return result;
}
- (id)messagesInConversation:(id)conversation excludeMessageTypes:(id)types limit:(unsigned long long)limit {
    [DKXSIMService observeHistoryQuery:conversation manager:self];
    id result = %orig;
    [DKXSIMService observeHistoryResults:result manager:self];
    return result;
}
%end

// 自动消息仅由前台通知调度，不在切页和返回设置时重复执行。

%ctor {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (![defaults boolForKey:@"DKXSFriendShareLaunchRefreshConfigured"]) {
        [defaults setBool:YES forKey:@"DKXSFriendShareAutoRefreshEnabled"];
        [defaults setBool:YES forKey:@"DKXSFriendShareLaunchRefreshConfigured"];
    }
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
        [DKXSFriendShareService applicationBecameActive];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [DKXSAutoMessage runDailyMessageCheckIfNeeded];
        });
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
        [DKXSFriendShareService applicationEnteredBackground];
    }];
}

