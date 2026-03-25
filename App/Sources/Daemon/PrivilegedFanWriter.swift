import Foundation

enum PrivilegedFanWriterError: LocalizedError {
    case helperFailed(String)

    var errorDescription: String? {
        switch self {
        case let .helperFailed(message):
            message
        }
    }
}

struct PrivilegedFanWriter: Sendable {
    func probe() throws {
        _ = try readFanPayloads()
    }

    func readFanPayloads() throws -> [PrivilegedFanSnapshotPayload] {
        let rawSnapshots: [AeroPulseSMCFanSnapshot]
        do {
            rawSnapshots = try SMCRawFanReader.readRawSnapshots(fallbackError: "Failed to read AppleSMC fan access.")
        } catch let error as SMCRawFanReaderError {
            switch error {
            case let .readFailed(message):
                throw PrivilegedFanWriterError.helperFailed(message)
            }
        }

        return rawSnapshots.map { snapshot in
            PrivilegedFanSnapshotPayload(
                identifier: Int(snapshot.identifier),
                currentRPM: Int(snapshot.currentRPM),
                targetRPM: Int(snapshot.targetRPM),
                minRPM: Int(snapshot.minRPM),
                maxRPM: Int(snapshot.maxRPM),
                modeHint: Int(snapshot.modeHint)
            )
        }
    }

    func dumpFanModeKeys() throws -> String {
        var outputBuffer = [CChar](repeating: 0, count: 4096)
        var errorBuffer = [CChar](repeating: 0, count: Int(AEROPULSE_SMC_ERROR_BUFFER_LENGTH))

        let status = outputBuffer.withUnsafeMutableBufferPointer { outputBuffer in
            errorBuffer.withUnsafeMutableBufferPointer { errorBuffer in
                AeroPulseSMCDumpFanModeKeys(
                    outputBuffer.baseAddress,
                    UInt32(outputBuffer.count),
                    errorBuffer.baseAddress,
                    UInt32(errorBuffer.count)
                )
            }
        }

        guard status == 0 else {
            throw PrivilegedFanWriterError.helperFailed(
                Self.errorMessage(from: errorBuffer, fallback: "Failed to dump AppleSMC fan mode keys.")
            )
        }

        return Self.errorMessage(from: outputBuffer, fallback: "empty")
    }

    func setAuto(fanIDs: [Int]) throws {
        try fanIDs.forEach { fanID in
            var errorBuffer = [CChar](repeating: 0, count: Int(AEROPULSE_SMC_ERROR_BUFFER_LENGTH))
            let status = errorBuffer.withUnsafeMutableBufferPointer { errorBuffer in
                AeroPulseSMCSetFanAuto(
                    UInt32(fanID),
                    errorBuffer.baseAddress,
                    UInt32(errorBuffer.count)
                )
            }

            guard status == 0 else {
                throw PrivilegedFanWriterError.helperFailed(Self.errorMessage(from: errorBuffer, fallback: "Failed to set fan \(fanID) to auto."))
            }
        }
    }

    func setManualRPM(fanIDs: [Int], rpm: Int) throws {
        try fanIDs.forEach { fanID in
            var errorBuffer = [CChar](repeating: 0, count: Int(AEROPULSE_SMC_ERROR_BUFFER_LENGTH))
            let status = errorBuffer.withUnsafeMutableBufferPointer { errorBuffer in
                AeroPulseSMCSetFanTargetRPM(
                    UInt32(fanID),
                    UInt32(rpm),
                    errorBuffer.baseAddress,
                    UInt32(errorBuffer.count)
                )
            }

            guard status == 0 else {
                throw PrivilegedFanWriterError.helperFailed(Self.errorMessage(from: errorBuffer, fallback: "Failed to set fan \(fanID) to \(rpm) RPM."))
            }
        }
    }

    private static func errorMessage(from buffer: [CChar], fallback: String) -> String {
        let message = String(decoding: buffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? fallback : message
    }
}
