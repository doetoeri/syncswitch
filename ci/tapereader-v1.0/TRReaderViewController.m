#import "TRReaderViewController.h"
#import "TRDocumentStore.h"
#import "TRPDFView.h"
#import "TRReviewViewController.h"
#import "TRGeometry.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>
@interface TRReaderViewController ()
@property(nonatomic, strong, readwrite) TRDocument *document;
@property(nonatomic, readwrite) BOOL reviewing;
@end
@implementation TRReaderViewController {
    UIScrollView *_scroll;
    UIView *_canvas;
    TRPDFView *_pdfView;
    UIToolbar *_toolbar;
    UISegmentedControl *_modes;
    UIBarButtonItem *_pageItem;
    UIBarButtonItem *_previous;
    UIBarButtonItem *_next;
    UIBarButtonItem *_answerItem;
    UIBarButtonItem *_reviewItem;
    UIBarButtonItem *_hideAllItem;
    UIBarButtonItem *_selectAllItem;
    UIBarButtonItem *_selectionActionsItem;
    UIBarButtonItem *_thicknessItem;
    UIBarButtonItem *_fitItem;
    UIPanGestureRecognizer *_create;
    CGPoint _start;
    TRTapeView *_draft;
    TRTapeView *_selected;
    UIActionSheet *_sheet;
    UIPopoverController *_popover;
    NSUInteger _page, _pageCount, _reviewIndex;
    NSArray *_reviewTapes;
    NSMutableSet *_selectedTapeIDs;
    CGFloat _thickness;
    CGSize _lastSize;
    BOOL _saveErrorShown;
    BOOL _batchThickness;
}
- (id)initWithDocument:(TRDocument *)document { return [self initWithDocument:document reviewTapes:nil]; }
- (id)initWithDocument:(TRDocument *)document reviewTapes:(NSArray *)tapes {
    if ((self = [super init])) {
        self.document = document; self.reviewing = (tapes != nil); _reviewTapes = [tapes copy];
        _selectedTapeIDs = [NSMutableSet set];
        _thickness = [[NSUserDefaults standardUserDefaults] floatForKey:@"TapeThickness"];
        if (_thickness < 8 || _thickness > 80) _thickness = 24;
        CGPDFDocumentRef pdf = CGPDFDocumentCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:document.pdfPath]);
        if (pdf) { _pageCount = CGPDFDocumentGetNumberOfPages(pdf); CGPDFDocumentRelease(pdf); }
        _page = _pageCount ? MIN(document.lastPage,_pageCount-1) : 0;
        if (_reviewTapes.count) _page = ((TRTape *)_reviewTapes[0]).pageIndex;
        document.lastOpened = [NSDate date];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(persist) name:UIApplicationWillResignActiveNotification object:nil];
    } return self;
}
- (UIBarButtonItem *)button:(NSString *)title action:(SEL)action { return [[UIBarButtonItem alloc] initWithTitle:title style:UIBarButtonItemStyleBordered target:self action:action]; }
- (UIBarButtonItem *)space { return [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL]; }
- (BOOL)isEditingMode { return !self.reviewing && _modes && _modes.selectedSegmentIndex == 1; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor = [UIColor scrollViewTexturedBackgroundColor]; self.title = self.document.title;
    _scroll = [[UIScrollView alloc] initWithFrame:CGRectZero]; _scroll.delegate = self;
    _scroll.maximumZoomScale = 6; _scroll.bouncesZoom = YES; _scroll.decelerationRate = UIScrollViewDecelerationRateFast; [self.view addSubview:_scroll];
    _toolbar = [[UIToolbar alloc] initWithFrame:CGRectZero]; [self.view addSubview:_toolbar];
    _pageItem = [self button:@"페이지" action:@selector(jump)];
    if (self.reviewing) {
        _previous = [self button:@"이전" action:@selector(reviewPrevious)]; _next = [self button:@"다음" action:@selector(reviewNext)];
        _answerItem = [self button:@"정답 보기" action:@selector(toggleReviewAnswer)];
        _toolbar.items = @[_previous,[self space],_answerItem,[self space],[self button:@"★ 모름" action:@selector(rateUnknown)], [self button:@"? 애매" action:@selector(rateUnsure)], [self button:@"✓ 외움" action:@selector(rateKnown)],[self space],_next];
        self.navigationItem.rightBarButtonItem = _pageItem;
    } else {
        _modes = [[UISegmentedControl alloc] initWithItems:@[@"학습",@"편집"]];
        _modes.segmentedControlStyle = UISegmentedControlStyleBar; _modes.selectedSegmentIndex = 0;
        [_modes addTarget:self action:@selector(modeChanged) forControlEvents:UIControlEventValueChanged];
        _modes.frame = CGRectMake(0,0,150,30);
        _reviewItem = [self button:@"복습" action:@selector(openReview)];
        _hideAllItem = [self button:@"모두 보기" action:@selector(toggleCurrentPageReveal)];
        _selectAllItem = [self button:@"전체 선택" action:@selector(toggleSelectAll)];
        _selectionActionsItem = [self button:@"선택 작업" action:@selector(showSelectionActions)];
        _thicknessItem = [self button:@"테이프 두께" action:@selector(defaultThickness)];
        _fitItem = [self button:@"화면 맞춤" action:@selector(resetZoom)];
        _previous = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRewind target:self action:@selector(previousPage)];
        _next = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFastForward target:self action:@selector(nextPage)];
        _toolbar.items = @[_previous,[self space],[[UIBarButtonItem alloc] initWithCustomView:_modes],[self space],_pageItem,[self space],_thicknessItem,[self space],_next];
        [self updateModeChrome];
    }
    [self displayPage:_page];
}
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; if (!_pageCount) [self message:@"PDF를 열 수 없습니다."]; }
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(persist) object:nil];
    [_popover dismissPopoverAnimated:NO]; [_sheet dismissWithClickedButtonIndex:_sheet.cancelButtonIndex animated:NO]; [self persist];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; if (_canvas) [self rebuildTapes]; else if ([self isViewLoaded] && _pageCount) [self displayPage:_page]; }
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews]; CGSize size = self.view.bounds.size;
    _toolbar.frame = CGRectMake(0,MAX(0,size.height-44),size.width,44);
    _scroll.frame = CGRectMake(0,0,size.width,MAX(0,size.height-44));
    if (!CGSizeEqualToSize(size,_lastSize)) { _lastSize = size; [self fitPage]; }
}
- (void)fitPage {
    if (!_canvas || _scroll.bounds.size.width <= 0 || _scroll.bounds.size.height <= 0) return;
    CGFloat fit = MIN(_scroll.bounds.size.width/_canvas.bounds.size.width,_scroll.bounds.size.height/_canvas.bounds.size.height);
    _scroll.minimumZoomScale = MIN(fit,1); _scroll.maximumZoomScale = MAX(6,fit*6);
    _scroll.zoomScale = fit; [self centerPage];
    if (self.reviewing) [self focusReviewTape];
}
- (void)centerPage {
    CGSize content = _scroll.contentSize, area = _scroll.bounds.size;
    _canvas.center = CGPointMake(MAX(content.width,area.width)*.5,MAX(content.height,area.height)*.5);
}
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView { return _canvas; }
- (void)scrollViewDidZoom:(UIScrollView *)scrollView { [self centerPage]; }
- (void)displayPage:(NSUInteger)page {
    if (!_pageCount || page >= _pageCount) return;
    [_popover dismissPopoverAnimated:NO]; _popover = nil; _selected = nil; _draft = nil; _batchThickness = NO;
    [_selectedTapeIDs removeAllObjects];
    [_canvas removeFromSuperview]; _canvas = nil; _pdfView = nil;
    _scroll.zoomScale = 1; _scroll.contentInset = UIEdgeInsetsZero; _scroll.contentOffset = CGPointZero;
    _page = page; self.document.lastPage = page;
    _pdfView = [[TRPDFView alloc] initWithPath:self.document.pdfPath pageIndex:page];
    if (!_pdfView) { [self message:@"페이지를 렌더링할 수 없습니다."]; return; }
    _canvas = [[UIView alloc] initWithFrame:(CGRect){CGPointZero,_pdfView.pageSize}];
    _canvas.backgroundColor = [UIColor whiteColor]; _canvas.clipsToBounds = YES;
    [_canvas addSubview:_pdfView]; [_scroll addSubview:_canvas]; _scroll.contentSize = _canvas.bounds.size;
    _create = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(createTape:)];
    _create.minimumNumberOfTouches = 1; _create.maximumNumberOfTouches = 1; _create.delegate = self; [_canvas addGestureRecognizer:_create];
    [self rebuildTapes]; [self modeChanged]; [self fitPage]; [self updatePageLabel]; [self schedulePersist];
}
- (void)updatePageLabel {
    _pageItem.title = [NSString stringWithFormat:@"%lu / %lu",(unsigned long)_page+1,(unsigned long)_pageCount];
    _previous.enabled = self.reviewing ? _reviewIndex > 0 : _page > 0;
    _next.enabled = self.reviewing ? _reviewIndex+1 < _reviewTapes.count : _page+1 < _pageCount;
    if (self.reviewing) { self.title = [NSString stringWithFormat:@"복습 %lu / %lu",(unsigned long)_reviewIndex+1,(unsigned long)_reviewTapes.count]; [self updateReviewAnswerTitle]; }
    else { [self updateSelectionChrome]; [self updatePageRevealTitle]; }
}
- (NSArray *)tapesOnCurrentPage {
    NSMutableArray *items = [NSMutableArray array];
    for (TRTape *t in self.document.tapes) if (t.pageIndex == _page) [items addObject:t];
    return items;
}
- (NSArray *)selectedTapesOnCurrentPage {
    NSMutableArray *items = [NSMutableArray array];
    for (TRTape *t in self.document.tapes) if (t.pageIndex == _page && [_selectedTapeIDs containsObject:t.identifier]) [items addObject:t];
    return items;
}
- (void)updatePageRevealTitle {
    if (self.reviewing || !_hideAllItem) return;
    NSArray *pageTapes = [self tapesOnCurrentPage];
    BOOL allVisible = pageTapes.count > 0;
    for (TRTape *t in pageTapes) if (!t.revealed) { allVisible = NO; break; }
    _hideAllItem.enabled = pageTapes.count > 0;
    _hideAllItem.title = allVisible ? @"모두 가리기" : @"모두 보기";
}
- (void)updateSelectionChrome {
    if (self.reviewing || !_modes) return;
    BOOL editing = [self isEditingMode];
    _thicknessItem.enabled = editing;
    if (!editing) {
        self.navigationItem.rightBarButtonItems = @[_reviewItem,_hideAllItem]; self.title = self.document.title; return;
    }
    NSArray *pageTapes = [self tapesOnCurrentPage], *selected = [self selectedTapesOnCurrentPage];
    BOOL all = pageTapes.count && selected.count == pageTapes.count;
    _selectAllItem.title = all ? @"선택 해제" : @"전체 선택";
    _selectionActionsItem.title = selected.count ? [NSString stringWithFormat:@"작업(%lu)",(unsigned long)selected.count] : @"선택 작업";
    _selectionActionsItem.enabled = selected.count > 0;
    self.navigationItem.rightBarButtonItems = @[_selectionActionsItem,_selectAllItem];
    self.title = selected.count ? [NSString stringWithFormat:@"%@ · %lu개 선택",self.document.title,(unsigned long)selected.count] : self.document.title;
}
- (void)rebuildTapes {
    for (UIView *v in [_canvas.subviews copy]) if ([v isKindOfClass:[TRTapeView class]]) [v removeFromSuperview];
    _selected = nil; _draft = nil;
    for (TRTape *t in self.document.tapes) if (t.pageIndex == _page) {
        TRTapeView *v = [[TRTapeView alloc] initWithFrame:CGRectZero]; v.tape = t; v.delegate = self;
        v.editable = [self isEditingMode];
        v.selectedForEditing = [_selectedTapeIDs containsObject:t.identifier];
        v.focused = self.reviewing && _reviewTapes.count && t == _reviewTapes[_reviewIndex];
        [_canvas addSubview:v]; [v refresh];
    }
    for (TRTapeView *v in [_canvas.subviews copy])
        if ([v isKindOfClass:[TRTapeView class]] && (v.focused || v.selectedForEditing)) [_canvas bringSubviewToFront:v];
    [self updateSelectionChrome]; [self updatePageRevealTitle];
}
- (void)modeChanged {
    BOOL editing = [self isEditingMode];
    if (!editing) [_selectedTapeIDs removeAllObjects];
    _create.enabled = editing;
    _scroll.panGestureRecognizer.minimumNumberOfTouches = editing ? 2 : 1;
    for (TRTapeView *v in _canvas.subviews) if ([v isKindOfClass:[TRTapeView class]]) { v.editable = editing; v.selectedForEditing = editing && [_selectedTapeIDs containsObject:v.tape.identifier]; }
    [self updateModeChrome]; [self updateSelectionChrome];
}
- (void)updateModeChrome {
    if (self.reviewing || !_modes) return;
    BOOL editing = [self isEditingMode];
    _thicknessItem.enabled = editing;
    UIBarButtonItem *modeItem = [[UIBarButtonItem alloc] initWithCustomView:_modes];
    _toolbar.items = @[_previous,[self space],modeItem,[self space],_pageItem,[self space],editing ? _thicknessItem : _fitItem,[self space],_next];
    [self updateSelectionChrome]; [self updatePageRevealTitle];
}
- (void)resetZoom { [self fitPage]; }
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    return g != _create || ![touch.view isKindOfClass:[TRTapeView class]];
}
- (CGPoint)canvasPointForGesture:(UIGestureRecognizer *)g {
    CGPoint p = [g locationInView:_canvas];
    CGSize s = _canvas.bounds.size;
    return CGPointMake(TRClamp(p.x,0,s.width),TRClamp(p.y,0,s.height));
}
- (void)createTape:(UIPanGestureRecognizer *)g {
    if (![self isEditingMode]) return;
    CGSize s = _canvas.bounds.size; CGPoint p = [self canvasPointForGesture:g];
    if (g.state == UIGestureRecognizerStateBegan) {
        _start = p;
        TRTape *t = [[TRTape alloc] init]; t.pageIndex = _page;
        _draft = [[TRTapeView alloc] initWithFrame:CGRectZero]; _draft.tape = t; _draft.delegate = self; _draft.editable = YES; [_canvas addSubview:_draft];
    }
    if (!_draft) return;
    if (g.state == UIGestureRecognizerStateCancelled || g.state == UIGestureRecognizerStateFailed) { [_draft removeFromSuperview]; _draft = nil; return; }
    CGFloat endX = TRClamp(p.x,0,s.width);
    CGFloat x = MIN(_start.x,endX), width = fabs(endX-_start.x);
    CGFloat height = MIN(_thickness,s.height), y = TRClamp(_start.y-height*.5,0,s.height-height);
    width = MIN(MAX(1,width),s.width-x);
    _draft.tape.normalizedRect = CGRectMake(x/s.width,y/s.height,width/s.width,height/s.height); [_draft refresh];
    if (g.state == UIGestureRecognizerStateEnded) {
        if (width >= 8) {
            [self.document.tapes addObject:_draft.tape]; [_selectedTapeIDs removeAllObjects]; [_selectedTapeIDs addObject:_draft.tape.identifier];
            _draft.selectedForEditing = YES; [self schedulePersist]; [self updateSelectionChrome];
        } else [_draft removeFromSuperview];
        _draft = nil;
    }
}
- (void)previousPage { if (_page) [self displayPage:_page-1]; }
- (void)nextPage { if (_page+1 < _pageCount) [self displayPage:_page+1]; }
- (void)jump {
    if (self.reviewing) { [self focusReviewTape]; return; }
    UIAlertView *a = [[UIAlertView alloc] initWithTitle:@"페이지 이동" message:[NSString stringWithFormat:@"1–%lu",(unsigned long)_pageCount] delegate:self cancelButtonTitle:@"취소" otherButtonTitles:@"이동",nil];
    a.alertViewStyle = UIAlertViewStylePlainTextInput; [a textFieldAtIndex:0].keyboardType = UIKeyboardTypeNumberPad; a.tag = 1; [a show];
}
- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)button {
    if (alert.tag == 1 && button == 1) {
        NSInteger page = [[alert textFieldAtIndex:0].text integerValue];
        if (page >= 1 && page <= (NSInteger)_pageCount) [self displayPage:page-1]; else [self message:@"문서 안의 페이지 번호를 입력하세요."];
    }
}
- (void)tapeViewTapped:(TRTapeView *)view {
    if (self.reviewing) {
        if (!_reviewTapes.count || view.tape != _reviewTapes[_reviewIndex]) return;
        view.tape.revealed = !view.tape.revealed; [view refresh]; [self updateReviewAnswerTitle]; [self schedulePersist]; return;
    }
    if ([self isEditingMode]) {
        if ([_selectedTapeIDs containsObject:view.tape.identifier]) [_selectedTapeIDs removeObject:view.tape.identifier];
        else [_selectedTapeIDs addObject:view.tape.identifier];
        view.selectedForEditing = [_selectedTapeIDs containsObject:view.tape.identifier];
        if (view.selectedForEditing) [_canvas bringSubviewToFront:view];
        [self updateSelectionChrome]; return;
    }
    view.tape.revealed = !view.tape.revealed; [view refresh]; [self updatePageRevealTitle]; [self schedulePersist];
}
- (void)tapeViewChanged:(TRTapeView *)view {
    if ([self isEditingMode] && view.selectedForEditing) [_selectedTapeIDs addObject:view.tape.identifier];
    [self updateSelectionChrome]; [self schedulePersist];
}
- (void)tapeViewHeld:(TRTapeView *)view {
    [_popover dismissPopoverAnimated:NO]; _selected = view;
    if ([self isEditingMode]) {
        if (![_selectedTapeIDs containsObject:view.tape.identifier]) { [_selectedTapeIDs removeAllObjects]; [_selectedTapeIDs addObject:view.tape.identifier]; view.selectedForEditing = YES; [self updateSelectionChrome]; }
        if ([self selectedTapesOnCurrentPage].count > 1) { [self showSelectionActions]; return; }
    }
    _sheet = [[UIActionSheet alloc] initWithTitle:@"테이프 상태" delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:@"★ 모름",@"? 애매함",@"✓ 외움",nil];
    _sheet.tag = 1;
    if ([self isEditingMode]) { [_sheet addButtonWithTitle:@"두께 변경"]; [_sheet addButtonWithTitle:@"삭제"]; _sheet.destructiveButtonIndex = 4; }
    _sheet.cancelButtonIndex = [_sheet addButtonWithTitle:@"취소"];
    [_sheet showFromRect:view.bounds inView:view animated:YES];
}
- (void)toggleSelectAll {
    if (![self isEditingMode]) return;
    NSArray *pageTapes = [self tapesOnCurrentPage];
    if (!pageTapes.count) { [self message:@"이 페이지에는 테이프가 없습니다."]; return; }
    BOOL all = [self selectedTapesOnCurrentPage].count == pageTapes.count;
    [_selectedTapeIDs removeAllObjects];
    if (!all) for (TRTape *t in pageTapes) [_selectedTapeIDs addObject:t.identifier];
    [self rebuildTapes];
}
- (void)showSelectionActions {
    NSArray *selected = [self selectedTapesOnCurrentPage];
    if (!selected.count) { [self message:@"편집 모드에서 테이프를 탭해 선택하세요."]; return; }
    [_popover dismissPopoverAnimated:NO]; _selected = nil;
    _sheet = [[UIActionSheet alloc] initWithTitle:[NSString stringWithFormat:@"선택한 %lu개 테이프",(unsigned long)selected.count] delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:@"★ 모름",@"? 애매함",@"✓ 외움",@"모두 가리기",@"두께 맞추기",@"가로선 맞춤",@"삭제",nil];
    _sheet.tag = 2; _sheet.destructiveButtonIndex = 6; _sheet.cancelButtonIndex = [_sheet addButtonWithTitle:@"취소"];
    [_sheet showFromBarButtonItem:_selectionActionsItem animated:YES];
}
- (void)actionSheet:(UIActionSheet *)sheet didDismissWithButtonIndex:(NSInteger)index {
    if (index == sheet.cancelButtonIndex || index < 0) return;
    if (sheet.tag == 2) {
        NSArray *selected = [[self selectedTapesOnCurrentPage] copy]; if (!selected.count) return;
        if (index <= 2) for (TRTape *t in selected) t.memoryState = index+1;
        else if (index == 3) for (TRTape *t in selected) t.revealed = NO;
        else if (index == 4) { [self showThicknessForSelection]; return; }
        else if (index == 5) {
            CGFloat centerY = 0;
            for (TRTape *t in selected) centerY += t.normalizedRect.origin.y + t.normalizedRect.size.height*.5;
            centerY /= selected.count;
            for (TRTape *t in selected) { CGRect r = t.normalizedRect; r.origin.y = TRClamp(centerY-r.size.height*.5,0,1-r.size.height); t.normalizedRect = r; }
        }
        else if (index == 6) { for (TRTape *t in selected) [self.document.tapes removeObject:t]; [_selectedTapeIDs removeAllObjects]; }
        [self rebuildTapes]; [self schedulePersist]; return;
    }
    if (!_selected) return;
    if (index <= 2) { _selected.tape.memoryState = index+1; [_selected refresh]; [self schedulePersist]; }
    else if (index == 3) [self showThicknessForTape:_selected];
    else if (index == 4) { [self.document.tapes removeObject:_selected.tape]; [_selectedTapeIDs removeObject:_selected.tape.identifier]; [_selected removeFromSuperview]; _selected = nil; [self updateSelectionChrome]; [self schedulePersist]; }
}
- (void)defaultThickness { _batchThickness = NO; [self showThicknessForTape:nil]; }
- (void)showThicknessForSelection { _batchThickness = YES; _selected = nil; [self showThicknessPopoverWithTitle:@"선택한 테이프 두께"]; }
- (void)showThicknessForTape:(TRTapeView *)tape { _batchThickness = NO; _selected = tape; [self showThicknessPopoverWithTitle:tape ? @"선택한 테이프 두께" : @"다음 테이프 두께"]; }
- (void)showThicknessPopoverWithTitle:(NSString *)title {
    [_popover dismissPopoverAnimated:NO];
    UIViewController *content = [[UIViewController alloc] init]; content.contentSizeForViewInPopover = CGSizeMake(320,108);
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0,0,320,108)]; v.backgroundColor = [UIColor groupTableViewBackgroundColor]; content.view = v;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(15,10,290,28)]; label.backgroundColor = [UIColor clearColor]; label.textAlignment = NSTextAlignmentCenter;
    label.text = title; label.font = [UIFont boldSystemFontOfSize:15]; [v addSubview:label];
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(24,48,272,36)]; slider.minimumValue = 8; slider.maximumValue = 80;
    if (_batchThickness) { TRTape *first = [[self selectedTapesOnCurrentPage] count] ? [[self selectedTapesOnCurrentPage] objectAtIndex:0] : nil; slider.value = first ? first.normalizedRect.size.height*_canvas.bounds.size.height : _thickness; }
    else slider.value = _selected ? _selected.tape.normalizedRect.size.height*_canvas.bounds.size.height : _thickness;
    [slider addTarget:self action:@selector(thicknessChanged:) forControlEvents:UIControlEventValueChanged];
    [slider addTarget:self action:@selector(thicknessEnded:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel]; [v addSubview:slider];
    _popover = [[UIPopoverController alloc] initWithContentViewController:content]; _popover.delegate = self;
    [_popover presentPopoverFromBarButtonItem:_thicknessItem permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
}
- (void)applyThickness:(CGFloat)value toTape:(TRTape *)tape {
    CGRect r = tape.normalizedRect; CGFloat h = MIN(1,value/_canvas.bounds.size.height); CGFloat center = r.origin.y+r.size.height*.5;
    r.size.height = h; r.origin.y = TRClamp(center-h*.5,0,1-h); tape.normalizedRect = r;
}
- (void)thicknessChanged:(UISlider *)slider {
    _thickness = slider.value;
    if (_batchThickness) {
        for (TRTape *t in [self selectedTapesOnCurrentPage]) [self applyThickness:_thickness toTape:t];
        for (TRTapeView *v in _canvas.subviews) if ([v isKindOfClass:[TRTapeView class]] && [_selectedTapeIDs containsObject:v.tape.identifier]) [v refresh];
    } else if (_selected) { [self applyThickness:_thickness toTape:_selected.tape]; [_selected refresh]; }
}
- (void)thicknessEnded:(UISlider *)slider { [self schedulePersist]; }
- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popover { [self schedulePersist]; _selected = nil; _batchThickness = NO; }
- (void)toggleCurrentPageReveal {
    NSArray *pageTapes = [self tapesOnCurrentPage]; if (!pageTapes.count) return;
    BOOL allVisible = YES; for (TRTape *t in pageTapes) if (!t.revealed) { allVisible = NO; break; }
    for (TRTape *t in pageTapes) t.revealed = !allVisible;
    for (TRTapeView *v in _canvas.subviews) if ([v isKindOfClass:[TRTapeView class]]) [v refresh];
    [self updatePageRevealTitle]; [self schedulePersist];
}
- (void)openReview { [self persist]; [self.navigationController pushViewController:[[TRReviewViewController alloc] initWithDocument:self.document] animated:YES]; }
- (void)focusReviewTape {
    if (!_reviewTapes.count || !_canvas) return;
    TRTape *t = _reviewTapes[_reviewIndex]; CGRect n = t.normalizedRect; CGSize s = _canvas.bounds.size;
    CGRect focus = CGRectMake(n.origin.x*s.width,n.origin.y*s.height,n.size.width*s.width,n.size.height*s.height);
    focus = CGRectInset(focus,-55,-100); focus = CGRectIntersection(focus,_canvas.bounds);
    [_scroll zoomToRect:focus animated:NO];
}
- (TRTapeView *)visibleViewForTape:(TRTape *)tape {
    for (UIView *v in _canvas.subviews) if ([v isKindOfClass:[TRTapeView class]] && ((TRTapeView *)v).tape == tape) return (TRTapeView *)v;
    return nil;
}
- (void)updateReviewAnswerTitle {
    if (!self.reviewing || !_answerItem || !_reviewTapes.count) return;
    TRTape *t = _reviewTapes[_reviewIndex]; _answerItem.title = t.revealed ? @"다시 가리기" : @"정답 보기";
}
- (void)toggleReviewAnswer {
    if (!_reviewTapes.count) return; TRTape *t = _reviewTapes[_reviewIndex]; t.revealed = !t.revealed;
    [[self visibleViewForTape:t] refresh]; [self updateReviewAnswerTitle]; [self schedulePersist];
}
- (void)showReviewIndex:(NSUInteger)index {
    if (index >= _reviewTapes.count) return; _reviewIndex = index;
    TRTape *t = _reviewTapes[index]; t.revealed = NO;
    if (_page != t.pageIndex) [self displayPage:t.pageIndex]; else { [self rebuildTapes]; [self focusReviewTape]; [self updatePageLabel]; [self schedulePersist]; }
}
- (void)reviewPrevious { if (_reviewIndex) [self showReviewIndex:_reviewIndex-1]; }
- (void)reviewNext { if (_reviewIndex+1 < _reviewTapes.count) [self showReviewIndex:_reviewIndex+1]; }
- (void)rate:(TRMemoryState)state {
    if (!_reviewTapes.count) return; TRTape *t = _reviewTapes[_reviewIndex];
    if (!t.revealed) { [self message:@"먼저 ‘정답 보기’를 눌러 확인하세요."]; return; }
    t.memoryState = state; t.revealed = NO; [self schedulePersist];
    if (_reviewIndex+1 < _reviewTapes.count) [self reviewNext];
    else { [self persist]; [self rebuildTapes]; [self updateReviewAnswerTitle]; [self message:@"복습을 마쳤습니다. 상태가 저장되었습니다."]; }
}
- (void)rateUnknown { [self rate:TRUnknown]; }
- (void)rateUnsure { [self rate:TRUnsure]; }
- (void)rateKnown { [self rate:TRKnown]; }
- (void)schedulePersist {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(persist) object:nil];
    [self performSelector:@selector(persist) withObject:nil afterDelay:.45];
}
- (void)persist {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(persist) object:nil];
    [[NSUserDefaults standardUserDefaults] setFloat:_thickness forKey:@"TapeThickness"];
    NSError *error = nil;
    if (![[TRDocumentStore sharedStore] saveDocument:self.document error:&error]) {
        if (!_saveErrorShown) { _saveErrorShown = YES; [self message:[NSString stringWithFormat:@"저장 실패: %@",error.localizedDescription]]; }
    } else _saveErrorShown = NO;
}
- (void)message:(NSString *)message { [[[UIAlertView alloc] initWithTitle:@"TapeReader" message:message delegate:nil cancelButtonTitle:@"확인" otherButtonTitles:nil] show]; }
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning]; [self persist]; [_pdfView reduceMemoryUsage];
    if ([self isViewLoaded] && !self.view.window) { [_canvas removeFromSuperview]; _canvas = nil; _pdfView = nil; _draft = nil; _selected = nil; }
    else if (_canvas) { _scroll.zoomScale = _scroll.minimumZoomScale; [_pdfView setNeedsDisplay]; }
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [_canvas removeFromSuperview]; _canvas = nil; _pdfView = nil;
    _draft = nil; _selected = nil; _create = nil;
}
- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)orientation duration:(NSTimeInterval)duration {
    [_popover dismissPopoverAnimated:NO]; [_sheet dismissWithClickedButtonIndex:_sheet.cancelButtonIndex animated:NO]; [self persist];
}
- (void)dealloc { [NSObject cancelPreviousPerformRequestsWithTarget:self]; [[NSNotificationCenter defaultCenter] removeObserver:self]; _scroll.delegate = nil; _popover.delegate = nil; _sheet.delegate = nil; }
@end
