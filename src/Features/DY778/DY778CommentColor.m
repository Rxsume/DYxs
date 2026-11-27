//
//  DY778CommentColor.m
//  评论蓝字（DY778 1.1-2 移植，2026-11-27）。
//  机制（1.1-2 实证）：hook 三处，均先签名校验再安装——
//   ① AWECommentModel.textExtras（渲染）；
//   ② AWECommentInputContentModel.setExtraInfo:（输入）；
//   ③ AWESendCommentRequestModel.generateRequestParamsDict:（发送：注入）。
//  0.6.9.71 起 ①② 只透传不再注入：40.1.0 的 Swift 评论数据解析对本地拼的
//  裸 segments（缺 user_id 等字段）会空指针崩溃（2026-11-27 .ips 实证，
//  comment_data_controller_execute 线程 EXC_BAD_ACCESS）。只保留 ③ 发送侧注入，
//  服务端回传的评论自带完整 segments，本机渲染走原生数据。
//  segments 形如 {type（数值）, range{start,end}}，range 覆盖符号内层文字。
//  文本键多拼写兼容；媒体键一律不碰。
//

#import "DY778CommentColor.h"
#import "DY778Core.h"
#import <objc/runtime.h>

static NSString *const kDY778CommentEnabledKey = @"comment.blue.enabled";
static NSString *const kDY778CommentRulesKey = @"comment.blue.rules";

NSArray<NSDictionary *> *DY778CommentStyles(void) {
    static NSArray<NSDictionary *> *styles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        styles = @[
            @{@"type": @32, @"name": @"AI 蓝字", @"icon": @"sparkles", @"hint": @"AI 气泡标识"},
            @{@"type": @36, @"name": @"私信蓝字", @"icon": @"paperplane", @"hint": @"纸飞机标识"},
            @{@"type": @14, @"name": @"链接蓝字", @"icon": @"link", @"hint": @"链条标识"},
            @{@"type": @22, @"name": @"播放蓝字", @"icon": @"play.circle", @"hint": @"播放标识"},
            @{@"type": @23, @"name": @"对话蓝字", @"icon": @"bubble.left.and.bubble.right", @"hint": @"双对话气泡标识"},
            @{@"type": @31, @"name": @"纯蓝色", @"icon": @"textformat", @"hint": @"纯蓝文字·无附加图标"},
        ];
    });
    return styles;
}

static NSArray<NSDictionary *> *DY778CommentDefaultRules(void) {
    return @[
        @{@"type": @32, @"open": @"《", @"close": @"》"},
        @{@"type": @36, @"open": @"", @"close": @""},
        @{@"type": @14, @"open": @"{", @"close": @"}"},
        @{@"type": @22, @"open": @"<", @"close": @">"},
        @{@"type": @23, @"open": @"「", @"close": @"」"},
        @{@"type": @31, @"open": @"〔", @"close": @"〕"},
    ];
}

