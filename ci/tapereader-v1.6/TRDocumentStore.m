#import "TRDocumentStore.h"
#import "TRTape.h"
#import <CoreGraphics/CoreGraphics.h>
#import <UIKit/UIKit.h>

@interface TRDocumentStore ()
@property(nonatomic, readwrite, copy) NSString *rootPath;
@property(nonatomic, readwrite, strong) NSMutableArray *documents;
@property(nonatomic, readwrite, copy) NSString *loadWarning;
@end

static TRDocumentStore *TRSharedStore = nil;

@implementation TRDocumentStore

+ (instancetype)sharedStore { if (!TRSharedStore) TRSharedStore = [[self alloc] init]; return TRSharedStore; }

- (NSString *)dataPath:(NSString *)identifier {
    return [[self.rootPath stringByAppendingPathComponent:@"Data"] stringByAppendingPathComponent:[identifier stringByAppendingPathExtension:@"plist"]];
}

- (NSString *)safeName:(NSString *)name fallback:(NSString *)fallback {
    NSString *s = [name length] ? name : fallback;
    NSMutableString *m = [NSMutableString stringWithString:s];
    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|\n\r\t"];
    for (NSInteger i=(NSInteger)[m length]-1; i>=0; i--) {
        unichar c = [m characterAtIndex:(NSUInteger)i];
        if ([bad characterIsMember:c]) [m replaceCharactersInRange:NSMakeRange((NSUInteger)i,1) withString:@"_"];
    }
    while ([m hasSuffix:@"."]) [m deleteCharactersInRange:NSMakeRange([m length]-1,1)];
    if (![m length]) return fallback;
    if ([m length] > 72) return [m substringToIndex:72];
    return m;
}

- (NSString *)uniqueExportPathWithBase:(NSString *)base extension:(NSString *)extension {
    NSString *folder = [self.rootPath stringByAppendingPathComponent:@"Export"];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *safe = [self safeName:base fallback:@"TapeReader"];
    NSString *path = [folder stringByAppendingPathComponent:[safe stringByAppendingPathExtension:extension]];
    NSUInteger n = 2;
    while ([fm fileExistsAtPath:path]) {
        NSString *candidate = [NSString stringWithFormat:@"%@ %lu",safe,(unsigned long)n++];
        path = [folder stringByAppendingPathComponent:[candidate stringByAppendingPathExtension:extension]];
    }
    return path;
}

- (id)init {
    if ((self = [super init])) {
        self.rootPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0] stringByAppendingPathComponent:@"TapeReader"];
        self.documents = [NSMutableArray array];
        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSString *folder in @[@"PDFs", @"Data", @"Import", @"Export"]) {
            if (![fm createDirectoryAtPath:[self.rootPath stringByAppendingPathComponent:folder] withIntermediateDirectories:YES attributes:nil error:NULL])
                self.loadWarning = @"저장 폴더를 만들지 못했습니다. Documents 쓰기 권한을 확인하세요.";
        }

        NSString *data = [self.rootPath stringByAppendingPathComponent:@"Data"];
        for (NSString *file in [fm contentsOfDirectoryAtPath:data error:NULL]) {
            if (![[file pathExtension] isEqualToString:@"plist"]) continue;
            NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:[data stringByAppendingPathComponent:file]];
            NSString *identifier = [file stringByDeletingPathExtension];
            if (![p[@"version"] isEqual:@1] || ![p[@"title"] isKindOfClass:[NSString class]] || ![p[@"tapes"] isKindOfClass:[NSArray class]] ||
                ![p[@"lastPage"] isKindOfClass:[NSNumber class]] || ![p[@"id"] isEqual:identifier]) {
                self.loadWarning = @"읽을 수 없는 주석 파일이 있습니다. 원본은 보존했습니다. Data 폴더를 백업해 주세요.";
                continue;
            }

            TRDocument *d = [[TRDocument alloc] init];
            d.identifier = identifier;
            d.title = p[@"title"];
            d.pdfPath = [[self.rootPath stringByAppendingPathComponent:@"PDFs"] stringByAppendingPathComponent:[identifier stringByAppendingPathExtension:@"pdf"]];

            NSString *pending = [d.pdfPath stringByAppendingString:@".deleting"];
            if (![fm fileExistsAtPath:d.pdfPath] && [fm fileExistsAtPath:pending]) [fm moveItemAtPath:pending toPath:d.pdfPath error:NULL];
            if (![fm fileExistsAtPath:d.pdfPath]) {
                self.loadWarning = @"일부 PDF 원본이 없습니다. Data 주석은 보존했습니다.";
                continue;
            }

            d.lastPage = MAX(0, [p[@"lastPage"] integerValue]);
            d.lastOpened = [p[@"opened"] isKindOfClass:[NSDate class]] ? p[@"opened"] : nil;
            d.modified = [p[@"modified"] isKindOfClass:[NSDate class]] ? p[@"modified"] : [NSDate date];

            BOOL invalid = NO;
            for (id raw in p[@"tapes"]) {
                TRTape *t = [TRTape fromDictionary:raw];
                if (t) [d.tapes addObject:t]; else invalid = YES;
            }
            if (invalid) {
                self.loadWarning = @"손상된 주석이 있는 문서를 열지 않았습니다. Data 원본은 보존했습니다.";
                continue;
            }
            [self.documents addObject:d];
        }
    }
    return self;
}

