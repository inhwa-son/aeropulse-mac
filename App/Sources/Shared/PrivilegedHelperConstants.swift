import Foundation

/// Single source of truth for identifiers the app, helper, and installer all
/// need to agree on. Centralising these strings prevents the kind of silent
/// drift that would leave the XPC client talking to a label that no one is
/// listening on, or the helper validating against the wrong bundle ID.
enum PrivilegedHelperConstants {
    /// Mach service name exported by the privileged helper, used by both the
    /// `NSXPCListener` inside the helper and `NSXPCConnection` in the app.
    static let machServiceName = "com.dan.aeropulse.helperd2"

    /// File name of the `LaunchDaemon` plist that registers the helper with
    /// `launchd`. The `.plist` suffix is included because `SMAppService.daemon`
    /// and the path inside `/Library/LaunchDaemons/` both expect it.
    static let launchDaemonPlistName = "\(machServiceName).plist"

    /// GCD label for the reassert timer's serial queue.
    static let reassertQueueLabel = "\(machServiceName).reassert"

    /// Interval between re-assertions of the current manual RPM target. Must be
    /// faster than the firmware's reclaim cadence (~1.5s on M3+).
    static let reassertInterval: DispatchTimeInterval = .milliseconds(500)

    /// Grace period after the last XPC client disconnects before the helper
    /// exits to free resources.
    static let idleTerminationGraceSeconds: TimeInterval = 20.0
}
