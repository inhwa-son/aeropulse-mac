import Foundation

enum AppTab: String, Hashable, Sendable {
    case dashboard
    case sensors
    case automation
    case settings
}

enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case korean
    case english

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .system:
            "settings.language.system"
        case .korean:
            "settings.language.korean"
        case .english:
            "settings.language.english"
        }
    }

    var bundleLanguageCode: String? {
        switch self {
        case .system:
            nil
        case .korean:
            "ko"
        case .english:
            "en"
        }
    }

    var localeIdentifier: String? {
        switch self {
        case .system:
            nil
        case .korean:
            "ko_KR"
        case .english:
            "en_US"
        }
    }
}

enum AppTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .system:
            "settings.theme.system"
        case .light:
            "settings.theme.light"
        case .dark:
            "settings.theme.dark"
        }
    }
}

enum SensorSource: String, Codable, CaseIterable, Sendable {
    case hid
    case ismc
}

enum FanMode: String, Codable, CaseIterable, Sendable {
    case auto = "Auto"
    case manual = "Manual"
    case unknown = "Unknown"
}

enum AutomationDecision: Equatable, Sendable {
    case auto
    case manual(rpm: Int)

    var summary: String {
        switch self {
        case .auto:
            "Auto"
        case let .manual(rpm):
            "\(rpm) RPM"
        }
    }

    var isAuto: Bool {
        if case .auto = self { return true }
        return false
    }
}

enum ControlStrategy: String, Codable, CaseIterable, Sendable {
    case systemDefault
    case curve
    case maximumCooling
}

enum ProfilePresetID: String, Codable, CaseIterable, Identifiable, Sendable {
    case macDefault
    case performanceLight
    case performanceMedium
    case performanceStrong
    case maxCooling

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .macDefault:
            "profile.mac_default.title"
        case .performanceLight:
            "profile.performance_light.title"
        case .performanceMedium:
            "profile.performance_medium.title"
        case .performanceStrong:
            "profile.performance_strong.title"
        case .maxCooling:
            "profile.max_cooling.title"
        }
    }

    var descriptionKey: String {
        switch self {
        case .macDefault:
            "profile.mac_default.description"
        case .performanceLight:
            "profile.performance_light.description"
        case .performanceMedium:
            "profile.performance_medium.description"
        case .performanceStrong:
            "profile.performance_strong.description"
        case .maxCooling:
            "profile.max_cooling.description"
        }
    }
}

enum SensorSelectionKind: String, Codable, CaseIterable, Sendable {
    case hottest
    case hottestCPUCore
    case cpuAverage
    case gpuAverage
    case batteryAverage
    case specific
}

struct SensorSelection: Hashable, Codable, Sendable {
    var kind: SensorSelectionKind
    var key: String?

    static let hottest = SensorSelection(kind: .hottest, key: nil)
    static let hottestCPUCore = SensorSelection(kind: .hottestCPUCore, key: nil)
    static let cpuAverage = SensorSelection(kind: .cpuAverage, key: nil)
    static let gpuAverage = SensorSelection(kind: .gpuAverage, key: nil)
    static let batteryAverage = SensorSelection(kind: .batteryAverage, key: nil)
    static func specific(_ key: String?) -> SensorSelection { .init(kind: .specific, key: key) }
}

struct TemperatureSensor: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let key: String
    var name: String
    var celsius: Double
    var source: SensorSource
}

struct FanSnapshot: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    var mode: FanMode
    var currentRPM: Int
    var targetRPM: Int
    var minRPM: Int
    var maxRPM: Int

    var name: String {
        "Fan \(id)"
    }
}

struct CurvePoint: Identifiable, Hashable, Codable, Sendable {
    var id: UUID = UUID()
    var temperature: Double
    var rpm: Int
}

