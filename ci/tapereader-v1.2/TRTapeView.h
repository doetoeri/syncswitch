#import "TRTape.h"
@class TRTapeView;
@protocol TRTapeViewDelegate <NSObject>
- (void)tapeViewTapped:(TRTapeView *)view;
- (void)tapeViewChanged:(TRTapeView *)view;
- (void)tapeViewHeld:(TRTapeView *)view;
@end
@interface TRTapeView : UIView <UIGestureRecognizerDelegate>
@property(nonatomic, strong) TRTape *tape;
@property(nonatomic, weak) id<TRTapeViewDelegate> delegate;
@property(nonatomic) BOOL editable;
@property(nonatomic) BOOL focused;
@property(nonatomic) BOOL selectedForEditing;
@property(nonatomic) BOOL peelEnabled;
- (void)refresh;
- (void)togglePeelAnimated;
@end
