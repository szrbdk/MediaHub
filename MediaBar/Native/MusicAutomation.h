#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface MusicAutomation : NSObject
- (void)cancelPendingRequests;
- (void)favoriteForTitle:(NSString *)title artist:(NSString *)artist add:(BOOL)add
             completion:(void (^)(NSNumber * _Nullable favorite, NSString * _Nullable error))completion;
- (void)dislikeAndSkipForTitle:(NSString *)title artist:(NSString *)artist
                   completion:(void (^)(BOOL success, NSString * _Nullable error))completion;
@end
NS_ASSUME_NONNULL_END