struct ControlProfile: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var presetID: ProfilePresetID
    var nameKey: String
    var descriptionKey: String
    var strategy: ControlStrategy
    var sensorSelection: SensorSelection
    var fanIDs: [Int]
    var hysteresis: Double
    var minimumHoldSeconds: Double
    var curve: [CurvePoint]

    static let `default` = ControlProfile(
        id: ProfilePresetID.performanceMedium.rawValue,
        presetID: .performanceMedium,
        nameKey: ProfilePresetID.performanceMedium.titleKey,
        descriptionKey: ProfilePresetID.performanceMedium.descriptionKey,
        strategy: .curve,
        sensorSelection: .cpuAverage,
        fanIDs: [1, 2],
        hysteresis: 1.5,
        minimumHoldSeconds: 3.0,
        curve: [
            CurvePoint(temperature: 38, rpm: 3200),
            CurvePoint(temperature: 46, rpm: 4300),
            CurvePoint(temperature: 54, rpm: 5700),
            CurvePoint(temperature: 62, rpm: 6900),
            CurvePoint(temperature: 70, rpm: 7600),
            CurvePoint(temperature: 78, rpm: 7800)
        ]
    )

    static let presets: [ControlProfile] = [
        ControlProfile(
            id: ProfilePresetID.macDefault.rawValue,
            presetID: .macDefault,
            nameKey: ProfilePresetID.macDefault.titleKey,
            descriptionKey: ProfilePresetID.macDefault.descriptionKey,
            strategy: .systemDefault,
            sensorSelection: .cpuAverage,
            fanIDs: [1, 2],
            hysteresis: 0,
            minimumHoldSeconds: 1,
            curve: []
        ),
        ControlProfile(
            id: ProfilePresetID.performanceLight.rawValue,
            presetID: .performanceLight,
            nameKey: ProfilePresetID.performanceLight.titleKey,
            descriptionKey: ProfilePresetID.performanceLight.descriptionKey,
            strategy: .curve,
            sensorSelection: .cpuAverage,
            fanIDs: [1, 2],
            hysteresis: 1.8,
            minimumHoldSeconds: 3.6,
            curve: [
                CurvePoint(temperature: 40, rpm: 2800),
                CurvePoint(temperature: 48, rpm: 3600),
                CurvePoint(temperature: 56, rpm: 4900),
                CurvePoint(temperature: 64, rpm: 6200),
                CurvePoint(temperature: 72, rpm: 7200),
                CurvePoint(temperature: 80, rpm: 7600)
            ]
        ),
        ControlProfile(
            id: ProfilePresetID.performanceMedium.rawValue,
            presetID: .performanceMedium,
            nameKey: ProfilePresetID.performanceMedium.titleKey,
            descriptionKey: ProfilePresetID.performanceMedium.descriptionKey,
            strategy: .curve,
            sensorSelection: .cpuAverage,
            fanIDs: [1, 2],
            hysteresis: 1.5,
            minimumHoldSeconds: 3.0,
            curve: [
                CurvePoint(temperature: 38, rpm: 3200),
                CurvePoint(temperature: 46, rpm: 4300),
                CurvePoint(temperature: 54, rpm: 5700),
                CurvePoint(temperature: 62, rpm: 6900),
                CurvePoint(temperature: 70, rpm: 7600),
                CurvePoint(temperature: 78, rpm: 7800)
            ]
        ),
        ControlProfile(
            id: ProfilePresetID.performanceStrong.rawValue,
            presetID: .performanceStrong,
            nameKey: ProfilePresetID.performanceStrong.titleKey,
            descriptionKey: ProfilePresetID.performanceStrong.descriptionKey,
            strategy: .curve,
            sensorSelection: .cpuAverage,
            fanIDs: [1, 2],
            hysteresis: 1.2,
            minimumHoldSeconds: 2.4,
            curve: [
                CurvePoint(temperature: 35, rpm: 3600),
                CurvePoint(temperature: 42, rpm: 5000),
                CurvePoint(temperature: 50, rpm: 6400),
                CurvePoint(temperature: 58, rpm: 7300),
                CurvePoint(temperature: 66, rpm: 7700),
                CurvePoint(temperature: 74, rpm: 7800)
            ]
        ),
        ControlProfile(
            id: ProfilePresetID.maxCooling.rawValue,
            presetID: .maxCooling,
            nameKey: ProfilePresetID.maxCooling.titleKey,
            descriptionKey: ProfilePresetID.maxCooling.descriptionKey,
            strategy: .maximumCooling,
            sensorSelection: .cpuAverage,
            fanIDs: [1, 2],
            hysteresis: 0,
            minimumHoldSeconds: 1,
            curve: []
        )
    ]

    static func preset(_ presetID: ProfilePresetID) -> ControlProfile {
        presets.first(where: { $0.presetID == presetID }) ?? .default
    }
}

