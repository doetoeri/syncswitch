#import "TRTapeView.h"
#import "TRGeometry.h"
#import <QuartzCore/QuartzCore.h>

static CGColorSpaceRef TRTapeColorSpace = NULL;
static CGGradientRef TRTapeGradient = NULL;

@implementation TRTapeView {
    UIPanGestureRecognizer *_drag;
    CGRect _initial;
    NSInteger _resizeEdge;
    BOOL _peelAnimating;
    CAGradientLayer *_peelShine;
}

+ (void)initialize {
    if (self != [TRTapeView class] || TRTapeGradient) return;
    TRTapeColorSpace = CGColorSpaceCreateDeviceRGB();
    CGFloat colors[] = { .995,.955,.73,1.0, .94,.84,.49,1.0 };
    TRTapeGradient = CGGradientCreateWithColorComponents(TRTapeColorSpace,colors,NULL,2);
}

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.layer.masksToBounds = NO;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = .15;
        self.layer.shadowRadius = 1.25;
        self.layer.shadowOffset = CGSizeMake(0,1);

        _peelShine = [CAGradientLayer layer];
        _peelShine.colors = @[
            (id)[UIColor colorWithWhite:1 alpha:0].CGColor,
            (id)[UIColor colorWithWhite:1 alpha:.72].CGColor,
            (id)[UIColor colorWithWhite:1 alpha:.08].CGColor
        ];
        _peelShine.locations = @[@0,@.55,@1];
        _peelShine.startPoint = CGPointMake(0,0);
        _peelShine.endPoint = CGPointMake(1,0);
        _peelShine.opacity = 0;
        [self.layer addSublayer:_peelShine];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
        UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(held:)];
        hold.minimumPressDuration = .42;
        [tap requireGestureRecognizerToFail:hold];
        [self addGestureRecognizer:tap];
        [self addGestureRecognizer:hold];

        _drag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragged:)];
        _drag.minimumNumberOfTouches = 1;
        _drag.maximumNumberOfTouches = 1;
        _drag.cancelsTouchesInView = YES;
        _drag.delegate = self;
        [self addGestureRecognizer:_drag];
        [tap requireGestureRecognizerToFail:_drag];

        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
    }
    return self;
}

- (void)setEditable:(BOOL)editable {
    _editable = editable;
    _drag.enabled = editable;
    [self setNeedsDisplay];
}

- (void)setPeelEnabled:(BOOL)peelEnabled {
    _peelEnabled = peelEnabled;
    if (!peelEnabled && _peelAnimating) {
        [self.layer removeAllAnimations];
        [UIView beginAnimations:nil context:NULL];
        [UIView setAnimationDuration:0];
        self.transform = CGAffineTransformIdentity;
        self.alpha = 1;
        [UIView commitAnimations];
        _peelAnimating = NO;
        _peelShine.opacity = 0;
    }
}

- (void)setFocused:(BOOL)focused { _focused = focused; [self setNeedsDisplay]; }
- (void)setSelectedForEditing:(BOOL)selectedForEditing { _selectedForEditing = selectedForEditing; [self setNeedsDisplay]; }
- (void)setReviewOrder:(NSInteger)reviewOrder { _reviewOrder = reviewOrder; [self setNeedsDisplay]; }

- (CGFloat)interactionZoomScale {
    UIView *v = self.superview;
    while (v) {
        if ([v isKindOfClass:[UIScrollView class]]) {
            CGFloat z = ((UIScrollView *)v).zoomScale;
            return z > .01 ? z : 1;
        }
        v = v.superview;
    }
    return 1;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    // Keep the effective hit target almost constant on the physical screen.
    // Without compensating for UIScrollView zoom, a 44 pt target can shrink
    // to a frustrating ~25-30 pt target when a whole PDF page is fitted.
    CGFloat zoom = [self interactionZoomScale];
    CGFloat targetScreen = self.selectedForEditing ? 52.0 : 46.0;
    CGFloat targetLocal = targetScreen / zoom;
    CGFloat sidePad = 8.0 / zoom;
    CGFloat extraX = MAX(sidePad,(targetLocal-self.bounds.size.width)*.5);
    CGFloat extraY = MAX(sidePad,(targetLocal-self.bounds.size.height)*.5);
    return CGRectContainsPoint(CGRectInset(self.bounds,-extraX,-extraY),point);
}

