//
//  DKKeys.h
//  集中管理所有 NSUserDefaults 开关键与插件元信息。
//  开关键字符串用于 NSUserDefaults 持久化。
//

#ifndef DKKeys_h
#define DKKeys_h

#import <Foundation/Foundation.h>

#ifndef DK_VERSION
#error DK_VERSION must be injected by Makefile from control Version.
#endif

#pragma mark - 功能组：视频全屏

// 首页、朋友页、好友聊天页、搜索页、其他用户作品页统一由这一个开关控制。
static NSString *const DKKeyVideoFullscreen = @"DYxsVideoFullscreen";

#pragma mark - 功能组：评论区

// 评论区回复底栏（单选，整数）：0 显示 / 1 隐藏（原位置可点击回复）/ 2 移除（点击交给列表）；后两档列表均铺满。
static NSString *const DKKeyCommentReplyBottomBarMode = @"DYxsCommentReplyBottomBarMode";
static NSString *const DKKeyCommentAIParseMode = @"DYxsCommentAIParseMode";
static NSString *const DKKeyCommentSearchAnchorMode = @"DYxsCommentSearchAnchorMode";
static NSString *const DKKeyCommentLunaAnchorMode = @"DYxsCommentLunaAnchorMode";
static NSString *const DKKeyCommentLocationMode = @"DYxsCommentLocationMode";
static NSString *const DKKeyCommentGameAnchorMode = @"DYxsCommentGameAnchorMode";
static NSString *const DKKeyCommentPlayerDiscussionMode = @"DYxsCommentPlayerDiscussionMode";
static NSString *const DKKeyCommentStoreReviewMode = @"DYxsCommentStoreReviewMode";
static NSString *const DKKeyCommentSeriesAnchorMode = @"DYxsCommentSeriesAnchorMode";
static NSString *const DKKeyCommentDramaAnchorMode = @"DYxsCommentDramaAnchorMode";
static NSString *const DKKeyCommentDramaReviewMode = @"DYxsCommentDramaReviewMode";
static NSString *const DKKeyCommentRemoveAllTopTags = @"DYxsCommentRemoveAllTopTags";
static NSString *const DKKeyCommentRemoveAllTabs = @"DYxsCommentRemoveAllTabs";
// 移除评论列表中的「评论氛围是否满意」评价卡片。
static NSString *const DKKeyRemoveCommentSurvey = @"DYxsRemoveCommentSurvey";
static NSString *const DKKeyCommentMediaCleanBottomBar = @"DYxsCommentMediaCleanBottomBar";
// 材质单选（DKMakeGlassChoice）：总开关 + 清透档两个 BOOL，清透档关即系统 Regular。
static NSString *const DKKeyCommentGlass         = @"DYxsCommentGlass";
static NSString *const DKKeyCommentGlassClear    = @"DYxsCommentGlassClear";

#pragma mark - 功能组：分享

// 材质单选（DKMakeGlassChoice）：总开关 + 清透档两个 BOOL，清透档关即系统 Regular。
static NSString *const DKKeySharePanelGlass      = @"DYxsSharePanelGlass";
static NSString *const DKKeySharePanelGlassClear = @"DYxsSharePanelGlassClear";
// 分享面板精简：入口、累计功能目录、前缀 + shareType 的独立移除开关。
static NSString *const DKKeyShareMenu            = @"DYxsShareMenu";
static NSString *const DKKeyShareMenuCatalog     = @"DYxsShareMenuCatalog";
static NSString *const DKKeyShareMenuHidePrefix  = @"DYxsHideShareMenu.";

#pragma mark - 功能组：搜索页精简

static NSString *const DKKeySearchRemoveHistory = @"DYxsSearchRemoveHistory";
static NSString *const DKKeySearchRemoveGuess = @"DYxsSearchRemoveGuess";
static NSString *const DKKeySearchRemoveAllRanks = @"DYxsSearchRemoveAllRanks";
static NSString *const DKKeySearchRemoveRankFooter = @"DYxsSearchRemoveRankFooter";
static NSString *const DKKeySearchRemoveVoice = @"DYxsSearchRemoveVoice";
// 相机入口：0 显示 / 1 隐藏（保留位置与点击）/ 2 移除（原生布局收拢）。
static NSString *const DKKeySearchCameraMode = @"DYxsSearchCameraMode";

#pragma mark - 功能组：应用内通知

// 材质单选（DKMakeGlassChoice）：总开关 + 清透档两个 BOOL，清透档关即系统 Regular。
static NSString *const DKKeyInnerNotiGlass      = @"DYxsInnerNotiGlass";
static NSString *const DKKeyInnerNotiGlassClear = @"DYxsInnerNotiGlassClear";
// 0–100：0 为抖音原圆角，100 为胶囊。未写入时按 100。
static NSString *const DKKeyInnerNotiCorner     = @"DYxsInnerNotiCorner";
static NSString *const DKKeyTipsGlass          = @"DYxsTipsGlass";
static NSString *const DKKeyTipsGlassClear     = @"DYxsTipsGlassClear";

#pragma mark - 功能组：底栏

