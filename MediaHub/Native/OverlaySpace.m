#import "OverlaySpace.h"
#import <dlfcn.h>
#import <limits.h>
#import <os/log.h>

// These private SkyLight entry points are also used by SketchyBar to keep
// windows stationary during Space transitions. Resolve them at runtime so an
// unavailable API leaves the ordinary AppKit presentation intact.
typedef int (*MainConnection)(void);
// Space IDs are opaque 64-bit values, not signed window/connection IDs.
typedef uint64_t (*CreateSpace)(int, int, CFDictionaryRef);
typedef void (*SetSpaceLevel)(int, uint64_t, int);
typedef void (*ShowSpaces)(int, CFArrayRef);
typedef CGError (*MoveWindows)(int, uint64_t, CFArrayRef, int);
typedef void (*DestroySpace)(int, uint64_t);
typedef CFArrayRef (*CopyWindowSpaces)(int, int, CFArrayRef);

@implementation OverlaySpace {
    int _connection;
    uint64_t _space;
    __weak NSWindow *_window;
    NSWindowCollectionBehavior _fallbackBehavior;
    NSUInteger _generation;
    id _spaceObserver;
    os_log_t _log;
    BOOL _reportedFailure;
    MainConnection _mainConnection;
    CreateSpace _createSpace;
    SetSpaceLevel _setSpaceLevel;
    ShowSpaces _showSpaces;
    MoveWindows _moveWindows;
    DestroySpace _destroySpace;
    CopyWindowSpaces _copyWindowSpaces;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _log = os_log_create("com.sezerbudak.MediaHub", "OverlaySpace");
        // Keep the framework loaded for the lifetime of the process.
        static void *framework;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            framework = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL);
        });
        if (framework) {
            _mainConnection = (MainConnection)dlsym(framework, "SLSMainConnectionID");
            _createSpace = (CreateSpace)dlsym(framework, "SLSSpaceCreate");
            _setSpaceLevel = (SetSpaceLevel)dlsym(framework, "SLSSpaceSetAbsoluteLevel");
            _showSpaces = (ShowSpaces)dlsym(framework, "SLSShowSpaces");
            _moveWindows = (MoveWindows)dlsym(framework, "SLSSpaceAddWindowsAndRemoveFromSpaces");
            _destroySpace = (DestroySpace)dlsym(framework, "SLSSpaceDestroy");
            _copyWindowSpaces = (CopyWindowSpaces)dlsym(framework, "SLSCopySpacesForWindows");
        }
        __weak OverlaySpace *weakSelf = self;
        _spaceObserver = [NSWorkspace.sharedWorkspace.notificationCenter
            addObserverForName:NSWorkspaceActiveSpaceDidChangeNotification object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(NSNotification *notification) {
                OverlaySpace *owner = weakSelf;
                if (!owner) return;
                NSWindow *window = owner->_window;
                if (window.isVisible) [owner attachWindow:window];
            }];
    }
    return self;
}

- (BOOL)attachWindow:(NSWindow *)window {
    NSAssert(NSThread.isMainThread, @"Overlay spaces must be managed on the main thread");
    if (_window != window) {
        _window = window;
        _fallbackBehavior = window.collectionBehavior;
    }
    BOOL attached = [self ensureAttachment:window];
    // AppKit can flush its own collection behavior after orderFront/setFrame.
    // Verify again after that flush, without repeatedly ordering the window in.
    NSUInteger generation = ++_generation;
    __weak OverlaySpace *weakSelf = self;
    for (NSNumber *delay in @[@0, @0.2]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            OverlaySpace *owner = weakSelf;
            if (!owner || owner->_generation != generation) return;
            NSWindow *currentWindow = owner->_window;
            if (currentWindow.isVisible) [owner ensureAttachment:currentWindow];
        });
    }
    return attached;
}

- (BOOL)ensureAttachment:(NSWindow *)window {
    if (!_mainConnection || !_createSpace || !_setSpaceLevel || !_showSpaces || !_moveWindows || !_destroySpace || !_copyWindowSpaces) {
        [self reportFailure:@"Required SkyLight entry point is unavailable"];
        return NO;
    }
    NSInteger number = window.windowNumber;
    if (number <= 0 || number > INT_MAX) return NO;
    if (!_space) {
        _connection = _mainConnection();
        _space = _createSpace(_connection, 1, NULL);
        if (!_space) {
            [self reportFailure:@"SkyLight did not create an overlay space"];
            return NO;
        }
        // Keep the default space level: Dock and system overlays stay above us.
        _setSpaceLevel(_connection, _space, 0);
    }
    // Show again after wake/Space changes, even if membership survived.
    NSArray<NSNumber *> *spaces = @[@(_space)];
    _showSpaces(_connection, (__bridge CFArrayRef)spaces);
    // AppKit's sticky-desktop membership must not compete with the independent
    // space. Keep the original behavior available if adoption fails.
    if (window.collectionBehavior & NSWindowCollectionBehaviorCanJoinAllSpaces) {
        window.collectionBehavior &= ~NSWindowCollectionBehaviorCanJoinAllSpaces;
    }
    NSArray<NSNumber *> *windows = @[@((int)number)];
    NSArray *previous = CFBridgingRelease(_copyWindowSpaces(_connection, 0x7, (__bridge CFArrayRef)windows));
    if (previous.count == 1 && [previous.firstObject isEqual:spaces.firstObject]) return YES;
    CGError result = _moveWindows(_connection, _space, (__bridge CFArrayRef)windows, 0x7);
    NSArray *actual = CFBridgingRelease(_copyWindowSpaces(_connection, 0x7, (__bridge CFArrayRef)windows));
    BOOL attached = result == kCGErrorSuccess && actual.count == 1 && [actual.firstObject isEqual:spaces.firstObject];
    if (attached) {
        _reportedFailure = NO;
        os_log_info(_log, "Attached window %ld to independent space %llu", (long)number, (unsigned long long)_space);
    } else {
        window.collectionBehavior = _fallbackBehavior;
        [self reportFailure:[NSString stringWithFormat:@"Window %ld, target %llu, actual %@, move result %d",
            (long)number, (unsigned long long)_space, actual, result]];
    }
    return attached;
}

- (void)reportFailure:(NSString *)reason {
    if (_reportedFailure) return;
    _reportedFailure = YES;
    os_log_error(_log, "Could not establish stationary overlay: %{public}@", reason);
}

- (void)invalidate {
    ++_generation;
    _window = nil;
    if (_space) {
        _destroySpace(_connection, _space);
        _space = 0;
    }
}

- (void)dealloc {
    if (_spaceObserver) [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:_spaceObserver];
    [self invalidate];
}
@end
