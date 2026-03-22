#include "AeroPulseSMCBridge.h"

#include <IOKit/IOKitLib.h>
#include <mach/error.h>
#include <mach/mach.h>
#include <stdbool.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define AEROPULSE_SMC_SERVICE "AppleSMC"
#define AEROPULSE_SMC_KEY_SIZE 4

enum {
    AEROPULSE_SMC_SUCCESS = 0,
    AEROPULSE_SMC_GET_KEY_INFO = 9,
    AEROPULSE_SMC_READ_KEY = 5,
    AEROPULSE_SMC_WRITE_KEY = 6,
    AEROPULSE_SMC_HANDLE_YPC_EVENT = 2
};

typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved;
    uint16_t release;
} AeroPulseSMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} AeroPulseSMCPLimitData;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} AeroPulseSMCKeyInfoData;

typedef struct {
    uint32_t key;
    AeroPulseSMCVersion vers;
    AeroPulseSMCPLimitData pLimitData;
    AeroPulseSMCKeyInfoData keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} AeroPulseSMCParamStruct;

static uint32_t aeroPulseSMCKeyToUInt32(const char *key)
{
    uint32_t value = 0;
    for (int index = 0; index < AEROPULSE_SMC_KEY_SIZE; index++) {
        value |= ((uint32_t)(uint8_t)key[index]) << (24 - (index * 8));
    }
    return value;
}

static void aeroPulseSMCDataTypeToString(uint32_t dataType, char output[5])
{
    output[0] = (char)((dataType >> 24) & 0xFF);
    output[1] = (char)((dataType >> 16) & 0xFF);
    output[2] = (char)((dataType >> 8) & 0xFF);
    output[3] = (char)(dataType & 0xFF);
    output[4] = '\0';
}

static void aeroPulseSMCWriteError(char *buffer, uint32_t capacity, const char *message)
{
    if (buffer == NULL || capacity == 0) {
        return;
    }

    snprintf(buffer, capacity, "%s", message);
}

static void aeroPulseSMCWriteKernelError(char *buffer, uint32_t capacity, const char *context, kern_return_t status)
{
    if (buffer == NULL || capacity == 0) {
        return;
    }

    const char *reason = mach_error_string(status);
    snprintf(buffer, capacity, "%s (%d: %s)", context, status, reason != NULL ? reason : "unknown");
}

static kern_return_t aeroPulseSMCCall(
    io_connect_t connection,
    AeroPulseSMCParamStruct *input,
    AeroPulseSMCParamStruct *output
)
{
    size_t inputSize = sizeof(AeroPulseSMCParamStruct);
    size_t outputSize = sizeof(AeroPulseSMCParamStruct);

    return IOConnectCallStructMethod(
        connection,
        AEROPULSE_SMC_HANDLE_YPC_EVENT,
        input,
        inputSize,
        output,
        &outputSize
    );
}

static kern_return_t aeroPulseSMCOpen(io_connect_t *connection)
{
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(AEROPULSE_SMC_SERVICE));
    if (service == IO_OBJECT_NULL) {
        return kIOReturnNotFound;
    }

    kern_return_t status = IOServiceOpen(service, mach_task_self(), 0, connection);
    IOObjectRelease(service);
    return status;
}

static kern_return_t aeroPulseSMCReadKey(
    io_connect_t connection,
    const char *key,
    uint8_t bytes[32],
    uint32_t *dataSize,
    char dataType[5]
)
{
    AeroPulseSMCParamStruct input;
    AeroPulseSMCParamStruct output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));

    input.key = aeroPulseSMCKeyToUInt32(key);
    input.data8 = AEROPULSE_SMC_GET_KEY_INFO;

    kern_return_t status = aeroPulseSMCCall(connection, &input, &output);
    if (status != KERN_SUCCESS) {
        return status;
    }
    if (output.result != AEROPULSE_SMC_SUCCESS) {
        return kIOReturnError;
    }

    *dataSize = output.keyInfo.dataSize;
    aeroPulseSMCDataTypeToString(output.keyInfo.dataType, dataType);

    memset(&input, 0, sizeof(input));
    input.key = aeroPulseSMCKeyToUInt32(key);
    input.data8 = AEROPULSE_SMC_READ_KEY;
    input.keyInfo.dataSize = output.keyInfo.dataSize;

    memset(&output, 0, sizeof(output));
    status = aeroPulseSMCCall(connection, &input, &output);
    if (status != KERN_SUCCESS) {
        return status;
    }
    if (output.result != AEROPULSE_SMC_SUCCESS) {
        return kIOReturnError;
    }

    memcpy(bytes, output.bytes, sizeof(output.bytes));
    return KERN_SUCCESS;
}