// 材质单选（DKMakeGlassChoice）：总开关 + 清透档两个 BOOL，清透档关即系统默认磨砂。
static NSString *const DKKeyGlassTabBar      = @"DYxsGlassTabBar";
static NSString *const DKKeyGlassTabBarClear = @"DYxsGlassTabBarClear";
// iPad 玻璃底栏位置（单选）：0 默认居中 / 1 左端 / 2 右端；仅 iPad 生效（见 DKGlassPadElements.xm）。
static NSString *const DKKeyGlassTabBarPadPosition = @"DYxsGlassTabBarPadPosition";
// 悬浮玻璃底栏尺寸（百分比，100 为抖音默认效果）：胶囊等比缩放、胶囊长度、拍摄圆键直径，三者都以底边为锚。
// 常规范围见 DKAdjustRange.m，开启「扩展所有缩放与位移」后放宽。
static NSString *const DKKeyGlassTabBarCapsuleHeight = @"DYxsGlassTabBarCapsuleHeight";
static NSString *const DKKeyGlassTabBarCapsuleLength = @"DYxsGlassTabBarCapsuleLength";
static NSString *const DKKeyGlassTabBarPlusSize      = @"DYxsGlassTabBarPlusSize";
// 自定义拍摄图标：图片本体存文件（见 DKPlusIcon.xm），这个键只作设置项 identifier，
// NSUserDefaults 里不写值。是否使用由「拍摄按钮」（DKKeyPlusStyle）选「自定义图片」决定。
static NSString *const DKKeyPlusIcon         = @"DYxsPlusIcon";
// 底栏项目移除：每项一个 BOOL 键，前缀 + 抖音 tabID（见 DKTabBarRemoval.xm）。
static NSString *const DKKeyBottomBarHidePrefix = @"DYxsHideBottomBar.";
static NSString *const DKKeyHidePlusButton      = @"DYxsHideBottomBar.homepage_publish";
// 设置主页入口的 identifier，NSUserDefaults 里不写值。
static NSString *const DKKeyBottomBar           = @"DYxsBottomBar";

#pragma mark - 功能组：外观定制

// 底栏样式（单选，整数）：0 默认 / 1 单图标 / 2 图标+文字，作用于首页、朋友或商城、消息、我。
static NSString *const DKKeyTabBarStyle = @"DYxsTabBarStyle";
// 拍摄按钮（单选，整数）：0 默认 / 1 新图标 / 2 新双色图标 / 3 自定义图片（图片本体见 DKKeyPlusIcon）。
static NSString *const DKKeyPlusStyle   = @"DYxsPlusStyle";
// 底栏文字：每项一个字符串键，前缀 + 抖音 tabID；未设置即抖音默认文字。
static NSString *const DKKeyTabTitlePrefix       = @"DYxsTabBarTitle.";
static NSString *const DKKeyTabTitleHome         = @"DYxsTabBarTitle.homepage_home";
static NSString *const DKKeyTabTitleFriends      = @"DYxsTabBarTitle.homepage_familiar";
static NSString *const DKKeyTabTitleMall         = @"DYxsTabBarTitle.homepage_mall";
static NSString *const DKKeyTabTitleNotification = @"DYxsTabBarTitle.homepage_notification";
static NSString *const DKKeyTabTitleProfile      = @"DYxsTabBarTitle.homepage_profile";

#pragma mark - 功能组：互动按钮

// 图标单选：0 默认 / 1 第一款内置 / 2 第二款内置 / 3 自定义；图片项标识只用于文件与备份。
static NSString *const DKKeyInteractionLikeStyle = @"DYxsInteractionLikeStyle";
static NSString *const DKKeyInteractionCommentStyle = @"DYxsInteractionCommentStyle";
static NSString *const DKKeyInteractionFavoriteStyle = @"DYxsInteractionFavoriteStyle";
static NSString *const DKKeyInteractionShareStyle = @"DYxsInteractionShareStyle";
static NSString *const DKKeyInteractionLikeBeforeIcon = @"DYxsInteractionLikeBeforeIcon";
static NSString *const DKKeyInteractionLikeAfterIcon = @"DYxsInteractionLikeAfterIcon";
static NSString *const DKKeyInteractionCommentIcon = @"DYxsInteractionCommentIcon";
static NSString *const DKKeyInteractionFavoriteBeforeIcon = @"DYxsInteractionFavoriteBeforeIcon";
static NSString *const DKKeyInteractionFavoriteAfterIcon = @"DYxsInteractionFavoriteAfterIcon";
static NSString *const DKKeyInteractionShareIcon = @"DYxsInteractionShareIcon";

