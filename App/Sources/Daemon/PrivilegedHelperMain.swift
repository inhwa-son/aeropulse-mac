import Foundation
import Security

private let privilegedHelperMachServiceName = "com.dan.aeropulse.helperd2"
private let allowedTeamID = "Y9TRXFZMR5"

final class PrivilegedFanControlListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let listener = NSXPCListener(machServiceName: privilegedHelperMachServiceName)
    private let stateLock = NSLock()
    private var idleTerminationWorkItem: DispatchWorkItem?
    private var activeConnectionCount = 0
    private let idleGraceSeconds = 20.0

    func run() {
        helperDebugLog("listener starting")
        listener.delegate = self
        listener.resume()
        helperDebugLog("listener resumed")
        RunLoop.current.run()
    }

    /// Validate that the connecting process is signed by our team.
    /// Uses the connection's PID to look up the code signature,
    /// then checks the team identifier matches `allowedTeamID`.
    /// Falls back to UID validation if code signing check is inconclusive.
    private func validateConnection(_ connection: NSXPCConnection) -> Bool {
        // Layer 1: Code signature validation via PID
        let pid = connection.processIdentifier
        let attributes = [kSecGuestAttributePid: pid] as CFDictionary

        var codeOpt: SecCode?
        let copyStatus = SecCodeCopyGuestWithAttributes(nil, attributes, [], &codeOpt)

        if copyStatus == errSecSuccess, let code = codeOpt {
            var staticCodeOpt: SecStaticCode?
            let staticStatus = SecCodeCopyStaticCode(code, [], &staticCodeOpt)

            if staticStatus == errSecSuccess, let staticCode = staticCodeOpt {
                var infoOpt: CFDictionary?
                let infoStatus = SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &infoOpt)

                if infoStatus == errSecSuccess, let info = infoOpt as? [String: Any] {
                    if let teamID = info[kSecCodeInfoTeamIdentifier as String] as? String {
                        if teamID == allowedTeamID {
                            helperDebugLog("connection validated: team ID \(teamID) matches")
                            return true
                        } else {
                            helperDebugLog("connection REJECTED: team ID \(teamID) does not match \(allowedTeamID)")
                            return false
                        }
                    } else {
                        helperDebugLog("connection: no team identifier in code signature, falling back to UID check")
                    }
                }
            }
        } else {
            helperDebugLog("SecCodeCopyGuestWithAttributes failed: \(copyStatus)")
        }

        // Layer 2: Fallback — restrict to same effective user
        let peerUID = connection.effectiveUserIdentifier
        let myUID = getuid()
        if peerUID == myUID {
            helperDebugLog("connection accepted via UID fallback (uid=\(peerUID))")
            return true
        }

        helperDebugLog("connection REJECTED: UID \(peerUID) != \(myUID) and code signing unavailable")
        return false
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard validateConnection(newConnection) else {
            helperDebugLog("rejected new connection")
            return false
        }

        helperDebugLog("accepting new connection")
        let exported = PrivilegedFanControlService()
        incrementConnections()
        newConnection.exportedInterface = makePrivilegedFanControlInterface()
        newConnection.exportedObject = exported
        newConnection.invalidationHandler = { [weak self] in
            helperDebugLog("connection invalidated")
            exported.restoreAutoOnDisconnect()
            self?.connectionDidClose()
        }
        newConnection.interruptionHandler = {
            helperDebugLog("connection interrupted")
            exported.restoreAutoOnDisconnect()
        }
        newConnection.resume()
        helperDebugLog("connection resumed")
        return true
    }

    private func incrementConnections() {
        stateLock.lock()
        idleTerminationWorkItem?.cancel()
        idleTerminationWorkItem = nil
        activeConnectionCount += 1
        let count = activeConnectionCount
        stateLock.unlock()
        helperDebugLog("active connections incremented to \(count)")
    }

    private func connectionDidClose() {
        stateLock.lock()
        activeConnectionCount = max(0, activeConnectionCount - 1)
        let shouldTerminate = activeConnectionCount == 0
        let count = activeConnectionCount
        stateLock.unlock()
        helperDebugLog("connection closed, active connections now \(count)")

        guard shouldTerminate else { return }
        scheduleIdleTermination()
    }

    private func scheduleIdleTermination() {
        let workItem = DispatchWorkItem { [weak self] in
            self?.terminateIfIdle()
        }

        stateLock.lock()
        idleTerminationWorkItem?.cancel()
        idleTerminationWorkItem = workItem
        stateLock.unlock()

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + idleGraceSeconds, execute: workItem)
    }

    private func terminateIfIdle() {
        stateLock.lock()
        let shouldTerminate = activeConnectionCount == 0
        if shouldTerminate {
            idleTerminationWorkItem = nil
        }
        stateLock.unlock()

        guard shouldTerminate else { return }
        helperDebugLog("terminating helper because it is idle")
        exit(EXIT_SUCCESS)
    }
}

@main
struct PrivilegedHelperMain {
    static func main() {
        helperDebugLog("main entry")
        let delegate = PrivilegedFanControlListenerDelegate()
        delegate.run()
    }
}
