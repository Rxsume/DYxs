//
//  DKSettingsPanelViewController.m
//  DYxs 设置面板（DYYY 风格，2026-11-27 移植自 huami1314/DYYY 的
//  DYYYSettingViewController 视觉与交互）：深色毛玻璃 + 振动层 + 0.3
//  黑色遮罩、内嵌分组表格（透明底、无分隔线）、分区标题可折叠、
//  白色半透明行底、渐变动画标题、底部版本字。行数据与行为仍是
//  DYxs 的 AWESettingItemModel：开关行走 switchChangedBlock，其余行
//  走 cellTappedBlock（弹窗宿主由 DKSettingsCurrentPage 提供，本页
//  在 viewWillAppear 时登记自己）。灰显与 ⓘ 说明沿用 DYxs 联动锁。
//

#import "DKSettingsPanelViewController.h"
#import "DKSettingsInternal.h"
#import <objc/runtime.h>

static char kDKPanelItemKey;

@interface DKSettingsPanelViewController () <UITableViewDelegate, UITableViewDataSource>
@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic, copy) NSString *panelTitle;
@property(nonatomic, strong) NSArray<AWESettingSectionModel *> *sections;
@property(nonatomic, copy) NSString *note;
@property(nonatomic, strong) NSMutableSet<NSNumber *> *expandedSections;
@property(nonatomic, strong) UIVisualEffectView *blurEffectView;
@property(nonatomic, strong) UIVisualEffectView *vibrancyEffectView;
@end

@implementation DKSettingsPanelViewController

+ (instancetype)mainPanel {
    return [[self alloc] initWithTitle:@"DYxs" sections:DKSettingsBuildMainSections() note:nil];
}

- (instancetype)initWithTitle:(NSString *)title
                     sections:(NSArray<AWESettingSectionModel *> *)sections
                         note:(NSString *)note {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _panelTitle = [title copy];
        _sections = sections ?: @[];
        _note = [note copy];
        _expandedSections = [NSMutableSet set];
        DKSettingsApplyLocks(_sections);
    }
    return self;
}

- (NSArray<AWESettingSectionModel *> *)dk_sections {
    return _sections;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.panelTitle;
    [self setupAppearance];
    [self setupBlurEffect];
    [self setupTableView];
    [self setupFooterLabel];
    [self addTitleGradientAnimation];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 接管弹窗宿主：项上的弹窗块以 DKSettingsCurrentPage 为 presenter。
    DKSettingsSetCurrentPage(self);
    [self dk_reload];
}

- (void)setupAppearance {
    self.navigationController.navigationBar.barTintColor = [UIColor clearColor];
    self.navigationController.navigationBar.tintColor = [UIColor whiteColor];
    self.navigationController.navigationBar.largeTitleTextAttributes = @{NSForegroundColorAttributeName: [UIColor whiteColor]};
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationController.navigationBar.prefersLargeTitles = YES;
}

- (void)setupBlurEffect {
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    self.blurEffectView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    self.blurEffectView.frame = self.view.bounds;
    self.blurEffectView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.blurEffectView];

    UIVibrancyEffect *vibrancyEffect = [UIVibrancyEffect effectForBlurEffect:blurEffect];
    self.vibrancyEffectView = [[UIVisualEffectView alloc] initWithEffect:vibrancyEffect];
    self.vibrancyEffectView.frame = self.blurEffectView.bounds;
    self.vibrancyEffectView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.blurEffectView.contentView addSubview:self.vibrancyEffectView];

    UIView *overlayView = [[UIView alloc] initWithFrame:self.view.bounds];
    overlayView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.3];
    overlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:overlayView];
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.contentInset = UIEdgeInsetsMake(20, 0, 0, 0);
    self.tableView.sectionHeaderTopPadding = 0;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.tableView];
    if (self.note.length) {
        UILabel *noteLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 0)];
        noteLabel.text = self.note;
        noteLabel.numberOfLines = 0;
        noteLabel.font = [UIFont systemFontOfSize:13];
        noteLabel.textColor = [UIColor colorWithWhite:1 alpha:0.7];
        CGSize size = [noteLabel sizeThatFits:CGSizeMake(self.view.bounds.size.width - 64, CGFLOAT_MAX)];
        UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, size.height + 16)];
        noteLabel.frame = CGRectMake(32, 8, self.view.bounds.size.width - 64, size.height);
        [header addSubview:noteLabel];
        self.tableView.tableHeaderView = header;
    }
    if (!self.sections.count) {
        UILabel *empty = [[UILabel alloc] init];
        empty.text = @"暂无设置项";
        empty.textAlignment = NSTextAlignmentCenter;
        empty.font = [UIFont systemFontOfSize:13];
        empty.textColor = [UIColor colorWithWhite:1 alpha:0.5];
        self.tableView.backgroundView = empty;
    }
}