// 透明度：0–100，默认 100；缩放：常规 50–100，默认 100；
// 显示方式：0 显示 / 1 隐藏（不显示、仍可点击）/ 2 移除（不显示、不可点击，所在行收拢）。
// 缩放与上移的范围登记在 DKAdjustRange.m，开启「扩展所有缩放与位移」后放宽。
static NSString *const DKKeyInteractionIconAlpha  = @"DYxsInteractionIconAlpha";
static NSString *const DKKeyInteractionLabelAlpha = @"DYxsInteractionLabelAlpha";
static NSString *const DKKeyAvatarAlpha           = @"DYxsAvatarAlpha";
static NSString *const DKKeyMusicAlpha            = @"DYxsMusicAlpha";
static NSString *const DKKeyInteractionScale      = @"DYxsInteractionScale";
static NSString *const DKKeyAvatarScale            = @"DYxsAvatarScale";
static NSString *const DKKeyMusicScale             = @"DYxsMusicScale";
static NSString *const DKKeyInteractionDisplay    = @"DYxsInteractionDisplay";
static NSString *const DKKeyAvatarDisplay         = @"DYxsAvatarDisplay";
static NSString *const DKKeyMusicDisplay          = @"DYxsMusicDisplay";
// 头像下方关注入口：0 显示 / 1 隐藏（仍可点击）/ 2 移除（与已关注作者时一致）。
static NSString *const DKKeyFollowButtonDisplay   = @"DYxsFollowButtonDisplayMode";
// 互动区域上移：0–100 pt，默认 0（抖音原位）；头像、互动按钮、音乐整体上移。
static NSString *const DKKeyInteractionOffset     = @"DYxsInteractionOffset";

#pragma mark - 功能组：昵称文案

// 视频左下昵称一行与文案及其余信息行。透明度：0–100，默认 100；缩放：常规 25–100，默认 100；
// 上移：常规 0–100 pt，默认 0。缩放与上移的范围登记在 DKAdjustRange.m。
static NSString *const DKKeyNicknameAlpha    = @"DYxsNicknameAlpha";
static NSString *const DKKeyDescriptionAlpha = @"DYxsDescriptionAlpha";
static NSString *const DKKeyNicknameScale    = @"DYxsNicknameScale";
static NSString *const DKKeyDescriptionScale = @"DYxsDescriptionScale";
static NSString *const DKKeyInfoOffset       = @"DYxsInfoOffset";

#pragma mark - 功能组：进度条与图片指示器位置

// 视频进度条上移、图文图片指示器上移：常规 0–100 pt，默认 0。范围登记在 DKAdjustRange.m。
static NSString *const DKKeyProgressOffset       = @"DYxsProgressOffset";
static NSString *const DKKeyStoryIndicatorOffset = @"DYxsStoryIndicatorOffset";
static NSString *const DKKeyRelatedBarOffset = @"DYxsRelatedBarOffset";
// 本机实测缓存（不进备份）：进度条底边、图片指示器底边到交互层底边的原生距离（pt，不含本插件的上移），
// 供「位置同图片指示器」提示使用。
static NSString *const DKKeyProgressBaseBottom       = @"DYxsProgressBaseBottom";
static NSString *const DKKeyStoryIndicatorBaseBottom = @"DYxsStoryIndicatorBaseBottom";

#pragma mark - 功能组：弹幕改色

// 颜色模式：0 固定颜色 / 1 随机纯色 / 2 随机渐变 / 3 固定彩虹 / 4 自定义渐变 / 5 旋转彩虹。
static NSString *const DKKeyDanmakuColorEnabled = @"DYxsEnableDanmakuColor";
static NSString *const DKKeyDanmakuColorMode = @"DYxsDanmakuColorMode";
// 固定颜色的唯一规范存值；十六进制入口是同一值的另一个编辑入口。
static NSString *const DKKeyDanmakuFixedColor = @"DYxsDanmakuFixedColor";
static NSString *const DKKeyDanmakuHexColor = @"DYxsDanmakuHexColor";
static NSString *const DKKeyDanmakuGradientColors = @"DYxsDanmakuGradientColors";

#pragma mark - 功能组：发布时间与地区

// 主页作品信息，与播放页的开关独立。
static NSString *const DKKeyProfilePublishTime = @"DYxsProfileShowPublishTime";
static NSString *const DKKeyProfilePublishLocation = @"DYxsProfileShowPublishLocation";
// 播放页文案下方一行：具体发布时间（作品创建时间，按设备时区）与发布地区（作品城市代码与国家地区码，不含作者自选地点）。
static NSString *const DKKeyPublishTimeEnabled = @"DYxsShowPublishTime";
static NSString *const DKKeyPublishLocationEnabled = @"DYxsShowPublishLocation";
// 国外地名解析用的 GeoNames 用户名；空串为未填写。两个网页入口只作行标识，不存值。
static NSString *const DKKeyGeoNamesUsername = @"DYxsGeoNamesUsername";
static NSString *const DKKeyGeoNamesRegister = @"DYxsGeoNamesRegister";
static NSString *const DKKeyGeoNamesWebServices = @"DYxsGeoNamesWebServices";
// 「文字颜色」子页入口标识，不存值。
static NSString *const DKKeyPublishTextColors = @"DYxsPublishTextColors";
// 时间、地区两段文字各一套颜色：改色开关 / 颜色模式（同弹幕改色六种）/ 固定颜色 / 十六进制入口 / 渐变颜色。
static NSString *const DKKeyPublishTimeColorEnabled = @"DYxsPublishTimeColor";
static NSString *const DKKeyPublishTimeColorMode = @"DYxsPublishTimeColorMode";
static NSString *const DKKeyPublishTimeFixedColor = @"DYxsPublishTimeFixedColor";
static NSString *const DKKeyPublishTimeHexColor = @"DYxsPublishTimeHexColor";
static NSString *const DKKeyPublishTimeGradientColors = @"DYxsPublishTimeGradientColors";
static NSString *const DKKeyPublishLocationColorEnabled = @"DYxsPublishLocationColor";
static NSString *const DKKeyPublishLocationColorMode = @"DYxsPublishLocationColorMode";
static NSString *const DKKeyPublishLocationFixedColor = @"DYxsPublishLocationFixedColor";
static NSString *const DKKeyPublishLocationHexColor = @"DYxsPublishLocationHexColor";
static NSString *const DKKeyPublishLocationGradientColors = @"DYxsPublishLocationGradientColors";

