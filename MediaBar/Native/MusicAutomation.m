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

static NSAppleEventDescriptor *sendMusicEvent(AEEventClass eventClass, AEEventID command, NSAppleEventDescriptor *object,
                                             NSAppleEventDescriptor *value, NSString **error) {
    NSAppleEventDescriptor *target = [NSAppleEventDescriptor descriptorWithDescriptorType:typeApplicationBundleID
        data:[@"com.apple.Music" dataUsingEncoding:NSUTF8StringEncoding]];
    NSAppleEventDescriptor *event = [NSAppleEventDescriptor appleEventWithEventClass:eventClass
        eventID:command targetDescriptor:target returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
    if (object) [event setParamDescriptor:object forKeyword:keyDirectObject];
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

static NSAppleEventDescriptor *sendEvent(AEEventID command, NSAppleEventDescriptor *object,
                                        NSAppleEventDescriptor *value, NSString **error) {
    return sendMusicEvent(kAECoreSuite, command, object, value, error);
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
- (void)favoriteForTitle:(NSString *)title artist:(NSString *)artist add:(BOOL)add
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
                    if (add && !error && !favorite.boolValue && [self isCurrentGeneration:generation]) {
                        // The object specifier returned by Music pins this operation
                        // to the resolved track instead of a later "current track".
                        sendEvent(kAESetData, favoriteProperty, [NSAppleEventDescriptor descriptorWithBoolean:YES], &error);
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
- (void)dislikeAndSkipForTitle:(NSString *)title artist:(NSString *)artist
                   completion:(void (^)(BOOL, NSString *))completion {
    NSUInteger generation;
    @synchronized (self) { generation = _generation; }
    dispatch_async(_queue, ^{
        @autoreleasepool {
            NSString *error = nil;
            BOOL success = NO;
            if ([self isCurrentGeneration:generation] &&
                [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.Music"].count) {
                NSAppleEventDescriptor *track = sendEvent(kAEGetData, property('pTrk', nil), nil, &error);
                NSString *name = !error && track ? sendEvent(kAEGetData, property('pnam', track), nil, &error).stringValue : nil;
                NSString *source = !error && track ? sendEvent(kAEGetData, property('pArt', track), nil, &error).stringValue : nil;
                NSString *identity = !error && track ? sendEvent(kAEGetData, property('pPIS', track), nil, &error).stringValue : nil;
                if (!error && identity.length && [name isEqualToString:title] && [(source ?: @"") isEqualToString:artist]
                    && [self isCurrentGeneration:generation]) {
                    NSAppleEventDescriptor *dislikedProperty = property('pHat', track);
                    // Write only true; repeated requests never toggle Suggest Less off.
                    sendEvent(kAESetData, dislikedProperty, [NSAppleEventDescriptor descriptorWithBoolean:YES], &error);
                    NSAppleEventDescriptor *confirmed = !error ? sendEvent(kAEGetData, dislikedProperty, nil, &error) : nil;
                    if (!error && confirmed.booleanValue && [self isCurrentGeneration:generation]) {
                        NSAppleEventDescriptor *current = sendEvent(kAEGetData, property('pTrk', nil), nil, &error);
                        NSString *currentID = !error && current ? sendEvent(kAEGetData, property('pPIS', current), nil, &error).stringValue : nil;
                        if (!error && [self isCurrentGeneration:generation]) {
                            if ([identity isEqualToString:currentID]) {
                                // Target Music itself, not whichever player owns the
                                // system Now Playing slot when this request completes.
                                sendMusicEvent('hook', 'Next', nil, nil, &error);
                                success = error == nil;
                            } else if (currentID.length) {
                                // Music already moved on; never skip the new track.
                                success = YES;
                            }
                        }
                    }
                }
            }
            if (!success && !error) error = @"Suggest Less was not confirmed, or the current track changed";
            dispatch_async(dispatch_get_main_queue(), ^{ completion(success, error); });
        }
    });
}
@end
