import Foundation
import SwiftUI
import Testing
@testable import AeroPulse

// MARK: - Shared Infrastructure

enum TestRepo {
    static let root: URL = {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            url = url.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Project.swift").path) { return url }
        }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }()

    static let features = root.appendingPathComponent("App/Sources/Features")
    static let resources = root.appendingPathComponent("App/Resources")

    static func read(_ path: String) -> String {
        (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
    }

    static func read(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    static func swiftFiles(in dir: URL) -> [URL] {
        FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)?
            .compactMap { ($0 as? URL).flatMap { $0.pathExtension == "swift" ? $0 : nil } } ?? []
    }

    static func extractKeys(from url: URL) -> Set<String> {
        let content = read(url)
        var keys = Set<String>()
        let regex = try! NSRegularExpression(pattern: #"^"([^"]+)"\s*="#, options: .anchorsMatchLines)
        regex.enumerateMatches(in: content, range: NSRange(content.startIndex..., in: content)) { m, _, _ in
            if let m, let r = Range(m.range(at: 1), in: content) { keys.insert(String(content[r])) }
        }
        return keys
    }

    static func count(_ pattern: String, in text: String) -> Int {
        (try? NSRegularExpression(pattern: pattern))?.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) ?? 0
    }
}

// MARK: - Architecture Enforcement

struct ArchitectureTests {

