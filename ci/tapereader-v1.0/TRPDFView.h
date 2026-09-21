#import <UIKit/UIKit.h>
@interface TRPDFView : UIView
@property(nonatomic, readonly) CGSize pageSize;
- (id)initWithPath:(NSString *)path pageIndex:(NSUInteger)index;
- (void)reduceMemoryUsage;
@end
