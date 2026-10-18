#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const IMBVisibilityErrorDomain;

/// Wraps macOS 27's private MenuBarClientCore "assessment mode" restriction.
/// While a restriction is active, only apps in the allow-list keep their status items
/// in the menu bar. The restriction is bound to this process: if it quits or crashes,
/// macOS restores every item.
@interface IMBVisibilityShim : NSObject

/// Why the private API can't be used, or nil when it's available.
@property (class, nonatomic, readonly, nullable) NSString *unavailableReason;

/// Whether a restriction is currently active.
@property (nonatomic, readonly) BOOL isActive;

/// Activates a restriction with the given allow-list, then drops the previous one
/// (in that order, so the menu bar doesn't flash). `completion` runs on the main queue.
- (void)applyAllowedBundleIDs:(NSArray<NSString *> *)bundleIDs
                  systemItems:(NSArray<NSNumber *> *)systemItems
                   completion:(void (^)(NSError *_Nullable error))completion;

/// Drops the restriction; every status item returns.
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
