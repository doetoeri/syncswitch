#import "TRTapeView.h"
#import "TRGeometry.h"
#import <QuartzCore/QuartzCore.h>
@implementation TRTapeView {
    UIPanGestureRecognizer *_drag;
    CGRect _initial;
    NSInteger _resizeEdge;
}
- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor]; self.opaque = NO;
        self.layer.shadowColor = [UIColor blackColor].CGColor; self.layer.shadowOpacity = .18;
        self.layer.shadowRadius = 1.5; self.layer.shadowOffset = CGSizeMake(0,1);
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
        UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(held:)];
        hold.minimumPressDuration = .48; [tap requireGestureRecognizerToFail:hold];
        [self addGestureRecognizer:tap]; [self addGestureRecognizer:hold];
        _drag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragged:)];
        _drag.maximumNumberOfTouches = 1; _drag.delegate = self; [self addGestureRecognizer:_drag];
        [tap requireGestureRecognizerToFail:_drag];
        self.isAccessibilityElement = YES; self.accessibilityTraits = UIAccessibilityTraitButton;
    } return self;
}
- (void)setEditable:(BOOL)editable { _editable = editable; _drag.enabled = editable; [self setNeedsDisplay]; }
- (void)setFocused:(BOOL)focused { _focused = focused; [self setNeedsDisplay]; }
- (void)setSelectedForEditing:(BOOL)selectedForEditing { _selectedForEditing = selectedForEditing; [self setNeedsDisplay]; }
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    CGRect hit = CGRectInset(self.bounds,-10,-14);
    return CGRectContainsPoint(hit,point);
}
- (void)refresh {
    CGRect n = self.tape.normalizedRect; CGSize s = self.superview.bounds.size;
    self.frame = CGRectMake(n.origin.x*s.width,n.origin.y*s.height,n.size.width*s.width,n.size.height*s.height);
    self.alpha = 1;
    self.layer.shadowOpacity = self.tape.revealed ? .05 : .18;
    self.accessibilityLabel = [NSString stringWithFormat:@"테이프, %@, %@", @[@"미분류",@"모름",@"애매함",@"외움"][self.tape.memoryState], self.tape.revealed ? @"정답 공개" : @"가림"];
    self.accessibilityHint = self.editable ? @"탭하여 선택하고 드래그하여 이동합니다." : @"탭하여 정답을 확인합니다.";
    self.layer.shadowPath = [UIBezierPath bezierPathWithRect:self.bounds].CGPath; [self setNeedsDisplay];
}
- (void)tapped:(UITapGestureRecognizer *)g { [self.delegate tapeViewTapped:self]; }
- (void)held:(UILongPressGestureRecognizer *)g { if (g.state == UIGestureRecognizerStateBegan) [self.delegate tapeViewHeld:self]; }
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g { return self.editable; }
- (void)dragged:(UIPanGestureRecognizer *)g {
    CGSize s = self.superview.bounds.size; if (s.width <= 0 || s.height <= 0) return;
    if (g.state == UIGestureRecognizerStateBegan) {
        _initial = self.tape.normalizedRect;
        CGPoint p = [g locationInView:self], delta = [g translationInView:self];
        CGFloat downX = p.x-delta.x;
        CGFloat handle = MIN(30,MAX(16,self.bounds.size.width*.25));
        if (downX < handle) _resizeEdge = -1;
        else if (downX > self.bounds.size.width-handle) _resizeEdge = 1;
        else _resizeEdge = 0;
        self.selectedForEditing = YES;
    }
    if (g.state == UIGestureRecognizerStateCancelled || g.state == UIGestureRecognizerStateFailed) {
        self.tape.normalizedRect = _initial; [self refresh]; return;
    }
    CGPoint delta = [g translationInView:self.superview]; CGRect r = _initial;
    CGFloat dx = delta.x/s.width;
    CGFloat minimum = MIN(14/s.width,1);
    if (_resizeEdge > 0) {
        r.size.width = TRResizeWidth(r.origin.x,r.size.width,dx,MIN(minimum,1-r.origin.x));
    } else if (_resizeEdge < 0) {
        CGFloat right = _initial.origin.x+_initial.size.width;
        CGFloat newX = TRClamp(_initial.origin.x+dx,0,right-MIN(minimum,right));
        r.origin.x = newX; r.size.width = right-newX;
    } else {
        r.origin.x = TRMoveOrigin(r.origin.x,dx,r.size.width);
        r.origin.y = TRMoveOrigin(r.origin.y,delta.y/s.height,r.size.height);
    }
    self.tape.normalizedRect = r; [self refresh];
    if (g.state == UIGestureRecognizerStateEnded) [self.delegate tapeViewChanged:self];
}
- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext(); CGRect b = self.bounds;
    CGFloat alpha = self.tape.revealed ? .14 : 1.0;
    CGFloat colors[] = { .99,.94,.70,alpha, .94,.84,.50,alpha };
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space,colors,NULL,2);
    CGContextDrawLinearGradient(c,gradient,CGPointMake(0,0),CGPointMake(0,b.size.height),0);
    CGGradientRelease(gradient); CGColorSpaceRelease(space);
    CGContextSetRGBStrokeColor(c,.50,.40,.16,self.tape.revealed ? .08 : .13); CGContextSetLineWidth(c,.5);
    for (CGFloat y = 3; y < b.size.height; y += 5) {
        CGContextMoveToPoint(c,0,y); CGContextAddLineToPoint(c,b.size.width,y+.6);
    } CGContextStrokePath(c);
    CGContextSetRGBStrokeColor(c,1,1,1,self.tape.revealed ? .16 : .55);
    CGContextMoveToPoint(c,0,.5); CGContextAddLineToPoint(c,b.size.width,.5); CGContextStrokePath(c);
    NSString *mark = @[@"",@"★",@"?",@"✓"][self.tape.memoryState];
    [[UIColor colorWithWhite:.18 alpha:self.tape.revealed ? .55 : 1] set];
    [mark drawAtPoint:CGPointMake(4,0) withFont:[UIFont boldSystemFontOfSize:MAX(1,MIN(14,b.size.height-1))]];
    if (self.editable) {
        CGContextSetRGBFillColor(c,.25,.22,.13,.55);
        CGFloat gripH = MAX(4,b.size.height-6);
        CGContextFillRect(c,CGRectMake(2,3,3,gripH));
        CGContextFillRect(c,CGRectMake(MAX(0,b.size.width-5),3,3,gripH));
    }
    if (self.selectedForEditing) {
        CGContextSetRGBStrokeColor(c,.08,.38,.86,1); CGContextSetLineWidth(c,3);
        CGContextStrokeRect(c,CGRectInset(b,1.5,1.5));
    } else if (self.focused) {
        CGContextSetRGBStrokeColor(c,.12,.48,.90,1); CGContextSetLineWidth(c,3);
        CGContextStrokeRect(c,CGRectInset(b,1.5,1.5));
    }
}
@end
