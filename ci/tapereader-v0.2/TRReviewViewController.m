#import "TRReviewViewController.h"
#import "TRReaderViewController.h"
#import "TRDocumentStore.h"
#import "TRTape.h"
@implementation TRReviewViewController {
    TRDocument *_document;
}
- (id)initWithDocument:(TRDocument *)document {
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) { _document = document; self.title = @"복습"; } return self;
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }
- (NSArray *)queueForMode:(NSInteger)mode {
    NSMutableArray *q = [NSMutableArray array];
    for (TRTape *t in _document.tapes) {
        BOOL include = mode == 1 || (mode == 2 && t.memoryState == TRUnknown) || (mode == 3 && (t.memoryState == TRUnknown || t.memoryState == TRUnsure));
        if (include) [q addObject:t];
    }
    [q sortUsingComparator:^NSComparisonResult(TRTape *a, TRTape *b) {
        if (a.pageIndex != b.pageIndex) return a.pageIndex < b.pageIndex ? NSOrderedAscending : NSOrderedDescending;
        if (a.normalizedRect.origin.y != b.normalizedRect.origin.y) return a.normalizedRect.origin.y < b.normalizedRect.origin.y ? NSOrderedAscending : NSOrderedDescending;
        if (a.normalizedRect.origin.x != b.normalizedRect.origin.x) return a.normalizedRect.origin.x < b.normalizedRect.origin.x ? NSOrderedAscending : NSOrderedDescending;
        return [a.identifier compare:b.identifier];
    }]; return q;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 4; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"복습 화면에서는 큰 ‘정답 보기’ 버튼이나 테이프 탭으로 답을 확인합니다. 확인한 뒤 모름·애매·외움을 선택하면 다음 항목으로 이동합니다.";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"review"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"review"];
    cell.textLabel.text = @[@"모든 테이프 다시 가리기",@"전체 테이프 복습",@"★ 모르는 테이프만",@"★ 모름 + ? 애매함"][path.row];
    cell.detailTextLabel.text = path.row ? [NSString stringWithFormat:@"%lu개",(unsigned long)[self queueForMode:path.row].count] : nil;
    cell.accessoryType = path.row ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone; return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    NSArray *queue = path.row ? [self queueForMode:path.row] : nil;
    if (path.row && !queue.count) { [[[UIAlertView alloc] initWithTitle:@"복습할 항목이 없습니다" message:@"편집 또는 학습 화면에서 테이프를 추가하거나 상태를 표시하세요." delegate:nil cancelButtonTitle:@"확인" otherButtonTitles:nil] show]; return; }
    for (TRTape *t in _document.tapes) t.revealed = NO;
    NSError *error = nil;
    if (![[TRDocumentStore sharedStore] saveDocument:_document error:&error]) { [[[UIAlertView alloc] initWithTitle:@"저장 실패" message:error.localizedDescription delegate:nil cancelButtonTitle:@"확인" otherButtonTitles:nil] show]; return; }
    if (!path.row) { [[[UIAlertView alloc] initWithTitle:@"모두 가렸습니다" message:nil delegate:nil cancelButtonTitle:@"확인" otherButtonTitles:nil] show]; return; }
    [self.navigationController pushViewController:[[TRReaderViewController alloc] initWithDocument:_document reviewTapes:queue] animated:YES];
}
@end