- (void)refresh {
    CGRect n = self.tape.normalizedRect;
    CGSize s = self.superview.bounds.size;
    self.frame = CGRectMake(n.origin.x*s.width,n.origin.y*s.height,n.size.width*s.width,n.size.height*s.height);
    if (!_peelAnimating) {
        self.alpha = 1;
        self.transform = CGAffineTransformIdentity;
        _peelShine.opacity = 0;
    }
    self.layer.shadowOpacity = self.tape.revealed ? .04 : .15;
    self.layer.shadowRadius = 1.25;
    self.layer.shadowOffset = CGSizeMake(0,1);
    self.layer.shadowPath = [UIBezierPath bezierPathWithRect:self.bounds].CGPath;

    CGFloat shineW = MAX(18,self.bounds.size.width*.30);
    _peelShine.frame = CGRectMake(MAX(0,self.bounds.size.width-shineW),0,shineW,self.bounds.size.height);

    self.accessibilityLabel = [NSString stringWithFormat:@"테이프, %@, %@",
        @[@"미분류",@"모름",@"애매함",@"외움"][self.tape.memoryState],
        self.tape.revealed ? @"떼어짐, 정답 공개" : @"붙어 있음, 정답 가림"];
    self.accessibilityHint = self.editable ? @"탭하여 선택하고 가운데를 끌어 이동합니다. 양 끝을 끌어 길이를 바꿉니다." :
        (self.peelEnabled ? @"탭하면 테이프를 떼거나 다시 붙입니다." : @"탭하여 정답을 확인합니다.");
    [self setNeedsDisplay];
}

- (void)tapped:(UITapGestureRecognizer *)g {
    if (self.peelEnabled) {
        [self togglePeelAnimated];
        return;
    }
    self.alpha = .72;
    [UIView animateWithDuration:.10 animations:^{ self.alpha = 1; }];
    [self.delegate tapeViewTapped:self];
}

