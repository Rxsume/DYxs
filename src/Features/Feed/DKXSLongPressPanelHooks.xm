//
//  DKXSLongPressPanelHooks.xm
//  DYxs（第 4 批 staging，尚未并入 DYxs 源码）
//
//  移植来源：Wtrwx/DYYY 的 DYYYLongPressPanel.xm 里不撞 dataArray 的部分。
//  改名一律 DYYY -> DKXS；设置键见 DKXSBatch4Settings.xm。
//  本文件含 4 组 hook，逐项冲突核查见 REPORT.md，DYxs src 里均无同类同方法：
//  1. AWELongPressPanelViewGroupModel：加 isDKXSCustomGroup 属性（上游 %property 原样，
//     供长按菜单项合并片段标记自定义组、供下面两处单元格尺寸 hook 识别）。
//  2. AWEModernLongPressHorizontalSettingCell / AWEModernLongPressInteractiveCell：
//     自定义组行的单元格按组内条目数均分宽度（上游原样）。
//  3. 评论分享隐藏：AWEIMCommentShareUserHorizontalCollectionViewCell +
//     AWEIMCommentShareUserHorizontalSectionController（键 DKXSHideCommentShareToFriends）。
//  4. 评论长按面板过滤：运行时查到的
//     AWECommentLongPressPanelSwiftImpl.CommentLongPressPanelNormalSectionViewModel 的
//     setModelsArray，按 8 个 DKXSHideCommentLongPress* 键过滤元素（上游 %group 原样）。
//  偏离（见 REPORT.md）：上游主 %ctor 以 DYYYUserAgreementAccepted 为门，
//  DYxs 没有用户协议流程，故本文件 %ctor 无条件安装；各功能本身仍由各自开关
//  门控（全部默认关），不装即不生效与装了但开关关的效果一致。
//  本文件不 import 上游 AwemeHeaders，也不 import DouyinHeaders；
//  所需抖音类属性只给最小接口声明（取自上游 AwemeHeaders.h 已有声明）。
//
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#define DKXSGetBool(key) [[NSUserDefaults standardUserDefaults] boolForKey:key]

@interface AWELongPressPanelViewGroupModel : NSObject
@property(nonatomic, assign) unsigned long long groupType;
@property(nonatomic, strong) NSArray *groupArr;
@property(nonatomic, assign) BOOL isModern;
@property(nonatomic, assign) BOOL isDKXSCustomGroup;
@end

@interface AWEModernLongPressHorizontalSettingCell : UITableViewCell
@property(nonatomic, strong) NSArray *dataArray;
@property(nonatomic, strong) AWELongPressPanelViewGroupModel *longPressViewGroupModel;
@end

@interface AWEModernLongPressInteractiveCell : UITableViewCell
@property(nonatomic, strong) NSArray *dataArray;
@property(nonatomic, strong) AWELongPressPanelViewGroupModel *longPressViewGroupModel;
@end

// 最小接口声明：评论分享 cell 的 layoutSubviews 里读写 self.hidden；
// hidden 为 UIView 属性，基类按其 CollectionViewCell 身份声明，不 import DouyinHeaders。
@interface AWEIMCommentShareUserHorizontalCollectionViewCell : UICollectionViewCell
@end

%hook AWELongPressPanelViewGroupModel
%property(nonatomic, assign) BOOL isDKXSCustomGroup;
%end

// 修复 Modern 风格长按面板水平设置单元格的大小计算（上游原样）。
%hook AWEModernLongPressHorizontalSettingCell
- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    if (self.longPressViewGroupModel && [self.longPressViewGroupModel isDKXSCustomGroup]) {
        if (self.dataArray && indexPath.item < self.dataArray.count) {
            CGFloat totalWidth = collectionView.bounds.size.width;
            NSInteger itemCount = self.dataArray.count;
            CGFloat itemWidth = totalWidth / itemCount;
            return CGSizeMake(itemWidth, 73);
        }
        return CGSizeMake(73, 73);
    }
    return %orig;
}
%end

