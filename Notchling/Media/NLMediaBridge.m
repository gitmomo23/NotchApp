#import "NLMediaBridge.h"
#import <dlfcn.h>
#import <os/log.h>

typedef void (*NLGetNowPlayingFunc)(dispatch_queue_t queue, void (^handler)(NSDictionary *information));
typedef Boolean (*NLSendCommandFunc)(int command, id userInfo);
typedef void (*NLRegisterFunc)(dispatch_queue_t queue);

static void *nl_handle = NULL;
static NLGetNowPlayingFunc nl_getInfo = NULL;
static NLSendCommandFunc nl_send = NULL;
static NLRegisterFunc nl_register = NULL;
static BOOL nl_attempted = NO;
static BOOL nl_observing = NO;
static void (^nl_handler)(void) = nil;

@implementation NLMediaBridge

+ (BOOL)loadFramework {
    if (nl_attempted) {
        return nl_getInfo != NULL;
    }
    nl_attempted = YES;
    nl_handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
    if (nl_handle == NULL) {
        os_log_error(OS_LOG_DEFAULT, "Notchling MediaRemote dlopen failed: %{public}s", dlerror());
        return NO;
    }
    nl_getInfo = (NLGetNowPlayingFunc)dlsym(nl_handle, "MRMediaRemoteGetNowPlayingInfo");
    nl_send = (NLSendCommandFunc)dlsym(nl_handle, "MRMediaRemoteSendCommand");
    nl_register = (NLRegisterFunc)dlsym(nl_handle, "MRMediaRemoteRegisterForNowPlayingNotifications");
    if (nl_getInfo == NULL) {
        os_log_error(OS_LOG_DEFAULT, "Notchling MediaRemote symbols missing");
    }
    return nl_getInfo != NULL;
}

+ (BOOL)isAvailable {
    return [self loadFramework];
}

+ (NSString *)stringFrom:(NSDictionary *)info key:(NSString *)key {
    id value = info[key];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

+ (NSNumber *)numberFrom:(NSDictionary *)info key:(NSString *)key {
    id value = info[key];
    return [value isKindOfClass:[NSNumber class]] ? value : nil;
}

+ (NSDictionary<NSString *, id> *)normalized:(NSDictionary *)info {
    NSMutableDictionary<NSString *, id> *result = [NSMutableDictionary dictionary];
    NSString *title = [self stringFrom:info key:@"kMRMediaRemoteNowPlayingInfoTitle"];
    NSString *artist = [self stringFrom:info key:@"kMRMediaRemoteNowPlayingInfoArtist"];
    NSString *album = [self stringFrom:info key:@"kMRMediaRemoteNowPlayingInfoAlbum"];
    NSString *client = [self stringFrom:info key:@"kMRMediaRemoteNowPlayingApplicationDisplayName"];
    if (title) result[@"title"] = title;
    if (artist) result[@"artist"] = artist;
    if (album) result[@"album"] = album;
    if (client.length > 0) {
        result[@"source"] = client;
    }

    NSNumber *duration = [self numberFrom:info key:@"kMRMediaRemoteNowPlayingInfoDuration"];
    NSNumber *elapsed = [self numberFrom:info key:@"kMRMediaRemoteNowPlayingInfoElapsedTime"];
    NSNumber *rate = [self numberFrom:info key:@"kMRMediaRemoteNowPlayingInfoPlaybackRate"];
    id timestamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
    if (duration) result[@"duration"] = duration;
    double rateValue = rate ? rate.doubleValue : 0;
    result[@"rate"] = @(rateValue);
    if (elapsed) {
        NSTimeInterval seconds = elapsed.doubleValue;
        if ([timestamp isKindOfClass:[NSDate class]] && rateValue > 0) {
            seconds += [[NSDate date] timeIntervalSinceDate:(NSDate *)timestamp] * rateValue;
        }
        if (seconds < 0) seconds = 0;
        result[@"elapsed"] = @(seconds);
    }

    id artwork = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
    if ([artwork isKindOfClass:[NSData class]] && [(NSData *)artwork length] > 0 && [(NSData *)artwork length] < (8 * 1024 * 1024)) {
        result[@"artwork"] = artwork;
    }
    return result;
}

+ (void)fetchNowPlaying:(void (^)(NSDictionary<NSString *, id> *_Nullable))completion {
    if (![self loadFramework] || nl_getInfo == NULL) {
        completion(nil);
        return;
    }
    nl_getInfo(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(NSDictionary *information) {
        if (![information isKindOfClass:[NSDictionary class]] || information.count == 0) {
            completion(nil);
            return;
        }
        NSDictionary *normalized = [self normalized:information];
        if ([normalized[@"title"] isKindOfClass:[NSString class]] && [(NSString *)normalized[@"title"] length] == 0) {
            completion(nil);
            return;
        }
        completion(normalized);
    });
}

+ (BOOL)sendCommand:(NLMediaCommand)command {
    if (![self loadFramework] || nl_send == NULL) {
        return NO;
    }
    Boolean ok = nl_send((int)command, nil);
    return ok ? YES : NO;
}

+ (void)startObserving:(void (^)(void))handler {
    nl_handler = [handler copy];
    if (nl_observing) {
        return;
    }
    nl_observing = YES;
    [self loadFramework];
    if (nl_register != NULL) {
        nl_register(dispatch_get_main_queue());
    }
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(nowPlayingChanged:)
                                                 name:@"kMRMediaRemoteNowPlayingInfoDidChangeNotification"
                                               object:nil];
}

+ (void)nowPlayingChanged:(NSNotification *)note {
    (void)note;
    if (nl_handler != nil) {
        nl_handler();
    }
}

@end