    @Test static func noRawSystemColorsInFeatures() {
        let banned = ["\\.red\\b", "\\.orange\\b", "\\.green\\b", "\\.mint\\b", "\\.blue\\b",
                      "\\.yellow\\b", "\\.pink\\b", "\\.purple\\b", "\\.cyan\\b", "\\.teal\\b",
                      "Color\\.red", "Color\\.orange", "Color\\.green", "Color\\.blue", "Color\\.mint", "Color\\.yellow"]
        var violations = [(String, Int, String)]()

        for file in TestRepo.swiftFiles(in: TestRepo.features) where file.lastPathComponent != "DesignTokens.swift" {
            let lines = TestRepo.read(file).components(separatedBy: .newlines)
            for (i, line) in lines.enumerated() {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard !t.hasPrefix("//"), !t.hasPrefix("*") else { continue }
                for p in banned {
                    if (try? NSRegularExpression(pattern: p))?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                        violations.append((file.lastPathComponent, i + 1, p))
                    }
                }
            }
        }
        if !violations.isEmpty {
            Issue.record("Raw colors: \(violations.map { "\($0.0):\($0.1) \($0.2)" }.joined(separator: ", "))")
        }
    }

    @Test static func localizationKeysInSync() {
        let en = TestRepo.extractKeys(from: TestRepo.resources.appendingPathComponent("en.lproj/Localizable.strings"))
        let ko = TestRepo.extractKeys(from: TestRepo.resources.appendingPathComponent("ko.lproj/Localizable.strings"))
        let missingKo = en.subtracting(ko), missingEn = ko.subtracting(en)
        if !missingKo.isEmpty { Issue.record("Missing in ko: \(missingKo.sorted())") }
        if !missingEn.isEmpty { Issue.record("Missing in en: \(missingEn.sorted())") }
    }

    @Test static func designTokensComplete() {
        let c = TestRepo.read("App/Sources/Features/DesignTokens.swift")
        for t in ["thermalCool","thermalNormal","thermalWarm","thermalHot",
                   "statusSuccess","statusWarning","statusError","statusInfo","statusNeutral",
                   "chart1","chart2","chart3","chart4","chart5"] {
            #expect(c.contains("static let \(t)"), "Missing token: \(t)")
        }
    }

    @Test static func designTokensAdaptive() {
        let c = TestRepo.read("App/Sources/Features/DesignTokens.swift")
        let colors = TestRepo.count(#"\.init\(name:\s*nil\)"#, in: c)
        let branches = TestRepo.count(#"appearance\.isDark"#, in: c)
        #expect(colors > 0, "No dynamic colors found")
        #expect(colors == branches, "Colors(\(colors)) ≠ isDark branches(\(branches))")
    }

    @Test static func noHardcodedKoreanInText() {
        let pattern = try! NSRegularExpression(pattern: #"Text\("[^"]*[\uAC00-\uD7AF]"#)
        var violations = [(String, Int)]()
        for file in TestRepo.swiftFiles(in: TestRepo.features) where file.lastPathComponent != "DesignTokens.swift" {
            for (i, line) in TestRepo.read(file).components(separatedBy: .newlines).enumerated() {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard !t.hasPrefix("//"), !t.hasPrefix("*") else { continue }
                if pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                    violations.append((file.lastPathComponent, i + 1))
                }
            }
        }
        if !violations.isEmpty { Issue.record("Hardcoded Korean: \(violations.map { "\($0.0):\($0.1)" })") }
    }

    @Test func independentDefaults() {
        #expect(AppSettings.default.fanExecutablePath.isEmpty)
        #expect(AppSettings.default.iSMCExecutablePath.isEmpty)
    }

    @Test func thermalAccentCoverage() {
        let noData = APColor.thermalAccent(for: nil)
        for temp in [30.0, 52.0, 68.0, 85.0] { #expect(APColor.thermalAccent(for: temp) != noData) }
    }

    @Test func backendAccentCoverage() {
        for s: FanWriteBackendState in [.booting, .privilegedDaemon, .awaitingApproval, .noFansDetected, .fallbackCLI(reason: nil), .unavailable] {
            let _ = APColor.backendAccent(for: s)
        }
    }

    @Test static func versionConsistency() {
        let c = TestRepo.read("Project.swift")
        let extract = { (p: String) -> String? in
            (try? NSRegularExpression(pattern: p))?.firstMatch(in: c, range: NSRange(c.startIndex..., in: c))
                .flatMap { Range($0.range(at: 1), in: c) }.map { String(c[$0]) }
        }
        let mv = extract(#""MARKETING_VERSION":\s*"([^"]+)""#)
        let bv = extract(#""CFBundleShortVersionString":\s*"([^"]+)""#)
        #expect(mv == bv, "MARKETING_VERSION(\(mv ?? "nil")) ≠ CFBundleShortVersionString(\(bv ?? "nil"))")
    }
}

// MARK: - AGENTS.md Hardening

struct AgentsMDHardeningTests {
    private static nonisolated(unsafe) let fm = FileManager.default

    @Test static func agentsMDExists() {
        #expect(fm.fileExists(atPath: TestRepo.root.appendingPathComponent("AGENTS.md").path))
    }

    @Test static func claudeMDIsSymlink() {
        let p = TestRepo.root.appendingPathComponent("CLAUDE.md").path
        let attrs = try? fm.attributesOfItem(atPath: p)
        #expect(attrs?[.type] as? FileAttributeType == .typeSymbolicLink, "CLAUDE.md must be symlink")
        if let dest = try? fm.destinationOfSymbolicLink(atPath: p) {
            #expect(dest == "AGENTS.md" || dest.hasSuffix("/AGENTS.md"))
        }
    }

    @Test static func requiredSections() {
        let c = TestRepo.read("AGENTS.md")
        for s in ["Design Principles","Autonomous Default Mode","Commands","Code Rules","Version","CI/CD","References"] {
            #expect(c.contains("## \(s)"), "Missing section: \(s)")
        }
    }

    @Test static func referencedFilesExist() {
        let c = TestRepo.read("AGENTS.md")
        for f in ["README.md",".github/workflows/release.yml","scripts/release-build.sh",
                   "scripts/create-dmg.sh","scripts/bump-version.sh","scripts/notarize.sh",
                   "scripts/setup-github-secrets.sh","scripts/release-doctor.sh","scripts/release-register.sh"] {
            guard c.contains(f) else { continue }
            #expect(fm.fileExists(atPath: TestRepo.root.appendingPathComponent(f).path), "Missing: \(f)")
        }
    }

    @Test static func scriptsExecutable() {
        for s in ["release-build.sh","release-doctor.sh","release-register.sh","create-dmg.sh",
                   "bump-version.sh","notarize.sh","setup-github-secrets.sh"] {
            let p = TestRepo.root.appendingPathComponent("scripts/\(s)").path
            guard fm.fileExists(atPath: p) else { continue }
            #expect(fm.isExecutableFile(atPath: p), "\(s) not executable")
        }
    }

    @Test static func codePathsClaimed() {
        for p in ["App/Sources/Features/DesignTokens.swift","App/Sources/Domain/Models.swift",
                   "App/Sources/App/AeroPulseApp.swift","App/Sources/Shared/PrivilegedFanControlProtocol.swift",
                   "App/Resources/en.lproj/Localizable.strings","App/Resources/ko.lproj/Localizable.strings"] {
            #expect(fm.fileExists(atPath: TestRepo.root.appendingPathComponent(p).path), "Missing: \(p)")
        }
    }

    @Test static func versionSynced() {
        let proj = TestRepo.read("Project.swift")
        let agents = TestRepo.read("AGENTS.md")
        if let m = (try? NSRegularExpression(pattern: #""MARKETING_VERSION":\s*"([^"]+)""#))?
            .firstMatch(in: proj, range: NSRange(proj.startIndex..., in: proj)),
           let r = Range(m.range(at: 1), in: proj) {
            let v = String(proj[r])
            #expect(agents.contains("| `MARKETING_VERSION` | \(v)"), "AGENTS.md version stale (expected \(v))")
        }
    }

    @Test static func paidDeveloperProgramIsOptional() {
        // The project intentionally supports ad-hoc signed local builds so a paid
        // Apple Developer Program membership is never required. The sources must
        // not hardcode a team identifier in a way that forces paid-only signing.
        let helper = TestRepo.read("App/Sources/Daemon/PrivilegedHelperMain.swift")
        #expect(helper.contains("allowedClientIdentifiers"), "helper must validate by bundle identifier, not hardcoded team ID")
        #expect(helper.contains("trustedTeamIdentifiers"), "helper must expose an optional team-id allowlist, not a required one")
        #expect(!helper.contains("let allowedTeamID ="), "helper must not hardcode a single required team ID")
    }

    @Test static func diagnosticCLIIsGatedByDebug() {
        // The diagnostic / raw-SMC commands grant root-level SMC access through
        // the privileged helper's XPC. They must compile out of Release builds
        // so an untrusted process that matches the client identifier allow-list
        // still has no path to arbitrary SMC writes.
        let commands = TestRepo.read("App/Sources/App/AppCommand.swift")
        let protocolSource = TestRepo.read("App/Sources/Shared/PrivilegedFanControlProtocol.swift")
        let client = TestRepo.read("App/Sources/Infrastructure/PrivilegedFanControlClient.swift")
        let service = TestRepo.read("App/Sources/Daemon/PrivilegedFanControlService.swift")

        for (source, label) in [(commands, "AppCommand"), (protocolSource, "Protocol"), (client, "Client"), (service, "Service")] {
            let hasRawKey = source.contains("writeRawKey") || source.contains("readRawKey")
                || source.contains("fanExperiment") || source.contains("smcEnumerate")
                || source.contains("smcReadRaw") || source.contains("smcWriteRaw")
                || source.contains("smcReadHelper") || source.contains("smcWriteHelper")
            if hasRawKey {
                #expect(source.contains("#if DEBUG"), "\(label) exposes diagnostic/raw-SMC symbols that must be gated by #if DEBUG")
            }
        }
    }

    @Test static func reassertTimerCancelsWhenAllFansGoAuto() {
        // Regression guard for the setAuto-vs-reassert race: the service must
        // clear its desired-state map BEFORE issuing the SMC auto write so a
        // pending reassert tick cannot re-arm manual mode for the just-cleared
        // fans. Grep enforces the ordering.
        let service = TestRepo.read("App/Sources/Daemon/PrivilegedFanControlService.swift")
        guard let setAutoRange = service.range(of: "func setAuto("),
              let nextFunc = service.range(of: "\n    func ", range: setAutoRange.upperBound..<service.endIndex) else {
            Issue.record("unable to locate setAuto body")
            return
        }
        let body = service[setAutoRange.lowerBound..<nextFunc.lowerBound]
        guard let clearIdx = body.range(of: "manualTargets.removeValue"),
              let writeIdx = body.range(of: "writer.setAuto") else {
            Issue.record("setAuto must clear manualTargets and call writer.setAuto")
            return
        }
        #expect(clearIdx.lowerBound < writeIdx.lowerBound,
                "setAuto must remove manualTargets entries before issuing the SMC write")
        #expect(body.contains("stopReassertTimer"),
                "setAuto must stop the reassert timer when no manual targets remain")
    }

    @Test static func reassertTickLogsOnSMCFailures() {
        // If firmware or another SMC writer rejects a reassert, the tick must
        // log so a quiet "fans drifted back to auto" regression is observable
        // in production via the helper debug log.
        let service = TestRepo.read("App/Sources/Daemon/PrivilegedFanControlService.swift")
        guard let tickRange = service.range(of: "private func reassertTick"),
              let nextFunc = service.range(of: "\n    private func ", range: tickRange.upperBound..<service.endIndex) else {
            Issue.record("unable to locate reassertTick body")
            return
        }
        let body = service[tickRange.lowerBound..<nextFunc.lowerBound]
        #expect(body.contains("helperDebugLog"),
                "reassertTick must log SMC write failures rather than swallowing them silently")
    }

    @Test static func ciRunsTests() {
        #expect(TestRepo.read(".github/workflows/ci.yml").contains("test"))
    }

    @Test static func agentsMDReferencesDesignSystem() {
        let agents = TestRepo.read("AGENTS.md")
        // AGENTS.md must mention the design token system — detail lives in code + ArchitectureTests
        #expect(agents.contains("APColor"), "AGENTS.md must reference APColor design token system")
        #expect(agents.contains("DesignTokens.swift"), "AGENTS.md must reference DesignTokens.swift")
        #expect(agents.contains("String.tr"), "AGENTS.md must reference String.tr localization")
    }

    @Test static func launchDaemonPlistUsesBundleProgramForRelocationSafety() {
        let plist = TestRepo.read("App/Support/LaunchDaemons/com.dan.aeropulse.helperd2.plist")

        #expect(plist.contains("<key>BundleProgram</key>"), "LaunchDaemon plist must use BundleProgram for app relocation safety")
        #expect(
            plist.contains("Contents/Library/PrivilegedHelperTools/AeroPulsePrivilegedHelper"),
            "LaunchDaemon plist must reference the embedded helper via bundle-relative path"
        )
        #expect(!plist.contains("__AEROPULSE_HELPER_PATH__"), "LaunchDaemon plist must not depend on placeholder helper paths")
        #expect(!plist.contains("<key>ProgramArguments</key>"), "LaunchDaemon plist must not bake helper paths into ProgramArguments")
    }

    @Test static func releaseBuildScriptDoesNotRewriteHelperPathToAbsoluteProgramArguments() {
        let script = TestRepo.read("scripts/release-build.sh")

        #expect(!script.contains("rewrite_launchd_program_arguments"), "release-build.sh must not rewrite helper paths after build")
        #expect(!script.contains("data[\"ProgramArguments\"]"), "release-build.sh must not inject absolute ProgramArguments for the helper")
        #expect(!script.contains("data.pop(\"BundleProgram\", None)"), "release-build.sh must preserve BundleProgram-based helper registration")
    }

    @Test static func releaseWorkflowDoesNotRewriteHelperPathToAbsoluteProgramArguments() {
        let workflow = TestRepo.read(".github/workflows/release.yml")

        #expect(!workflow.contains("data.pop('BundleProgram', None)"), "release.yml must preserve BundleProgram-based helper registration")
        #expect(!workflow.contains("data['ProgramArguments']"), "release.yml must not inject absolute ProgramArguments for the helper")
        #expect(!workflow.contains("Rewrite LaunchDaemon plist"), "release.yml must not rewrite LaunchDaemon helper paths after build")
    }
}