#pragma mark - 功能组：音频可视化

// 两项都是单选，用对话框选，故存整数而非 BOOL。
// 位置：0 关闭 / 1 胶囊上方水平 / 2 胶囊整栏环绕 / 3 拍摄圆键环绕
static NSString *const DKKeyAudioVizPosition = @"DYxsAudioVizPosition";
// 形态：0 离散条 / 1 连续流体
static NSString *const DKKeyAudioVizStyle = @"DYxsAudioVizStyle";

#pragma mark - 功能组：播放体验

static NSString *const DKKeyDoubleTapOpenComment = @"DYxsDoubleTapOpenComment";
// 播放页长按左下昵称复制「@昵称」、长按文案复制作品完整文案。
static NSString *const DKKeyLongPressCopyNickname = @"DYxsLongPressCopyNickname";
static NSString *const DKKeyLongPressCopyDescription = @"DYxsLongPressCopyDescription";
static NSString *const DKKeyDetailHideBottomBar = @"DYxsHideChatVideoBottomBar";
static NSString *const DKKeyDetailReturnMode = @"DYxsDetailReturnMode";
static NSString *const DKKeyDetailSearchMode = @"DYxsDetailSearchMode";
// 所有视频常态下都显示底部进度条。
static NSString *const DKKeyProgressAlwaysVisible = @"DYxsProgressAlwaysVisible";
// 进度条只显示已播部分：隐藏未播放的那段轨道，显隐仍按抖音原逻辑。
static NSString *const DKKeyProgressPlayedOnly = @"DYxsProgressPlayedOnly";
// 进度条旁的已播 / 总时长：0 关闭 / 1 两端（与进度条同一行）/ 2 右端 · 上方 / 3 右端 · 下方 / 4 两端 · 上方 / 5 两端 · 下方
static NSString *const DKKeyProgressTimeStyle = @"DYxsProgressTimeStyle";

#pragma mark - 功能组：播放页精简

