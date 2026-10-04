#import "CoreBrightnessBridge.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/runtime.h>

static id _client = nil;
static dispatch_once_t _initToken;
static bool _initialized = false;

static id getClient(void) {
    dispatch_once(&_initToken, ^{
        void *handle = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY);
        if (!handle) return;

        Class cls = NSClassFromString(@"CBBlueLightClient");
        if (!cls) return;

        _client = [[cls alloc] init];
        _initialized = (_client != nil);
    });
    return _client;
}

#define CALL_BOOL_VOID(selName) \
    id c = getClient(); \
    if (!c) return false; \
    SEL sel = NSSelectorFromString(@selName); \
    IMP imp = [c methodForSelector:sel]; \
    return ((BOOL(*)(id, SEL))imp)(c, sel);

#define CALL_BOOL_FLOAT_OUT(selName, outPtr) \
    id c = getClient(); \
    if (!c) return false; \
    SEL sel = NSSelectorFromString(@selName); \
    IMP imp = [c methodForSelector:sel]; \
    return ((BOOL(*)(id, SEL, float*))imp)(c, sel, outPtr);

#define CALL_BOOL_FLOAT_BOOL(selName, fVal, bVal) \
    id c = getClient(); \
    if (!c) return false; \
    SEL sel = NSSelectorFromString(@selName); \
    IMP imp = [c methodForSelector:sel]; \
    return ((BOOL(*)(id, SEL, float, BOOL))imp)(c, sel, fVal, bVal);

bool CBBridge_initialize(void) {
    getClient();
    return _initialized;
}

bool CBBridge_setCCT(float cct, bool commit) {
    CALL_BOOL_FLOAT_BOOL("setCCT:commit:", cct, commit);
}

bool CBBridge_getCCT(float *outCCT) {
    CALL_BOOL_FLOAT_OUT("getCCT:", outCCT);
}

bool CBBridge_getCCTRange(float *outMin, float *outMax, float *outDefault) {
    id c = getClient();
    if (!c) return false;

    typedef struct { float min; float max; float def; } CCTRange;
    CCTRange range = {0, 0, 0};

    SEL sel = NSSelectorFromString(@"getCCTRange:");
    IMP imp = [c methodForSelector:sel];
    BOOL ok = ((BOOL(*)(id, SEL, CCTRange*))imp)(c, sel, &range);

    if (ok) {
        if (outMin) *outMin = range.min;
        if (outMax) *outMax = range.max;
        if (outDefault) *outDefault = range.def;
    }
    return ok;
}

bool CBBridge_setStrength(float strength, bool commit) {
    CALL_BOOL_FLOAT_BOOL("setStrength:commit:", strength, commit);
}

bool CBBridge_getStrength(float *outStrength) {
    CALL_BOOL_FLOAT_OUT("getStrength:", outStrength);
}

bool CBBridge_setEnabled(bool enabled) {
    id c = getClient();
    if (!c) return false;
    SEL sel = NSSelectorFromString(@"setEnabled:");
    IMP imp = [c methodForSelector:sel];
    return ((BOOL(*)(id, SEL, BOOL))imp)(c, sel, enabled);
}

bool CBBridge_setMode(int mode) {
    id c = getClient();
    if (!c) return false;
    SEL sel = NSSelectorFromString(@"setMode:");
    IMP imp = [c methodForSelector:sel];
    return ((BOOL(*)(id, SEL, int))imp)(c, sel, mode);
}

bool CBBridge_getStatus(bool *outEnabled, int *outMode) {
    id c = getClient();
    if (!c) return false;

    // CBBlueLightClient Status struct — layout stable since macOS 10.12.4
    // (same layout used by open-source Night Shift tools, e.g. smudge/nightlight)
    typedef struct {
        char active;
        char enabled;
        char sunSchedulePermitted;
        int mode;
        struct {
            struct { int hour; int minute; } fromTime;
            struct { int hour; int minute; } toTime;
        } schedule;
        unsigned long long disableFlags;
        char available;
    } CBStatus;

    CBStatus status;
    memset(&status, 0, sizeof(status));

    SEL sel = NSSelectorFromString(@"getBlueLightStatus:");
    if (![c respondsToSelector:sel]) return false;
    IMP imp = [c methodForSelector:sel];
    BOOL ok = ((BOOL(*)(id, SEL, CBStatus*))imp)(c, sel, &status);

    if (ok) {
        if (outEnabled) *outEnabled = (status.enabled != 0);
        if (outMode) *outMode = status.mode;
    }
    return ok;
}

bool CBBridge_isSupported(void) {
    id c = getClient();
    if (!c) return false;
    SEL sel = NSSelectorFromString(@"supported");
    IMP imp = [c methodForSelector:sel];
    return ((BOOL(*)(id, SEL))imp)(c, sel);
}
