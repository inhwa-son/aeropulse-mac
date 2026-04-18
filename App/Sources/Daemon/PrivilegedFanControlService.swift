import Foundation

final class PrivilegedFanControlService: NSObject, PrivilegedFanControlProtocol {
    private let writer = PrivilegedFanWriter()
    private let stateLock = NSLock()
    // Apple Silicon (M3+) firmware resets `F<i>Tg` back to 0 within ~1.5s.
    // The helper re-asserts manual RPM targets every 500ms so the firmware
    // never wins. `manualTargets` is the single source of truth; the timer
    // runs iff this map is non-empty.
    private var manualTargets: [Int: Int] = [:]
    private var reassertTimer: DispatchSourceTimer?
    private let reassertQueue = DispatchQueue(label: PrivilegedHelperConstants.reassertQueueLabel, qos: .userInitiated)

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
            // Clear desired state BEFORE the SMC write so a pending reassert
            // tick cannot re-arm manual mode for these fans after auto lands.
            stateLock.lock()
            for id in resolvedFanIDs { manualTargets.removeValue(forKey: id) }
            let shouldStop = manualTargets.isEmpty
            stateLock.unlock()
            if shouldStop { stopReassertTimer() }

            try writer.setAuto(fanIDs: resolvedFanIDs)
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
            for id in resolvedFanIDs { manualTargets[id] = rpm.intValue }
            stateLock.unlock()
            startReassertTimerIfNeeded()
            helperDebugLog("setManualRPM succeeded for fanIDs=\(resolvedFanIDs), rpm=\(rpm.intValue)")
            reply(nil)
        } catch {
            helperDebugLog("setManualRPM failed: \(error.localizedDescription)")
            reply(error.localizedDescription)
        }
    }

    /// On Apple Silicon (M3/M4/M5), thermalmonitord / firmware reverts the
    /// `F<i>Tg` target-RPM key to 0 within ~1.5s of a user-space SMC write.
    /// A private serial timer re-issues the manual RPM at `reassertInterval`
    /// so the firmware never wins the race.
    private func startReassertTimerIfNeeded() {
        stateLock.lock()
        guard reassertTimer == nil else { stateLock.unlock(); return }
        let timer = DispatchSource.makeTimerSource(queue: reassertQueue)
        reassertTimer = timer
        stateLock.unlock()

        timer.schedule(
            deadline: .now() + PrivilegedHelperConstants.reassertInterval,
            repeating: PrivilegedHelperConstants.reassertInterval
        )
        timer.setEventHandler { [weak self] in
            self?.reassertTick()
        }
        timer.resume()
        helperDebugLog("reassert timer started")
    }

    private func reassertTick() {
        stateLock.lock()
        let snapshot = manualTargets
        stateLock.unlock()
        guard !snapshot.isEmpty else {
            stopReassertTimer()
            return
        }
        // One SMC write per unique RPM keeps the tick O(distinct targets).
        for (rpm, entries) in Dictionary(grouping: snapshot, by: { $0.value }) {
            let fanIDs = entries.map(\.key)
            do {
                try writer.setManualRPM(fanIDs: fanIDs, rpm: rpm)
            } catch {
                helperDebugLog("reassert tick write failed fans=\(fanIDs) rpm=\(rpm): \(error.localizedDescription)")
            }
        }
    }

    private func stopReassertTimer() {
        stateLock.lock()
        let timer = reassertTimer
        reassertTimer = nil
        stateLock.unlock()
        timer?.cancel()
        if timer != nil { helperDebugLog("reassert timer stopped") }
    }

#if DEBUG
    // ⚠️  Diagnostic-only: compiled out of Release builds. A Release helper
    // therefore exposes no mechanism for arbitrary SMC key I/O, ensuring the
    // root privilege boundary is limited to documented fan-control semantics.
    func writeRawKey(key: NSString, type: NSString, hexBytes: NSString, withReply reply: @escaping (String?) -> Void) {
        helperDebugLog("writeRawKey key=\(key) type=\(type) hex=\(hexBytes)")
        let keyStr = key as String
        let typeStr = type as String
        guard keyStr.utf8.count == 4, typeStr.utf8.count == 4 else {
            reply("key and type must be exactly 4 bytes")
            return
        }

        let bytes: [UInt8]
        do {
            bytes = try SMCHex.bytes(from: hexBytes as String)
        } catch {
            reply(error.localizedDescription)
            return
        }

        var errbuf = [CChar](repeating: 0, count: Int(AEROPULSE_SMC_ERROR_BUFFER_LENGTH))
        let status = keyStr.withCString { kp in
            typeStr.withCString { tp in
                bytes.withUnsafeBufferPointer { bp in
                    errbuf.withUnsafeMutableBufferPointer { ep in
                        AeroPulseSMCWriteRawKey(kp, tp, bp.baseAddress, UInt32(bp.count), ep.baseAddress, UInt32(ep.count))
                    }
                }
            }
        }
        if status == 0 {
            helperDebugLog("writeRawKey ok")
            reply(nil)
        } else {
            let msg = String(cString: errbuf)
            helperDebugLog("writeRawKey failed: \(msg)")
            reply(msg.isEmpty ? "raw SMC write failed (status=\(status))" : msg)
        }
    }

    func readRawKey(key: NSString, withReply reply: @escaping (NSString?, String?) -> Void) {
        let keyStr = key as String
        guard keyStr.utf8.count == 4 else {
            reply(nil, "key must be 4 bytes")
            return
        }
        var outbuf = [CChar](repeating: 0, count: Int(AEROPULSE_SMC_ERROR_BUFFER_LENGTH))
        var errbuf = [CChar](repeating: 0, count: Int(AEROPULSE_SMC_ERROR_BUFFER_LENGTH))
        let status = keyStr.withCString { kp in
            outbuf.withUnsafeMutableBufferPointer { op in
                errbuf.withUnsafeMutableBufferPointer { ep in
                    AeroPulseSMCReadRawKey(kp, op.baseAddress, UInt32(op.count), ep.baseAddress, UInt32(ep.count))
                }
            }
        }
        if status == 0 {
            reply(String(cString: outbuf) as NSString, nil)
        } else {
            reply(nil, String(cString: errbuf))
        }
    }
#endif

    func restoreAutoOnDisconnect() {
        helperDebugLog("restoreAutoOnDisconnect invoked")
        stateLock.lock()
        let fanIDs = Array(manualTargets.keys).sorted()
        manualTargets.removeAll()
        stateLock.unlock()

        stopReassertTimer()

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
