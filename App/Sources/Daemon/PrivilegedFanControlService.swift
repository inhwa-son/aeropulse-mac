import Foundation

final class PrivilegedFanControlService: NSObject, PrivilegedFanControlProtocol {
    private let writer = PrivilegedFanWriter()
    private let stateLock = NSLock()
    private var manualFanIDs: Set<Int> = []

    func probe(withReply reply: @escaping (String?) -> Void) {
        helperDebugLog("probe called")
        do {
            try writer.probe()
            helperDebugLog("probe succeeded")
            reply(nil)
        } catch {
            helperDebugLog("probe failed: \(error.localizedDescription)")
            reply(error.localizedDescription)
        }
    }

    func readFans(withReply reply: @escaping (NSData?) -> Void) {
        helperDebugLog("readFans called")
        do {
            let payload = try JSONEncoder().encode(
                PrivilegedFanReadResponse(
                    snapshots: writer.readFanPayloads(),
                    errorMessage: nil
                )
            ) as NSData
            helperDebugLog("readFans returning payload")
            reply(payload)
        } catch {
            helperDebugLog("readFans failed: \(error.localizedDescription)")
            let payload = try? JSONEncoder().encode(
                PrivilegedFanReadResponse(
                    snapshots: nil,
                    errorMessage: error.localizedDescription
                )
            ) as NSData
            reply(payload)
        }
    }

    func dumpFanModeKeys(withReply reply: @escaping (NSData?) -> Void) {
        helperDebugLog("dumpFanModeKeys called")
        do {
            let payload = try JSONEncoder().encode(
                PrivilegedStringResponse(
                    value: writer.dumpFanModeKeys(),
                    errorMessage: nil
                )
            ) as NSData
            helperDebugLog("dumpFanModeKeys returning payload")
            reply(payload)
        } catch {
            helperDebugLog("dumpFanModeKeys failed: \(error.localizedDescription)")
            let payload = try? JSONEncoder().encode(
                PrivilegedStringResponse(
                    value: nil,
                    errorMessage: error.localizedDescription
                )
            ) as NSData
            reply(payload)
        }
    }

    func setAuto(fanIDsCSV: NSString, withReply reply: @escaping (String?) -> Void) {
        let resolvedFanIDs = Self.parseFanIDs(from: fanIDsCSV as String)
        helperDebugLog("setAuto called for fanIDs=\(resolvedFanIDs)")
        do {
            guard !resolvedFanIDs.isEmpty else {
                throw PrivilegedFanWriterError.helperFailed("No fan IDs were received by privileged helper.")
            }
            try writer.setAuto(fanIDs: resolvedFanIDs)
            stateLock.lock()
            manualFanIDs.subtract(resolvedFanIDs)
            stateLock.unlock()
            helperDebugLog("setAuto succeeded for fanIDs=\(resolvedFanIDs)")
            reply(nil)
        } catch {
            helperDebugLog("setAuto failed: \(error.localizedDescription)")
            reply(error.localizedDescription)
        }
    }

    func setManualRPM(fanIDsCSV: NSString, rpm: NSNumber, withReply reply: @escaping (String?) -> Void) {
        let resolvedFanIDs = Self.parseFanIDs(from: fanIDsCSV as String)
        helperDebugLog("setManualRPM called for fanIDs=\(resolvedFanIDs), rpm=\(rpm)")
        do {
            guard !resolvedFanIDs.isEmpty else {
                throw PrivilegedFanWriterError.helperFailed("No fan IDs were received by privileged helper.")
            }
            try writer.setManualRPM(fanIDs: resolvedFanIDs, rpm: rpm.intValue)
            stateLock.lock()
            manualFanIDs.formUnion(resolvedFanIDs)
            stateLock.unlock()
            helperDebugLog("setManualRPM succeeded for fanIDs=\(resolvedFanIDs), rpm=\(rpm.intValue)")
            reply(nil)
        } catch {
            helperDebugLog("setManualRPM failed: \(error.localizedDescription)")
            reply(error.localizedDescription)
        }
    }

    func restoreAutoOnDisconnect() {
        helperDebugLog("restoreAutoOnDisconnect invoked")
        stateLock.lock()
        let fanIDs = Array(manualFanIDs).sorted()
        manualFanIDs.removeAll()
        stateLock.unlock()

        guard !fanIDs.isEmpty else { return }
        helperDebugLog("restoring auto for fanIDs=\(fanIDs)")
        try? writer.setAuto(fanIDs: fanIDs)
    }

    private static func parseFanIDs(from csv: String) -> [Int] {
        csv
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
}
