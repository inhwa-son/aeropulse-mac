import Foundation

enum SMCRawFanReaderError: LocalizedError {
    case readFailed(String)

    var errorDescription: String? {
        switch self {
        case let .readFailed(message):
            message
        }
    }
}

enum SMCRawFanReader {
    static func readRawSnapshots(fallbackError: String = "AppleSMC fan read failed.") throws -> [AeroPulseSMCFanSnapshot] {
        var count: UInt32 = 0
        var errorBuffer = [CChar](repeating: 0, count: Int(AEROPULSE_SMC_ERROR_BUFFER_LENGTH))
        var rawSnapshots = Array(
            repeating: AeroPulseSMCFanSnapshot(
                identifier: 0,
                currentRPM: 0,
                targetRPM: 0,
                minRPM: 0,
                maxRPM: 0,
                modeHint: 0
            ),
            count: Int(AEROPULSE_SMC_MAX_FANS)
        )

        let status = rawSnapshots.withUnsafeMutableBufferPointer { snapshotBuffer in
            errorBuffer.withUnsafeMutableBufferPointer { errorBuffer in
                AeroPulseSMCReadFans(
                    snapshotBuffer.baseAddress,
                    UInt32(snapshotBuffer.count),
                    &count,
                    errorBuffer.baseAddress,
                    UInt32(errorBuffer.count)
                )
            }
        }

        guard status == 0 else {
            let message = String(decoding: errorBuffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw SMCRawFanReaderError.readFailed(message.isEmpty ? fallbackError : message)
        }

        return Array(rawSnapshots.prefix(Int(count)))
    }
}