- (TRDocument *)importBackupURL:(NSURL *)url error:(NSError **)error {
    NSData *bytes = [NSData dataWithContentsOfURL:url options:0 error:error];
    if (!bytes) return nil;

    id root = [NSPropertyListSerialization propertyListWithData:bytes options:NSPropertyListImmutable format:NULL error:error];
    if (![root isKindOfClass:[NSDictionary class]]) {
        if (error) *error = [NSError errorWithDomain:@"TapeReader" code:30 userInfo:@{NSLocalizedDescriptionKey:@"TapeReader 백업 파일 형식이 아닙니다."}];
        return nil;
    }

    NSDictionary *backup = (NSDictionary *)root;
    if (![backup[@"format"] isEqual:@"TapeReaderBackup"] || ![backup[@"version"] isEqual:@1] ||
        ![backup[@"pdf"] isKindOfClass:[NSData class]] || ![backup[@"document"] isKindOfClass:[NSDictionary class]]) {
        if (error) *error = [NSError errorWithDomain:@"TapeReader" code:31 userInfo:@{NSLocalizedDescriptionKey:@"지원하지 않는 백업 파일입니다."}];
        return nil;
    }

    NSDictionary *meta = backup[@"document"];
    if (![meta[@"title"] isKindOfClass:[NSString class]] || ![meta[@"tapes"] isKindOfClass:[NSArray class]]) {
        if (error) *error = [NSError errorWithDomain:@"TapeReader" code:32 userInfo:@{NSLocalizedDescriptionKey:@"백업의 문서 정보가 손상되었습니다."}];
        return nil;
    }

    TRDocument *d = [[TRDocument alloc] init];
    d.identifier = [[NSUUID UUID] UUIDString];
    d.title = meta[@"title"];
    d.lastPage = [meta[@"lastPage"] respondsToSelector:@selector(unsignedIntegerValue)] ? [meta[@"lastPage"] unsignedIntegerValue] : 0;
    d.lastOpened = [NSDate date];

    for (id raw in meta[@"tapes"]) {
        TRTape *t = [TRTape fromDictionary:raw];
        if (!t) {
            if (error) *error = [NSError errorWithDomain:@"TapeReader" code:33 userInfo:@{NSLocalizedDescriptionKey:@"백업의 테이프 정보가 손상되었습니다."}];
            return nil;
        }
        [d.tapes addObject:t];
    }

    d.pdfPath = [[self.rootPath stringByAppendingPathComponent:@"PDFs"] stringByAppendingPathComponent:[d.identifier stringByAppendingPathExtension:@"pdf"]];
    NSData *pdfData = backup[@"pdf"];
    if (![pdfData writeToFile:d.pdfPath options:NSDataWritingAtomic error:error]) return nil;

    CGPDFDocumentRef pdf = CGPDFDocumentCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:d.pdfPath]);
    BOOL valid = pdf && (!CGPDFDocumentIsEncrypted(pdf) || CGPDFDocumentIsUnlocked(pdf)) && CGPDFDocumentGetNumberOfPages(pdf) > 0;
    if (pdf) CGPDFDocumentRelease(pdf);
    if (!valid) {
        [[NSFileManager defaultManager] removeItemAtPath:d.pdfPath error:NULL];
        if (error) *error = [NSError errorWithDomain:@"TapeReader" code:34 userInfo:@{NSLocalizedDescriptionKey:@"백업 안의 PDF가 손상되었습니다."}];
        return nil;
    }

    if (![self saveDocument:d error:error]) {
        [[NSFileManager defaultManager] removeItemAtPath:d.pdfPath error:NULL];
        return nil;
    }
    [self.documents addObject:d];
    return d;
}

