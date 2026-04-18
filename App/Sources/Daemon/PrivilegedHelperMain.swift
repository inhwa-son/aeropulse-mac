import Foundation
import Security

// Accepted client bundle identifiers. The app itself and Xcode previews / CLI
// sub-processes of the same bundle are all legitimate clients.
private let allowedClientIdentifiers: Set<String> = [
    "com.dan.aeropulse",
    PrivilegedHelperConstants.machServiceName
]
// Optional allow-list for team identifiers. If a client is signed with a
// trusted Developer team, we accept it even without a bundle-identifier match.
// Empty when the author is not enrolled in the paid Developer Program and the
// build is ad-hoc signed. Not required for the helper to function.
private let trustedTeamIdentifiers: Set<String> = []

final class PrivilegedFanControlListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let listener = NSXPCListener(machServiceName: PrivilegedHelperConstants.machServiceName)
    private let stateLock = NSLock()
    private var idleTerminationWorkItem: DispatchWorkItem?
    private var activeConnectionCount = 0
    private let idleGraceSeconds = PrivilegedHelperConstants.idleTerminationGraceSeconds

    func run() {
        helperDebugLog("listener starting")
        listener.delegate = self
        listener.resume()
        helperDebugLog("listener resumed")
        RunLoop.current.run()
    }

    /// Validates the connecting process's code signature.
    ///
    /// The helper ships without requiring a paid Apple Developer Program
    /// subscription. To support ad-hoc signed local builds we authenticate
    /// by the client's code-signing **identifier** (bundle ID), which every
    /// codesign invocation produces — ad-hoc or Developer ID alike. If an
    /// optional team identifier is configured, a match on that is also
    /// sufficient for acceptance.
    private func validateConnection(_ connection: NSXPCConnection) -> Bool {
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
                    let teamID = info[kSecCodeInfoTeamIdentifier as String] as? String
                    let identifier = info[kSecCodeInfoIdentifier as String] as? String

                    if let teamID, trustedTeamIdentifiers.contains(teamID) {
                        helperDebugLog("connection accepted via trusted team ID \(teamID)")
                        return true
                    }
                    if let identifier, allowedClientIdentifiers.contains(identifier) {
                        helperDebugLog("connection accepted via signing identifier \(identifier)")
                        return true
                    }
                    helperDebugLog("connection REJECTED: signing identifier=\(identifier ?? "nil"), team=\(teamID ?? "nil"); neither allowlisted")
                    return false
                }
            }
        } else {
            helperDebugLog("SecCodeCopyGuestWithAttributes failed: \(copyStatus)")
        }

        // Fallback: accept peers that run as the helper's same effective user.
        // In practice this only covers rare edge cases where the guest lookup
        // fails; the typical path is the bundle-identifier match above.
        let peerUID = connection.effectiveUserIdentifier
        let myUID = getuid()
        if peerUID == myUID {
            helperDebugLog("connection accepted via UID fallback (uid=\(peerUID))")
            return true
        }

        helperDebugLog("connection REJECTED: code signing unavailable and peer UID \(peerUID) != \(myUID)")
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
