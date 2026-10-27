#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@protocol MediaServiceProtocol
- (void)readStateWithReply:(void (^)(NSDictionary * _Nullable, NSString * _Nullable))reply NS_SWIFT_NAME(readState(reply:));
- (void)sendCommand:(NSInteger)command reply:(void (^)(BOOL))reply;
- (void)seekToPosition:(double)seconds reply:(void (^)(BOOL))reply;
- (void)flushWithReply:(void (^)(void))reply NS_SWIFT_NAME(flush(reply:));
@end
NS_ASSUME_NONNULL_END