struct AppSettings: Hashable, Codable, Sendable {
    static let legacyCompatibilityFanPath = "/Applications/FanControl.app/Contents/MacOS/fan"
    static let legacyCompatibilityISMCPath = "/Applications/FanControl.app/Contents/Resources/iSMC"

    var pollingInterval: Double
    var fanExecutablePath: String
    var iSMCExecutablePath: String
    var automationEnabled: Bool
    var selectedPresetID: ProfilePresetID
    var profile: ControlProfile
    var customProfiles: [ProfilePresetID: ControlProfile]
    var menuBarSensorSelection: SensorSelection
    var language: AppLanguage
    var theme: AppTheme
    var helperAutoRegistrationEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case pollingInterval
        case fanExecutablePath
        case iSMCExecutablePath
        case automationEnabled
        case selectedPresetID
        case profile
        case customProfiles
        case menuBarSensorSelection
        case language
        case theme
        case helperAutoRegistrationEnabled
    }

    init(
        pollingInterval: Double,
        fanExecutablePath: String,
        iSMCExecutablePath: String,
        automationEnabled: Bool,
        selectedPresetID: ProfilePresetID,
        profile: ControlProfile,
        customProfiles: [ProfilePresetID: ControlProfile],
        menuBarSensorSelection: SensorSelection,
        language: AppLanguage,
        theme: AppTheme,
        helperAutoRegistrationEnabled: Bool
    ) {
        self.pollingInterval = pollingInterval
        self.fanExecutablePath = fanExecutablePath
        self.iSMCExecutablePath = iSMCExecutablePath
        self.automationEnabled = automationEnabled
        self.selectedPresetID = selectedPresetID
        self.profile = profile
        self.customProfiles = customProfiles
        self.menuBarSensorSelection = menuBarSensorSelection
        self.language = language
        self.theme = theme
        self.helperAutoRegistrationEnabled = helperAutoRegistrationEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings.default

        pollingInterval = try container.decodeIfPresent(Double.self, forKey: .pollingInterval) ?? defaults.pollingInterval
        fanExecutablePath = try container.decodeIfPresent(String.self, forKey: .fanExecutablePath) ?? defaults.fanExecutablePath
        iSMCExecutablePath = try container.decodeIfPresent(String.self, forKey: .iSMCExecutablePath) ?? defaults.iSMCExecutablePath
        automationEnabled = try container.decodeIfPresent(Bool.self, forKey: .automationEnabled) ?? defaults.automationEnabled
        profile = try container.decodeIfPresent(ControlProfile.self, forKey: .profile) ?? defaults.profile
        selectedPresetID = try container.decodeIfPresent(ProfilePresetID.self, forKey: .selectedPresetID) ?? profile.presetID
        customProfiles = try container.decodeIfPresent([ProfilePresetID: ControlProfile].self, forKey: .customProfiles) ?? [:]
        menuBarSensorSelection = try container.decodeIfPresent(SensorSelection.self, forKey: .menuBarSensorSelection) ?? defaults.menuBarSensorSelection
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? defaults.language
        theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? defaults.theme
        helperAutoRegistrationEnabled = try container.decodeIfPresent(Bool.self, forKey: .helperAutoRegistrationEnabled) ?? defaults.helperAutoRegistrationEnabled
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pollingInterval, forKey: .pollingInterval)
        try container.encode(fanExecutablePath, forKey: .fanExecutablePath)
        try container.encode(iSMCExecutablePath, forKey: .iSMCExecutablePath)
        try container.encode(automationEnabled, forKey: .automationEnabled)
        try container.encode(selectedPresetID, forKey: .selectedPresetID)
        try container.encode(profile, forKey: .profile)
        try container.encode(customProfiles, forKey: .customProfiles)
        try container.encode(menuBarSensorSelection, forKey: .menuBarSensorSelection)
        try container.encode(language, forKey: .language)
        try container.encode(theme, forKey: .theme)
        try container.encode(helperAutoRegistrationEnabled, forKey: .helperAutoRegistrationEnabled)
    }

    static let `default` = AppSettings(
        pollingInterval: 1.5,
        fanExecutablePath: "",
        iSMCExecutablePath: "",
        automationEnabled: false,
        selectedPresetID: .performanceMedium,
        profile: .default,
        customProfiles: [:],
        menuBarSensorSelection: .cpuAverage,
        language: .system,
        theme: .system,
        helperAutoRegistrationEnabled: true
    )
}

