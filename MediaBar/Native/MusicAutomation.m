#import "MusicAutomation.h"
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>

// Direct Apple Events: no AppleScript source, interpreter, or subprocess.
static NSAppleEventDescriptor *property(OSType code, NSAppleEventDescriptor *container) {
    NSAppleEventDescriptor *record = [NSAppleEventDescriptor recordDescriptor];
    [record setDescriptor:[NSAppleEventDescriptor descriptorWithTypeCode:code] forKeyword:keyAEKeyData];
    [record setDescriptor:[NSAppleEventDescriptor descriptorWithEnumCode:formPropertyID] forKeyword:keyAEKeyForm];
    [record setDescriptor:[NSAppleEventDescriptor descriptorWithTypeCode:typeProperty] forKeyword:keyAEDesiredClass];
    [record setDescriptor:container ?: [NSAppleEventDescriptor nullDescriptor] forKeyword:keyAEContainer];
    return [record coerceToDescriptorType:typeObjectSpecifier];
}

static NSAppleEventDescriptor *sendEvent(AEEventID command, NSAppleEventDescriptor *object,
                                        NSAppleEventDescriptor *value, NSString **error) {
    NSAppleEventDescriptor *target = [NSAppleEventDescriptor descriptorWithDescriptorType:typeApplicationBundleID
        data:[@"com.apple.Music" dataUsingEncoding:NSUTF8StringEncoding]];
    NSAppleEventDescriptor *event = [NSAppleEventDescriptor appleEventWithEventClass:kAECoreSuite
        eventID:command targetDescriptor:target returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
    [event setParamDescriptor:object forKeyword:keyDirectObject];
    if (value) [event setParamDescriptor:value forKeyword:keyAEData];
    AppleEvent reply = {typeNull, NULL};
    OSStatus status = AESendMessage(event.aeDesc, &reply, kAEWaitReply | kAENeverInteract, 3 * 60);
    if (status != noErr) {
        AEDisposeDesc(&reply);
        *error = [NSString stringWithFormat:@"Music Apple Event failed (%d)", (int)status];
        return nil;
    }
    NSAppleEventDescriptor *response = [[NSAppleEventDescriptor alloc] initWithAEDescNoCopy:&reply];
    int code = [response paramDescriptorForKeyword:keyErrorNumber].int32Value;
    if (code) {
        *error = [NSString stringWithFormat:@"Music rejected Apple Event (%d): %@", code,
            [response paramDescriptorForKeyword:keyErrorString].stringValue ?: @""];
        return nil;
    }
    return [response paramDescriptorForKeyword:keyDirectObject];
}

@implementation MusicAutomation {
    dispatch_queue_t _queue;
    NSUInteger _generation;
}
- (instancetype)init {
    if ((self = [super init])) _queue = dispatch_queue_create("com.sezerbudak.MediaBar.music", DISPATCH_QUEUE_SERIAL);
    return self;
}
- (void)cancelPendingRequests {
    @synchronized (self) { _generation += 1; }
}
- (BOOL)isCurrentGeneration:(NSUInteger)generation {
    @synchronized (self) { return _generation == generation; }
}
- (void)readFavoriteForTitle:(NSString *)title artist:(NSString *)artist
             completion:(void (^)(NSNumber *, NSString *))completion {
    [self favoriteForTitle:title artist:artist desired:nil completion:completion];
}
- (void)setFavoriteForTitle:(NSString *)title artist:(NSString *)artist favorite:(BOOL)favorite
             completion:(void (^)(NSNumber *, NSString *))completion {
    [self favoriteForTitle:title artist:artist desired:@(favorite) completion:completion];
}
- (void)favoriteForTitle:(NSString *)title artist:(NSString *)artist desired:(NSNumber *)desired
             completion:(void (^)(NSNumber *, NSString *))completion {
    __block NSUInteger generation;
    @synchronized (self) { generation = _generation; }
    dispatch_async(_queue, ^{
        @autoreleasepool {
            NSString *error = nil;
            NSNumber *favorite = nil;
            // Never launch Music just to query a favorite.
            if ([self isCurrentGeneration:generation] &&
                [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.Music"].count) {
                NSAppleEventDescriptor *track = sendEvent(kAEGetData, property('pTrk', nil), nil, &error);
                NSString *name = track ? sendEvent(kAEGetData, property('pnam', track), nil, &error).stringValue : nil;
                NSString *source = !error && track ? sendEvent(kAEGetData, property('pArt', track), nil, &error).stringValue : nil;
                if (!error && [name isEqualToString:title] && [source ?: @"" isEqualToString:artist]) {
                    NSAppleEventDescriptor *favoriteProperty = property('pLov', track);
                    NSAppleEventDescriptor *result = sendEvent(kAEGetData, favoriteProperty, nil, &error);
                    if (!error && result) favorite = @(result.booleanValue);
                    if (desired && !error && favorite && [self isCurrentGeneration:generation]) {
                        // The object specifier returned by Music pins this operation
                        // to the resolved track instead of a later "current track".
                        sendEvent(kAESetData, favoriteProperty,
                                  [NSAppleEventDescriptor descriptorWithBoolean:desired.boolValue], &error);
                        if (!error) {
                            result = sendEvent(kAEGetData, favoriteProperty, nil, &error);
                            favorite = result && !error ? @(result.booleanValue) : nil;
                        }
                    }
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{ completion(favorite, error); });
        }
    });
}
@end