// 每项单选，存整数：0 显示 / 1 隐藏（不显示、仍可点击，位置保留）/ 2 移除（不显示、不可点击，按抖音原生排布收拢）。
static NSString *const DKKeyPlaybackFullscreenMode         = @"DYxsPlaybackFullscreenMode";
static NSString *const DKKeyPlaybackDanmakuMode            = @"DYxsPlaybackDanmakuMode";
// 锚点标签：同一种锚点元素，按锚点业务号区分。
// 总开关为 BOOL：开启后所有锚点行（含未登记的业务号）按「移除」处理，各锚点项锁定显示为「移除」，存值不动。
static NSString *const DKKeyPlaybackRemoveAllAnchors       = @"DYxsPlaybackRemoveAllAnchors";
// 统一三档与动态目录：目录只记录实际遇到的类型，独立档位沿用既有键或动态前缀。
static NSString *const DKKeyPlaybackAllAnchorsMode         = @"DYxsPlaybackAllAnchorsMode";
static NSString *const DKKeyPlaybackAnchorsPage            = @"DYxsPlaybackAnchorsPage";
static NSString *const DKKeyPlaybackAnchorCatalog          = @"DYxsPlaybackAnchorCatalog";
static NSString *const DKKeyPlaybackAnchorModePrefix       = @"DYxsPlaybackAnchorMode.";
// 自定义名称：前缀 + 编码后的身份 → 单行文字；进备份，目录本身不进。
static NSString *const DKKeyPlaybackAnchorNamePrefix       = @"DYxsPlaybackAnchorName.";
static NSString *const DKKeyPlaybackAnchorRenamePage       = @"DYxsPlaybackAnchorRenamePage";
static NSString *const DKKeyPlaybackGameTagMode            = @"DYxsPlaybackGameTagMode";
static NSString *const DKKeyPlaybackMusicAnchorMode        = @"DYxsPlaybackMusicAnchorMode";
static NSString *const DKKeyPlaybackPropEffectMode         = @"DYxsPlaybackPropEffectMode";
static NSString *const DKKeyPlaybackJianyingMode           = @"DYxsPlaybackJianyingMode";
static NSString *const DKKeyPlaybackPaidContentMode        = @"DYxsPlaybackPaidContentMode";
static NSString *const DKKeyPlaybackLocationMode           = @"DYxsPlaybackLocationMode";
// 文案上方
static NSString *const DKKeyPlaybackOtherUserRecommendMode = @"DYxsPlaybackOtherUserRecommendMode";
static NSString *const DKKeyPlaybackFriendRecommendMode    = @"DYxsPlaybackFriendRecommendMode";
static NSString *const DKKeyPlaybackFriendShareMode        = @"DYxsPlaybackFriendShareMode";
static NSString *const DKKeyPlaybackSelectedMode           = @"DYxsPlaybackSelectedMode";
static NSString *const DKKeyPlaybackStoreMode              = @"DYxsPlaybackStoreMode";
// 昵称右侧
static NSString *const DKKeyPlaybackChapterHighlightsMode  = @"DYxsPlaybackChapterHighlightsMode";
static NSString *const DKKeyPlaybackCoCreatorMode          = @"DYxsPlaybackCoCreatorMode";
static NSString *const DKKeyPlaybackSlidesTagMode          = @"DYxsPlaybackSlidesTagMode";
static NSString *const DKKeyPlaybackArticleTagMode         = @"DYxsPlaybackArticleTagMode";
// 文案下方
static NSString *const DKKeyPlaybackRiskNoticeMode         = @"DYxsPlaybackRiskNoticeMode";
static NSString *const DKKeyPlaybackMusicInfoMode          = @"DYxsPlaybackMusicInfoMode";
static NSString *const DKKeyPlaybackQuickReplyMode         = @"DYxsPlaybackQuickReplyMode";
// 底部栏目：总开关覆盖原生底部容器中的全部业务行，单项存值保持不变。
static NSString *const DKKeyPlaybackRemoveAllBottomBars    = @"DYxsPlaybackRemoveAllBottomBars";
static NSString *const DKKeyPlaybackAllBottomBarsMode      = @"DYxsPlaybackAllBottomBarsMode";
static NSString *const DKKeyPlaybackBottomBarsPage         = @"DYxsPlaybackBottomBarsPage";
static NSString *const DKKeyPlaybackBottomBarCatalog       = @"DYxsPlaybackBottomBarCatalog";
static NSString *const DKKeyPlaybackBottomBarModePrefix    = @"DYxsPlaybackBottomBarMode.";
static NSString *const DKKeyPlaybackBottomBarNamePrefix    = @"DYxsPlaybackBottomBarName.";
// 底部栏目背景透明：覆盖原生底部容器中的全部业务行。
static NSString *const DKKeyPlaybackBottomBarTransparent   = @"DYxsPlaybackBottomBarTransparent";
static NSString *const DKKeyPlaybackBottomBarRenamePage    = @"DYxsPlaybackBottomBarRenamePage";
static NSString *const DKKeyPlaybackRelatedSearchMode      = @"DYxsPlaybackRelatedSearchMode";
static NSString *const DKKeyPlaybackRelatedVideoMode       = @"DYxsPlaybackRelatedVideoMode";
static NSString *const DKKeyPlaybackVideoCollectionMode    = @"DYxsPlaybackVideoCollectionMode";
static NSString *const DKKeyPlaybackHotspotMode            = @"DYxsPlaybackHotspotMode";
static NSString *const DKKeyPlaybackAppDownloadMode        = @"DYxsPlaybackAppDownloadMode";

#pragma mark - 功能组：内容过滤

static NSString *const DKKeyFilterLowLikes = @"DYxsFilterLowLikes";
static NSString *const DKKeyMinimumLikes = @"DYxsMinimumLikes";
static NSString *const DKKeyRemoveRecommendedLive = @"DYxsRemoveRecommendedLive";
static NSString *const DKKeyFilterRecommendedMusic = @"DYxsFilterRecommendedMusic";
static NSString *const DKKeyFilterRecommendedArticle = @"DYxsFilterRecommendedArticle";
// 商家笔记：图文作品上的 POI 富内容卡片（店铺/团购笔记）。
static NSString *const DKKeyFilterRecommendedMerchantNote = @"DYxsFilterRecommendedMerchantNote";
// 特殊卡片：总开关开启时全部类别（含未单独分类的业务）过滤，各类别开关锁定显示为开启，存值不动。
static NSString *const DKKeyFilterRecommendedSpecialCard = @"DYxsFilterRecommendedSpecialCard";
static NSString *const DKKeyFilterRecommendedHotspot = @"DYxsFilterRecommendedHotspot";
static NSString *const DKKeyFilterRecommendedCreation = @"DYxsFilterRecommendedCreation";
static NSString *const DKKeyFilterRecommendedEcommerce = @"DYxsFilterRecommendedEcommerce";
static NSString *const DKKeyFilterRecommendedGame = @"DYxsFilterRecommendedGame";
static NSString *const DKKeyFilterRecommendedSocial = @"DYxsFilterRecommendedSocial";
static NSString *const DKKeyFilterRecommendedInterest = @"DYxsFilterRecommendedInterest";
static NSString *const DKKeyFilterRecommendedMicroApp = @"DYxsFilterRecommendedMicroApp";
static NSString *const DKKeyFilterAds = @"DYxsFilterAds";

#pragma mark - 功能组：顶部频道

// 每个频道一个 BOOL 键：前缀 + channelID。
static NSString *const DKKeyTopChannelHidePrefix = @"DYxsHideTopChannel.";
// 扫描到的频道目录：NSArray<NSDictionary>，每项含 id/name/title/locked/present。
static NSString *const DKKeyTopChannelCatalog = @"DYxsTopChannelCatalog";
// 设置主页入口的 identifier，NSUserDefaults 里不写值。
static NSString *const DKKeyTopChannels = @"DYxsTopChannels";

