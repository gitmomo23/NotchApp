#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Brightness helpers. Values are 0...1. Reads return -1 when unavailable.
/// Private DisplayServices is separate from the public IOKit path so callers
/// can disable it after a failed probe.
@interface NLDisplayBridge : NSObject
+ (float)readIOBrightness;
+ (BOOL)setIOBrightness:(float)value;
+ (float)readPrivateBrightness;
+ (BOOL)setPrivateBrightness:(float)value;
@end

NS_ASSUME_NONNULL_END
