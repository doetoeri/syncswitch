#import "TRLibraryViewController.h"
#import "TRDocumentStore.h"
#import "TRReaderViewController.h"
#import "TRTape.h"
@implementation TRLibraryViewController {
    TRDocument *_pendingDelete;
    NSDateFormatter *_dateFormatter;
}
- (id)init {
    if ((self = [super initWithStyle:UITableViewStylePlain])) { self.title = @"TapeReader"; _dateFormatter = [[NSDateFormatter alloc] init]; _dateFormatter.dateStyle = NSDateFormatterShortStyle; _dateFormatter.timeStyle = NSDateFormatterShortStyle; } return self;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.tableView.rowHeight = 78;
    self.navigationItem.leftBarButtonItem = self.editButtonItem;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addPDF)];
    UILabel *help = [[UILabel alloc] initWithFrame:CGRectMake(0,0,600,92)]; help.numberOfLines = 0; help.textAlignment = NSTextAlignmentCenter; help.font = [UIFont systemFontOfSize:14]; help.backgroundColor = [UIColor clearColor];
    help.text = @"학습: 테이프 탭으로 정답 확인 · 편집: 드래그로 테이프 추가\n여러 테이프를 선택해 상태·두께·정렬·삭제를 한꺼번에 처리\nSafari·Mail의 ‘다음에서 열기’ 또는 + 로 PDF 가져오기"; self.tableView.tableFooterView = help;
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; static BOOL warned = NO; if (!warned && [TRDocumentStore sharedStore].loadWarning) { warned = YES; [self message:[TRDocumentStore sharedStore].loadWarning]; } }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [TRDocumentStore sharedStore].documents.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"pdf"]; if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"pdf"];
    TRDocument *d = [TRDocumentStore sharedStore].documents[path.row]; cell.textLabel.text = d.title;
    NSUInteger known = 0; for (TRTape *t in d.tapes) if (t.memoryState == TRKnown) known++;
    NSString *date = d.lastOpened && [d.lastOpened timeIntervalSince1970] > 0 ? [_dateFormatter stringFromDate:d.lastOpened] : @"아직 열지 않음";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"마지막 %lu쪽 · 테이프 %lu개 · 외움 %lu/%lu · %@",(unsigned long)d.lastPage+1,(unsigned long)d.tapes.count,(unsigned long)known,(unsigned long)d.tapes.count,date];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path { [self openDocument:[TRDocumentStore sharedStore].documents[path.row]]; }
- (void)openDocument:(TRDocument *)document { [self.navigationController popToRootViewControllerAnimated:NO]; [self.navigationController pushViewController:[[TRReaderViewController alloc] initWithDocument:document] animated:YES]; }
- (void)addPDF {
    NSArray *urls = [[TRDocumentStore sharedStore] pendingImportURLs];
    if (!urls.count) { [self message:[NSString stringWithFormat:@"Safari·Mail에서 PDF를 연 뒤 ‘다음에서 열기’에서 TapeReader를 선택하세요.\n\n또는 아래 폴더에 PDF를 복사한 뒤 +를 누르세요.\n%@/Import\n\n가져오기 성공 후 원본 파일은 Import 폴더에서 제거됩니다.",[TRDocumentStore sharedStore].rootPath]]; return; }
    NSMutableArray *failures = [NSMutableArray array]; NSUInteger count = 0;
    for (NSURL *url in urls) { @autoreleasepool { NSError *error = nil; TRDocument *d = [[TRDocumentStore sharedStore] importURL:url error:&error]; if (d) { count++; [[NSFileManager defaultManager] removeItemAtURL:url error:NULL]; } else [failures addObject:[NSString stringWithFormat:@"%@: %@",url.lastPathComponent,error.localizedDescription]]; } }
    [self.tableView reloadData]; [self message:[NSString stringWithFormat:@"%lu개 가져왔습니다.%@",(unsigned long)count, failures.count ? [@"\n" stringByAppendingString:[failures componentsJoinedByString:@"\n"]] : @""]];
}
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
    if (style != UITableViewCellEditingStyleDelete) return; _pendingDelete = [TRDocumentStore sharedStore].documents[path.row];
    UIAlertView *a = [[UIAlertView alloc] initWithTitle:@"PDF와 테이프를 삭제할까요?" message:_pendingDelete.title delegate:self cancelButtonTitle:@"취소" otherButtonTitles:@"삭제",nil]; a.tag = 10; [a show];
}
- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)button {
    if (alert.tag == 10 && button == 1 && _pendingDelete) { NSError *error = nil; if (![[TRDocumentStore sharedStore] deleteDocument:_pendingDelete error:&error]) [self message:error.localizedDescription]; [self.tableView reloadData]; } _pendingDelete = nil;
}
- (void)message:(NSString *)message { [[[UIAlertView alloc] initWithTitle:@"TapeReader" message:message delegate:nil cancelButtonTitle:@"확인" otherButtonTitles:nil] show]; }
@end