NSArray<NSDictionary *> *DY778CommentRules(void) {
    id stored = [DY778Preferences() objectForKey:kDY778CommentRulesKey];
    if ([stored isKindOfClass:NSArray.class] && ((NSArray *)stored).count) {
        NSMutableArray *rules = [NSMutableArray array];
        for (id item in (NSArray *)stored) {
            if (![item isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *dict = item;
            NSString *open = [dict[@"open"] isKindOfClass:NSString.class] ? dict[@"open"] : nil;
            NSString *close = [dict[@"close"] isKindOfClass:NSString.class] ? dict[@"close"] : nil;
            NSNumber *type = [dict[@"type"] isKindOfClass:NSNumber.class] ? dict[@"type"] : nil;
            if (open.length && close.length && type) [rules addObject:@{@"type": type, @"open": open, @"close": close}];
        }
        if (rules.count) return [rules copy];
    }
    return DY778CommentDefaultRules();
}

NSString *DY778CommentValidateRules(NSArray<NSDictionary *> *rules) {
    if (rules.count < 1 || rules.count > 8) return @"请配置 1–8 组符号";
    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@" \n\r\t"];
    NSMutableArray<NSString *> *opens = [NSMutableArray array];
    for (NSDictionary *rule in rules) {
        NSString *open = rule[@"open"], *close = rule[@"close"];
        if (!open.length || !close.length || open.length > 4 || close.length > 4 ||
            [open rangeOfCharacterFromSet:bad].location != NSNotFound ||
            [close rangeOfCharacterFromSet:bad].location != NSNotFound)
            return @"左右符号不能为空或过长，请勿包含空格或换行";
        BOOL knownType = NO;
        for (NSDictionary *style in DY778CommentStyles())
            if ([style[@"type"] isEqual:rule[@"type"]]) { knownType = YES; break; }
        if (!knownType) return @"请选择 AI、私信、链接、播放、对话或纯蓝色样式";
        for (NSString *other in opens)
            if ([open hasPrefix:other] || [other hasPrefix:open])
                return @"不同组的起始符号不能相同或互为前缀";
        [opens addObject:open];
    }
    return nil;
}

NSString *DY778CommentSaveRules(NSArray<NSDictionary *> *rules) {
    NSString *error = DY778CommentValidateRules(rules);
    if (error) return error;
    DY778Set(kDY778CommentRulesKey, rules);
    return nil;
}

NSArray<NSDictionary *> *DY778CommentSegmentsForText(NSString *text) {
    if (!text.length) return @[];
    NSArray<NSDictionary *> *rules = DY778CommentRules();
    NSMutableArray *segments = [NSMutableArray array];
    NSUInteger length = text.length;
    NSUInteger cursor = 0;
    while (cursor < length) {
        // 找最近的一个起始符号。
        NSRange bestOpen = NSMakeRange(NSNotFound, 0);
        NSDictionary *bestRule = nil;
        for (NSDictionary *rule in rules) {
            NSRange found = [text rangeOfString:rule[@"open"] options:0
                                          range:NSMakeRange(cursor, length - cursor)];
            if (found.location != NSNotFound &&
                (bestOpen.location == NSNotFound || found.location < bestOpen.location)) {
                bestOpen = found;
                bestRule = rule;
            }
        }
        if (!bestRule) break;
        NSUInteger innerStart = bestOpen.location + bestOpen.length;
        if (innerStart >= length) break;
        NSRange closeRange = [text rangeOfString:bestRule[@"close"] options:0
                                            range:NSMakeRange(innerStart, length - innerStart)];
        if (closeRange.location == NSNotFound || closeRange.location == innerStart) {
            cursor = innerStart;
            continue;
        }
        [segments addObject:@{
            @"type": bestRule[@"type"],
            @"range": @{@"start": @(innerStart), @"end": @(closeRange.location)},
        }];
        cursor = closeRange.location + closeRange.length;
    }
    return [segments copy];
}

// 把扫描出的 segments 合并进一个 text_extra 字典（原样保留其它键）。
static NSDictionary *DY778CommentMergeExtras(NSDictionary *extras, NSString *text) {
    NSArray *segments = DY778CommentSegmentsForText(text);
    if (!segments.count) return extras;
    NSMutableDictionary *merged = extras ? [extras mutableCopy] : [NSMutableDictionary dictionary];
    NSMutableArray *all = [NSMutableArray array];
    if ([merged[@"segments"] isKindOfClass:NSArray.class]) [all addObjectsFromArray:merged[@"segments"]];
    [all addObjectsFromArray:segments];
    merged[@"segments"] = [all copy];
    return [merged copy];
}

static BOOL DY778CommentEnabled(void) {
    return DY778Bool(kDY778CommentEnabledKey);
}

static NSString *DY778CommentTextFromParams(NSDictionary *params) {
    for (NSString *key in @[@"text", @"comment_text", @"commentText"]) {
        id value = params[key];
        if ([value isKindOfClass:NSString.class] && ((NSString *)value).length) return value;
    }
    return nil;
}

// ③ 发送：generateRequestParamsDict: 返回后注入 segments。
static id (*origGenerateParams)(id, SEL, id);
static id DY778GenerateParams(id self, SEL _cmd, id arg) {
    id result = origGenerateParams ? origGenerateParams(self, _cmd, arg) : nil;
    if (!DY778CommentEnabled() || ![result isKindOfClass:NSDictionary.class]) return result;
    @try {
        NSDictionary *params = result;
        NSString *text = DY778CommentTextFromParams(params);
        if (!text.length) return result;
        NSArray *segments = DY778CommentSegmentsForText(text);
        if (!segments.count) return result;
        NSMutableDictionary *mutable = [params mutableCopy];
        NSString *extraKey = nil;
        for (NSString *key in @[@"text_extra", @"comment_text_extra", @"textExtra", @"commentTextExtra"]) {
            if ([mutable[key] isKindOfClass:NSDictionary.class]) { extraKey = key; break; }
        }
        if (!extraKey) extraKey = @"text_extra";
        mutable[extraKey] = DY778CommentMergeExtras(mutable[extraKey], text);
        return [mutable copy];
    } @catch (NSException *exception) {
        return result;
    }
}

// ① 渲染：只透传原生 textExtras，不再合并本地 segments（见文件头说明）。
static id (*origTextExtras)(id, SEL);
static id DY778TextExtras(id self, SEL _cmd) {
    return origTextExtras ? origTextExtras(self, _cmd) : nil;
}

// ② 输入：只透传，不再按文本补 segments（发送侧 ③ 已覆盖）。
static void (*origSetExtraInfo)(id, SEL, id);
static void DY778SetExtraInfo(id self, SEL _cmd, id info) {
    if (origSetExtraInfo) origSetExtraInfo(self, _cmd, info);
}

void DY778InstallCommentColorHooks(void) {
    static BOOL installed;
    if (installed) return;
    installed = YES;
    // ③ 发送注入。
    Class sendModel = NSClassFromString(@"AWESendCommentRequestModel");
    SEL generateSel = NSSelectorFromString(@"generateRequestParamsDict:");
    Method generateMethod = sendModel ? class_getInstanceMethod(sendModel, generateSel) : NULL;
    BOOL sendOK = NO;
    if (generateMethod && method_getNumberOfArguments(generateMethod) == 3) {
        char ret[64] = {0};
        method_getReturnType(generateMethod, ret, sizeof(ret));
        if (ret[0] == '@') sendOK = DY778Hook(sendModel, generateSel, (IMP)DY778GenerateParams, (IMP *)&origGenerateParams);
    }
    DY778RecordHook(@"comment.generateRequestParamsDict", sendOK);
    // ① 渲染。
    Class commentModel = NSClassFromString(@"AWECommentModel");
    SEL extrasSel = NSSelectorFromString(@"textExtras");
    Method extrasMethod = commentModel ? class_getInstanceMethod(commentModel, extrasSel) : NULL;
    BOOL renderOK = NO;
    if (extrasMethod && method_getNumberOfArguments(extrasMethod) == 2) {
        char ret[64] = {0};
        method_getReturnType(extrasMethod, ret, sizeof(ret));
        if (ret[0] == '@') renderOK = DY778Hook(commentModel, extrasSel, (IMP)DY778TextExtras, (IMP *)&origTextExtras);
    }
    DY778RecordHook(@"comment.textExtras", renderOK);
    // ② 输入。
    Class inputModel = NSClassFromString(@"AWECommentInputContentModel");
    SEL setInfoSel = NSSelectorFromString(@"setExtraInfo:");
    Method setInfoMethod = inputModel ? class_getInstanceMethod(inputModel, setInfoSel) : NULL;
    BOOL inputOK = NO;
    if (setInfoMethod && method_getNumberOfArguments(setInfoMethod) == 3) {
        char ret[64] = {0};
        method_getReturnType(setInfoMethod, ret, sizeof(ret));
        if (ret[0] == 'v') inputOK = DY778Hook(inputModel, setInfoSel, (IMP)DY778SetExtraInfo, (IMP *)&origSetExtraInfo);
    }
    DY778RecordHook(@"comment.setExtraInfo", inputOK);
}

// ---------- 符号编辑器 ----------
@interface DY778CommentSymbolEditorViewController : UITableViewController
@property(nonatomic, strong) NSMutableArray<NSMutableDictionary *> *draft;
@end

@implementation DY778CommentSymbolEditorViewController

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _draft = [NSMutableArray array];
        for (NSDictionary *rule in DY778CommentRules()) [_draft addObject:[rule mutableCopy]];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"评论蓝字符号";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"保存"
        style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
        target:self action:@selector(cancel)];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"rule"];
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)save {
    // 从可见 cell 读回文本框内容。
    for (UITableViewCell *cell in self.tableView.visibleCells) {
        NSIndexPath *path = [self.tableView indexPathForCell:cell];
        if (!path || path.section != 0 || path.row >= (NSInteger)self.draft.count) continue;
        UITextField *openField = [cell.contentView viewWithTag:101];
        UITextField *closeField = [cell.contentView viewWithTag:102];
        if (openField) self.draft[path.row][@"open"] = openField.text ?: @"";
        if (closeField) self.draft[path.row][@"close"] = closeField.text ?: @"";
    }
    NSString *error = DY778CommentSaveRules(self.draft);
    if (error) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"符号配置无效"
            message:error preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSString *)styleNameForType:(NSNumber *)type {
    for (NSDictionary *style in DY778CommentStyles())
        if ([style[@"type"] isEqual:type]) return style[@"name"];
    return @"蓝字";
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? (NSInteger)self.draft.count : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"符号组（1–8 组，一句中可混用）" : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == 0 ? @"在评论里用符号包住文字，如《你好》，发送后内层文字变蓝。点样式名可切换样式。" : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"rule" forIndexPath:indexPath];
    for (UIView *sub in cell.contentView.subviews.copy) [sub removeFromSuperview];
    if (indexPath.section == 1) {
        cell.textLabel.text = @"添加一组";
        cell.textLabel.textColor = self.draft.count >= 8 ? UIColor.tertiaryLabelColor : UIColor.systemBlueColor;
        cell.selectionStyle = self.draft.count >= 8 ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleDefault;
        return cell;
    }
    NSDictionary *rule = self.draft[indexPath.row];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(16, 0, 92, 44)];
    name.text = [self styleNameForType:rule[@"type"]];
    name.font = [UIFont systemFontOfSize:15];
    name.userInteractionEnabled = YES;
    name.tag = 100;
    [name addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cycleStyle:)]];
    [cell.contentView addSubview:name];
    UITextField *openField = [[UITextField alloc] initWithFrame:CGRectMake(116, 6, 64, 32)];
    openField.tag = 101;
    openField.text = rule[@"open"];
    openField.placeholder = @"起始";
    openField.borderStyle = UITextBorderStyleRoundedRect;
    openField.textAlignment = NSTextAlignmentCenter;
    [cell.contentView addSubview:openField];
    UILabel *dots = [[UILabel alloc] initWithFrame:CGRectMake(184, 0, 24, 44)];
    dots.text = @"…";
    dots.textAlignment = NSTextAlignmentCenter;
    [cell.contentView addSubview:dots];
    UITextField *closeField = [[UITextField alloc] initWithFrame:CGRectMake(212, 6, 64, 32)];
    closeField.tag = 102;
    closeField.text = rule[@"close"];
    closeField.placeholder = @"结束";
    closeField.borderStyle = UITextBorderStyleRoundedRect;
    closeField.textAlignment = NSTextAlignmentCenter;
    [cell.contentView addSubview:closeField];
    return cell;
}

