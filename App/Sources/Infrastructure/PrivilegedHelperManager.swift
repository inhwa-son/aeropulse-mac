import Foundation
import Security
import ServiceManagement

enum PrivilegedHelperConfiguration {
    static let plistName = "com.dan.aeropulse.helperd2.plist"
    static let machServiceName = "com.dan.aeropulse.helperd2"
}

@MainActor
final class PrivilegedHelperManager {

    private var service: SMAppService? {
        guard #available(macOS 13.0, *) else {
            return nil
        }

        return SMAppService.daemon(plistName: PrivilegedHelperConfiguration.plistName)
    }

    func status() -> PrivilegedHelperStatus {
        guard #available(macOS 13.0, *) else {
            return .unsupported
        }

        guard let service else {
            return .notFound
        }

        switch service.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered:
            return .notRegistered
        case .notFound:
            return .notFound
        @unknown default:
            return .failed("Unknown SMAppService status.")
        }
    }

    func register() throws -> PrivilegedHelperStatus {
        guard #available(macOS 13.0, *) else {
            return .unsupported
        }

        guard let service else {
            return .notFound
        }

        do {
            try service.register()
            return status()
        } catch {
            let latestStatus = status()
            switch latestStatus {
            case .enabled, .requiresApproval:
                return latestStatus
            case .notRegistered, .notFound, .failed, .unsupported:
                return .failed(error.localizedDescription)
            }
        }
    }

    func unregister() throws -> PrivilegedHelperStatus {
        guard #available(macOS 13.0, *) else {
            return .unsupported
        }

        guard let service else {
            return .notFound
        }

        do {
            try service.unregister()
            return status()
        } catch {
            let latestStatus = status()
            switch latestStatus {
            case .notRegistered, .notFound:
                return latestStatus
            case .enabled, .requiresApproval, .failed, .unsupported:
                return .failed(error.localizedDescription)
            }
        }
    }

    func preflightNotes() -> [String] {
        preflightNotes(for: diagnostics())
    }

    func preflightNotes(for diagnostics: PrivilegedHelperDiagnostics) -> [String] {
        var notes: [String] = []

        if !diagnostics.isInstalledInApplications {
            notes.append(String.tr("helper.guidance.install_applications"))
        }

        if diagnostics.teamIdentifier == nil {
            notes.append(String.tr("helper.guidance.signed_build"))
        }

        if !diagnostics.helperToolEmbedded {
            notes.append(String.tr("helper.guidance.missing_helper_tool"))
        }

        if !diagnostics.launchDaemonEmbedded {
            notes.append(String.tr("helper.guidance.missing_launchd_plist"))
        }

        return notes
    }

    func fastDiagnostics() -> PrivilegedHelperDiagnostics {
        let bundlePath = Bundle.main.bundleURL.path
        let helperToolPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/PrivilegedHelperTools/AeroPulsePrivilegedHelper")
            .path
        let launchDaemonPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchDaemons/\(PrivilegedHelperConfiguration.plistName)")
            .path

        return PrivilegedHelperDiagnostics(
            bundlePath: bundlePath,
            teamIdentifier: nil,
            isInstalledInApplications: bundlePath.hasPrefix("/Applications/"),
            helperToolEmbedded: FileManager.default.isExecutableFile(atPath: helperToolPath),
            launchDaemonEmbedded: FileManager.default.fileExists(atPath: launchDaemonPath)
        )
    }

    func diagnostics() -> PrivilegedHelperDiagnostics {
        var diagnostics = fastDiagnostics()
        diagnostics.teamIdentifier = currentTeamIdentifier()
        return diagnostics
    }

    func loadTeamIdentifier() async -> String? {
        let bundleURL = Bundle.main.bundleURL
        return await Task.detached(priority: .utility) {
            Self.currentTeamIdentifier(for: bundleURL)
        }.value
    }

    func openLoginItemsSettings() {
        guard #available(macOS 13.0, *) else {
            return
        }

        SMAppService.openSystemSettingsLoginItems()
    }

    private func currentTeamIdentifier() -> String? {
        Self.currentTeamIdentifier(for: Bundle.main.bundleURL)
    }

    nonisolated private static func currentTeamIdentifier(for bundleURL: URL) -> String? {
        var staticCode: SecStaticCode?
        let status = SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode)
        guard status == errSecSuccess, let staticCode else {
            return nil
        }

        var signingInformation: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &signingInformation)
        guard infoStatus == errSecSuccess,
              let signingInfo = signingInformation as? [String: Any] else {
            return nil
        }

        return signingInfo[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
