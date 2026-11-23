#import "DY778LiveAppearance.h"
#import "DY778Core.h"
#import "DY778MiscPolicy.h"

// DY778 1.0-8 模块 4：直播外观编辑（规格 §7）。
// 值模型常量全部实锤；枚举映射为高置信度静态推断，须运行时回读验证。

DY778LiveAppearance DY778LiveAppearanceDefault(void) {
    DY778LiveAppearance value;
    value.alignment = DY778LiveAppearanceDefaultAlignment;
    value.order = DY778LiveAppearanceDefaultOrder;
    value.scale = DY778LiveAppearanceDefaultScale;
    return value;
}

double DY778LiveAppearanceClampScale(double value) {
    // NaN/无穷 → 1.0；夹到 [0.75, 1.5]（规格 §7.2）。
    if (!(value >= 0)) return DY778LiveAppearanceDefaultScale;
    if (value < DY778LiveAppearanceMinimumScale) return DY778LiveAppearanceMinimumScale;
    if (value > DY778LiveAppearanceMaximumScale) return DY778LiveAppearanceMaximumScale;
    return value;
}

DY778LiveAppearance DY778LiveAppearanceNormalize(DY778LiveAppearance value) {
    if (value.alignment >= 3 || value.alignment < 0) value.alignment = DY778LiveAppearanceDefaultAlignment;
    if (value.order >= 2 || value.order < 0) value.order = DY778LiveAppearanceDefaultOrder;
    value.scale = DY778LiveAppearanceClampScale(value.scale);
    return value;
}

static long long DY778LiveAppearanceAlignmentFromString(NSString *text) {
    if ([text isEqualToString:@"left"]) return 0;
    if ([text isEqualToString:@"right"]) return 2;
    return 1;
}
static long long DY778LiveAppearanceOrderFromString(NSString *text) {
    if ([text isEqualToString:@"durationFirst"]) return 1;
    return 0;
}

DY778LiveAppearance DY778LiveAppearanceFromStoredValue(NSDictionary *stored) {
    DY778LiveAppearance value = DY778LiveAppearanceDefault();
    if (![stored isKindOfClass:NSDictionary.class]) return value;
    id alignment = stored[@"alignment"];
    if ([alignment isKindOfClass:NSString.class]) value.alignment = DY778LiveAppearanceAlignmentFromString(alignment);
    else if ([alignment respondsToSelector:@selector(longLongValue)]) value.alignment = [alignment longLongValue];
    id order = stored[@"order"];
    if ([order isKindOfClass:NSString.class]) value.order = DY778LiveAppearanceOrderFromString(order);
    else if ([order respondsToSelector:@selector(longLongValue)]) value.order = [order longLongValue];
    id scale = stored[@"scale"];
    if ([scale respondsToSelector:@selector(doubleValue)]) value.scale = [scale doubleValue];
    return DY778LiveAppearanceNormalize(value);
}

NSDictionary *DY778LiveAppearanceStoredValue(DY778LiveAppearance value) {
    value = DY778LiveAppearanceNormalize(value);
    NSString *alignment = value.alignment == 0 ? @"left" : value.alignment == 2 ? @"right" : @"center";
    NSString *order = value.order == 1 ? @"durationFirst" : @"viewersFirst";
    return @{@"alignment": alignment, @"order": order, @"scale": @(value.scale)};
}

CGSize DY778LiveAppearanceCapsuleSize(CGFloat textWidth, double scale) {
    scale = DY778LiveAppearanceClampScale(scale);
    CGFloat height = DY778LiveAppearanceCapsuleBaseHeight * scale;
    CGFloat width = MIN(DY778LiveAppearanceCapsuleBaseWidth * scale,
                        33 * scale + MAX(18 * scale, ceil(textWidth)));
    return CGSizeMake(width, height);
}

void DY778LiveAppearanceComputeLayout(DY778LiveAppearance value, CGRect available, CGRect anchor,
                                      CGSize viewersSize, CGSize durationSize,
                                      CGRect *viewersFrame, CGRect *durationFrame) {
    if (viewersFrame) *viewersFrame = CGRectZero;
    if (durationFrame) *durationFrame = CGRectZero;
    if (!(value.scale >= DY778LiveAppearanceMinimumScale) || value.scale > DY778LiveAppearanceMaximumScale) return;
    value = DY778LiveAppearanceNormalize(value);
    CGSize scaledViewers = CGSizeMake(viewersSize.width * value.scale, viewersSize.height * value.scale);
    CGSize scaledDuration = CGSizeMake(durationSize.width * value.scale, durationSize.height * value.scale);
    CGFloat anchorMidX = CGRectGetMidX(anchor);
    CGFloat viewersX = DY778LiveAppearanceLayoutX(value.alignment, available, anchorMidX, scaledViewers.width);
    CGFloat durationX = DY778LiveAppearanceLayoutX(value.alignment, available, anchorMidX, scaledDuration.width);
    CGFloat top = CGRectGetMinY(available);
    CGFloat secondTop = top + scaledViewers.height + 6;
    if (value.order == 1) {
        // durationFirst：时长胶囊在上，人数在下。
        if (durationFrame) *durationFrame = CGRectMake(round(durationX), round(top), ceil(scaledDuration.width), scaledDuration.height);
        if (viewersFrame) *viewersFrame = CGRectMake(round(viewersX), round(secondTop), ceil(scaledViewers.width), scaledViewers.height);
    } else {
        if (viewersFrame) *viewersFrame = CGRectMake(round(viewersX), round(top), ceil(scaledViewers.width), scaledViewers.height);
        if (durationFrame) *durationFrame = CGRectMake(round(durationX), round(secondTop), ceil(scaledDuration.width), scaledDuration.height);
    }
}

