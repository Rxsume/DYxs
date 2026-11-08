//
//  DKXSBatch10Settings.xm
//  DYxs（第 10 批：Si-yi/DYads- 0ee4792 新模块移植）
//
//  第 10 批设置登记（%ctor + DKSettingsRegister + DKMakeSwitch，
//  与第 7/8/9 批同款写法）。4 个开关全部默认关。
//  登记 4 项，全部在本批有读取方（DKXSArticleChrome / DKXSDoubleColumnChrome /
//  DKXSFeedTopTabStyle / DKXSContentMetadata）：
//  文章详情页顶部毛玻璃、文章详情页底部毛玻璃、首页频道文字选中提亮、
//  隐藏详情创作引导栏。
//  改名一律 DYYY -> DKXS（键与类名同步改名，见各模块文件头）。
//  注意：上游的设置行构建方法不移植，行改由本文件登记；
//  顶栏提亮与创作引导栏上游默认开，DYxs 移植惯例默认关，不跟随。
//  文章两项开关同时控制双列页视口扩展（DKXSDoubleColumnChrome 共用同一对键）。
//  创作引导栏开关切换时刷新已挂载的引导栏。
//

#import "DKSettings.h"
#import "DKXSArticleChrome.h"
#import "DKXSDoubleColumnChrome.h"
#import "DKXSFeedTopTabStyle.h"
#import "DKXSContentMetadata.h"

%ctor {
    DKSettingsRegister(@"DKXSEnableArticleTopGlass", ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(@"DKXSEnableArticleTopGlass", @"文章详情页顶部毛玻璃",
                                                 @"文章详情页与富内容页的顶部栏改为毛玻璃，返回与搜索入口保留在玻璃胶囊内；双列首页同时向上扩展视口。");
        DKSettingsOnChange(item, ^{ [DKXSArticleChrome refresh]; [DKXSDoubleColumnChrome refresh]; });
        return item;
    });
    DKSettingsRegister(@"DKXSEnableArticleBottomGlass", ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(@"DKXSEnableArticleBottomGlass", @"文章详情页底部毛玻璃",
                                                 @"文章详情页与富内容页的底部评论输入与操作区改为毛玻璃；双列首页同时向下扩展视口。");
        DKSettingsOnChange(item, ^{ [DKXSArticleChrome refresh]; [DKXSDoubleColumnChrome refresh]; });
        return item;
    });
    DKSettingsRegister(@"DKXSEnableFeedTopTabHighlight", ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(@"DKXSEnableFeedTopTabHighlight", @"首页频道文字选中提亮",
                                                 @"首页频道栏选中的文字随滑动进度提亮，深色背景加轻微阴影；字体、字号与自定义标题名称不变。");
        DKSettingsOnChange(item, ^{ [DKXSFeedTopTabStyle refreshVisibleTitles]; });
        return item;
    });
    DKSettingsRegister(@"DKXSHideContentCreationInfo", ^AWESettingItemModel *{
        AWESettingItemModel *item = DKMakeSwitch(@"DKXSHideContentCreationInfo", @"隐藏详情创作引导栏",
                                                 @"隐藏文案上方整栏的活动话题、参与人数、去发布等内容，不按文案匹配。");
        DKSettingsOnChange(item, ^{ [DKXSContentMetadata refresh]; });
        return item;
    });
}