static bool aeroPulseSMCReadUInt(
    io_connect_t connection,
    const char *key,
    uint32_t *value,
    char *errorMessage,
    uint32_t errorMessageCapacity
)
{
    uint8_t bytes[32] = { 0 };
    uint32_t dataSize = 0;
    char dataType[5] = { 0 };

    kern_return_t status = aeroPulseSMCReadKey(connection, key, bytes, &dataSize, dataType);
    if (status != KERN_SUCCESS) {
        aeroPulseSMCWriteKernelError(errorMessage, errorMessageCapacity, key, status);
        return false;
    }

    if ((strncmp(dataType, "ui8 ", 4) == 0 || strncmp(dataType, "ui8", 3) == 0) && dataSize >= 1) {
        *value = bytes[0];
        return true;
    }

    if ((strncmp(dataType, "ui16", 4) == 0) && dataSize >= 2) {
        *value = ((uint32_t)bytes[0] << 8) | bytes[1];
        return true;
    }

    if ((strncmp(dataType, "ui32", 4) == 0) && dataSize >= 4) {
        *value = ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) | ((uint32_t)bytes[2] << 8) | bytes[3];
        return true;
    }

    aeroPulseSMCWriteError(errorMessage, errorMessageCapacity, "Unsupported unsigned fan key type.");
    return false;
}

static void aeroPulseSMCAppendBytesAsHex(
    const uint8_t *bytes,
    uint32_t dataSize,
    char *output,
    uint32_t outputCapacity,
    uint32_t *offset
)
{
    if (output == NULL || outputCapacity == 0 || offset == NULL) {
        return;
    }

    for (uint32_t index = 0; index < dataSize && *offset < outputCapacity; index++) {
        int written = snprintf(
            output + *offset,
            outputCapacity - *offset,
            "%s%02X",
            index == 0 ? "" : " ",
            bytes[index]
        );

        if (written < 0) {
            return;
        }

        uint32_t consumed = (uint32_t)written;
        if (consumed >= outputCapacity - *offset) {
            *offset = outputCapacity - 1;
            output[*offset] = '\0';
            return;
        }

        *offset += consumed;
    }
}

static void aeroPulseSMCAppendKeyDump(
    io_connect_t connection,
    const char *key,
    char *output,
    uint32_t outputCapacity,
    uint32_t *offset
)
{
    if (output == NULL || outputCapacity == 0 || offset == NULL) {
        return;
    }

    uint8_t bytes[32] = { 0 };
    uint32_t dataSize = 0;
    char dataType[5] = { 0 };

    kern_return_t status = aeroPulseSMCReadKey(connection, key, bytes, &dataSize, dataType);
    if (status != KERN_SUCCESS) {
        int written = snprintf(
            output + *offset,
            outputCapacity - *offset,
            "%s: unavailable (%d: %s)\n",
            key,
            status,
            mach_error_string(status)
        );
        if (written < 0) {
            return;
        }

        uint32_t consumed = (uint32_t)written;
        if (consumed >= outputCapacity - *offset) {
            *offset = outputCapacity - 1;
            output[*offset] = '\0';
            return;
        }

        *offset += consumed;
        return;
    }

    int written = snprintf(
        output + *offset,
        outputCapacity - *offset,
        "%s: type=%s size=%u bytes=",
        key,
        dataType,
        dataSize
    );
    if (written < 0) {
        return;
    }

    uint32_t consumed = (uint32_t)written;
    if (consumed >= outputCapacity - *offset) {
        *offset = outputCapacity - 1;
        output[*offset] = '\0';
        return;
    }
    *offset += consumed;

    aeroPulseSMCAppendBytesAsHex(bytes, dataSize, output, outputCapacity, offset);

    if ((strncmp(dataType, "ui8 ", 4) == 0 || strncmp(dataType, "ui8", 3) == 0) && dataSize >= 1) {
        written = snprintf(output + *offset, outputCapacity - *offset, " uint=%u", bytes[0]);
    } else if (strncmp(dataType, "ui16", 4) == 0 && dataSize >= 2) {
        uint32_t value = ((uint32_t)bytes[0] << 8) | bytes[1];
        written = snprintf(output + *offset, outputCapacity - *offset, " uint=%u", value);
    } else if (strncmp(dataType, "ui32", 4) == 0 && dataSize >= 4) {
        uint32_t value =
            ((uint32_t)bytes[0] << 24) |
            ((uint32_t)bytes[1] << 16) |
            ((uint32_t)bytes[2] << 8) |
            bytes[3];
        written = snprintf(output + *offset, outputCapacity - *offset, " uint=%u", value);
    } else if ((strncmp(dataType, "flt ", 4) == 0 || strncmp(dataType, "flt", 3) == 0) && dataSize >= 4) {
        float value = 0;
        memcpy(&value, bytes, sizeof(float));
        written = snprintf(output + *offset, outputCapacity - *offset, " float=%.1f", value);
    } else if (strncmp(dataType, "fpe2", 4) == 0 && dataSize >= 2) {
        uint32_t value = ((uint32_t)bytes[0] << 6) + ((uint32_t)bytes[1] << 2);
        written = snprintf(output + *offset, outputCapacity - *offset, " rpm=%u", value);
    } else {
        written = snprintf(output + *offset, outputCapacity - *offset, " raw");
    }

    if (written < 0) {
        return;
    }

    consumed = (uint32_t)written;
    if (consumed >= outputCapacity - *offset) {
        *offset = outputCapacity - 1;
        output[*offset] = '\0';
        return;
    }
    *offset += consumed;

    written = snprintf(output + *offset, outputCapacity - *offset, "\n");
    if (written < 0) {
        return;
    }

    consumed = (uint32_t)written;
    if (consumed >= outputCapacity - *offset) {
        *offset = outputCapacity - 1;
        output[*offset] = '\0';
        return;
    }

    *offset += consumed;
}

