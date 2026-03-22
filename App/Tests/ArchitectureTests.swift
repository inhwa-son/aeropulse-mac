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
        for s: FanWriteBackendState in [.booting, .privilegedDaemon, .awaitingApproval, .fallbackCLI(reason: nil), .unavailable] {
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

    @Test static func teamIDConsistent() {
        for (file, label) in [("Project.swift","Project"),("AGENTS.md","AGENTS"),(".github/workflows/release.yml","CI")] {
            #expect(TestRepo.count("Y9TRXFZMR5", in: TestRepo.read(file)) > 0, "Team ID missing in \(label)")
        }
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
}