DY778LiveAppearance DY778LiveAppearanceCurrent(void) {
    id stored = [DY778Preferences() objectForKey:@"liveInfo.cardAppearance"];
    return DY778LiveAppearanceFromStoredValue(stored);
}

CGFloat DY778LiveAppearanceLayoutX(long long alignment, CGRect available, CGFloat anchorMidX, CGFloat width) {
    CGFloat x;
    if (alignment == 0) x = CGRectGetMinX(available);
    else if (alignment == 2) x = CGRectGetMaxX(available) - width;
    else x = anchorMidX - width / 2;
    return MAX(CGRectGetMinX(available), MIN(x, CGRectGetMaxX(available) - width));
}

void DY778LiveAppearanceSave(DY778LiveAppearance value) {
    DY778Set(@"liveInfo.cardAppearance", DY778LiveAppearanceStoredValue(value));
    DY778Set(@"liveAppearance.alignment", value.alignment == 0 ? @"left" : value.alignment == 2 ? @"right" : @"center");
    DY778Set(@"liveAppearance.order", value.order == 1 ? @"durationFirst" : @"viewersFirst");
    DY778Set(@"liveAppearance.scale", @(value.scale));
}

// ---------- DY778LiveAppearanceDraft ----------

@implementation DY778LiveAppearanceDraft {
    BOOL _finished;
}
- (instancetype)init {
    if ((self = [super init])) { _appearance = DY778LiveAppearanceDefault(); }
    return self;
}
- (instancetype)initWithStoredValue:(NSDictionary *)stored {
    if ((self = [super init])) { _appearance = DY778LiveAppearanceFromStoredValue(stored); }
    return self;
}
- (BOOL)isFinished { return _finished; }
- (void)commit {
    DY778LiveAppearanceSave(self.appearance);
    _finished = YES;
}
- (void)cancel {
    _finished = YES;
}
@end

// ---------- DY778LiveAppearancePreview ----------

@implementation DY778LiveAppearancePreview

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _appearance = DY778LiveAppearanceDefault();
        self.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(__unused UITraitCollection *traits) {
            return [UIColor colorWithWhite:0 alpha:0.45];
        }];
        self.layer.cornerRadius = 14;
        self.clipsToBounds = YES;
        _group = [[UIView alloc] init];
        _viewers = [[UILabel alloc] init];
        _viewers.text = @"1.2万 人在看";
        _viewers.font = [UIFont systemFontOfSize:13];
        _viewers.textColor = UIColor.whiteColor;
        _duration = [[UILabel alloc] init];
        _duration.text = @"00:12:34";
        _duration.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
        _duration.textColor = UIColor.whiteColor;
        [_group addSubview:_viewers];
        [_group addSubview:_duration];
        [self addSubview:_group];
    }
    return self;
}
- (void)setAppearance:(DY778LiveAppearance)appearance {
    _appearance = DY778LiveAppearanceNormalize(appearance);
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat scale = self.appearance.scale;
    CGSize viewersSize = [self.viewers sizeThatFits:CGSizeMake(CGFLOAT_MAX, DY778LiveAppearanceCapsuleBaseHeight * scale)];
    CGSize durationSize = [self.duration sizeThatFits:CGSizeMake(CGFLOAT_MAX, DY778LiveAppearanceCapsuleBaseHeight * scale)];
    CGRect viewersFrame = CGRectZero, durationFrame = CGRectZero;
    DY778LiveAppearanceComputeLayout(self.appearance, self.bounds, self.bounds, viewersSize, durationSize, &viewersFrame, &durationFrame);
    self.viewers.frame = viewersFrame;
    self.duration.frame = durationFrame;
    self.group.frame = self.bounds;
}
@end

// ---------- DY778LiveAppearanceEditor ----------