static bool aeroPulseSMCReadRPM(
    io_connect_t connection,
    const char *key,
    uint32_t *value,
    char *errorMessage,
    uint32_t errorMessageCapacity
)
{
    uint8_t bytes[32] = { 0 };
    uint32_t dataSize = 0;
    char dataType[5] = { 0 };

    kern_return_t status = aeroPulseSMCReadKey(connection, key, bytes, &dataSize, dataType);
    if (status != KERN_SUCCESS) {
        aeroPulseSMCWriteKernelError(errorMessage, errorMessageCapacity, key, status);
        return false;
    }

    if ((strncmp(dataType, "flt ", 4) == 0 || strncmp(dataType, "flt", 3) == 0) && dataSize >= 4) {
        float rawValue = 0;
        memcpy(&rawValue, bytes, sizeof(float));
        *value = rawValue > 0 ? (uint32_t)lroundf(rawValue) : 0;
        return true;
    }

    if (strncmp(dataType, "fpe2", 4) == 0 && dataSize >= 2) {
        *value = ((uint32_t)bytes[0] << 6) + ((uint32_t)bytes[1] << 2);
        return true;
    }

    if ((strncmp(dataType, "ui16", 4) == 0) && dataSize >= 2) {
        *value = ((uint32_t)bytes[0] << 8) | bytes[1];
        return true;
    }

    aeroPulseSMCWriteError(errorMessage, errorMessageCapacity, "Unsupported fan RPM key type.");
    return false;
}

static kern_return_t aeroPulseSMCWriteKey(
    io_connect_t connection,
    const char *key,
    const uint8_t *bytes,
    uint32_t expectedSize,
    const char *expectedType,
    char *errorMessage,
    uint32_t errorMessageCapacity
)
{
    AeroPulseSMCParamStruct input;
    AeroPulseSMCParamStruct output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));

    input.key = aeroPulseSMCKeyToUInt32(key);
    input.data8 = AEROPULSE_SMC_GET_KEY_INFO;

    kern_return_t status = aeroPulseSMCCall(connection, &input, &output);
    if (status != KERN_SUCCESS) {
        aeroPulseSMCWriteKernelError(errorMessage, errorMessageCapacity, key, status);
        return status;
    }
    if (output.result != AEROPULSE_SMC_SUCCESS) {
        aeroPulseSMCWriteError(errorMessage, errorMessageCapacity, "Failed to fetch SMC key info for write.");
        return kIOReturnError;
    }

    char discoveredType[5] = { 0 };
    aeroPulseSMCDataTypeToString(output.keyInfo.dataType, discoveredType);
    if (output.keyInfo.dataSize != expectedSize || strncmp(discoveredType, expectedType, 4) != 0) {
        aeroPulseSMCWriteError(errorMessage, errorMessageCapacity, "SMC key type mismatch.");
        return kIOReturnBadArgument;
    }

    memset(&input, 0, sizeof(input));
    input.key = aeroPulseSMCKeyToUInt32(key);
    input.data8 = AEROPULSE_SMC_WRITE_KEY;
    input.keyInfo.dataSize = expectedSize;
    memcpy(input.bytes, bytes, expectedSize);

    memset(&output, 0, sizeof(output));
    status = aeroPulseSMCCall(connection, &input, &output);
    if (status != KERN_SUCCESS) {
        aeroPulseSMCWriteKernelError(errorMessage, errorMessageCapacity, key, status);
        return status;
    }
    if (output.result != AEROPULSE_SMC_SUCCESS) {
        aeroPulseSMCWriteError(errorMessage, errorMessageCapacity, "SMC write returned an error.");
        return kIOReturnError;
    }

    return KERN_SUCCESS;
}