struct DashboardSummary: Sendable {
    var cpuAverage: Double?
    var gpuAverage: Double?
    var batteryAverage: Double?
    var hottest: TemperatureSensor?

    static let empty = DashboardSummary(cpuAverage: nil, gpuAverage: nil, batteryAverage: nil, hottest: nil)
}

struct AutomationSnapshot: Sendable {
    var decision: AutomationDecision
    var sensor: TemperatureSensor?
    var reason: String
    var timestamp: Date
    var controlTemperature: Double?
    var controlDetail: String?
}

enum IntegrationState: Equatable, Sendable {
    case ready
    case awaitingApproval
    case missingFanCLI
    case missingISMC
    case failed(String)

    var isOperational: Bool {
        switch self {
        case .ready, .missingISMC:
            true
        case .awaitingApproval, .missingFanCLI, .failed:
            false
        }
    }
}

enum FanWriteBackendState: Equatable, Sendable {
    case booting
    case privilegedDaemon
    case awaitingApproval
    case noFansDetected
    case fallbackCLI(reason: String?)
    case unavailable

    var titleKey: String {
        switch self {
        case .booting:
            "backend.booting.title"
        case .privilegedDaemon:
            "backend.privileged.title"
        case .awaitingApproval:
            "backend.awaiting_approval.title"
        case .noFansDetected:
            "backend.no_fans.title"
        case .fallbackCLI:
            "backend.fallback.title"
        case .unavailable:
            "backend.unavailable.title"
        }
    }

    var detailKey: String {
        switch self {
        case .booting:
            "backend.booting.detail"
        case .privilegedDaemon:
            "backend.privileged.detail"
        case .awaitingApproval:
            "backend.awaiting_approval.detail"
        case .noFansDetected:
            "backend.no_fans.detail"
        case .fallbackCLI:
            "backend.fallback.detail"
        case .unavailable:
            "backend.unavailable.detail"
        }
    }

    var reason: String? {
        switch self {
        case let .fallbackCLI(reason):
            reason
        default:
            nil
        }
    }
}

enum PrivilegedHelperStatus: Equatable, Sendable {
    case unsupported
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    case failed(String)

    var titleKey: String {
        switch self {
        case .unsupported:
            "helper.unsupported.title"
        case .notRegistered:
            "helper.not_registered.title"
        case .enabled:
            "helper.enabled.title"
        case .requiresApproval:
            "helper.requires_approval.title"
        case .notFound:
            "helper.not_found.title"
        case .failed:
            "helper.failed.title"
        }
    }