- (void)cycleStyle:(UITapGestureRecognizer *)gesture {
    UIView *view = gesture.view;
    UITableViewCell *cell = nil;
    for (UIView *node = view; node; node = node.superview)
        if ([node isKindOfClass:UITableViewCell.class]) { cell = (UITableViewCell *)node; break; }
    NSIndexPath *path = cell ? [self.tableView indexPathForCell:cell] : nil;
    if (!path || path.section != 0 || path.row >= (NSInteger)self.draft.count) return;
    NSArray *styles = DY778CommentStyles();
    NSNumber *current = self.draft[path.row][@"type"];
    NSUInteger index = 0;
    for (NSUInteger i = 0; i < styles.count; i++)
        if ([styles[i][@"type"] isEqual:current]) { index = i; break; }
    self.draft[path.row][@"type"] = styles[(index + 1) % styles.count][@"type"];
    [self.tableView reloadRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1 && self.draft.count < 8) {
        [self.draft addObject:[@{@"type": @31, @"open": @"", @"close": @""} mutableCopy]];
        [tableView reloadData];
    }
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 0 && self.draft.count > 1;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (style == UITableViewCellEditingStyleDelete && indexPath.section == 0 && self.draft.count > 1) {
        [self.draft removeObjectAtIndex:(NSUInteger)indexPath.row];
        [tableView reloadData];
    }
}

@end

UIViewController *DY778CommentSymbolEditorController(void) {
    return [[DY778CommentSymbolEditorViewController alloc] init];
}
