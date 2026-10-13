#import "NLDisplayBridge.h"
#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/IOKitLib.h>
#import <dlfcn.h>
#import <os/log.h>

typedef IOReturn (*NLDisplayGetFunc)(io_service_t service, IOOptionBits options, CFStringRef parameter, float *value);
typedef IOReturn (*NLDisplaySetFunc)(io_service_t service, IOOptionBits options, CFStringRef parameter, float value);
typedef int (*NLDSGetFunc)(int display, float *brightness);
typedef int (*NLDSSetFunc)(int display, float brightness);

static NLDisplayGetFunc nl_ioGet = NULL;
static NLDisplaySetFunc nl_ioSet = NULL;
static BOOL nl_ioLoaded = NO;
static NLDSGetFunc nl_dsGet = NULL;
static NLDSSetFunc nl_dsSet = NULL;
static BOOL nl_dsLoaded = NO;

static void NLLoadIODisplay(void) {
    if (nl_ioLoaded) return;
    nl_ioLoaded = YES;
    void *handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
    if (handle == NULL) return;
    nl_ioGet = (NLDisplayGetFunc)dlsym(handle, "IODisplayGetFloatParameter");
    nl_ioSet = (NLDisplaySetFunc)dlsym(handle, "IODisplaySetFloatParameter");
}

static void NLLoadDisplayServices(void) {
    if (nl_dsLoaded) return;
    nl_dsLoaded = YES;
    void *handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY);
    if (handle == NULL) {
        os_log_info(OS_LOG_DEFAULT, "Notchling DisplayServices unavailable");
        return;
    }
    nl_dsGet = (NLDSGetFunc)dlsym(handle, "DisplayServicesGetBrightness");
    nl_dsSet = (NLDSSetFunc)dlsym(handle, "DisplayServicesSetBrightness");
}

static BOOL NLPlausible(float value) {
    return value >= 0.f && value <= 1.f;
}

static float NLReadService(io_service_t service) {
    if (nl_ioGet == NULL) return -1.f;
    float value = -1.f;
    IOReturn result = nl_ioGet(service, 0, CFSTR("brightness"), &value);
    if (result == KERN_SUCCESS && NLPlausible(value)) {
        return value;
    }
    return -1.f;
}

static BOOL NLWriteService(io_service_t service, float value) {
    if (nl_ioSet == NULL) return NO;
    IOReturn result = nl_ioSet(service, 0, CFSTR("brightness"), value);
    return result == KERN_SUCCESS;
}

static void NLVisitDisplays(BOOL writing, float input, float *output, BOOL *wrote) {
    const char *names[] = {"IODisplayConnect", "AppleBacklightDisplay"};
    for (size_t index = 0; index < 2; index++) {
        io_iterator_t iterator = 0;
        kern_return_t kr = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(names[index]), &iterator);
        if (kr != KERN_SUCCESS) continue;
        io_service_t service = 0;
        while ((service = IOIteratorNext(iterator)) != 0) {
            if (writing) {
                if (NLWriteService(service, input)) {
                    *wrote = YES;
                    IOObjectRelease(service);
                    break;
                }
            } else {
                float value = NLReadService(service);
                if (NLPlausible(value)) {
                    *output = value;
                    IOObjectRelease(service);
                    break;
                }
            }
            IOObjectRelease(service);
        }
        IOObjectRelease(iterator);
        if (writing && *wrote) return;
        if (!writing && NLPlausible(*output)) return;
    }
}

@implementation NLDisplayBridge

+ (float)readIOBrightness {
    NLLoadIODisplay();
    if (nl_ioGet == NULL) return -1.f;
    float value = -1.f;
    BOOL wrote = NO;
    NLVisitDisplays(NO, 0, &value, &wrote);
    return value;
}

+ (BOOL)setIOBrightness:(float)value {
    NLLoadIODisplay();
    if (nl_ioSet == NULL) return NO;
    float clamped = MIN(1.f, MAX(0.f, value));
    float ignored = -1.f;
    BOOL wrote = NO;
    NLVisitDisplays(YES, clamped, &ignored, &wrote);
    return wrote;
}

+ (float)readPrivateBrightness {
    NLLoadDisplayServices();
    if (nl_dsGet == NULL) return -1.f;
    float value = -1.f;
    nl_dsGet(0, &value);
    if (NLPlausible(value)) return value;
    value = -1.f;
    nl_dsGet((int)CGMainDisplayID(), &value);
    if (NLPlausible(value)) return value;
    return -1.f;
}

+ (BOOL)setPrivateBrightness:(float)value {
    NLLoadDisplayServices();
    if (nl_dsSet == NULL) return NO;
    float clamped = MIN(1.f, MAX(0.f, value));
    int rc = nl_dsSet((int)CGMainDisplayID(), clamped);
    if (rc != 0) {
        rc = nl_dsSet(0, clamped);
    }
    return rc == 0;
}

@end