// 修复 Modern 风格长按面板交互单元格的大小计算（上游原样）。
%hook AWEModernLongPressInteractiveCell
- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    if (self.longPressViewGroupModel && [self.longPressViewGroupModel isDKXSCustomGroup]) {
        if (self.dataArray && indexPath.item < self.dataArray.count) {
            NSInteger itemCount = self.dataArray.count;
            CGFloat totalWidth = collectionView.bounds.size.width - 12 * (itemCount - 1);
            CGFloat itemWidth = totalWidth / itemCount;
            return CGSizeMake(itemWidth, 73);
        }
        return CGSizeMake(73, 73);
    }
    return %orig;
}
%end

// 隐藏评论分享功能（上游原样，键改名）。
%hook AWEIMCommentShareUserHorizontalCollectionViewCell
- (void)layoutSubviews {
    %orig;
    self.hidden = DKXSGetBool(@"DKXSHideCommentShareToFriends");
}
%end

%hook AWEIMCommentShareUserHorizontalSectionController
- (CGSize)sizeForItemAtIndex:(NSInteger)index model:(id)model collectionViewSize:(CGSize)size {
    if (DKXSGetBool(@"DKXSHideCommentShareToFriends")) return CGSizeZero;
    return %orig;
}
- (void)configCell:(id)cell index:(NSInteger)index model:(id)model {
    if (DKXSGetBool(@"DKXSHideCommentShareToFriends")) return;
    %orig;
}
%end

%group DKXSCommentLongPressFilterGroup

%hook HOOK_TARGET_OWNER_CLASS

- (void)setModelsArray:(id)arg1 {
    if (![arg1 isKindOfClass:[NSArray class]]) {
        %orig(arg1);
        return;
    }
    NSArray *inputArray = (NSArray *)arg1;
    NSMutableArray *filteredArray = nil;
    for (id item in inputArray) {
        NSString *className = NSStringFromClass([item class]);
        BOOL shouldFilter = ([className isEqualToString:@"AWECommentLongPressPanelSwiftImpl.CommentLongPressPanelFavoriteCommentElement"] && DKXSGetBool(@"DKXSHideCommentLongPressFavorite")) ||
                            ([className isEqualToString:@"AWECommentIMSwiftImpl.CommentLongPressPanelForwardElement"] && DKXSGetBool(@"DKXSHideCommentLongPressDaily")) ||
                            ([className isEqualToString:@"AWECommentLongPressPanelSwiftImpl.CommentLongPressPanelCopyElement"] && DKXSGetBool(@"DKXSHideCommentLongPressCopy")) ||
                            ([className isEqualToString:@"AWECommentLongPressPanelSwiftImpl.CommentLongPressPanelSaveImageElement"] && DKXSGetBool(@"DKXSHideCommentLongPressSaveImage")) ||
                            ([className isEqualToString:@"AWECommentLongPressPanelSwiftImpl.CommentLongPressPanelReportElement"] && DKXSGetBool(@"DKXSHideCommentLongPressReport")) ||
                            ([className isEqualToString:@"AWECommentStudioSwiftImpl.CommentLongPressPanelVideoReplyElement"] && DKXSGetBool(@"DKXSHideCommentLongPressVideoReply")) ||
                            ([className isEqualToString:@"AWECommentSearchSwiftImpl.CommentLongPressPanelPictureSearchElement"] && DKXSGetBool(@"DKXSHideCommentLongPressPictureSearch")) ||
                            ([className isEqualToString:@"AWECommentSearchSwiftImpl.CommentLongPressPanelSearchElement"] && DKXSGetBool(@"DKXSHideCommentLongPressSearch"));
        if (shouldFilter) {
            if (!filteredArray) {
                filteredArray = [NSMutableArray arrayWithCapacity:inputArray.count];
                for (id keepItem in inputArray) {
                    if (keepItem == item) break;
                    [filteredArray addObject:keepItem];
                }
            }
            continue;
        }
        if (filteredArray) [filteredArray addObject:item];
    }
    if (filteredArray) {
        %orig([filteredArray copy]);
    } else {
        %orig(arg1);
    }
}

%end

%end

%ctor {
    %init;
    Class ownerClass = objc_getClass("AWECommentLongPressPanelSwiftImpl.CommentLongPressPanelNormalSectionViewModel");
    if (ownerClass) {
        %init(DKXSCommentLongPressFilterGroup, HOOK_TARGET_OWNER_CLASS = ownerClass);
    }
}