- (TRDocument *)importURL:(NSURL *)url error:(NSError **)error {
    if (!url.isFileURL) {
        if (error) *error = [NSError errorWithDomain:@"TapeReader" code:1 userInfo:@{NSLocalizedDescriptionKey:@"로컬 파일만 가져올 수 있습니다."}];
        return nil;
    }

    NSString *ext = [[[url pathExtension] lowercaseString] copy];
    if ([ext isEqualToString:@"tapereaderbackup"]) return [self importBackupURL:url error:error];

    if (![ext isEqualToString:@"pdf"]) {
        if (error) *error = [NSError errorWithDomain:@"TapeReader" code:3 userInfo:@{NSLocalizedDescriptionKey:@"PDF 또는 TapeReader 백업 파일만 가져올 수 있습니다."}];
        return nil;
    }

    CGPDFDocumentRef pdf = CGPDFDocumentCreateWithURL((__bridge CFURLRef)url);
    BOOL valid = pdf && (!CGPDFDocumentIsEncrypted(pdf) || CGPDFDocumentIsUnlocked(pdf)) && CGPDFDocumentGetNumberOfPages(pdf) > 0;
    if (pdf) CGPDFDocumentRelease(pdf);
    if (!valid) {
        if (error) *error = [NSError errorWithDomain:@"TapeReader" code:2 userInfo:@{NSLocalizedDescriptionKey:@"유효하지 않거나 암호로 잠긴 PDF입니다. 암호 없는 PDF를 사용하세요."}];
        return nil;
    }

    TRDocument *d = [[TRDocument alloc] init];
    d.identifier = [[NSUUID UUID] UUIDString];
    d.title = [[url lastPathComponent] stringByDeletingPathExtension];
    d.pdfPath = [[self.rootPath stringByAppendingPathComponent:@"PDFs"] stringByAppendingPathComponent:[d.identifier stringByAppendingPathExtension:@"pdf"]];
    if (![[NSFileManager defaultManager] copyItemAtPath:url.path toPath:d.pdfPath error:error]) return nil;
    if (![self saveDocument:d error:error]) {
        [[NSFileManager defaultManager] removeItemAtPath:d.pdfPath error:NULL];
        return nil;
    }
    [self.documents addObject:d];
    return d;
}

- (BOOL)saveDocument:(TRDocument *)d error:(NSError **)error {
    NSMutableArray *tapes = [NSMutableArray arrayWithCapacity:d.tapes.count];
    for (TRTape *t in d.tapes) [tapes addObject:[t dictionary]];
    d.modified = [NSDate date];
    NSDictionary *p = @{@"version":@1, @"id":d.identifier, @"title":d.title, @"lastPage":@(d.lastPage),
        @"opened":d.lastOpened ?: [NSDate distantPast], @"modified":d.modified, @"tapes":tapes};
    NSData *bytes = [NSPropertyListSerialization dataWithPropertyList:p format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    return bytes && [bytes writeToFile:[self dataPath:d.identifier] options:NSDataWritingAtomic error:error];
}

- (BOOL)deleteDocument:(TRDocument *)d error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *trash = [d.pdfPath stringByAppendingString:@".deleting"];
    if (![fm moveItemAtPath:d.pdfPath toPath:trash error:error]) return NO;
    if (![fm removeItemAtPath:[self dataPath:d.identifier] error:error]) {
        [fm moveItemAtPath:trash toPath:d.pdfPath error:NULL];
        return NO;
    }
    [fm removeItemAtPath:trash error:NULL];
    [self.documents removeObject:d];
    return YES;
}

- (NSArray *)pendingImportURLs {
    NSMutableArray *result = [NSMutableArray array];
    NSString *documents = [self.rootPath stringByDeletingLastPathComponent];
    NSArray *folders = @[[self.rootPath stringByAppendingPathComponent:@"Import"], [documents stringByAppendingPathComponent:@"Inbox"], documents];
    for (NSString *folder in folders) {
        for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:NULL]) {
            NSString *ext = [[f pathExtension] lowercaseString];
            if ([ext isEqualToString:@"pdf"] || [ext isEqualToString:@"tapereaderbackup"])
                [result addObject:[NSURL fileURLWithPath:[folder stringByAppendingPathComponent:f]]];
        }
    }
    return result;
}