    var detailKey: String {
        switch self {
        case .unsupported:
            "helper.unsupported.detail"
        case .notRegistered:
            "helper.not_registered.detail"
        case .enabled:
            "helper.enabled.detail"
        case .requiresApproval:
            "helper.requires_approval.detail"
        case .notFound:
            "helper.not_found.detail"
        case .failed:
            "helper.failed.detail"
        }
    }

    var isReadyForWrites: Bool {
        if case .enabled = self {
            return true
        }
        return false
    }

    var failureReason: String? {
        if case let .failed(message) = self {
            return message
        }
        return nil
    }
}

struct PrivilegedHelperDiagnostics: Equatable, Sendable {
    var bundlePath: String
    var teamIdentifier: String?
    var isInstalledInApplications: Bool
    var helperToolEmbedded: Bool
    var launchDaemonEmbedded: Bool
    var registeredProgramPath: String? = nil

    static let empty = PrivilegedHelperDiagnostics(
        bundlePath: "",
        teamIdentifier: nil,
        isInstalledInApplications: false,
        helperToolEmbedded: false,
        launchDaemonEmbedded: false,
        registeredProgramPath: nil
    )

    var isReadyForReleaseRegistration: Bool {
        isInstalledInApplications && teamIdentifier != nil && helperToolEmbedded && launchDaemonEmbedded
    }

    var expectedHelperProgramPath: String {
        guard !bundlePath.isEmpty else { return "" }
        return bundlePath + "/Contents/Library/PrivilegedHelperTools/AeroPulsePrivilegedHelper"
    }

    var hasRegistrationPathMismatch: Bool {
        guard let registeredProgramPath, !expectedHelperProgramPath.isEmpty else {
            return false
        }

        return registeredProgramPath != expectedHelperProgramPath
    }
}

enum HelperSetupStepState: Sendable {
    case complete
    case actionRequired
    case pendingApproval

    var titleKey: String {
        switch self {
        case .complete:
            "helper.check.state.complete"
        case .actionRequired:
            "helper.check.state.action"
        case .pendingApproval:
            "helper.check.state.pending"
        }
    }
}

struct HelperSetupCheckpoint: Identifiable, Sendable {
    let id: String
    let titleKey: String
    let detailKey: String
    let state: HelperSetupStepState
}

enum QuitPreparationStage: Sendable {
    case idle
    case restoringFans
    case closingConnections
    case finalizing

    var detailKey: String {
        switch self {
        case .idle:
            "quit.banner.body"
        case .restoringFans:
            "quit.banner.progress.restore"
        case .closingConnections:
            "quit.banner.progress.connections"
        case .finalizing:
            "quit.banner.progress.finalize"
        }
    }
}

extension Collection where Element == TemperatureSensor {
    func sensor(matching key: String?) -> TemperatureSensor? {
        guard let key else { return nil }
        return first(where: { $0.key == key })
    }

    func hottestSensor() -> TemperatureSensor? {
        self.max(by: { $0.celsius < $1.celsius })
    }

    func average(containing token: String) -> Double? {
        let matches = filter { $0.name.localizedCaseInsensitiveContains(token) }
        guard !matches.isEmpty else { return nil }
        return matches.map(\.celsius).reduce(0, +) / Double(matches.count)
    }

    func dashboardSummary() -> DashboardSummary {
        DashboardSummary(
            cpuAverage: average(containing: "CPU"),
            gpuAverage: average(containing: "GPU"),
            batteryAverage: average(containing: "Battery"),
            hottest: hottestSensor()
        )
    }
}

extension ControlProfile {
    var sortedCurve: [CurvePoint] {
        curve.sorted { $0.temperature < $1.temperature }
    }

    var temperatureRiseAlpha: Double {
        switch presetID {
        case .macDefault, .maxCooling:
            1.0
        case .performanceLight:
            0.62
        case .performanceMedium:
            0.74
        case .performanceStrong:
            0.88
        }
    }

