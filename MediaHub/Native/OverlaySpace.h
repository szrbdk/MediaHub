#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Owns an application space independent of the animated desktop spaces.
@interface OverlaySpace : NSObject
- (BOOL)attachWindow:(NSWindow *)window;
- (void)invalidate;
@end

NS_ASSUME_NONNULL_END