#pragma mark - 功能组：顶栏入口

// 单选，存整数：0 显示 / 1 隐藏（不显示、仍可点击）/ 2 移除（不显示、不可点击）。
static NSString *const DKKeyTopBarSideBarMode = @"DYxsTopBarSideBarMode";
static NSString *const DKKeyTopBarSearchMode  = @"DYxsTopBarSearchMode";
// 屏蔽在最左侧频道右滑展开左侧栏。
static NSString *const DKKeyBlockSideBarSwipe = @"DYxsBlockSideBarSwipe";
// 顶栏透明度：0–100，默认 100；作用于左侧栏入口、全部频道与搜索图标。
static NSString *const DKKeyTopBarAlpha       = @"DYxsTopBarAlpha";
// 顶栏液态玻璃的材质单选（DKMakeGlassChoice）：总开关 + 清透档两个 BOOL，清透档关即系统 Regular。
static NSString *const DKKeyTopBarGlass        = @"DYxsTopBarGlass";
static NSString *const DKKeyTopBarGlassClear   = @"DYxsTopBarGlassClear";
// 顶栏液态玻璃尺寸：圆钮与胶囊的统一高度（百分比）、胶囊长度（百分比）。
static NSString *const DKKeyTopBarGlassHeight  = @"DYxsTopBarGlassHeight";
static NSString *const DKKeyTopBarGlassLength  = @"DYxsTopBarGlassLength";

#pragma mark - 功能组：未读红点

// 移除未读红点（点状 / 数字 / 文字）：底栏按钮、首页顶栏频道、左侧栏（≡ 入口与侧边栏面板）三处各一个开关。
static NSString *const DKKeyTabBarRemoveBadge  = @"DYxsTabBarRemoveBadge";
static NSString *const DKKeyTopBarRemoveBadge  = @"DYxsTopBarRemoveBadge";
static NSString *const DKKeySideBarRemoveBadge = @"DYxsSideBarRemoveBadge";

#pragma mark - 功能组：朋友页精简

// 每项单选，存整数：0 显示 / 1 隐藏（不显示、仍可点击，位置保留）/ 2 移除（不显示、不可点击，按抖音原生排布收拢）。
// 顶栏：左上角头像和加号（日常相机）、中间「限时日常」胶囊（移除时天窗也不再展开）、右上角朋友按钮。
static NSString *const DKKeyFriendAvatarEntryMode   = @"DYxsFriendAvatarEntryMode";
static NSString *const DKKeyFriendDailyMode         = @"DYxsFriendDailyMode";
static NSString *const DKKeyFriendButtonMode        = @"DYxsFriendButtonMode";
// 作品：文案上方「朋友」标记、文案下方「私信 xxx」面板、头像下方「私信」图标；凡出现处都生效。
static NSString *const DKKeyFriendRelationTagMode   = @"DYxsFriendRelationTagMode";
static NSString *const DKKeyFriendFastReplyMode     = @"DYxsFriendFastReplyMode";
static NSString *const DKKeyFriendSendMessageMode   = @"DYxsFriendSendMessageMode";
// 作品：昵称右侧「日常」标签、文案上方关注标签（你的关注 / 互相关注等关系文案）。
static NSString *const DKKeyFriendStoryTagMode      = @"DYxsFriendStoryTagMode";
static NSString *const DKKeyFriendFollowTagMode     = @"DYxsFriendFollowTagMode";
// 内容：移除朋友页内容流里的「看看朋友推荐的作品」卡片（开关）。
static NSString *const DKKeyFriendRemoveRecommendCard = @"DYxsFriendRemoveRecommendCard";

#pragma mark - 功能组：消息页精简

// 每项单选，存整数：0 显示 / 1 隐藏（不显示、仍可点击，位置保留）/ 2 移除（不显示、不可点击，按抖音原生排布收拢）。
// 顶栏
static NSString *const DKKeyMessageSideBarMode      = @"DYxsMessageSideBarMode";
static NSString *const DKKeyMessageSlotMode         = @"DYxsMessageSlotMode";
static NSString *const DKKeyMessageSearchMode       = @"DYxsMessageSearchMode";
static NSString *const DKKeyMessagePlusMode         = @"DYxsMessagePlusMode";
// 列表顶部：头像行开头的业务入口、头像行里的好友头像、互动消息会话。
static NSString *const DKKeyMessageDailyMode        = @"DYxsMessageDailyMode";
static NSString *const DKKeyMessageFriendAvatarMode = @"DYxsMessageFriendAvatarMode";
static NSString *const DKKeyMessageInteractionMode  = @"DYxsMessageInteractionMode";

#pragma mark - 功能组：聊天页输入区

