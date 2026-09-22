#import "TRDocument.h"
@interface TRDocumentStore : NSObject
@property(nonatomic, readonly) NSString *rootPath;
@property(nonatomic, readonly) NSMutableArray *documents;
@property(nonatomic, readonly) NSString *loadWarning;
+ (instancetype)sharedStore;
- (TRDocument *)importURL:(NSURL *)url error:(NSError **)error;
- (BOOL)saveDocument:(TRDocument *)document error:(NSError **)error;
- (BOOL)deleteDocument:(TRDocument *)document error:(NSError **)error;
- (NSArray *)pendingImportURLs;
- (NSURL *)exportPDFWithTapesForDocument:(TRDocument *)document error:(NSError **)error;
- (NSURL *)backupURLForDocument:(TRDocument *)document error:(NSError **)error;
@end