int32_t AeroPulseSMCReadFans(
    AeroPulseSMCFanSnapshot *fans,
    uint32_t capacity,
    uint32_t *count,
    char *errorMessage,
    uint32_t errorMessageCapacity
)
{
    if (fans == NULL || count == NULL || capacity == 0) {
        aeroPulseSMCWriteError(errorMessage, errorMessageCapacity, "Invalid fan output buffer.");
        return (int32_t)kIOReturnBadArgument;
    }

    *count = 0;
    if (errorMessage != NULL && errorMessageCapacity > 0) {
        errorMessage[0] = '\0';
    }

    io_connect_t connection = IO_OBJECT_NULL;
    kern_return_t status = aeroPulseSMCOpen(&connection);
    if (status != KERN_SUCCESS) {
        aeroPulseSMCWriteKernelError(errorMessage, errorMessageCapacity, "Failed to open AppleSMC", status);
        return (int32_t)status;
    }

    uint32_t fanCount = 0;
    if (!aeroPulseSMCReadUInt(connection, "FNum", &fanCount, errorMessage, errorMessageCapacity)) {
        IOServiceClose(connection);
        return (int32_t)kIOReturnError;
    }

    uint32_t resolvedCount = fanCount < capacity ? fanCount : capacity;
    for (uint32_t index = 0; index < resolvedCount; index++) {
        char key[5] = { 0 };
        AeroPulseSMCFanSnapshot snapshot;
        memset(&snapshot, 0, sizeof(snapshot));
        snapshot.identifier = index + 1;

        snprintf(key, sizeof(key), "F%uAc", index);
        if (!aeroPulseSMCReadRPM(connection, key, &snapshot.currentRPM, errorMessage, errorMessageCapacity)) {
            IOServiceClose(connection);
            return (int32_t)kIOReturnError;
        }

        snprintf(key, sizeof(key), "F%uTg", index);
        if (!aeroPulseSMCReadRPM(connection, key, &snapshot.targetRPM, errorMessage, errorMessageCapacity)) {
            IOServiceClose(connection);
            return (int32_t)kIOReturnError;
        }

        snprintf(key, sizeof(key), "F%uMn", index);
        if (!aeroPulseSMCReadRPM(connection, key, &snapshot.minRPM, errorMessage, errorMessageCapacity)) {
            IOServiceClose(connection);
            return (int32_t)kIOReturnError;
        }

        snprintf(key, sizeof(key), "F%uMx", index);
        if (!aeroPulseSMCReadRPM(connection, key, &snapshot.maxRPM, errorMessage, errorMessageCapacity)) {
            IOServiceClose(connection);
            return (int32_t)kIOReturnError;
        }

        uint32_t modeValue = 0;
        snprintf(key, sizeof(key), "F%umd", index);
        if (aeroPulseSMCReadUInt(connection, key, &modeValue, NULL, 0)) {
            snapshot.modeHint = modeValue == 0 ? 1 : 2;
        } else {
            snapshot.modeHint = snapshot.targetRPM == 0 ? 1 : 0;
        }
        fans[index] = snapshot;
    }

    IOServiceClose(connection);
    *count = resolvedCount;
    return (int32_t)KERN_SUCCESS;
}