static NSString *const DKKeyChatRemoveEmojiSuggestions = @"DYxsChatRemoveEmojiSuggestions";
static NSString *const DKKeyChatPlayEntryMode           = @"DYxsChatPlayEntryMode";
static NSString *const DKKeyChatRemovePlusPhotos        = @"DYxsChatRemovePlusPhotos";
static NSString *const DKKeyChatInputGlass              = @"DYxsChatInputGlass";
static NSString *const DKKeyChatInputGlassClear         = @"DYxsChatInputGlassClear";
static NSString *const DKKeyChatRemoveBack              = @"DYxsChatRemoveBack";
static NSString *const DKKeyChatRemoveUnread            = @"DYxsChatRemoveUnread";
static NSString *const DKKeyChatRemoveOnline            = @"DYxsChatRemoveOnline";
static NSString *const DKKeyChatRemoveCall              = @"DYxsChatRemoveCall";
static NSString *const DKKeyChatRemoveMenu              = @"DYxsChatRemoveMenu";
static NSString *const DKKeyChatGroupZoneNoAutoExpand   = @"DYxsChatGroupZoneNoAutoExpand";
// 聊天页顶栏自定义：子页面入口、顶部渐变模糊、居中头像（0 默认 / 1 居中）、火花与在线位置（0 居中 / 1 左侧 / 2 右侧）。
static NSString *const DKKeyChatTopCustomPage           = @"DYxsChatTopCustomPage";
static NSString *const DKKeyChatTopBlur                 = @"DYxsChatTopBlur";
static NSString *const DKKeyChatTopCenter               = @"DYxsChatTopCenter";
static NSString *const DKKeyChatTopStreakPosition       = @"DYxsChatTopStreakPosition";
static NSString *const DKKeyChatTopOnlinePosition       = @"DYxsChatTopOnlinePosition";

#pragma mark - 功能组：长按菜单

// 作品长按菜单：每个原生菜单项一个 BOOL 键，前缀 + 抖音菜单项标识（panelBizVMIdentifier）。
static NSString *const DKKeyFeedMenuHidePrefix    = @"DYxsHideFeedMenu.";
// 打开过的作品长按菜单里出现的原生菜单项：NSArray<NSDictionary>，每项含 id/title。
static NSString *const DKKeyFeedMenuCatalog       = @"DYxsFeedMenuCatalog";
// 宫格排列（单选，整数）：0 每行 1 个（抖音原生列表）/ 1 每行 2 个 / 2 每行 3 个 / 3 每行 4 个。
static NSString *const DKKeyFeedMenuColumns       = @"DYxsFeedMenuColumns";
// 设置子页入口的 identifier，NSUserDefaults 里不写值。
static NSString *const DKKeyFeedMenu              = @"DYxsFeedMenu";
// 长按作品不弹出长按面板（BOOL）。
static NSString *const DKKeyFeedMenuNoPanel       = @"DYxsFeedMenuNoPanel";
// 评论长按菜单：每项一个 BOOL 键，前缀 + 菜单项标识（元素 elementType 数字，或分享行 share）。
static NSString *const DKKeyCommentMenuHidePrefix = @"DYxsHideCommentMenu.";
static NSString *const DKKeyCommentMenuCatalog    = @"DYxsCommentMenuCatalog";
static NSString *const DKKeyCommentMenuColumns    = @"DYxsCommentMenuColumns";
static NSString *const DKKeyCommentMenu           = @"DYxsCommentMenu";
// 作品长按菜单的材质单选（DKMakeGlassChoice）：总开关 + 清透档两个 BOOL，清透档关即系统 Regular。
static NSString *const DKKeyFeedMenuGlass         = @"DYxsFeedMenuGlass";
static NSString *const DKKeyFeedMenuGlassClear    = @"DYxsFeedMenuGlassClear";
// 复制评论时去掉开头的「@用户名: 」，只复制评论内容。
static NSString *const DKKeyCommentCopyWithoutName = @"DYxsCommentCopyWithoutName";

#pragma mark - 功能组：字体

// 自定义字体：设置子页入口的 identifier，NSUserDefaults 里不写值。
static NSString *const DKKeyFont              = @"DYxsFont";
// 导入/恢复两个动作行的 identifier，NSUserDefaults 里不写值。
static NSString *const DKKeyFontImport        = @"DYxsFontImport";
static NSString *const DKKeyFontRestore       = @"DYxsFontRestore";
// 已导入字体文件的原文件名与 PostScript 名（恢复默认时一并清除）。
static NSString *const DKKeyFontFileName      = @"DYxsFontFileName";
static NSString *const DKKeyFontPostScript    = @"DYxsFontPostScriptName";

#pragma mark - 功能组：个人主页

static NSString *const DKKeyProfileHideUGCGuide = @"DYxsHideProfileUGCGuide";

