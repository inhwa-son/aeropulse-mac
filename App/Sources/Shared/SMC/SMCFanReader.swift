import Foundation

enum SMCFanReaderError: LocalizedError {
    case readFailed(String)

    var errorDescription: String? {
        switch self {
        case let .readFailed(message):
            message
        }
    }
}

struct SMCFanReader: Sendable {
    func readFans(previousSnapshots: [FanSnapshot] = []) throws -> [FanSnapshot] {
        let rawSnapshots: [AeroPulseSMCFanSnapshot]
        do {
            rawSnapshots = try SMCRawFanReader.readRawSnapshots()
        } catch let error as SMCRawFanReaderError {
            switch error {
            case let .readFailed(message):
                throw SMCFanReaderError.readFailed(message)
            }
        }

        let previousModes = Dictionary(uniqueKeysWithValues: previousSnapshots.map { ($0.id, $0.mode) })
        return rawSnapshots.map { snapshot in
            let fanID = Int(snapshot.identifier)
            let targetRPM = Int(snapshot.targetRPM)

            let mode: FanMode
            switch snapshot.modeHint {
            case 1:
                mode = .auto
            case 2:
                mode = .manual
            default:
                mode = previousModes[fanID] ?? (targetRPM > 0 ? .manual : .unknown)
            }

            return FanSnapshot(
                id: fanID,
                mode: mode,
                currentRPM: Int(snapshot.currentRPM),
                targetRPM: targetRPM,
                minRPM: Int(snapshot.minRPM),
                maxRPM: Int(snapshot.maxRPM)
            )
        }
    }
}
