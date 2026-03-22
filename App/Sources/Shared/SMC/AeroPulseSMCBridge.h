// AppleSMC interface based on community-documented behavior of the macOS
// System Management Controller kernel extension. Struct layouts and command
// codes are reverse-engineered by the open-source community and are not
// part of any official Apple SDK.

#ifndef AEROPULSE_SMC_BRIDGE_H
#define AEROPULSE_SMC_BRIDGE_H

#include <stdint.h>

#define AEROPULSE_SMC_MAX_FANS 8
#define AEROPULSE_SMC_ERROR_BUFFER_LENGTH 256

typedef struct {
    uint32_t identifier;
    uint32_t currentRPM;
    uint32_t targetRPM;
    uint32_t minRPM;
    uint32_t maxRPM;
    uint8_t modeHint;
} AeroPulseSMCFanSnapshot;

int32_t AeroPulseSMCReadFans(
    AeroPulseSMCFanSnapshot *fans,
    uint32_t capacity,
    uint32_t *count,
    char *errorMessage,
    uint32_t errorMessageCapacity
);

int32_t AeroPulseSMCSetFanAuto(
    uint32_t fanID,
    char *errorMessage,
    uint32_t errorMessageCapacity
);

int32_t AeroPulseSMCSetFanTargetRPM(
    uint32_t fanID,
    uint32_t rpm,
    char *errorMessage,
    uint32_t errorMessageCapacity
);

int32_t AeroPulseSMCDumpFanModeKeys(
    char *output,
    uint32_t outputCapacity,
    char *errorMessage,
    uint32_t errorMessageCapacity
);

#endif