- (void)setupFooterLabel {
    UILabel *footerLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 50)];
    footerLabel.text = [NSString stringWithFormat:@"DYxs\nVersion: %@", DK_VERSION];
    footerLabel.textAlignment = NSTextAlignmentCenter;
    footerLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
    footerLabel.textColor = [UIColor colorWithRed:173 / 255.0 green:216 / 255.0 blue:230 / 255.0 alpha:1.0];
    footerLabel.numberOfLines = 2;
    footerLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.tableView.tableFooterView = footerLabel;
}

- (void)addTitleGradientAnimation {
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.colors = @[(__bridge id)[UIColor systemRedColor].CGColor, (__bridge id)[UIColor systemBlueColor].CGColor];
    gradient.startPoint = CGPointMake(0, 0);
    gradient.endPoint = CGPointMake(1, 0);
    gradient.frame = CGRectMake(0, 0, 150, 30);

    UIView *titleView = [[UIView alloc] initWithFrame:gradient.frame];
    [titleView.layer addSublayer:gradient];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:titleView.bounds];
    titleLabel.text = self.title;
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont boldSystemFontOfSize:20];
    titleLabel.textColor = [UIColor clearColor];

    gradient.mask = titleLabel.layer;
    self.navigationItem.titleView = titleView;

    CABasicAnimation *colorChange = [CABasicAnimation animationWithKeyPath:@"colors"];
    colorChange.toValue = @[(__bridge id)[UIColor systemYellowColor].CGColor, (__bridge id)[UIColor systemGreenColor].CGColor];
    colorChange.duration = 2.0;
    colorChange.autoreverses = YES;
    colorChange.repeatCount = HUGE_VALF;
    [gradient addAnimation:colorChange forKey:@"colorChangeAnimation"];
}

#pragma mark - 刷新

- (void)dk_reload {
    DKSettingsApplyLocks(self.sections);
    [self.tableView reloadData];
}

- (void)dk_reloadItems:(NSArray<AWESettingItemModel *> *)items {
    if (!items.count) return;
    NSMutableArray<NSIndexPath *> *paths = [NSMutableArray array];
    for (AWESettingItemModel *item in items) {
        NSIndexPath *path = [self indexPathForItem:item];
        if (path) [paths addObject:path];
    }
    if (paths.count == items.count) {
        [self.tableView reloadRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationNone];
    } else {
        [self.tableView reloadData];
    }
}

- (NSIndexPath *)indexPathForItem:(AWESettingItemModel *)item {
    for (NSUInteger s = 0; s < self.sections.count; s++) {
        NSArray *rows = self.sections[s].itemArray;
        for (NSUInteger r = 0; r < rows.count; r++) {
            if (rows[r] == item) return [NSIndexPath indexPathForRow:(NSInteger)r inSection:(NSInteger)s];
        }
    }
    return nil;
}

