//
//  DY778SharedUI.m
//  DYxs — 见 DY778SharedUI.h。单元格工厂复刻上游 DY778RadarUI.m 的
//  DY778RadarCell；表格基类复刻 DY778RadarTableController 去掉的部分：
//  导航栏状态保存/恢复与 RadarMonitor 账号同步（Radar 未并入 DYxs）。
//

#import "DY778SharedUI.h"
#import "DY778Core.h"

UITableViewCell *DY778SharedCell(NSString *title, NSString *subtitle, NSString *symbol, BOOL disclosure) {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = DY778CardBackground();
    UIListContentConfiguration *config = [UIListContentConfiguration subtitleCellConfiguration];
    config.text = title; config.secondaryText = subtitle;
    config.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; config.textProperties.color = UIColor.labelColor;
    config.textProperties.numberOfLines = 0; config.secondaryTextProperties.numberOfLines = 0;
    config.secondaryTextProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    config.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    config.textToSecondaryTextVerticalPadding = 5;
    config.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(14, 20, 14, 20);
    if (symbol.length) {
        config.image = DY778MenuIcon(symbol); config.imageProperties.tintColor = DY778Accent();
        config.imageProperties.maximumSize = CGSizeMake(28, 28); config.imageProperties.reservedLayoutSize = CGSizeMake(28, 28); config.imageToTextPadding = 14;
    }
    cell.contentConfiguration = config;
    cell.accessoryType = disclosure ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    return cell;
}

@interface DY778SharedTableController ()
@property(nonatomic) BOOL hasAppeared;
@property(nonatomic) BOOL restoresOffset;
@property(nonatomic) CGPoint savedOffset;
@end

@implementation DY778SharedTableController

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) self.hidesBottomBarWhenPushed = YES;
    return self;
}

- (void)restoreTableOffset:(CGPoint)offset {
    [self.tableView layoutIfNeeded];
    CGFloat low = -self.tableView.adjustedContentInset.top;
    CGFloat high = MAX(low, self.tableView.contentSize.height - self.tableView.bounds.size.height + self.tableView.adjustedContentInset.bottom);
    [self.tableView setContentOffset:CGPointMake(offset.x, MIN(high, MAX(low, offset.y))) animated:NO];
}

- (void)viewDidLoad {
    [super viewDidLoad]; self.view.tintColor = DY778Accent(); self.tableView.backgroundColor = DY778Background();
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 70;
    self.tableView.sectionHeaderHeight = UITableViewAutomaticDimension; self.tableView.sectionFooterHeight = UITableViewAutomaticDimension;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.navigationItem.backButtonTitle = @"返回";
    self.clearsSelectionOnViewWillAppear = NO;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateTheme) name:DY778PreferencesChangedNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateTheme) name:UIApplicationDidBecomeActiveNotification object:nil];
    [self updateTheme];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateTheme]; [self refresh];
    if (self.restoresOffset) [self restoreTableOffset:self.savedOffset];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated]; self.hasAppeared = YES;
    if (self.restoresOffset) { [self restoreTableOffset:self.savedOffset]; self.restoresOffset = NO; }
}

- (void)viewWillDisappear:(BOOL)animated {
    self.savedOffset = self.tableView.contentOffset; self.restoresOffset = YES;
    [super viewWillDisappear:animated];
}

- (void)refresh {
    CGPoint offset = self.tableView.contentOffset;
    [self.tableView reloadData];
    if (self.hasAppeared) [self restoreTableOffset:offset];
}

- (void)updateTheme {
    UIUserInterfaceStyle style = DY778InterfaceStyle();
    if (self.overrideUserInterfaceStyle != style) self.overrideUserInterfaceStyle = style;
    UINavigationBarAppearance *appearance = [UINavigationBarAppearance new]; [appearance configureWithOpaqueBackground];
    UITraitCollection *traits = [UITraitCollection traitCollectionWithUserInterfaceStyle:style];
    appearance.backgroundColor = [DY778Background() resolvedColorWithTraitCollection:traits];
    appearance.titleTextAttributes = @{NSForegroundColorAttributeName: [UIColor.labelColor resolvedColorWithTraitCollection:traits]};
    UIColor *accent = [DY778Accent() resolvedColorWithTraitCollection:traits];
    appearance.buttonAppearance.normal.titleTextAttributes = @{NSForegroundColorAttributeName: accent};
    appearance.doneButtonAppearance.normal.titleTextAttributes = @{NSForegroundColorAttributeName: accent};
    appearance.backButtonAppearance.normal.titleTextAttributes = @{NSForegroundColorAttributeName: accent};
    self.navigationItem.standardAppearance = appearance; self.navigationItem.scrollEdgeAppearance = appearance; self.navigationItem.compactAppearance = appearance;
    if (self.view.window && self.navigationController.topViewController == self) self.navigationController.navigationBar.tintColor = accent;
    [self setNeedsStatusBarAppearanceUpdate];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous { [super traitCollectionDidChange:previous]; if (self.isViewLoaded) [self updateTheme]; }
- (UIStatusBarStyle)preferredStatusBarStyle { return DY778InterfaceStyle() == UIUserInterfaceStyleDark ? UIStatusBarStyleLightContent : UIStatusBarStyleDarkContent; }

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *header = self.tableView.tableHeaderView; if (!header) return;
    CGFloat width = self.tableView.bounds.size.width;
    CGSize size = [header systemLayoutSizeFittingSize:CGSizeMake(width, 0) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    CGFloat height = ceil(size.height);
    if (height > 0 && (fabs(header.frame.size.height - height) > 0.5 || fabs(header.frame.size.width - width) > 0.5)) {
        header.frame = CGRectMake(0, 0, width, height); self.tableView.tableHeaderView = header;
    }
}

- (BOOL)checkAccount:(NSString *)account {
    if (account.length && [account isEqualToString:DY778CurrentAccountID()]) return YES;
    DY778ShowNotice(self, @"账号已切换", @"已停止本次操作，请返回重新打开页面。");
    return NO;
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

@end