- (void)togglePeelAnimated {
    if (_peelAnimating) return;
    if (!self.peelEnabled) {
        [self.delegate tapeViewTapped:self];
        return;
    }

    _peelAnimating = YES;
    self.userInteractionEnabled = NO;
    BOOL wasRevealed = self.tape.revealed;

    if (!wasRevealed) {
        // 1) Lift one edge. The highlight and deeper shadow make the right edge feel detached.
        _peelShine.opacity = .85;
        self.layer.shadowOpacity = .38;
        self.layer.shadowRadius = 5.5;
        self.layer.shadowOffset = CGSizeMake(3,6);

        [UIView animateWithDuration:.09
                              delay:0
                            options:UIViewAnimationOptionCurveEaseOut|UIViewAnimationOptionAllowUserInteraction
                         animations:^{
                             CGAffineTransform t = CGAffineTransformIdentity;
                             t = CGAffineTransformTranslate(t,2,-4);
                             t = CGAffineTransformRotate(t,-0.028);
                             t = CGAffineTransformScale(t,.995,.92);
                             self.transform = t;
                         }
                         completion:^(BOOL finished) {
                             // 2) Peel the strip upward and away, then reveal the answer.
                             [UIView animateWithDuration:.17
                                                   delay:0
                                                 options:UIViewAnimationOptionCurveEaseIn|UIViewAnimationOptionAllowUserInteraction
                                              animations:^{
                                                  CGAffineTransform t = CGAffineTransformIdentity;
                                                  t = CGAffineTransformTranslate(t,9,-20);
                                                  t = CGAffineTransformRotate(t,-0.075);
                                                  t = CGAffineTransformScale(t,.965,.88);
                                                  self.transform = t;
                                                  self.alpha = .06;
                                                  _peelShine.opacity = .18;
                                              }
                                              completion:^(BOOL done) {
                                                  [self.delegate tapeViewTapped:self];
                                                  self.transform = CGAffineTransformIdentity;
                                                  self.alpha = 1;
                                                  self.layer.shadowOpacity = .04;
                                                  self.layer.shadowRadius = 1.25;
                                                  self.layer.shadowOffset = CGSizeMake(0,1);
                                                  _peelShine.opacity = 0;
                                                  _peelAnimating = NO;
                                                  self.userInteractionEnabled = YES;
                                                  [self refresh];
                                              }];
                         }];
    } else {
        // Put the tape state back first, then visually lay it down from a lifted position.
        [self.delegate tapeViewTapped:self];
        self.alpha = .10;
        self.layer.shadowOpacity = .42;
        self.layer.shadowRadius = 6;
        self.layer.shadowOffset = CGSizeMake(3,7);
        _peelShine.opacity = .80;

        CGAffineTransform start = CGAffineTransformIdentity;
        start = CGAffineTransformTranslate(start,9,-20);
        start = CGAffineTransformRotate(start,-0.075);
        start = CGAffineTransformScale(start,.965,.88);
        self.transform = start;

        [UIView animateWithDuration:.18
                              delay:0
                            options:UIViewAnimationOptionCurveEaseOut|UIViewAnimationOptionAllowUserInteraction
                         animations:^{
                             CGAffineTransform t = CGAffineTransformIdentity;
                             t = CGAffineTransformTranslate(t,0,1.5);
                             t = CGAffineTransformScale(t,1.004,.97);
                             self.transform = t;
                             self.alpha = 1;
                             self.layer.shadowOpacity = .20;
                             self.layer.shadowRadius = 2.0;
                             self.layer.shadowOffset = CGSizeMake(0,2);
                             _peelShine.opacity = .30;
                         }
                         completion:^(BOOL finished) {
                             // Tiny settling motion mimics pressing masking tape flat.
                             [UIView animateWithDuration:.07
                                                   delay:0
                                                 options:UIViewAnimationOptionCurveEaseInOut|UIViewAnimationOptionAllowUserInteraction
                                              animations:^{
                                                  self.transform = CGAffineTransformIdentity;
                                                  _peelShine.opacity = 0;
                                              }
                                              completion:^(BOOL done) {
                                                  self.layer.shadowOpacity = .15;
                                                  self.layer.shadowRadius = 1.25;
                                                  self.layer.shadowOffset = CGSizeMake(0,1);
                                                  _peelAnimating = NO;
                                                  self.userInteractionEnabled = YES;
                                                  [self refresh];
                                              }];
                         }];
    }
}

- (void)held:(UILongPressGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) [self.delegate tapeViewHeld:self];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g { return self.editable; }

- (void)dragged:(UIPanGestureRecognizer *)g {
    CGSize s = self.superview.bounds.size;
    if (s.width <= 0 || s.height <= 0) return;

    if (g.state == UIGestureRecognizerStateBegan) {
        _initial = self.tape.normalizedRect;
        CGPoint p = [g locationInView:self];
        CGFloat zoom = [self interactionZoomScale];
        CGFloat handle = MIN(self.bounds.size.width*.28,26.0/zoom);
        handle = MAX(12.0/zoom,handle);

        // First drag on an unselected tape always moves it. Resizing is only
        // armed after the tape is selected, which eliminates many accidental
        // length changes on small text lines.
        if (self.selectedForEditing && p.x <= handle) _resizeEdge = -1;
        else if (self.selectedForEditing && p.x >= self.bounds.size.width-handle) _resizeEdge = 1;
        else _resizeEdge = 0;

        self.selectedForEditing = YES;
        self.layer.shadowOpacity = .06;
        self.layer.shadowRadius = 2.2;
    }

    if (g.state == UIGestureRecognizerStateCancelled || g.state == UIGestureRecognizerStateFailed) {
        self.tape.normalizedRect = _initial;
        [self refresh];
        return;
    }

    CGPoint delta = [g translationInView:self.superview];
    CGRect r = _initial;
    CGFloat dx = delta.x/s.width;
    CGFloat zoom = [self interactionZoomScale];
    CGFloat minimum = MIN((14.0/zoom)/s.width,1);

    if (_resizeEdge > 0) {
        r.size.width = TRResizeWidth(r.origin.x,r.size.width,dx,MIN(minimum,1-r.origin.x));
    } else if (_resizeEdge < 0) {
        CGFloat right = _initial.origin.x+_initial.size.width;
        CGFloat newX = TRClamp(_initial.origin.x+dx,0,right-MIN(minimum,right));
        r.origin.x = newX;
        r.size.width = right-newX;
    } else {
        r.origin.x = TRMoveOrigin(r.origin.x,dx,r.size.width);
        r.origin.y = TRMoveOrigin(r.origin.y,delta.y/s.height,r.size.height);
    }

    self.tape.normalizedRect = r;
    [self refresh];

    if (g.state == UIGestureRecognizerStateEnded) {
        self.layer.shadowOpacity = .15;
        self.layer.shadowRadius = 1.25;
        [self.delegate tapeViewChanged:self];
    }
}

- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGRect b = self.bounds;
    if (!c) return;

    CGContextSaveGState(c);
    CGContextSetAlpha(c,self.tape.revealed ? .12 : 1.0);
    CGContextDrawLinearGradient(c,TRTapeGradient,CGPointMake(0,0),CGPointMake(0,b.size.height),0);
    CGContextRestoreGState(c);

    CGContextSetRGBStrokeColor(c,.42,.34,.13,self.tape.revealed ? .05 : .11);
    CGContextSetLineWidth(c,.45);
    for (CGFloat y = 4; y < b.size.height; y += 7) {
        CGContextMoveToPoint(c,0,y);
        CGContextAddLineToPoint(c,b.size.width,y+.45);
    }
    CGContextStrokePath(c);

    CGContextSetRGBStrokeColor(c,1,1,1,self.tape.revealed ? .12 : .52);
    CGContextMoveToPoint(c,0,.5);
    CGContextAddLineToPoint(c,b.size.width,.5);
    CGContextStrokePath(c);

    NSString *mark = @[@"",@"★",@"?",@"✓"][self.tape.memoryState];
    [[UIColor colorWithWhite:.18 alpha:self.tape.revealed ? .5 : 1] set];
    [mark drawAtPoint:CGPointMake(5,MAX(0,(b.size.height-14)*.5))
             withFont:[UIFont boldSystemFontOfSize:MIN(14,MAX(8,b.size.height-2))]];

    if (self.editable) {
        CGFloat zoom = [self interactionZoomScale];
        CGFloat gripW = MAX(3.0/zoom,3);
        CGFloat inset = MAX(2.0/zoom,2);
        CGFloat h = MAX(8.0/zoom,b.size.height-inset*2);
        CGFloat y = MAX(inset,(b.size.height-h)*.5);
        CGContextSetRGBFillColor(c,.20,.18,.12,self.selectedForEditing ? .82 : .48);
        CGContextFillRect(c,CGRectMake(inset,y,gripW,h));
        CGContextFillRect(c,CGRectMake(MAX(0,b.size.width-inset-gripW),y,gripW,h));
    }

    if (self.selectedForEditing || self.focused) {
        if (self.selectedForEditing) CGContextSetRGBStrokeColor(c,.05,.36,.85,1);
        else CGContextSetRGBStrokeColor(c,.10,.50,.95,1);
        CGContextSetLineWidth(c,3);
        CGContextStrokeRect(c,CGRectInset(b,1.5,1.5));
    }

    if (self.reviewOrder > 0) {
        CGFloat zoom = [self interactionZoomScale];
        CGFloat diameter = MAX(20.0/zoom,14.0);
        CGRect badge = CGRectMake(MAX(0,4.0/zoom),MAX(0,(b.size.height-diameter)*.5),diameter,diameter);
        CGContextSetRGBFillColor(c,.08,.24,.48,.96);
        CGContextFillEllipseInRect(c,badge);
        CGContextSetRGBStrokeColor(c,1,1,1,.92);
        CGContextSetLineWidth(c,MAX(1.0/zoom,.7));
        CGContextStrokeEllipseInRect(c,CGRectInset(badge,.7,.7));
        NSString *number = [NSString stringWithFormat:@"%ld",(long)self.reviewOrder];
        UIFont *font = [UIFont boldSystemFontOfSize:MAX(9.0/zoom,8.0)];
        CGSize ts = [number sizeWithFont:font];
        [[UIColor whiteColor] set];
        [number drawAtPoint:CGPointMake(CGRectGetMidX(badge)-ts.width*.5,CGRectGetMidY(badge)-ts.height*.5)
                   withFont:font];
    }
}

@end