- (AWESettingItemModel *)itemAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section >= (NSInteger)self.sections.count) return nil;
    NSArray *rows = self.sections[indexPath.section].itemArray;
    if (indexPath.row >= (NSInteger)rows.count) return nil;
    return rows[indexPath.row];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.expandedSections containsObject:@(section)] ? (NSInteger)self.sections[section].itemArray.count : 0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 44)];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, headerView.bounds.size.width - 50, 44)];
    titleLabel.text = self.sections[section].sectionHeaderTitle;
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    [headerView addSubview:titleLabel];

    UIImageView *arrowImageView = [[UIImageView alloc] initWithFrame:CGRectMake(titleLabel.frame.origin.x + titleLabel.frame.size.width - 30, 15, 14, 14)];
    arrowImageView.image = [UIImage systemImageNamed:[self.expandedSections containsObject:@(section)] ? @"chevron.down" : @"chevron.right"];
    arrowImageView.tintColor = [UIColor lightGrayColor];
    arrowImageView.tag = 100;
    arrowImageView.contentMode = UIViewContentModeScaleAspectFit;
    [headerView addSubview:arrowImageView];

    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = headerView.bounds;
    button.tag = section;
    [button addTarget:self action:@selector(headerTapped:) forControlEvents:UIControlEventTouchUpInside];
    [headerView addSubview:button];

    return headerView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 44;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    AWESettingItemModel *item = [self itemAtIndexPath:indexPath];

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DKPanelCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"DKPanelCell"];
        cell.textLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.textLabel.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16].active = YES;
        [cell.textLabel.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor].active = YES;
        UIView *selectedBackgroundView = [[UIView alloc] init];
        selectedBackgroundView.backgroundColor = [UIColor colorWithRed:84 / 255.0 green:84 / 255.0 blue:84 / 255.0 alpha:1.0];
        cell.selectedBackgroundView = selectedBackgroundView;
    }
    objc_setAssociatedObject(cell, &kDKPanelItemKey, item, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    cell.textLabel.text = item.title;
    cell.textLabel.textColor = DKSettingsItemIsDestructive(item) ? UIColor.systemRedColor : [UIColor whiteColor];
    cell.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1];
    cell.backgroundView = nil;
    cell.contentView.alpha = item.isEnable ? 1.0 : 0.4;

    if (indexPath.row == (NSInteger)self.sections[indexPath.section].itemArray.count - 1) {
        cell.layer.cornerRadius = 10;
        cell.layer.maskedCorners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
        cell.layer.masksToBounds = YES;
    } else {
        cell.layer.cornerRadius = 0;
        cell.layer.maskedCorners = 0;
        cell.layer.masksToBounds = NO;
    }

    // ⓘ 说明按钮（有说明文案时挂在标题后）。
    NSString *info = DKSettingsItemInfo(item);
    UIButton *infoButton = [cell.contentView viewWithTag:200];
    if (info) {
        if (!infoButton) {
            infoButton = [UIButton buttonWithType:UIButtonTypeCustom];
            infoButton.tag = 200;
            UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightRegular];
            [infoButton setImage:[UIImage systemImageNamed:@"info.circle" withConfiguration:config] forState:UIControlStateNormal];
            infoButton.tintColor = [UIColor colorWithWhite:1 alpha:0.45];
            infoButton.accessibilityLabel = @"说明";
            [infoButton addTarget:self action:@selector(infoTapped:) forControlEvents:UIControlEventTouchUpInside];
            [cell.contentView addSubview:infoButton];
        }
        infoButton.hidden = NO;
    } else {
        infoButton.hidden = YES;
    }

    if (item.cellType == 6) {
        // 开关行。
        UISwitch *switchView = [[UISwitch alloc] init];
        [switchView setOn:item.isSwitchOn animated:NO];
        switchView.enabled = item.isEnable;
        [switchView addTarget:self action:@selector(switchToggled:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = switchView;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        // 可点行：右侧当前值 + 箭头。
        UILabel *detailLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 120, 44)];
        detailLabel.text = item.detail;
        detailLabel.textColor = [UIColor colorWithWhite:1 alpha:0.7];
        detailLabel.font = [UIFont systemFontOfSize:14];
        detailLabel.textAlignment = NSTextAlignmentRight;
        detailLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        UIView *containerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 120, 44)];
        [containerView addSubview:detailLabel];
        [NSLayoutConstraint activateConstraints:@[
            [detailLabel.centerYAnchor constraintEqualToAnchor:containerView.centerYAnchor],
            [detailLabel.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor],
            [detailLabel.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor],
        ]];
        cell.accessoryView = containerView;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = item.isEnable ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat sectionInset = 16;
    cell.contentView.frame = UIEdgeInsetsInsetRect(cell.contentView.frame, UIEdgeInsetsMake(0, sectionInset, 0, sectionInset));
    // ⓘ 按钮跟在标题文字后。
    UIButton *infoButton = [cell.contentView viewWithTag:200];
    if (infoButton && !infoButton.hidden) {
        UILabel *title = cell.textLabel;
        CGRect titleRect = [title convertRect:title.bounds toView:cell.contentView];
        CGSize fit = [title sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGRectGetHeight(titleRect))];
        CGFloat textWidth = MIN(ceil(fit.width), CGRectGetWidth(titleRect));
        infoButton.frame = CGRectMake(CGRectGetMinX(titleRect) + textWidth - 2,
                                      CGRectGetMidY(titleRect) - 14, 28, 28);
        [cell.contentView bringSubviewToFront:infoButton];
    }
}

