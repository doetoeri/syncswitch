#import "TRPDFView.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import <stdlib.h>
@interface TRPDFTileLayer : CATiledLayer
@end
@implementation TRPDFTileLayer
+ (CFTimeInterval)fadeDuration { return 0.04; }
@end
@implementation TRPDFView {
    CGPDFDocumentRef _pdf;
    CGPDFPageRef _page;
    CGSize _pageSize;
    CGAffineTransform _pageTransform;
}
+ (Class)layerClass { return [TRPDFTileLayer class]; }
- (id)initWithPath:(NSString *)path pageIndex:(NSUInteger)index {
    if ((self = [super initWithFrame:CGRectZero])) {
        _pdf = CGPDFDocumentCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path]);
        if (!_pdf || index >= CGPDFDocumentGetNumberOfPages(_pdf)) return nil;
        _page = CGPDFDocumentGetPage(_pdf, index+1);
        CGRect crop = CGPDFPageGetBoxRect(_page, kCGPDFCropBox);
        CGFloat w = crop.size.width, h = crop.size.height;
        if (abs(CGPDFPageGetRotationAngle(_page)) % 180 == 90) { CGFloat t = w; w = h; h = t; }
        if (!isfinite(w) || !isfinite(h) || w <= 0 || h <= 0) return nil;
        CGFloat factor = 1024.0 / MAX(w,h);
        _pageSize = CGSizeMake(MAX(1,floor(w*factor+.5)),MAX(1,floor(h*factor+.5)));
        self.frame = (CGRect){CGPointZero,_pageSize};
        self.opaque = YES; self.backgroundColor = [UIColor whiteColor]; self.userInteractionEnabled = NO;
        self.contentScaleFactor = [UIScreen mainScreen].scale;
        _pageTransform = CGPDFPageGetDrawingTransform(_page,kCGPDFCropBox,(CGRect){CGPointZero,_pageSize},0,YES);
        CATiledLayer *tiles = (CATiledLayer *)self.layer;
        tiles.tileSize = CGSizeMake(256,256); tiles.levelsOfDetail = 1; tiles.levelsOfDetailBias = 4;
        tiles.contentsScale = [UIScreen mainScreen].scale;
        if ([tiles respondsToSelector:@selector(setDrawsAsynchronously:)]) tiles.drawsAsynchronously = YES;
    } return self;
}
- (CGSize)pageSize { return _pageSize; }
- (void)drawRect:(CGRect)rect {
    @autoreleasepool { @synchronized (self) {
        CGContextRef ctx = UIGraphicsGetCurrentContext(); if (!ctx || !_page) return;
        CGContextSaveGState(ctx);
        CGContextSetRGBFillColor(ctx,1,1,1,1); CGContextFillRect(ctx,CGContextGetClipBoundingBox(ctx));
        CGContextSetInterpolationQuality(ctx,kCGInterpolationHigh);
        CGContextSetShouldAntialias(ctx,true); CGContextSetAllowsAntialiasing(ctx,true);
        CGContextTranslateCTM(ctx,0,_pageSize.height); CGContextScaleCTM(ctx,1,-1);
        CGContextConcatCTM(ctx,_pageTransform); CGContextDrawPDFPage(ctx,_page);
        CGContextRestoreGState(ctx);
    } }
}
- (void)reduceMemoryUsage { CATiledLayer *tiles = (CATiledLayer *)self.layer; tiles.levelsOfDetailBias = 2; [self setNeedsDisplay]; }
- (void)dealloc { if (_pdf) CGPDFDocumentRelease(_pdf); }
@end
