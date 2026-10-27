#import "TouchBarSystem.h"
#import <dlfcn.h>

@interface NSTouchBar (MediaBarSystemModal)
+ (void)presentSystemModalTouchBar:(NSTouchBar *)bar systemTrayItemIdentifier:(NSString *)identifier;
+ (void)presentSystemModalTouchBar:(NSTouchBar *)bar placement:(long long)placement systemTrayItemIdentifier:(NSString *)identifier;
+ (void)dismissSystemModalTouchBar:(NSTouchBar *)bar;
@end

static void closeBox(BOOL visible) {
    static void *framework;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ framework = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY); });
    if (!framework) return;
    void (*setVisible)(BOOL) = dlsym(framework, "DFRSystemModalShowsCloseBoxWhenFrontMost");
    if (setVisible) setVisible(visible);
}
BOOL MBPresentTouchBar(NSTouchBar *bar) {
    if (![NSTouchBar respondsToSelector:@selector(dismissSystemModalTouchBar:)]) return NO;
    closeBox(NO);
    if ([NSTouchBar respondsToSelector:@selector(presentSystemModalTouchBar:placement:systemTrayItemIdentifier:)]) {
        [NSTouchBar presentSystemModalTouchBar:bar placement:0 systemTrayItemIdentifier:nil];
    } else if ([NSTouchBar respondsToSelector:@selector(presentSystemModalTouchBar:systemTrayItemIdentifier:)]) {
        [NSTouchBar presentSystemModalTouchBar:bar systemTrayItemIdentifier:nil];
    } else { return NO; }
    closeBox(NO);
    return YES;
}
void MBDismissTouchBar(NSTouchBar *bar) {
    if ([NSTouchBar respondsToSelector:@selector(dismissSystemModalTouchBar:)]) {
        [NSTouchBar dismissSystemModalTouchBar:bar];
        closeBox(YES);
    }
}