#pragma mark - UITableViewDelegate

- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath {
    AWESettingItemModel *item = [self itemAtIndexPath:indexPath];
    return item.isEnable && item.cellType != 6;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    AWESettingItemModel *item = [self itemAtIndexPath:indexPath];
    if (!item || !item.isEnable || item.cellType == 6) return;
    if (item.cellTappedBlock) item.cellTappedBlock();
}

#pragma mark - Actions

- (void)headerTapped:(UIButton *)sender {
    NSNumber *section = @(sender.tag);
    if ([self.expandedSections containsObject:section]) {
        [self.expandedSections removeObject:section];
    } else {
        [self.expandedSections addObject:section];
    }
    UIView *headerView = [self.tableView headerViewForSection:sender.tag];
    UIImageView *arrowImageView = [headerView viewWithTag:100];
    [UIView animateWithDuration:0.3 animations:^{
        arrowImageView.image = [UIImage systemImageNamed:[self.expandedSections containsObject:section] ? @"chevron.down" : @"chevron.right"];
    }];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:(NSUInteger)sender.tag] withRowAnimation:UITableViewRowAnimationFade];
}

- (void)switchToggled:(UISwitch *)sender {
    UITableViewCell *cell = nil;
    for (UIView *node = sender; node; node = node.superview) {
        if ([node isKindOfClass:UITableViewCell.class]) { cell = (UITableViewCell *)node; break; }
    }
    AWESettingItemModel *item = cell ? objc_getAssociatedObject(cell, &kDKPanelItemKey) : nil;
    if (!item) return;
    if (item.switchChangedBlock) item.switchChangedBlock();
    // 块内已翻转 isSwitchOn 并落盘；确认型开关可能被拨回，按项的真值对齐。
    [sender setOn:item.isSwitchOn animated:YES];
}

- (void)infoTapped:(UIButton *)sender {
    UITableViewCell *cell = nil;
    for (UIView *node = sender; node; node = node.superview) {
        if ([node isKindOfClass:UITableViewCell.class]) { cell = (UITableViewCell *)node; break; }
    }
    AWESettingItemModel *item = cell ? objc_getAssociatedObject(cell, &kDKPanelItemKey) : nil;
    NSString *info = DKSettingsItemInfo(item);
    if (!info) return;
    NSString *reason = item.isEnable ? nil : DKSettingsLockReason(item);
    DKSettingsShowTip(sender, reason ? [NSString stringWithFormat:@"%@\n%@", info, reason] : info);
}

@end
