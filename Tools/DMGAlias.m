#import "DMGAlias.h"
#import <CoreServices/CoreServices.h>

NSData *MHCreateDMGAlias(NSURL *base, NSURL *target) {
    FSRef from, to;
    if (!CFURLGetFSRef((__bridge CFURLRef)base, &from) ||
        !CFURLGetFSRef((__bridge CFURLRef)target, &to)) return nil;
    AliasHandle alias = NULL;
    if (FSNewAlias(&from, &to, &alias) != noErr || !alias) return nil;
    NSData *data = [NSData dataWithBytes:*alias length:GetHandleSize((Handle)alias)];
    DisposeHandle((Handle)alias);
    return data;
}