@implementation DY778LiveAppearanceEditor

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"直播外观";
    DY778StyleController(self);
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone target:self action:@selector(saveEditing)];
    id stored = [DY778Preferences() objectForKey:@"liveInfo.cardAppearance"];
    self.draft = [[DY778LiveAppearanceDraft alloc] initWithStoredValue:stored];
    self.preview = [[DY778LiveAppearancePreview alloc] initWithFrame:CGRectMake(0, 0, 320, 120)];
    self.preview.appearance = self.draft.appearance;
    self.alignmentControl = [[UISegmentedControl alloc] initWithItems:@[@"左", @"中", @"右"]];
    self.alignmentControl.selectedSegmentIndex = (NSInteger)self.draft.appearance.alignment;
    [self.alignmentControl addTarget:self action:@selector(changeAppearance:) forControlEvents:UIControlEventValueChanged];
    self.orderControl = [[UISegmentedControl alloc] initWithItems:@[@"人数在前", @"时长在前"]];
    self.orderControl.selectedSegmentIndex = (NSInteger)self.draft.appearance.order;
    [self.orderControl addTarget:self action:@selector(changeAppearance:) forControlEvents:UIControlEventValueChanged];
    self.scaleControl = [[UISlider alloc] init];
    self.scaleControl.minimumValue = (float)DY778LiveAppearanceMinimumScale;
    self.scaleControl.maximumValue = (float)DY778LiveAppearanceMaximumScale;
    self.scaleControl.value = (float)self.draft.appearance.scale;
    [self.scaleControl addTarget:self action:@selector(changeAppearance:) forControlEvents:UIControlEventValueChanged];
    self.scaleLabel = [[UILabel alloc] init];
    [self refreshPreview];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshPreview];
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (!self.draft.isFinished) [self.draft cancel];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 4;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return section == 0 ? 1 : section == 1 ? 2 : section == 2 ? 1 : 1;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return section == 0 ? @"预览" : section == 1 ? @"布局" : section == 2 ? @"缩放" : @"";
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (section == 2) return @"缩放 0.75–1.5，默认 1.0。";
    if (section == 3) return @"保存后写入 liveInfo.cardAppearance，直播间胶囊按此布局。";
    return nil;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    return indexPath.section == 0 ? 132 : 44;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"DY778LiveAppearanceCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    for (UIView *view in cell.contentView.subviews) [view removeFromSuperview];
    if (indexPath.section == 0) {
        self.preview.frame = CGRectMake(12, 6, tableView.bounds.size.width - 24, 120);
        [cell.contentView addSubview:self.preview];
    } else if (indexPath.section == 1 && indexPath.row == 0) {
        cell.textLabel.text = @"对齐";
        self.alignmentControl.frame = CGRectMake(tableView.bounds.size.width - 180, 7, 168, 30);
        [cell.contentView addSubview:self.alignmentControl];
    } else if (indexPath.section == 1 && indexPath.row == 1) {
        cell.textLabel.text = @"顺序";
        self.orderControl.frame = CGRectMake(tableView.bounds.size.width - 180, 7, 168, 30);
        [cell.contentView addSubview:self.orderControl];
    } else if (indexPath.section == 2) {
        cell.textLabel.text = @"缩放";
        self.scaleLabel.frame = CGRectMake(tableView.bounds.size.width - 150, 7, 44, 30);
        self.scaleControl.frame = CGRectMake(70, 7, tableView.bounds.size.width - 230, 30);
        [cell.contentView addSubview:self.scaleControl];
        [cell.contentView addSubview:self.scaleLabel];
    } else {
        cell.textLabel.text = @"恢复默认";
        cell.textLabel.textColor = DY778Accent();
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 3) return;
    self.draft.appearance = DY778LiveAppearanceDefault();
    self.alignmentControl.selectedSegmentIndex = (NSInteger)self.draft.appearance.alignment;
    self.orderControl.selectedSegmentIndex = (NSInteger)self.draft.appearance.order;
    self.scaleControl.value = (float)self.draft.appearance.scale;
    [self.draft commit];
    [self refreshPreview];
    [self.tableView reloadData];
    DY778ShowToast(@"liveAppearance", @"外观已恢复默认", NO, YES);
}
- (void)refreshPreview {
    self.preview.appearance = self.draft.appearance;
    self.scaleLabel.text = [NSString stringWithFormat:@"%.0f%%", self.draft.appearance.scale * 100];
    [self.preview setNeedsLayout];
}
- (void)changeAppearance:(id)sender {
    (void)sender;
    DY778LiveAppearance value = self.draft.appearance;
    value.alignment = self.alignmentControl.selectedSegmentIndex;
    value.order = self.orderControl.selectedSegmentIndex;
    value.scale = DY778LiveAppearanceClampScale(self.scaleControl.value);
    self.draft.appearance = value;
    [self refreshPreview];
}
- (void)saveEditing {
    [self.draft commit];
    if (self.navigationController) [self.navigationController popViewControllerAnimated:YES];
    else [self dismissViewControllerAnimated:YES completion:nil];
}

@end

void DY778PresentLiveAppearanceEditor(UIViewController *presenter) {
    DY778PresentController(presenter, [DY778LiveAppearanceEditor new]);
}
