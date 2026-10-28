#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface MusicAutomation : NSObject
- (void)cancelPendingRequests;
- (void)readFavoriteForTitle:(NSString *)title artist:(NSString *)artist
             completion:(void (^)(NSNumber * _Nullable favorite, NSString * _Nullable error))completion
    NS_SWIFT_NAME(readFavorite(forTitle:artist:completion:));
- (void)setFavoriteForTitle:(NSString *)title artist:(NSString *)artist favorite:(BOOL)favorite
             completion:(void (^)(NSNumber * _Nullable favorite, NSString * _Nullable error))completion
    NS_SWIFT_NAME(setFavorite(forTitle:artist:favorite:completion:));
@end
NS_ASSUME_NONNULL_END
