#import <Foundation/Foundation.h>
// Packaging only: create the legacy alias Finder expects for its background.
NSData * _Nullable MHCreateDMGAlias(NSURL * _Nonnull base, NSURL * _Nonnull target);
