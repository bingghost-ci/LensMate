//
//  LMExceptionCatcher.m
//  LensMate
//

#import "LMExceptionCatcher.h"

NSString * _Nullable LMCatchException(void (^block)(void)) {
    @try {
        block();
        return nil;
    }
    @catch (NSException *exception) {
        return exception.reason ?: exception.name;
    }
}