// 个人主页精简，只作用于自己的主页。
// 每项单选，存整数：0 显示 / 1 隐藏（不显示、仍可点击，位置保留）/ 2 移除（不显示、不可点击，按抖音原生排布收拢）。
// 顶栏：添加好友、访客、搜索图标、侧栏图标。
static NSString *const DKKeyProfileAddFriendMode     = @"DYxsProfileAddFriendMode";
static NSString *const DKKeyProfileVisitorMode       = @"DYxsProfileVisitorMode";
static NSString *const DKKeyProfileSearchMode        = @"DYxsProfileSearchMode";
static NSString *const DKKeyProfileSideBarMode       = @"DYxsProfileSideBarMode";
// 头像与昵称：头像右下角加号、昵称后的切换账号箭头、抖音号下方的胶囊行。
static NSString *const DKKeyProfileAvatarPlusMode    = @"DYxsProfileAvatarPlusMode";
static NSString *const DKKeyProfileSwitchAccountMode = @"DYxsProfileSwitchAccountMode";
static NSString *const DKKeyProfileCapsuleMode       = @"DYxsProfileCapsuleMode";
// 数据与按钮：获赞 / 互关 / 关注 / 粉丝整行、编辑主页；两者共用一行。
static NSString *const DKKeyProfileStatsMode         = @"DYxsProfileStatsMode";
static NSString *const DKKeyProfileEditMode          = @"DYxsProfileEditMode";
// 内容：「记录下幸福瞬间」等发布引导横幅（按所在分区识别）。
static NSString *const DKKeyProfileGuideBannerMode   = @"DYxsProfileGuideBannerMode";
// 功能区（开关）：移除观看历史、全部功能等入口所在的整行，不占位。
static NSString *const DKKeyProfileRemoveServiceArea = @"DYxsProfileRemoveServiceArea";
// 分页（开关）：开启即移除对应分页。
static NSString *const DKKeyProfileRemovePostTab      = @"DYxsProfileRemovePostTab";
static NSString *const DKKeyProfileRemoveDailyTab     = @"DYxsProfileRemoveDailyTab";
static NSString *const DKKeyProfileRemoveFavoriteTab  = @"DYxsProfileRemoveFavoriteTab";
static NSString *const DKKeyProfileRemoveLikeTab      = @"DYxsProfileRemoveLikeTab";
static NSString *const DKKeyProfileRemoveFootprintTab = @"DYxsProfileRemoveFootprintTab";

#pragma mark - 功能组：媒体保存

// 作品长按面板里的保存项；保存视频 / 保存当前图片开启时移除原生「保存至相册」。
static NSString *const DKKeyMediaSaveVideo         = @"DYxsMediaSaveVideo";
static NSString *const DKKeyMediaSaveCurrentImage  = @"DYxsMediaSaveCurrentImage";
static NSString *const DKKeyMediaSaveAllImages     = @"DYxsMediaSaveAllImages";
static NSString *const DKKeyMediaSaveCover         = @"DYxsMediaSaveCover";
static NSString *const DKKeyMediaSaveMusic         = @"DYxsMediaSaveMusic";
// 评论长按「保存到相册」改由插件保存图片、实况与视频评论。
static NSString *const DKKeyMediaSaveComment       = @"DYxsMediaSaveComment";
// 评论表情：长按菜单与单击后的表情页增加「保存表情包」。
static NSString *const DKKeyMediaSaveCommentSticker = @"DYxsMediaSaveCommentSticker";
// 抖音原生的评论图片 / 实况保存不带水印。
static NSString *const DKKeyCommentImageNoWatermark     = @"DYxsCommentImageNoWatermark";
static NSString *const DKKeyCommentLivePhotoNoWatermark = @"DYxsCommentLivePhotoNoWatermark";
// 私信表情消息长按菜单、单击后的表情页、表情面板长按预览增加「保存表情包」。
static NSString *const DKKeyMediaSaveChatSticker   = @"DYxsMediaSaveChatSticker";
static NSString *const DKKeyMediaSaveHaptic        = @"DYxsMediaSaveHaptic";
// 通用提示面板的材质单选：总开关关时为系统模糊，开时按清透档取 Regular / Clear。
static NSString *const DKKeyMediaSaveGlass         = @"DYxsMediaSaveGlass";
static NSString *const DKKeyMediaSaveGlassClear    = @"DYxsMediaSaveGlassClear";

#pragma mark - 功能组：备份工具

// 备份工具页的四个动作行，只作设置项 identifier，NSUserDefaults 里不写值。
static NSString *const DKKeyBackupExport  = @"DYxsBackupExport";
static NSString *const DKKeyBackupRestore = @"DYxsBackupRestore";
static NSString *const DKKeyBackupUndo    = @"DYxsBackupUndo";
static NSString *const DKKeyBackupReset   = @"DYxsBackupReset";
// 上次导出备份的时间（NSDate）。不属于任何设置项：不进备份，恢复默认也不清。
static NSString *const DKKeyBackupLastExportDate = @"DYxsBackupLastExportDate";

#pragma mark - 设置页

// 「液态玻璃 (iOS26+)」子页入口的 identifier，供玻璃守卫在低系统灰显整个入口；不写值。
static NSString *const DKKeySettingsPageGlass = @"DYxsPageLiquidGlass";

#pragma mark - 功能组：调整范围

// 扩展所有缩放与位移：开启后 DKAdjustRange 登记的各项按扩展范围生效。开启前须确认，不进备份。
static NSString *const DKKeyAdjustRangeExtended = @"DYxsAdjustRangeExtended";

#pragma mark - 功能组：快捷入口

// 个人主页功能区末尾的 DYxs 设置入口（开关，只作用于自己的主页）。
static NSString *const DKKeyProfileSettingsEntry     = @"DYxsProfileSettingsEntry";
// 入口文字（单选，整数）：0「DYxs」/ 1「插件设置」。
static NSString *const DKKeyProfileSettingsEntryName = @"DYxsProfileSettingsEntryName";

#pragma mark - 功能组：调试工具

static NSString *const DKKeyDebugInspectorEnabled = @"DYxsDebugInspectorEnabled";

#endif /* DKKeys_h */
