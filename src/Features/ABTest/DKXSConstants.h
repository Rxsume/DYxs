#ifndef DKXSConstants_h
#define DKXSConstants_h

#define DKXS_NAME @"DYxs"
#define DKXS_SETTINGS_NAME @"DYxs设置"

#define DKXS_VERSION @"0.6.9.2"

// 默认的远程 ABTest 配置地址
#define DKXS_DEFAULT_ABTEST_URL @"https://github.com/Nathalie-Annis/AWEABTestDataPatch/releases/latest/download/ABTestDataPatch_A.json"

// 是否使用远程配置的偏好键
#define DKXS_REMOTE_CONFIG_FLAG_KEY @"DKXSUseRemoteConfig"

// 远程配置状态改变的通知名
#define DKXS_REMOTE_CONFIG_CHANGED_NOTIFICATION @"DKXSRemoteConfigStateChanged"

// 配置应用方式中的远程模式名称
#define DKXS_REMOTE_MODE_STRING @"远程模式：启动时自动检查更新"

#define DKXSGeonamesErrorDomain @"com.dyxs.geonames.api.error"
#define DKXSGeonamesStatusUserInfoKey @"com.dyxs.geonames.api.status"

// 隐藏设置：搜索页（独立于 DYKiller 的配置与运行时实现）
#define DKXS_SEARCH_REMOVE_HISTORY_KEY @"DKXSSearchRemoveHistory"
#define DKXS_SEARCH_REMOVE_GUESS_KEY @"DKXSSearchRemoveGuess"
#define DKXS_SEARCH_REMOVE_ALL_RANKS_KEY @"DKXSSearchRemoveAllRanks"
#define DKXS_SEARCH_RANKS_KEY @"DKXSSearchRanks"
#define DKXS_SEARCH_RANK_CATALOG_KEY @"DKXSSearchRankCatalog"
#define DKXS_SEARCH_RANK_HIDE_PREFIX @"DKXSHideSearchRank."
#define DKXS_SEARCH_REMOVE_RANK_FOOTER_KEY @"DKXSSearchRemoveRankFooter"
#define DKXS_SEARCH_REMOVE_VOICE_KEY @"DKXSSearchRemoveVoice"
#define DKXS_SEARCH_CAMERA_MODE_KEY @"DKXSSearchCameraMode"

#endif