    var temperatureFallAlpha: Double {
        switch presetID {
        case .macDefault, .maxCooling:
            1.0
        case .performanceLight:
            0.18
        case .performanceMedium:
            0.24
        case .performanceStrong:
            0.3
        }
    }

    var rampUpRPMPerSecond: Double {
        switch presetID {
        case .macDefault:
            2400
        case .performanceLight:
            2000
        case .performanceMedium:
            2800
        case .performanceStrong:
            3600
        case .maxCooling:
            12000
        }
    }

    var rampDownRPMPerSecond: Double {
        switch presetID {
        case .macDefault:
            1200
        case .performanceLight:
            700
        case .performanceMedium:
            1000
        case .performanceStrong:
            1300
        case .maxCooling:
            12000
        }
    }

    var rpmQuantizationStep: Int {
        switch presetID {
        case .macDefault, .maxCooling:
            100
        case .performanceLight, .performanceMedium, .performanceStrong:
            200
        }
    }

    var minimumMeaningfulRPMDelta: Int {
        switch presetID {
        case .macDefault:
            200
        case .performanceLight:
            350
        case .performanceMedium:
            300
        case .performanceStrong:
            250
        case .maxCooling:
            0
        }
    }

    func filteredTemperature(previous: Double?, current: Double) -> Double {
        guard let previous else { return current }
        let alpha = current >= previous ? temperatureRiseAlpha : temperatureFallAlpha
        return previous + (current - previous) * alpha
    }

    func rampedManualRPM(from currentRPM: Int?, toward targetRPM: Int, elapsed: TimeInterval) -> Int {
        guard let currentRPM else {
            return quantizedRPM(targetRPM)
        }

        let safeElapsed = min(max(elapsed, 0.35), 1.0)
        let maxUpDelta = max(rpmQuantizationStep, Int((rampUpRPMPerSecond * safeElapsed).rounded()))
        let maxDownDelta = max(rpmQuantizationStep, Int((rampDownRPMPerSecond * safeElapsed).rounded()))

        if targetRPM > currentRPM {
            return quantizedRPM(min(targetRPM, currentRPM + maxUpDelta))
        }

        if targetRPM < currentRPM {
            return quantizedRPM(max(targetRPM, currentRPM - maxDownDelta))
        }

        return quantizedRPM(targetRPM)
    }

    func quantizedRPM(_ rpm: Int) -> Int {
        let step = max(rpmQuantizationStep, 1)
        let rounded = Double(rpm) / Double(step)
        return Int(rounded.rounded()) * step
    }

    func shouldHoldManualRPMTransition(from currentRPM: Int?, to targetRPM: Int, elapsed: TimeInterval) -> Bool {
        guard let currentRPM else { return false }
        guard elapsed < minimumHoldSeconds else { return false }
        return abs(targetRPM - currentRPM) < minimumMeaningfulRPMDelta
    }

    func evaluate(temperature: Double) -> AutomationDecision {
        switch strategy {
        case .systemDefault:
            return .auto
        case .maximumCooling:
            return .manual(rpm: .max)
        case .curve:
            break
        }

        let points = sortedCurve
        guard let first = points.first, let last = points.last else {
            return .auto
        }

        if temperature < first.temperature - hysteresis {
            return .auto
        }

        if temperature < first.temperature {
            return .manual(rpm: first.rpm)
        }

        if temperature >= last.temperature {
            return .manual(rpm: last.rpm)
        }

        for index in 0..<(points.count - 1) {
            let lower = points[index]
            let upper = points[index + 1]
            guard temperature >= lower.temperature, temperature < upper.temperature else {
                continue
            }

            if upper.temperature <= lower.temperature {
                return .manual(rpm: max(lower.rpm, upper.rpm))
            }

            let ratio = (temperature - lower.temperature) / (upper.temperature - lower.temperature)
            let interpolated = Double(lower.rpm) + ratio * Double(upper.rpm - lower.rpm)
            return .manual(rpm: Int(interpolated.rounded()))
        }

        return .auto
    }
}
