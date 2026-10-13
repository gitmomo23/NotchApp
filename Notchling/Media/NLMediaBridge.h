#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NLMediaCommand) {
    NLMediaCommandToggle = 2,
    NLMediaCommandNext = 4,
    NLMediaCommandPrevious = 5
};

/// Runtime access to the private MediaRemote framework. Lookups fail soft.
@interface NLMediaBridge : NSObject
+ (BOOL)isAvailable;
+ (void)fetchNowPlaying:(void (^)(NSDictionary<NSString *, id> *_Nullable info))completion;
+ (BOOL)sendCommand:(NLMediaCommand)command;
+ (void)startObserving:(void (^)(void))handler;
@end

NS_ASSUME_NONNULL_END