static int32_t aeroPulseSMCSetModeAndTarget(
    uint32_t fanID,
    uint8_t mode,
    float targetRPM,
    char *errorMessage,
    uint32_t errorMessageCapacity
)
{
    io_connect_t connection = IO_OBJECT_NULL;
    kern_return_t status = aeroPulseSMCOpen(&connection);
    if (status != KERN_SUCCESS) {
        aeroPulseSMCWriteKernelError(errorMessage, errorMessageCapacity, "Failed to open AppleSMC", status);
        return (int32_t)status;
    }

    uint32_t fanCount = 0;
    if (!aeroPulseSMCReadUInt(connection, "FNum", &fanCount, errorMessage, errorMessageCapacity)) {
        IOServiceClose(connection);
        return (int32_t)kIOReturnError;
    }

    if (fanID == 0 || fanID > fanCount) {
        aeroPulseSMCWriteError(errorMessage, errorMessageCapacity, "Fan identifier is out of range.");
        IOServiceClose(connection);
        return (int32_t)kIOReturnBadArgument;
    }

    char modeKey[5] = { 0 };
    char targetKey[5] = { 0 };
    char minKey[5] = { 0 };
    char maxKey[5] = { 0 };
    snprintf(modeKey, sizeof(modeKey), "F%umd", fanID - 1);
    snprintf(targetKey, sizeof(targetKey), "F%uTg", fanID - 1);

    if (mode == 1 && targetRPM > 0) {
        uint32_t minRPM = 0;
        uint32_t maxRPM = 0;
        snprintf(minKey, sizeof(minKey), "F%uMn", fanID - 1);
        snprintf(maxKey, sizeof(maxKey), "F%uMx", fanID - 1);

        if (!aeroPulseSMCReadRPM(connection, minKey, &minRPM, errorMessage, errorMessageCapacity) ||
            !aeroPulseSMCReadRPM(connection, maxKey, &maxRPM, errorMessage, errorMessageCapacity)) {
            IOServiceClose(connection);
            return (int32_t)kIOReturnError;
        }

        if (targetRPM < (float)minRPM) {
            targetRPM = (float)minRPM;
        }
        if (targetRPM > (float)maxRPM) {
            targetRPM = (float)maxRPM;
        }
    }

    uint8_t modeBytes[1] = { mode };
    status = aeroPulseSMCWriteKey(connection, modeKey, modeBytes, 1, "ui8 ", errorMessage, errorMessageCapacity);
    if (status != KERN_SUCCESS) {
        IOServiceClose(connection);
        return (int32_t)status;
    }

    if (mode == 0) {
        IOServiceClose(connection);
        return (int32_t)KERN_SUCCESS;
    }

    uint8_t targetBytes[4] = { 0 };
    memcpy(targetBytes, &targetRPM, sizeof(float));
    status = aeroPulseSMCWriteKey(connection, targetKey, targetBytes, 4, "flt ", errorMessage, errorMessageCapacity);
    IOServiceClose(connection);
    return (int32_t)status;
}

int32_t AeroPulseSMCSetFanAuto(
    uint32_t fanID,
    char *errorMessage,
    uint32_t errorMessageCapacity
)
{
    return aeroPulseSMCSetModeAndTarget(fanID, 0, 0.0f, errorMessage, errorMessageCapacity);
}

int32_t AeroPulseSMCSetFanTargetRPM(
    uint32_t fanID,
    uint32_t rpm,
    char *errorMessage,
    uint32_t errorMessageCapacity
)
{
    return aeroPulseSMCSetModeAndTarget(fanID, 1, (float)rpm, errorMessage, errorMessageCapacity);
}

int32_t AeroPulseSMCDumpFanModeKeys(
    char *output,
    uint32_t outputCapacity,
    char *errorMessage,
    uint32_t errorMessageCapacity
)
{
    if (output == NULL || outputCapacity == 0) {
        aeroPulseSMCWriteError(errorMessage, errorMessageCapacity, "Invalid mode dump output buffer.");
        return (int32_t)kIOReturnBadArgument;
    }

    output[0] = '\0';
    if (errorMessage != NULL && errorMessageCapacity > 0) {
        errorMessage[0] = '\0';
    }

    io_connect_t connection = IO_OBJECT_NULL;
    kern_return_t status = aeroPulseSMCOpen(&connection);
    if (status != KERN_SUCCESS) {
        aeroPulseSMCWriteKernelError(errorMessage, errorMessageCapacity, "Failed to open AppleSMC", status);
        return (int32_t)status;
    }

    static const char *keys[] = {
        "FNum",
        "FS! ",
        "F0Ac", "F0Tg", "F0Mn", "F0Mx", "F0Md", "F0md",
        "F1Ac", "F1Tg", "F1Mn", "F1Mx", "F1Md", "F1md"
    };

    uint32_t offset = 0;
    for (uint32_t index = 0; index < sizeof(keys) / sizeof(keys[0]); index++) {
        aeroPulseSMCAppendKeyDump(connection, keys[index], output, outputCapacity, &offset);
        if (offset >= outputCapacity - 1) {
            break;
        }
    }

    IOServiceClose(connection);
    return (int32_t)KERN_SUCCESS;
}
