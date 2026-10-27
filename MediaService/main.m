#import <AppKit/AppKit.h>
#import "MediaServiceProtocol.h"
#import "MediaRemote.h"

// XPC keeps the private MediaRemote identity separate from the application.
// Its bundle ID uses the com.apple prefix accepted by mediaremoted on this Mac.
@interface MediaService : NSObject <NSXPCListenerDelegate, MediaServiceProtocol>
@property(nonatomic, strong) MediaRemote *remote;
@end

@implementation MediaService
- (instancetype)init {
    if ((self = [super init])) _remote = [MediaRemote new];
    return self;
}
- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)connection {
    connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(MediaServiceProtocol)];
    connection.exportedObject = self;
    [connection resume];
    return YES;
}
- (void)readStateWithReply:(void (^)(NSDictionary *, NSString *))reply {
    MediaRemote *remote = self.remote;
    if (!remote.getNowPlayingInfo || !remote.getNowPlayingApplicationPID ||
        !remote.getNowPlayingApplicationIsPlaying || !remote.getNowPlayingClient) {
        reply(nil, @"MediaRemote symbols are unavailable");
        return;
    }
    // All callbacks and the deadline run on the same queue. Late replies cannot
    // mutate a returned snapshot, and every request completes exactly once.
    dispatch_queue_t queue = dispatch_queue_create("com.sezerbudak.MediaBar.snapshot", DISPATCH_QUEUE_SERIAL);
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    __block NSUInteger remaining = 4;
    __block BOOL finished = NO;
    void (^complete)(void) = ^{
        if (finished || --remaining != 0) return;
        finished = YES;
        reply([snapshot copy], nil);
    };
    remote.getNowPlayingInfo(queue, ^(NSDictionary *info) {
        if (finished) return;
        NSDictionary *keys = @{
            @"title": kMRMediaRemoteNowPlayingInfoTitle,
            @"artist": kMRMediaRemoteNowPlayingInfoArtist,
            @"album": kMRMediaRemoteNowPlayingInfoAlbum,
            @"uniqueIdentifier": kMRMediaRemoteNowPlayingInfoUniqueIdentifier,
            @"contentItemIdentifier": kMRMediaRemoteNowPlayingInfoContentItemIdentifier,
            @"playbackRate": kMRMediaRemoteNowPlayingInfoPlaybackRate
        };
        [keys enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *source, BOOL *stop) {
            id value = info[source];
            if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) snapshot[key] = value;
        }];
        NSDictionary *times = @{@"durationMicros": kMRMediaRemoteNowPlayingInfoDuration,
                                @"elapsedTimeMicros": kMRMediaRemoteNowPlayingInfoElapsedTime};
        [times enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *source, BOOL *stop) {
            id value = info[source];
            if ([value isKindOfClass:NSNumber.class]) snapshot[key] = @([value doubleValue] * 1000000);
        }];
        id timestamp = info[kMRMediaRemoteNowPlayingInfoTimestamp];
        if ([timestamp isKindOfClass:NSDate.class]) snapshot[@"timestampEpochMicros"] = @([timestamp timeIntervalSince1970] * 1000000);
        complete();
    });
    remote.getNowPlayingApplicationPID(queue, ^(int pid) {
        if (finished) return;
        NSString *bundle = [NSRunningApplication runningApplicationWithProcessIdentifier:pid].bundleIdentifier;
        if (bundle) snapshot[@"bundleIdentifier"] = bundle;
        complete();
    });
    remote.getNowPlayingClient(queue, ^(id client) {
        if (finished) return;
        if ([client respondsToSelector:@selector(parentApplicationBundleIdentifier)]) {
            NSString *bundle = [client parentApplicationBundleIdentifier];
            if (bundle.length) snapshot[@"parentApplicationBundleIdentifier"] = bundle;
        }
        complete();
    });
    remote.getNowPlayingApplicationIsPlaying(queue, ^(bool playing) {
        if (finished) return;
        snapshot[@"playing"] = @(playing);
        complete();
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), queue, ^{
        if (finished) return;
        finished = YES;
        reply(nil, @"MediaRemote snapshot timed out");
    });
}
- (void)sendCommand:(NSInteger)command reply:(void (^)(BOOL))reply {
    switch (command) {
        case 2: case 4: case 5: case 8: case 9: case 10: case 11: case 12: case 13:
            reply(self.remote.sendCommand && self.remote.sendCommand((MRCommand)command, nil));
            break;
        default: reply(NO);
    }
}
- (void)seekToPosition:(double)seconds reply:(void (^)(BOOL))reply {
    if (!isfinite(seconds) || seconds < 0 || !self.remote.setElapsedTime) { reply(NO); return; }
    self.remote.setElapsedTime(seconds);
    reply(YES);
}
- (void)flushWithReply:(void (^)(void))reply {
    // XPC invokes this after earlier command messages on this connection.
    reply();
}
@end

int main(void) {
    @autoreleasepool {
        MediaService *service = [MediaService new];
        NSXPCListener *listener = NSXPCListener.serviceListener;
        listener.delegate = service;
        [listener resume];
    }
    return 0;
}
