#ifndef CoreBrightnessBridge_h
#define CoreBrightnessBridge_h

#include <stdbool.h>

bool CBBridge_initialize(void);

bool CBBridge_setCCT(float cct, bool commit);
bool CBBridge_getCCT(float *outCCT);
bool CBBridge_getCCTRange(float *outMin, float *outMax, float *outDefault);

bool CBBridge_setStrength(float strength, bool commit);
bool CBBridge_getStrength(float *outStrength);

bool CBBridge_setEnabled(bool enabled);
bool CBBridge_setMode(int mode);
bool CBBridge_getStatus(bool *outEnabled, int *outMode);

bool CBBridge_isSupported(void);

#endif