- (NSURL *)backupURLForDocument:(TRDocument *)d error:(NSError **)error {
    if (![self saveDocument:d error:error]) return nil;
    NSData *pdf = [NSData dataWithContentsOfFile:d.pdfPath options:0 error:error];
    if (!pdf) return nil;

    NSMutableArray *tapes = [NSMutableArray arrayWithCapacity:d.tapes.count];
    for (TRTape *t in d.tapes) [tapes addObject:[t dictionary]];
    NSDictionary *meta = @{@"title":d.title ?: @"문서", @"lastPage":@(d.lastPage), @"tapes":tapes,
                           @"modified":d.modified ?: [NSDate date]};
    NSDictionary *backup = @{@"format":@"TapeReaderBackup", @"version":@1,
                             @"created":[NSDate date], @"document":meta, @"pdf":pdf};
    NSData *bytes = [NSPropertyListSerialization dataWithPropertyList:backup format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    if (!bytes) return nil;

    NSString *path = [self uniqueExportPathWithBase:[NSString stringWithFormat:@"%@ 백업",d.title ?: @"TapeReader"] extension:@"tapereaderbackup"];
    if (![bytes writeToFile:path options:NSDataWritingAtomic error:error]) return nil;
    return [NSURL fileURLWithPath:path];
}

- (NSURL *)exportPDFWithTapesForDocument:(TRDocument *)d error:(NSError **)error {
    CGPDFDocumentRef pdf = CGPDFDocumentCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:d.pdfPath]);
    if (!pdf) {
        if (error) *error = [NSError errorWithDomain:@"TapeReader" code:40 userInfo:@{NSLocalizedDescriptionKey:@"원본 PDF를 열 수 없습니다."}];
        return nil;
    }

    NSString *path = [self uniqueExportPathWithBase:[NSString stringWithFormat:@"%@ - 테이프",d.title ?: @"TapeReader"] extension:@"pdf"];
    UIGraphicsBeginPDFContextToFile(path, CGRectZero, nil);

    size_t count = CGPDFDocumentGetNumberOfPages(pdf);
    for (size_t index=0; index<count; index++) {
        @autoreleasepool {
            CGPDFPageRef page = CGPDFDocumentGetPage(pdf,index+1);
            if (!page) continue;

            CGRect crop = CGPDFPageGetBoxRect(page,kCGPDFCropBox);
            CGFloat w = crop.size.width, h = crop.size.height;
            NSInteger angle = CGPDFPageGetRotationAngle(page);
            if (labs(angle) % 180 == 90) { CGFloat tmp = w; w = h; h = tmp; }
            if (w <= 0 || h <= 0) continue;

            CGRect media = CGRectMake(0,0,w,h);
            UIGraphicsBeginPDFPageWithInfo(media,nil);
            CGContextRef ctx = UIGraphicsGetCurrentContext();
            CGContextSetRGBFillColor(ctx,1,1,1,1);
            CGContextFillRect(ctx,media);

            CGContextSaveGState(ctx);
            CGContextTranslateCTM(ctx,0,h);
            CGContextScaleCTM(ctx,1,-1);
            CGContextConcatCTM(ctx,CGPDFPageGetDrawingTransform(page,kCGPDFCropBox,media,0,YES));
            CGContextDrawPDFPage(ctx,page);
            CGContextRestoreGState(ctx);

            for (TRTape *t in d.tapes) {
                if (t.pageIndex != index) continue;
                CGRect n = t.normalizedRect;
                CGRect r = CGRectMake(n.origin.x*w,n.origin.y*h,n.size.width*w,n.size.height*h);

                CGContextSetRGBFillColor(ctx,0,0,0,.12);
                CGContextFillRect(ctx,CGRectOffset(r,0,1.5));

                CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
                CGFloat comps[] = {1.0,.93,.53,1.0, .93,.79,.31,1.0};
                CGGradientRef grad = CGGradientCreateWithColorComponents(cs,comps,NULL,2);
                CGContextSaveGState(ctx);
                CGContextClipToRect(ctx,r);
                CGContextDrawLinearGradient(ctx,grad,CGPointMake(CGRectGetMidX(r),CGRectGetMinY(r)),
                                             CGPointMake(CGRectGetMidX(r),CGRectGetMaxY(r)),0);
                CGContextRestoreGState(ctx);
                CGGradientRelease(grad);
                CGColorSpaceRelease(cs);

                CGContextSetRGBStrokeColor(ctx,.72,.60,.24,.45);
                CGContextSetLineWidth(ctx,.45);
                CGContextStrokeRect(ctx,r);
                CGContextSetRGBStrokeColor(ctx,1,1,1,.42);
                CGContextMoveToPoint(ctx,CGRectGetMinX(r),CGRectGetMinY(r)+.5);
                CGContextAddLineToPoint(ctx,CGRectGetMaxX(r),CGRectGetMinY(r)+.5);
                CGContextStrokePath(ctx);
            }
        }
    }

    UIGraphicsEndPDFContext();
    CGPDFDocumentRelease(pdf);

    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:error];
    if (!attrs || [attrs fileSize] == 0) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        if (error && !*error) *error = [NSError errorWithDomain:@"TapeReader" code:41 userInfo:@{NSLocalizedDescriptionKey:@"PDF 내보내기에 실패했습니다."}];
        return nil;
    }
    return [NSURL fileURLWithPath:path];
}

@end
