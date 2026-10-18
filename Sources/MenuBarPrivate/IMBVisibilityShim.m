#import "IMBVisibilityShim.h"

#import <dlfcn.h>
#import <objc/message.h>

NSErrorDomain const IMBVisibilityErrorDomain = @"com.karembadawy.icon.visibility";

static const char *IMBFrameworkPath = "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore";

static Class IMBConfigurationClass;
static Class IMBAssertionClass;
static SEL IMBInitSelector;
static SEL IMBActivateSelector;
static SEL IMBInvalidateSelector;
static NSString *IMBUnavailableReason;

static void IMBLoad(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        IMBInitSelector = NSSelectorFromString(@"initWithAllowedSystemItems:allowedBundleIdentifiers:");
        IMBActivateSelector = NSSelectorFromString(@"activateWithConfiguration:completionHandler:");
        IMBInvalidateSelector = NSSelectorFromString(@"invalidate");

        if (!dlopen(IMBFrameworkPath, RTLD_NOW)) {
            IMBUnavailableReason = @"MenuBarClientCore is missing on this version of macOS.";
            return;
        }
        Class configuration = NSClassFromString(@"MBAssessmentModeConfiguration");
        Class assertion = NSClassFromString(@"MBAssessmentModeAssertion");
        if (!configuration || !assertion) {
            IMBUnavailableReason = @"The menu bar restriction classes are missing.";
            return;
        }
        if (![configuration instancesRespondToSelector:IMBInitSelector] ||
            ![assertion instancesRespondToSelector:IMBActivateSelector] ||
            ![assertion instancesRespondToSelector:IMBInvalidateSelector]) {
            IMBUnavailableReason = @"The menu bar restriction API changed.";
            return;
        }
        IMBConfigurationClass = configuration;
        IMBAssertionClass = assertion;
    });
}

static NSError *IMBError(NSString *message) {
    return [NSError errorWithDomain:IMBVisibilityErrorDomain
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void IMBInvalidate(id assertion) {
    @try {
        ((void (*)(id, SEL))objc_msgSend)(assertion, IMBInvalidateSelector);
    } @catch (NSException *exception) {
        // Nothing to recover; the assertion is gone either way.
    }
}

@implementation IMBVisibilityShim {
    id _activeAssertion;
    /// Assertions still activating; -invalidate drops them too.
    NSMutableSet *_pendingAssertions;
    NSUInteger _generation;
}

- (instancetype)init {
    if ((self = [super init])) {
        _pendingAssertions = [NSMutableSet set];
    }
    return self;
}

+ (NSString *)unavailableReason {
    IMBLoad();
    return IMBUnavailableReason;
}

- (BOOL)isActive {
    return _activeAssertion != nil;
}

- (void)applyAllowedBundleIDs:(NSArray<NSString *> *)bundleIDs
                  systemItems:(NSArray<NSNumber *> *)systemItems
                   completion:(void (^)(NSError *_Nullable))completion {
    IMBLoad();
    if (IMBUnavailableReason) {
        completion(IMBError(IMBUnavailableReason));
        return;
    }

    NSUInteger generation = ++_generation;
    id assertion = nil;
    @try {
        // The configuration only accepts NSArray; an NSSet raises.
        id configuration = ((id (*)(id, SEL, NSArray *, NSArray *))objc_msgSend)(
            [IMBConfigurationClass alloc], IMBInitSelector, [systemItems copy], [bundleIDs copy]);
        assertion = [[IMBAssertionClass alloc] init];
        [_pendingAssertions addObject:assertion];

        __weak IMBVisibilityShim *weakSelf = self;
        id activating = assertion;
        void (^handler)(void *) = ^(void *result) {
            // The handler's first argument is nil on success. Only treat it as an
            // object when it plausibly is one.
            NSError *error = nil;
            if ((uintptr_t)result > 0xFFFF) {
                id object = (__bridge id)result;
                error = [object isKindOfClass:NSError.class] ? object : IMBError(@"Activation failed.");
            } else if (result) {
                error = IMBError(@"Activation failed.");
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf finishActivation:activating generation:generation error:error completion:completion];
            });
        };
        ((void (*)(id, SEL, id, id))objc_msgSend)(assertion, IMBActivateSelector, configuration, handler);
    } @catch (NSException *exception) {
        if (assertion) {
            [_pendingAssertions removeObject:assertion];
            IMBInvalidate(assertion);
        }
        completion(IMBError(exception.reason ?: exception.name));
    }
}

- (void)finishActivation:(id)assertion
              generation:(NSUInteger)generation
                   error:(NSError *)error
              completion:(void (^)(NSError *_Nullable))completion {
    [_pendingAssertions removeObject:assertion];
    if (error) {
        IMBInvalidate(assertion);
        completion(error);
        return;
    }
    if (generation != _generation) {
        // A newer configuration (or an invalidate) superseded this one.
        IMBInvalidate(assertion);
        completion(nil);
        return;
    }
    id previous = _activeAssertion;
    _activeAssertion = assertion;
    if (previous) IMBInvalidate(previous);
    completion(nil);
}

- (void)invalidate {
    _generation++;
    if (_activeAssertion) {
        IMBInvalidate(_activeAssertion);
        _activeAssertion = nil;
    }
    for (id assertion in _pendingAssertions) IMBInvalidate(assertion);
    [_pendingAssertions removeAllObjects];
}

@end
