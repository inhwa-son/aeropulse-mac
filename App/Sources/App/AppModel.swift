import AppKit
import Dispatch
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var settings: AppSettings = .default
    var selectedTab: AppTab = .dashboard
    var sensors: [TemperatureSensor] = []
    var fans: [FanSnapshot] = []
    var summary: DashboardSummary = .empty
    var automationSnapshot = AutomationSnapshot(
        decision: .auto,
        sensor: nil,
        reason: "Idle",
        timestamp: .now,
        controlTemperature: nil,
        controlDetail: nil
    )
    var integrationState: IntegrationState = .failed("Booting")
    var fanWriteBackendState: FanWriteBackendState = .booting
    var privilegedHelperStatus: PrivilegedHelperStatus = .notRegistered
    var privilegedHelperGuidance: [String] = []
    var privilegedHelperDiagnostics: PrivilegedHelperDiagnostics = .empty
    var privilegedHelperDoctorReport: String = ""
    var isRefreshing = false
    var isQuitBannerPresented = false
    var isPreparingToQuit = false
    var quitPreparationStage: QuitPreparationStage = .idle
    var lastErrorMessage: String?
    var lastNoticeMessage: String?

    private let configStore: ConfigurationStore
    private let privilegedHelperManager = PrivilegedHelperManager()
    private let privilegedFanControlClient = PrivilegedFanControlClient()
    private let fallbackFanCLI: FanCLIService
    private let smcFanReader = SMCFanReader()
    private let iSMCReader: ISMCReader
    private let hidService: HIDTemperatureService?

    let automationEngine = AutomationEngine()

    private var refreshTask: Task<Void, Never>?
    private var refreshRequestTask: Task<Void, Never>?
    private var lastDetailedSensorRefreshAt: Date = .distantPast

    var isSensorDataStale: Bool {
        let elapsed = Date().timeIntervalSince(lastDetailedSensorRefreshAt)
        let threshold = max(30.0, settings.pollingInterval * 10.0)
        return elapsed >= threshold
    }
    private var lastFanRefreshAt: Date = .distantPast
    private var lastWriteBackendProbeAt: Date = .distantPast
    private var cachedDetailedSensors: [TemperatureSensor] = []
    private var xpcRetryAfter: Date = .distantPast
    private var settingsSaveTask: Task<Void, Never>?
    private var helperSigningInfoTask: Task<Void, Never>?
    private var helperAutoRecoveryTask: Task<Void, Never>?
    private var pendingForcedRefresh = false
    private(set) var hasLoadedSettings = false
    private(set) var hasPreparedForTermination = false
    private var lastAutomaticHelperRegistrationAttemptAt: Date = .distantPast
    private var thermalStateObserver: NSObjectProtocol?
    private var powerStateObserver: NSObjectProtocol?
    private var workspaceWillSleepObserver: NSObjectProtocol?
    private var workspaceDidWakeObserver: NSObjectProtocol?
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var observedThermalState = ProcessInfo.processInfo.thermalState
    private var isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var memoryPressureState: RuntimePressureState = .normal
    private let requestRetryCooldownSeconds = 15.0
    private let inactiveIdlePollingFloorSeconds = 8.0
    private let safeQuitTimeoutSeconds = 2.5
    private let automaticHelperRegistrationCooldownSeconds = 12.0
    private let compatibilityFanCLIPaths = [
        "/Applications/FanControl.app/Contents/MacOS/fan",
        "/Applications/Macs Fan Control.app/Contents/MacOS/fan"
    ]
    private let compatibilityISMCPaths = [
        "/Applications/FanControl.app/Contents/Resources/iSMC",
        "/Applications/Macs Fan Control.app/Contents/Resources/iSMC"
    ]

    init(
        runner: CommandRunning = ProcessCommandRunner(),
        hidService: HIDTemperatureService? = HIDTemperatureService(),
        configStore: ConfigurationStore = ConfigurationStore()
    ) {
        self.configStore = configStore
        fallbackFanCLI = FanCLIService(runner: runner)
        iSMCReader = ISMCReader(runner: runner)
        self.hidService = hidService
        automationEngine.attach(to: self)

        guard !Self.isRunningUnderTests, currentAppCommand == nil else {
            return
        }

        refreshTask = Task { [weak self] in
            await self?.bootstrap()
        }
    }

    func bootstrap() async {
        let loadedConfiguration = await configStore.load()
        settings = loadedConfiguration.settings
        migrateLegacyCompatibilityDefaultsIfNeeded()
        enforceSettingsInvariants()
        AppLocalization.setLanguage(settings.language)
        applyConfigurationRecoveryNotice(loadedConfiguration.source)
        startRuntimeObserversIfNeeded()
        refreshPrivilegedHelperState()
        refreshPrivilegedHelperSigningInfo(force: true)
        hasLoadedSettings = true
        scheduleAutomaticHelperRecovery(force: true)
        startRefreshLoop()
    }

    func startRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await refreshOnce()
                let interval = effectivePollingInterval()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func requestRefresh(forceDetailed: Bool = false) {
        if forceDetailed {
            pendingForcedRefresh = true
        }

        guard refreshRequestTask == nil else { return }
        refreshRequestTask = Task { [weak self] in
            await self?.drainRefreshRequests()
        }
    }

    private func drainRefreshRequests() async {
        defer { refreshRequestTask = nil }

        while true {
            let forceDetailed = pendingForcedRefresh
            pendingForcedRefresh = false
            await refreshOnce(forceDetailed: forceDetailed)

            if !pendingForcedRefresh {
                break
            }
        }
    }

    func refreshOnce(forceDetailed: Bool = false) async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            enforceSettingsInvariants()
            let now = Date()
            let isInteractiveRefresh = settings.automationEnabled || NSApp.isActive
            let fallbackFanCLIPath = fanCLIPath()
            let resolvedISMCPath = resolvedISMCPath()
            let fanCLIFallbackAvailable = fallbackFanCLIPath != nil
            let richSensorAvailable = resolvedISMCPath != nil
            let detailedSensorRefreshInterval = detailedSensorRefreshInterval(isInteractive: isInteractiveRefresh)
            let fanRefreshInterval = fanRefreshInterval(isInteractive: isInteractiveRefresh)
            let helperRefreshInterval = helperRefreshInterval(isInteractive: isInteractiveRefresh)

            var liveSensors: [TemperatureSensor] = []
            if !richSensorAvailable, let hidService {
                liveSensors = await Task.detached { hidService.readSensors() }.value
            }

            if richSensorAvailable,
               forceDetailed || cachedDetailedSensors.isEmpty || now.timeIntervalSince(lastDetailedSensorRefreshAt) >= detailedSensorRefreshInterval {
                do {
                    if let ismcPath = resolvedISMCPath {
                        cachedDetailedSensors = try await iSMCReader.readTemperatures(executablePath: ismcPath)
                    }
                    lastDetailedSensorRefreshAt = now
                } catch {
                    lastErrorMessage = error.localizedDescription
                }
            }

            let nextSensors = cachedDetailedSensors.isEmpty ? liveSensors : cachedDetailedSensors
            if nextSensors != sensors {
                sensors = nextSensors
            }

            let nextSummary = sensors.dashboardSummary()
            if nextSummary.cpuAverage != summary.cpuAverage ||
                nextSummary.gpuAverage != summary.gpuAverage ||
                nextSummary.batteryAverage != summary.batteryAverage ||
                nextSummary.hottest != summary.hottest {
                summary = nextSummary
            }

            if forceDetailed || fans.isEmpty || now.timeIntervalSince(lastFanRefreshAt) >= fanRefreshInterval {
                let nextFans = try await listFans()
                if nextFans != fans {
                    fans = nextFans
                }
                lastFanRefreshAt = now
            }

            if forceDetailed || fanWriteBackendState == .booting || now.timeIntervalSince(lastWriteBackendProbeAt) >= helperRefreshInterval {
                refreshPrivilegedHelperState()
            }

            scheduleAutomaticHelperRecovery()

            let sensorCatalogAvailable = !nextSensors.isEmpty

            if privilegedHelperStatus.isReadyForWrites || fanCLIFallbackAvailable {
                integrationState = sensorCatalogAvailable ? .ready : .missingISMC
                await probeWriteBackendIfNeeded(
                    now: now,
                    force: forceDetailed,
                    fallbackFanCLIPath: fallbackFanCLIPath
                )
            } else if privilegedHelperStatus == .requiresApproval {
                integrationState = .awaitingApproval
                fanWriteBackendState = .awaitingApproval
            } else {
                integrationState = .missingFanCLI
                fanWriteBackendState = .unavailable
            }

            if settings.automationEnabled {
                await automationEngine.runAutomationIfNeeded()
            } else {
                automationEngine.resetSmoothingState()
                automationSnapshot = AutomationSnapshot(
                    decision: .auto,
                    sensor: selectedSensor(),
                    reason: String.tr("automation.reason.disabled"),
                    timestamp: .now,
                    controlTemperature: nil,
                    controlDetail: nil
                )
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            integrationState = .failed(error.localizedDescription)
        }
    }

    func saveConfiguration() {
        AppLocalization.setLanguage(settings.language)
        let snapshot = settingsSnapshotForPersistence()
        Task {
            do {
                try await configStore.save(snapshot)
            } catch {
                await MainActor.run {
                    self.lastErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func migrateLegacyCompatibilityDefaultsIfNeeded() {
        var didChange = false

        if settings.fanExecutablePath == AppSettings.legacyCompatibilityFanPath {
            settings.fanExecutablePath = ""
            didChange = true
        }

        if settings.iSMCExecutablePath == AppSettings.legacyCompatibilityISMCPath {
            settings.iSMCExecutablePath = ""
            didChange = true
        }

        if didChange {
            saveConfiguration()
        }
    }

    func scheduleConfigurationSave() {
        guard hasLoadedSettings else { return }
        AppLocalization.setLanguage(settings.language)
        let snapshot = settingsSnapshotForPersistence()
        settingsSaveTask?.cancel()
        settingsSaveTask = Task { [configStore] in
            do {
                try await Task.sleep(for: .milliseconds(350))
                try await configStore.save(snapshot)
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    self.lastErrorMessage = error.localizedDescription
                }
            }

            await MainActor.run {
                self.settingsSaveTask = nil
            }
        }
    }

    var availablePresets: [ProfilePresetID] {
        ProfilePresetID.allCases
    }

    func applyPreset(_ presetID: ProfilePresetID, persist: Bool = true, forceCanonicalReset: Bool = false) {
        synchronizeCurrentPresetCustomization()

        if presetID == settings.selectedPresetID,
           isSelectedPresetCustomized,
           !forceCanonicalReset {
            if persist {
                saveConfiguration()
            }
            return
        }

        settings.selectedPresetID = presetID
        if forceCanonicalReset {
            settings.customProfiles.removeValue(forKey: presetID)
            settings.profile = canonicalProfile(for: presetID)
        } else {
            settings.profile = storedOrCanonicalProfile(for: presetID)
        }
        automationEngine.resetState()

        if persist {
            saveConfiguration()
        }

        if settings.automationEnabled {
            requestRefresh(forceDetailed: true)
        }
    }

    func activatePreset(_ presetID: ProfilePresetID) async {
        applyPreset(presetID, persist: false)
        settings.automationEnabled = true
        saveConfiguration()
        requestRefresh(forceDetailed: true)
    }

    func selectedSensor() -> TemperatureSensor? {
        resolveSensor(for: settings.profile.sensorSelection)
    }

    var isSelectedPresetCustomized: Bool {
        settings.profile != canonicalProfile(for: settings.selectedPresetID)
    }

    var selectedProfileDisplayName: String {
        let base = String.tr(settings.selectedPresetID.titleKey)
        guard isSelectedPresetCustomized else { return base }
        return "\(base) (\(String.tr("profile.custom_suffix")))"
    }

    var automationControlLabelKey: String {
        settings.automationEnabled ? "automation.control_input" : "automation.sensor"
    }

    var automationControlSummary: String {
        guard settings.automationEnabled else {
            if let sensor = selectedSensor() {
                return "\(sensor.name) \(String(format: "%.1f", sensor.celsius))°C"
            }
            return String.tr("automation.reason.no_sensor")
        }

        guard let controlTemperature = automationSnapshot.controlTemperature else {
            if let sensor = selectedSensor() {
                return "\(sensor.name) \(String(format: "%.1f", sensor.celsius))°C"
            }
            return String.tr("automation.reason.no_sensor")
        }

        let detail = automationSnapshot.controlDetail ?? String.tr("automation.control_detail.raw")
        return "\(detail) \(String(format: "%.1f", controlTemperature))°C"
    }

    func menuBarSensor() -> TemperatureSensor? {
        resolveSensor(for: settings.menuBarSensorSelection)
            ?? hottestCPUSensor()
            ?? summary.hottest
    }

    func menuBarFanRPM() -> Int? {
        let configured = settings.profile.fanIDs
        let targetFanIDs = configured.isEmpty ? fans.map(\.id) : fans.map(\.id).filter { configured.contains($0) }
        let activeFans = fans.filter { targetFanIDs.contains($0.id) }
        let currentRPMs = activeFans.map(\.currentRPM).filter { $0 > 0 }
        guard !currentRPMs.isEmpty else { return nil }
        let average = currentRPMs.reduce(0, +) / currentRPMs.count
        return average
    }

    func isQuickProfileSelected(_ presetID: ProfilePresetID) -> Bool {
        settings.selectedPresetID == presetID
    }

    func showTab(_ tab: AppTab) {
        selectedTab = tab
        NSApp.activate()
        NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
    }

    func toggleAutomationFromMenuBar() async {
        settings.automationEnabled.toggle()
        saveConfiguration()
        requestRefresh(forceDetailed: true)
    }

    var preferredLocale: Locale {
        if let identifier = settings.language.localeIdentifier {
            return Locale(identifier: identifier)
        }
        return .autoupdatingCurrent
    }

    func toggleFanSelection(_ fanID: Int, enabled: Bool) {
        if enabled {
            if !settings.profile.fanIDs.contains(fanID) {
                settings.profile.fanIDs.append(fanID)
                settings.profile.fanIDs.sort()
            }
        } else {
            if settings.profile.fanIDs.count <= 1, settings.profile.fanIDs.contains(fanID) {
                lastNoticeMessage = String.tr("automation.fans.minimum_one")
                return
            }
            settings.profile.fanIDs.removeAll { $0 == fanID }
        }

        persistAutomationConfiguration()
    }

    func addCurvePoint() {
        let lastPoint = settings.profile.sortedCurve.last
        let nextTemperature = min((lastPoint?.temperature ?? 45) + 5, 100)
        let nextRPM = min((lastPoint?.rpm ?? 2200) + 400, 7800)
        settings.profile.curve.append(CurvePoint(temperature: nextTemperature, rpm: nextRPM))
        persistAutomationConfiguration()
    }

    func removeCurvePoint(_ pointID: UUID) {
        settings.profile.curve.removeAll { $0.id == pointID }
        if settings.profile.curve.isEmpty {
            settings.profile.curve = ControlProfile.preset(settings.selectedPresetID).curve
        }
        persistAutomationConfiguration()
    }

    func resetProfile() {
        applyPreset(settings.selectedPresetID, forceCanonicalReset: true)
    }

    func persistAutomationConfiguration(refresh: Bool = true) {
        synchronizeCurrentPresetCustomization()
        scheduleConfigurationSave()
        guard refresh, settings.automationEnabled else { return }
        requestRefresh(forceDetailed: true)
    }

    func registerPrivilegedHelper() async {
        do {
            settings.helperAutoRegistrationEnabled = true
            privilegedHelperStatus = try privilegedHelperManager.register()
            refreshPrivilegedHelperState()
            fanWriteBackendState = .booting
            scheduleConfigurationSave()
            requestRefresh(forceDetailed: true)
        } catch {
            privilegedHelperStatus = .failed(error.localizedDescription)
            refreshPrivilegedHelperState()
            lastErrorMessage = error.localizedDescription
        }
    }

    func unregisterPrivilegedHelper() async {
        do {
            settings.helperAutoRegistrationEnabled = false
            privilegedHelperStatus = try privilegedHelperManager.unregister()
            refreshPrivilegedHelperState()
            fanWriteBackendState = .booting
            scheduleConfigurationSave()
            requestRefresh(forceDetailed: true)
        } catch {
            privilegedHelperStatus = .failed(error.localizedDescription)
            refreshPrivilegedHelperState()
            lastErrorMessage = error.localizedDescription
        }
    }

    func prepareForTermination() async {
        guard !hasPreparedForTermination else { return }
        hasPreparedForTermination = true
        isPreparingToQuit = true
        quitPreparationStage = .restoringFans
        let persistedSettings = settings
        settings.automationEnabled = false
        settingsSaveTask?.cancel()
        settingsSaveTask = nil
        refreshTask?.cancel()
        refreshRequestTask?.cancel()
        helperSigningInfoTask?.cancel()
        helperAutoRecoveryTask?.cancel()

        if let thermalStateObserver { NotificationCenter.default.removeObserver(thermalStateObserver) }
        if let powerStateObserver { NotificationCenter.default.removeObserver(powerStateObserver) }
        if let workspaceWillSleepObserver { NotificationCenter.default.removeObserver(workspaceWillSleepObserver) }
        if let workspaceDidWakeObserver { NotificationCenter.default.removeObserver(workspaceDidWakeObserver) }
        thermalStateObserver = nil
        powerStateObserver = nil
        workspaceWillSleepObserver = nil
        workspaceDidWakeObserver = nil
        memoryPressureSource?.cancel()
        memoryPressureSource = nil

        let targetFanIDs = await terminationFanIDs()
        guard !targetFanIDs.isEmpty else {
            quitPreparationStage = .closingConnections
            await privilegedFanControlClient.shutdown()
            quitPreparationStage = .finalizing
            await flushConfigurationNow(snapshot: persistedSettings)
            isPreparingToQuit = false
            return
        }

        do {
            try await runWithTimeout(seconds: safeQuitTimeoutSeconds) {
                try await self.setFansAuto(targetFanIDs)
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        quitPreparationStage = .closingConnections
        await privilegedFanControlClient.shutdown()
        quitPreparationStage = .finalizing
        await flushConfigurationNow(snapshot: persistedSettings)
        isPreparingToQuit = false
    }

    private func terminationFanIDs() async -> [Int] {
        let knownIDs = fans.map(\.id)
        if !knownIDs.isEmpty {
            return knownIDs
        }

        if privilegedHelperStatus.isReadyForWrites {
            if let helperIDs = try? await privilegedFanControlClient.readFans(previousSnapshots: fans).map(\.id),
               !helperIDs.isEmpty {
                return helperIDs
            }
        }

        if let readerIDs = try? await Task.detached { try SMCFanReader().readFans().map(\.id) }.value, !readerIDs.isEmpty {
            return readerIDs
        }

        return []
    }

    func presentQuitBanner() {
        isQuitBannerPresented = true
    }

    func dismissQuitBanner() {
        guard !isPreparingToQuit else { return }
        isQuitBannerPresented = false
    }

    func requestSafeQuit() {
        isQuitBannerPresented = true
    }

    func confirmSafeQuit() {
        isQuitBannerPresented = false
        NSApp.terminate(nil)
    }

    var shouldShowHelperApprovalBanner: Bool {
        privilegedHelperStatus == .requiresApproval
    }

    var quitBannerDetail: String {
        String.tr(quitPreparationStage.detailKey)
    }

    func revealCurrentAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func openApplicationsFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
    }

    func openLoginItemsSettings() {
        privilegedHelperManager.openLoginItemsSettings()
    }

    func installCurrentAppToApplications() {
        installCurrentAppToApplications(relaunchInstalledCopy: false)
    }

    func installAndRelaunchFromApplications() {
        installCurrentAppToApplications(relaunchInstalledCopy: true)
    }

    var privilegedHelperChecklist: [HelperSetupCheckpoint] {
        [
            HelperSetupCheckpoint(
                id: "install",
                titleKey: "helper.check.install.title",
                detailKey: "helper.check.install.detail",
                state: privilegedHelperDiagnostics.isInstalledInApplications ? .complete : .actionRequired
            ),
            HelperSetupCheckpoint(
                id: "signature",
                titleKey: "helper.check.signature.title",
                detailKey: "helper.check.signature.detail",
                state: privilegedHelperDiagnostics.teamIdentifier == nil ? .actionRequired : .complete
            ),
            HelperSetupCheckpoint(
                id: "payload",
                titleKey: "helper.check.payload.title",
                detailKey: "helper.check.payload.detail",
                state: privilegedHelperDiagnostics.helperToolEmbedded && privilegedHelperDiagnostics.launchDaemonEmbedded ? .complete : .actionRequired
            ),
            HelperSetupCheckpoint(
                id: "approval",
                titleKey: "helper.check.approval.title",
                detailKey: "helper.check.approval.detail",
                state: helperApprovalState
            )
        ]
    }

    private var helperApprovalState: HelperSetupStepState {
        switch privilegedHelperStatus {
        case .enabled:
            .complete
        case .requiresApproval:
            .pendingApproval
        case .unsupported:
            .actionRequired
        case .notRegistered, .notFound, .failed:
            .actionRequired
        }
    }

    private func installCurrentAppToApplications(relaunchInstalledCopy: Bool) {
        let sourceURL = Bundle.main.bundleURL.standardizedFileURL
        let destinationURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
            .appendingPathComponent(sourceURL.lastPathComponent, isDirectory: true)

        do {
            if sourceURL == destinationURL {
                if relaunchInstalledCopy {
                    relaunchInstalledApp(at: destinationURL)
                } else {
                    NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
                    lastNoticeMessage = String.tr("settings.privileged_helper.install_already")
                }
                return
            }

            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destinationURL.path) {
                _ = try fileManager.replaceItemAt(destinationURL, withItemAt: sourceURL)
            } else {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            }

            if relaunchInstalledCopy {
                relaunchInstalledApp(at: destinationURL)
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
                lastNoticeMessage = String.tr("settings.privileged_helper.install_success")
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func runPrivilegedHelperDoctor() {
        refreshPrivilegedHelperState()
        privilegedHelperDoctorReport = makePrivilegedHelperDoctorReport()
        lastNoticeMessage = String.tr("settings.privileged_helper.doctor_refreshed")
    }

    func copyPrivilegedHelperDiagnostics() {
        let diagnostics = privilegedHelperDiagnostics
        let helperStatus = String.tr(privilegedHelperStatus.titleKey)
        let backendStatus = String.tr(fanWriteBackendState.titleKey)
        let guidance = privilegedHelperGuidance.isEmpty ? "none" : privilegedHelperGuidance.joined(separator: "\n- ")
        let payload = """
        AeroPulse Helper Diagnostics
        Helper Status: \(helperStatus)
        Fan Backend: \(backendStatus)
        Bundle Path: \(diagnostics.bundlePath)
        Team ID: \(diagnostics.teamIdentifier ?? "Unsigned")
        Install State: \(diagnostics.isInstalledInApplications ? "/Applications" : "Outside /Applications")
        Helper Tool: \(diagnostics.helperToolEmbedded ? "Embedded" : "Missing")
        LaunchDaemon: \(diagnostics.launchDaemonEmbedded ? "Embedded" : "Missing")
        Release Readiness: \(diagnostics.isReadyForReleaseRegistration ? "Ready" : "Needs Work")
        Guidance:
        - \(guidance)
        """

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(payload, forType: .string)
        lastNoticeMessage = String.tr("settings.privileged_helper.diagnostics_copied")
    }

    func copyPrivilegedHelperDoctorReport() {
        let report = privilegedHelperDoctorReport.isEmpty ? makePrivilegedHelperDoctorReport() : privilegedHelperDoctorReport
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report, forType: .string)
        privilegedHelperDoctorReport = report
        lastNoticeMessage = String.tr("settings.privileged_helper.doctor_copied")
    }

    func restoreFansToAutoIfNeeded() async {
        let fanIDsNeedingRestore = failsafeAutoRestoreFanIDs()
        guard !fanIDsNeedingRestore.isEmpty else { return }

        do {
            try await setFansAuto(fanIDsNeedingRestore)
            await refreshFanSnapshotsFromSMCIfPossible()
        } catch {
            recordBackendIssue(error, fallbackAvailable: fanCLIPath() != nil)
        }

        automationEngine.resetState()
    }

    private func refreshPrivilegedHelperState() {
        let previousDiagnostics = privilegedHelperDiagnostics
        let nextStatus = privilegedHelperManager.status()
        var nextDiagnostics = privilegedHelperManager.fastDiagnostics()
        nextDiagnostics.teamIdentifier = previousDiagnostics.teamIdentifier
        let nextGuidance = privilegedHelperManager.preflightNotes(for: nextDiagnostics)

        let didChange =
            nextStatus != privilegedHelperStatus ||
            nextDiagnostics != privilegedHelperDiagnostics ||
            nextGuidance != privilegedHelperGuidance

        privilegedHelperStatus = nextStatus
        privilegedHelperDiagnostics = nextDiagnostics
        privilegedHelperGuidance = nextGuidance

        if didChange || privilegedHelperDoctorReport.isEmpty {
            privilegedHelperDoctorReport = makePrivilegedHelperDoctorReport()
        }

        if nextDiagnostics.teamIdentifier == nil || nextDiagnostics.bundlePath != previousDiagnostics.bundlePath {
            refreshPrivilegedHelperSigningInfo()
        }
    }

    private func refreshPrivilegedHelperSigningInfo(force: Bool = false) {
        if !force, helperSigningInfoTask != nil {
            return
        }

        let expectedBundlePath = Bundle.main.bundleURL.path
        helperSigningInfoTask?.cancel()
        helperSigningInfoTask = Task { [weak self] in
            guard let self else { return }
            let teamIdentifier = await privilegedHelperManager.loadTeamIdentifier()
            guard !Task.isCancelled else { return }
            guard expectedBundlePath == privilegedHelperDiagnostics.bundlePath else { return }

            helperSigningInfoTask = nil

            if privilegedHelperDiagnostics.teamIdentifier != teamIdentifier {
                privilegedHelperDiagnostics.teamIdentifier = teamIdentifier
                privilegedHelperGuidance = privilegedHelperManager.preflightNotes(for: privilegedHelperDiagnostics)
                privilegedHelperDoctorReport = makePrivilegedHelperDoctorReport()
            }
        }
    }

    private func scheduleAutomaticHelperRecovery(force: Bool = false) {
        guard currentAppCommand == nil else { return }
        guard settings.helperAutoRegistrationEnabled else { return }
        guard privilegedHelperDiagnostics.isReadyForReleaseRegistration else { return }
        guard privilegedHelperDiagnostics.isInstalledInApplications else { return }

        let now = Date()
        if !force,
           now.timeIntervalSince(lastAutomaticHelperRegistrationAttemptAt) < automaticHelperRegistrationCooldownSeconds {
            return
        }

        switch privilegedHelperStatus {
        case .notRegistered, .requiresApproval:
            break
        case .enabled, .notFound, .unsupported, .failed:
            return
        }

        if helperAutoRecoveryTask != nil {
            return
        }

        lastAutomaticHelperRegistrationAttemptAt = now
        helperAutoRecoveryTask = Task { [weak self] in
            guard let self else { return }
            defer { helperAutoRecoveryTask = nil }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await attemptAutomaticHelperRegistration()
        }
    }

    private func attemptAutomaticHelperRegistration() async {
        guard settings.helperAutoRegistrationEnabled else { return }

        do {
            let registeredStatus = try privilegedHelperManager.register()
            privilegedHelperStatus = registeredStatus
            refreshPrivilegedHelperState()
            fanWriteBackendState = .booting

            if registeredStatus == .enabled {
                lastNoticeMessage = String.tr("settings.privileged_helper.install_success")
            }
        } catch {
            privilegedHelperStatus = .failed(error.localizedDescription)
            refreshPrivilegedHelperState()
        }
    }

    private func relaunchInstalledApp(at appURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.lastErrorMessage = error.localizedDescription
                    return
                }

                self.lastNoticeMessage = String.tr("settings.privileged_helper.relaunch_success")
                NSApp.terminate(nil)
            }
        }
    }

    private func makePrivilegedHelperDoctorReport() -> String {
        let diagnostics = privilegedHelperDiagnostics
        let guidance = privilegedHelperGuidance.isEmpty ? ["none"] : privilegedHelperGuidance
        return """
        AeroPulse Release Doctor
        Helper Status: \(String.tr(privilegedHelperStatus.titleKey))
        Fan Backend: \(String.tr(fanWriteBackendState.titleKey))
        Bundle Path: \(diagnostics.bundlePath)
        Team ID: \(diagnostics.teamIdentifier ?? "Unsigned")
        Install State: \(diagnostics.isInstalledInApplications ? "/Applications" : "Outside /Applications")
        Helper Tool: \(diagnostics.helperToolEmbedded ? "Embedded" : "Missing")
        LaunchDaemon: \(diagnostics.launchDaemonEmbedded ? "Embedded" : "Missing")
        Release Readiness: \(diagnostics.isReadyForReleaseRegistration ? "Ready" : "Needs Work")

        Suggested Next Step:
        \(suggestedReleaseStep(for: diagnostics))

        Guidance:
        - \(guidance.joined(separator: "\n- "))
        """
    }

    private func suggestedReleaseStep(for diagnostics: PrivilegedHelperDiagnostics) -> String {
        if !diagnostics.isInstalledInApplications {
            return String.tr("settings.privileged_helper.doctor_step.install")
        }

        if diagnostics.teamIdentifier == nil {
            return String.tr("settings.privileged_helper.doctor_step.sign")
        }

        if !diagnostics.helperToolEmbedded || !diagnostics.launchDaemonEmbedded {
            return String.tr("settings.privileged_helper.doctor_step.rebuild")
        }

        return String.tr("settings.privileged_helper.doctor_step.login_items")
    }

    private func activeFanIDs() -> [Int] {
        automationEngine.activeFanIDs()
    }

    private func failsafeAutoRestoreFanIDs() -> [Int] {
        let active = activeFanIDs()
        if !active.isEmpty {
            return active
        }

        let configured = settings.profile.fanIDs
        if !configured.isEmpty {
            return configured
        }

        let manualFanIDs = fans.filter { $0.mode == .manual }.map(\.id)
        if !manualFanIDs.isEmpty {
            return manualFanIDs
        }

        return fans.map(\.id)
    }

    private func startRuntimeObserversIfNeeded() {
        guard thermalStateObserver == nil,
              powerStateObserver == nil,
              workspaceWillSleepObserver == nil,
              workspaceDidWakeObserver == nil,
              memoryPressureSource == nil else {
            return
        }

        let notificationCenter = NotificationCenter.default
        let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
        thermalStateObserver = notificationCenter.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                observedThermalState = ProcessInfo.processInfo.thermalState
                requestRefresh()
            }
        }

        powerStateObserver = notificationCenter.addObserver(
            forName: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
                requestRefresh()
            }
        }

        workspaceWillSleepObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                xpcRetryAfter = .distantPast
                lastWriteBackendProbeAt = .distantPast
                await privilegedFanControlClient.shutdown()
                automationEngine.resetState()
            }
        }

        workspaceDidWakeObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                xpcRetryAfter = .distantPast
                lastDetailedSensorRefreshAt = .distantPast
                lastFanRefreshAt = .distantPast
                lastWriteBackendProbeAt = .distantPast
                await privilegedFanControlClient.shutdown()
                automationEngine.resetState()
                refreshPrivilegedHelperState()
                requestRefresh(forceDetailed: true)
            }
        }

        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let event = source.data
                if event.contains(.critical) {
                    memoryPressureState = .critical
                } else if event.contains(.warning) {
                    memoryPressureState = .warning
                } else {
                    memoryPressureState = .normal
                }

                requestRefresh()
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    func fanStateMatches(
        decision: AutomationDecision,
        fanIDs: [Int],
        snapshots: [FanSnapshot]
    ) -> Bool {
        automationEngine.fanStateMatches(
            decision: decision,
            fanIDs: fanIDs,
            snapshots: snapshots
        )
    }

    private func effectivePollingInterval() -> Double {
        let baseInterval = max(settings.pollingInterval, 0.5)
        guard !settings.automationEnabled, !NSApp.isActive else {
            return max(baseInterval, interactivePollingFloor())
        }

        return max(baseInterval, inactiveIdlePollingFloor())
    }

    private func interactivePollingFloor() -> Double {
        switch memoryPressureState {
        case .critical:
            return settings.automationEnabled ? 2.0 : 3.5
        case .warning:
            return settings.automationEnabled ? 1.8 : 3.0
        case .normal:
            break
        }

        if thermalStateSeverity(observedThermalState) >= 2 {
            return settings.automationEnabled ? 1.8 : 3.0
        }

        if isLowPowerModeEnabled {
            return settings.automationEnabled ? 1.6 : 2.5
        }

        return 0.5
    }

    private func inactiveIdlePollingFloor() -> Double {
        switch memoryPressureState {
        case .critical:
            return 18.0
        case .warning:
            return 12.0
        case .normal:
            break
        }

        if thermalStateSeverity(observedThermalState) >= 2 {
            return 12.0
        }

        if isLowPowerModeEnabled {
            return 10.0
        }

        return inactiveIdlePollingFloorSeconds
    }

    private func detailedSensorRefreshInterval(isInteractive: Bool) -> Double {
        var interval = isInteractive ? 2.0 : 15.0

        switch memoryPressureState {
        case .critical:
            interval = max(interval, isInteractive ? 4.0 : 24.0)
        case .warning:
            interval = max(interval, isInteractive ? 3.0 : 18.0)
        case .normal:
            break
        }

        if thermalStateSeverity(observedThermalState) >= 2 {
            interval = max(interval, isInteractive ? 2.5 : 18.0)
        }

        if isLowPowerModeEnabled {
            interval = max(interval, isInteractive ? 3.0 : 20.0)
        }

        return interval
    }

    private func fanRefreshInterval(isInteractive: Bool) -> Double {
        var interval = isInteractive ? 3.0 : 10.0

        switch memoryPressureState {
        case .critical:
            interval = max(interval, isInteractive ? 4.5 : 18.0)
        case .warning:
            interval = max(interval, isInteractive ? 3.5 : 14.0)
        case .normal:
            break
        }

        if isLowPowerModeEnabled {
            interval = max(interval, isInteractive ? 3.5 : 12.0)
        }

        return interval
    }

    private func helperRefreshInterval(isInteractive: Bool) -> Double {
        var interval = isInteractive ? 5.0 : 15.0

        if memoryPressureState == .critical {
            interval = max(interval, 20.0)
        } else if memoryPressureState == .warning {
            interval = max(interval, 12.0)
        }

        return interval
    }

    private func thermalStateSeverity(_ state: ProcessInfo.ThermalState) -> Int {
        switch state {
        case .nominal: 0
        case .fair: 1
        case .serious: 2
        case .critical: 3
        @unknown default: 1
        }
    }

    // MARK: - Forwarding to AutomationEngine (test compatibility)

    func emergencySafeguardDecision() -> (decision: AutomationDecision, reason: String?)? {
        automationEngine.emergencySafeguardDecision()
    }

    nonisolated static func interruptionDecision(
        lastAppliedDecision: AutomationDecision?,
        lastHealthyAt: Date,
        now: Date,
        fanIDs: [Int],
        snapshots: [FanSnapshot],
        graceSeconds: Double
    ) -> AutomationDecision? {
        AutomationEngine.interruptionDecision(
            lastAppliedDecision: lastAppliedDecision,
            lastHealthyAt: lastHealthyAt,
            now: now,
            fanIDs: fanIDs,
            snapshots: snapshots,
            graceSeconds: graceSeconds
        )
    }

    nonisolated static func shouldReapplyHeldDecision(
        _ heldDecision: AutomationDecision,
        fanIDs: [Int],
        snapshots: [FanSnapshot],
        writableBackendAvailable: Bool,
        verificationToleranceRPM: Int = 180
    ) -> Bool {
        AutomationEngine.shouldReapplyHeldDecision(
            heldDecision,
            fanIDs: fanIDs,
            snapshots: snapshots,
            writableBackendAvailable: writableBackendAvailable,
            verificationToleranceRPM: verificationToleranceRPM
        )
    }

    nonisolated static func shouldAttemptPrivilegedWrite(
        helperReady: Bool,
        currentBackendState: FanWriteBackendState,
        fallbackAvailable: Bool,
        now: Date,
        retryAfter: Date
    ) -> Bool {
        guard helperReady else { return false }

        if !fallbackAvailable {
            return true
        }

        switch currentBackendState {
        case .privilegedDaemon, .booting:
            return true
        case .fallbackCLI:
            return now >= retryAfter
        case .awaitingApproval, .unavailable:
            return false
        }
    }

    func enforceSettingsInvariants() {
        settings.profile = normalizedProfileMetadata(settings.profile, presetID: settings.selectedPresetID)
        settings.customProfiles = settings.customProfiles.reduce(into: [:]) { result, entry in
            let presetID = entry.key
            guard allowsCustomization(for: presetID) else { return }
            let normalized = normalizedProfileMetadata(entry.value, presetID: presetID)
            let canonical = canonicalProfile(for: presetID)
            guard normalized != canonical else { return }
            result[presetID] = normalized
        }

        let canonicalStaticProfile: ControlProfile?
        switch settings.selectedPresetID {
        case .macDefault, .maxCooling:
            canonicalStaticProfile = ControlProfile.preset(settings.selectedPresetID)
        case .performanceLight, .performanceMedium, .performanceStrong:
            canonicalStaticProfile = nil
        }

        guard let canonicalStaticProfile else { return }
        guard settings.profile != canonicalStaticProfile else { return }
        settings.profile = canonicalStaticProfile
        settings.customProfiles.removeValue(forKey: settings.selectedPresetID)
        if hasLoadedSettings {
            scheduleConfigurationSave()
        }
    }

    private func listFans() async throws -> [FanSnapshot] {
        let reader = smcFanReader
        let previous = fans
        do {
            return try await Task.detached { try reader.readFans(previousSnapshots: previous) }.value
        } catch {
            guard let fallbackFanCLIPath = fanCLIPath() else {
                throw error
            }
            return try await fallbackFanCLI.listFans(executablePath: fallbackFanCLIPath)
        }
    }

    private func probeWriteBackendIfNeeded(
        now: Date,
        force: Bool = false,
        fallbackFanCLIPath: String?
    ) async {
        guard force || fanWriteBackendState == .booting || now.timeIntervalSince(lastWriteBackendProbeAt) >= 10 else {
            return
        }

        lastWriteBackendProbeAt = now

        if privilegedHelperStatus.isReadyForWrites {
            do {
                try await privilegedFanControlClient.probe()
                xpcRetryAfter = .distantPast
                fanWriteBackendState = .privilegedDaemon
                return
            } catch {
                recordBackendIssue(error, fallbackAvailable: fallbackFanCLIPath != nil)
                xpcRetryAfter = Date().addingTimeInterval(requestRetryCooldownSeconds)
                if fallbackFanCLIPath != nil {
                    fanWriteBackendState = .fallbackCLI(reason: error.localizedDescription)
                    return
                }
                fanWriteBackendState = .unavailable
                return
            }
        }

        fanWriteBackendState = fallbackFanCLIPath != nil
            ? .fallbackCLI(reason: fallbackBackendReason())
            : .unavailable
    }

    func setFansAuto(_ fanIDs: [Int]) async throws {
        let allFansSelected = fanIDs.count == fans.count && !fanIDs.isEmpty
        let fallbackFanCLIPath = fanCLIPath()
        let fallbackCLIAvailable = fallbackFanCLIPath != nil

        if Self.shouldAttemptPrivilegedWrite(
            helperReady: privilegedHelperStatus.isReadyForWrites,
            currentBackendState: fanWriteBackendState,
            fallbackAvailable: fallbackCLIAvailable,
            now: Date(),
            retryAfter: xpcRetryAfter
        ) {
            if Date() < xpcRetryAfter, fallbackCLIAvailable {
                if let fallbackFanCLIPath {
                    try await fallbackFanCLI.setAuto(
                        executablePath: fallbackFanCLIPath,
                        fanIDs: fanIDs,
                        allFansSelected: allFansSelected
                    )
                    fanWriteBackendState = .fallbackCLI(reason: "Privileged helper retry cooldown active.")
                    applyLocalAutoState(to: fanIDs)
                    return
                }

                throw PrivilegedFanControlClientError.unavailable("Privileged helper retry cooldown active.")
            }

            do {
                try await privilegedFanControlClient.setAuto(fanIDs: fanIDs)
                xpcRetryAfter = .distantPast
                fanWriteBackendState = .privilegedDaemon
                applyLocalAutoState(to: fanIDs)
                return
            } catch {
                if await verifyPrivilegedAutoWrite(for: fanIDs) {
                    xpcRetryAfter = .distantPast
                    fanWriteBackendState = .privilegedDaemon
                    return
                }
                xpcRetryAfter = Date().addingTimeInterval(requestRetryCooldownSeconds)
                if let fallbackFanCLIPath {
                    recordBackendIssue(error, fallbackAvailable: true)
                    try await fallbackFanCLI.setAuto(
                        executablePath: fallbackFanCLIPath,
                        fanIDs: fanIDs,
                        allFansSelected: allFansSelected
                    )
                    fanWriteBackendState = .fallbackCLI(reason: error.localizedDescription)
                    applyLocalAutoState(to: fanIDs)
                    return
                }
                throw error
            }
        }

        guard let fallbackFanCLIPath else {
            throw PrivilegedFanControlClientError.unavailable("No fan control backend is available.")
        }
        try await fallbackFanCLI.setAuto(executablePath: fallbackFanCLIPath, fanIDs: fanIDs, allFansSelected: allFansSelected)
        fanWriteBackendState = .fallbackCLI(reason: fallbackBackendReason())
        applyLocalAutoState(to: fanIDs)
    }

    func setFansManual(_ fanIDs: [Int], rpm: Int) async throws {
        let allFansSelected = fanIDs.count == fans.count && !fanIDs.isEmpty
        let fallbackFanCLIPath = fanCLIPath()
        let fallbackCLIAvailable = fallbackFanCLIPath != nil

        if Self.shouldAttemptPrivilegedWrite(
            helperReady: privilegedHelperStatus.isReadyForWrites,
            currentBackendState: fanWriteBackendState,
            fallbackAvailable: fallbackCLIAvailable,
            now: Date(),
            retryAfter: xpcRetryAfter
        ) {
            if Date() < xpcRetryAfter, fallbackCLIAvailable {
                if let fallbackFanCLIPath {
                    try await fallbackFanCLI.setManualRPM(
                        executablePath: fallbackFanCLIPath,
                        fanIDs: fanIDs,
                        rpm: rpm,
                        allFansSelected: allFansSelected
                    )
                    fanWriteBackendState = .fallbackCLI(reason: "Privileged helper retry cooldown active.")
                    applyLocalManualState(to: fanIDs, rpm: rpm)
                    return
                }

                throw PrivilegedFanControlClientError.unavailable("Privileged helper retry cooldown active.")
            }

            do {
                try await privilegedFanControlClient.setManualRPM(fanIDs: fanIDs, rpm: rpm)
                xpcRetryAfter = .distantPast
                fanWriteBackendState = .privilegedDaemon
                applyLocalManualState(to: fanIDs, rpm: rpm)
                return
            } catch {
                if await verifyPrivilegedManualWrite(for: fanIDs, rpm: rpm) {
                    xpcRetryAfter = .distantPast
                    fanWriteBackendState = .privilegedDaemon
                    return
                }
                xpcRetryAfter = Date().addingTimeInterval(requestRetryCooldownSeconds)
                if let fallbackFanCLIPath {
                    recordBackendIssue(error, fallbackAvailable: true)
                    try await fallbackFanCLI.setManualRPM(
                        executablePath: fallbackFanCLIPath,
                        fanIDs: fanIDs,
                        rpm: rpm,
                        allFansSelected: allFansSelected
                    )
                    fanWriteBackendState = .fallbackCLI(reason: error.localizedDescription)
                    applyLocalManualState(to: fanIDs, rpm: rpm)
                    return
                }
                throw error
            }
        }

        guard let fallbackFanCLIPath else {
            throw PrivilegedFanControlClientError.unavailable("No fan control backend is available.")
        }
        try await fallbackFanCLI.setManualRPM(executablePath: fallbackFanCLIPath, fanIDs: fanIDs, rpm: rpm, allFansSelected: allFansSelected)
        fanWriteBackendState = .fallbackCLI(reason: fallbackBackendReason())
        applyLocalManualState(to: fanIDs, rpm: rpm)
    }

    private func fallbackBackendReason() -> String {
        switch privilegedHelperStatus {
        case .requiresApproval:
            "Privileged helper is awaiting macOS approval."
        case .notRegistered, .notFound:
            "Using the local CLI compatibility backend until the privileged helper is available."
        case .failed(let message):
            message
        case .unsupported:
            "Privileged helper is unavailable on this macOS version."
        case .enabled:
            "Using the local CLI compatibility backend."
        }
    }

    private func verifyPrivilegedAutoWrite(for fanIDs: [Int]) async -> Bool {
        await verifyPrivilegedWrite(timeoutSeconds: 4.0) { snapshots in
            fanIDs.allSatisfy { fanID in
                guard let snapshot = snapshots.first(where: { $0.id == fanID }) else {
                    return false
                }

                return snapshot.mode == .auto && snapshot.targetRPM == 0
            }
        }
    }

    private func applyConfigurationRecoveryNotice(_ source: ConfigurationLoadSource) {
        switch source {
        case .primary:
            break
        case .backupRecovered:
            lastNoticeMessage = String.tr("settings.storage.recovered_backup")
        case .defaults:
            lastNoticeMessage = String.tr("settings.storage.recovered_defaults")
        }
    }

    private func flushConfigurationNow(snapshot: AppSettings? = nil) async {
        guard hasLoadedSettings else { return }
        AppLocalization.setLanguage(settings.language)
        let settingsToPersist = snapshot ?? settingsSnapshotForPersistence()

        do {
            try await configStore.save(settingsToPersist)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func settingsSnapshotForPersistence() -> AppSettings {
        var snapshot = settings
        synchronizeCurrentPresetCustomization(into: &snapshot)
        snapshot.profile = normalizedProfileMetadata(snapshot.profile, presetID: snapshot.selectedPresetID)
        return snapshot
    }

    private func synchronizeCurrentPresetCustomization() {
        synchronizeCurrentPresetCustomization(into: &settings)
    }

    private func synchronizeCurrentPresetCustomization(into settings: inout AppSettings) {
        let presetID = settings.selectedPresetID
        let normalizedProfile = normalizedProfileMetadata(settings.profile, presetID: presetID)
        settings.profile = normalizedProfile

        guard allowsCustomization(for: presetID) else {
            settings.customProfiles.removeValue(forKey: presetID)
            return
        }

        let canonical = canonicalProfile(for: presetID)
        if normalizedProfile == canonical {
            settings.customProfiles.removeValue(forKey: presetID)
        } else {
            settings.customProfiles[presetID] = normalizedProfile
        }
    }

    private func storedOrCanonicalProfile(for presetID: ProfilePresetID) -> ControlProfile {
        if allowsCustomization(for: presetID),
           let customized = settings.customProfiles[presetID] {
            return normalizedProfileMetadata(customized, presetID: presetID)
        }
        return canonicalProfile(for: presetID)
    }

    private func canonicalProfile(for presetID: ProfilePresetID) -> ControlProfile {
        normalizedProfileMetadata(ControlProfile.preset(presetID), presetID: presetID)
    }

    private func normalizedProfileMetadata(_ profile: ControlProfile, presetID: ProfilePresetID) -> ControlProfile {
        var normalized = profile
        normalized.id = presetID.rawValue
        normalized.presetID = presetID
        normalized.nameKey = presetID.titleKey
        normalized.descriptionKey = presetID.descriptionKey
        return normalized
    }

    private func allowsCustomization(for presetID: ProfilePresetID) -> Bool {
        switch presetID {
        case .macDefault, .maxCooling:
            false
        case .performanceLight, .performanceMedium, .performanceStrong:
            true
        }
    }

    private func verifyPrivilegedManualWrite(for fanIDs: [Int], rpm: Int) async -> Bool {
        await verifyPrivilegedWrite(timeoutSeconds: 4.0) { snapshots in
            fanIDs.allSatisfy { fanID in
                guard let snapshot = snapshots.first(where: { $0.id == fanID }) else {
                    return false
                }

                return snapshot.mode == .manual && abs(snapshot.targetRPM - rpm) <= 120
            }
        }
    }

    private func verifyPrivilegedWrite(
        timeoutSeconds: Double,
        condition: @escaping @Sendable ([FanSnapshot]) -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        let reader = smcFanReader

        while Date() < deadline {
            let previous = fans
            if let snapshots = try? await Task.detached { try reader.readFans(previousSnapshots: previous) }.value,
               condition(snapshots) {
                fans = snapshots
                lastFanRefreshAt = Date()
                return true
            }

            try? await Task.sleep(for: .milliseconds(200))
        }

        return false
    }

    private func recordBackendIssue(_ error: Error, fallbackAvailable: Bool) {
        let message = error.localizedDescription

        if fallbackAvailable, isRecoverableHelperTimeout(message) {
            lastErrorMessage = nil
            lastNoticeMessage = message
            return
        }

        lastErrorMessage = message
    }

    private func isRecoverableHelperTimeout(_ message: String) -> Bool {
        message.localizedCaseInsensitiveContains("privileged helper timed out")
    }

    func refreshFanSnapshotsFromSMCIfPossible() async {
        let reader = smcFanReader
        let previous = fans
        guard let snapshots = try? await Task.detached { try reader.readFans(previousSnapshots: previous) }.value else {
            return
        }

        fans = snapshots
        lastFanRefreshAt = Date()
    }

    private func runWithTimeout(
        seconds: Double,
        operation: @escaping @Sendable () async throws -> Void
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw CommandRunnerError.timeout(seconds)
            }

            let result: Void? = try await group.next()
            group.cancelAll()
            _ = result
        }
    }

    private func applyLocalAutoState(to fanIDs: [Int]) {
        let selected = Set(fanIDs)
        fans = fans.map { fan in
            guard selected.contains(fan.id) else { return fan }
            var updated = fan
            updated.mode = .auto
            return updated
        }
    }

    private func applyLocalManualState(to fanIDs: [Int], rpm: Int) {
        let selected = Set(fanIDs)
        fans = fans.map { fan in
            guard selected.contains(fan.id) else { return fan }
            var updated = fan
            updated.mode = .manual
            updated.targetRPM = rpm
            return updated
        }
    }

    private func virtualSensor(key: String, name: String, celsius: Double) -> TemperatureSensor {
        TemperatureSensor(
            id: key,
            key: key,
            name: name,
            celsius: celsius,
            source: .hid
        )
    }

    private func resolveSensor(for selection: SensorSelection) -> TemperatureSensor? {
        switch selection.kind {
        case .hottest:
            return summary.hottest
        case .hottestCPUCore:
            return hottestCPUSensor()
        case .cpuAverage:
            return summary.cpuAverage.map { virtualSensor(key: "virtual.cpu.average", name: String.tr("sensor.cpu_average"), celsius: $0) }
        case .gpuAverage:
            return summary.gpuAverage.map { virtualSensor(key: "virtual.gpu.average", name: String.tr("sensor.gpu_average"), celsius: $0) }
        case .batteryAverage:
            return summary.batteryAverage.map { virtualSensor(key: "virtual.battery.average", name: String.tr("sensor.battery_average"), celsius: $0) }
        case .specific:
            return sensors.sensor(matching: selection.key) ?? summary.hottest
        }
    }

    func hottestCPUSensor() -> TemperatureSensor? {
        sensors
            .filter { sensor in
                sensor.name.localizedCaseInsensitiveContains("CPU") &&
                sensor.name.localizedCaseInsensitiveContains("Core")
            }
            .max(by: { $0.celsius < $1.celsius })
    }

    private func fanCLIPath() -> String? {
        resolvedExecutablePath(
            configuredPath: settings.fanExecutablePath,
            compatibilityCandidates: compatibilityFanCLIPaths
        )
    }

    private func resolvedISMCPath() -> String? {
        resolvedExecutablePath(
            configuredPath: settings.iSMCExecutablePath,
            compatibilityCandidates: compatibilityISMCPaths
        )
    }

    private func resolvedExecutablePath(
        configuredPath: String,
        compatibilityCandidates: [String]
    ) -> String? {
        let trimmedPath = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPath.isEmpty, FileManager.default.isExecutableFile(atPath: trimmedPath) {
            return trimmedPath
        }

        for candidate in compatibilityCandidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }

        return nil
    }

    private static var isRunningUnderTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

// MARK: - AutomationEnvironment Conformance

extension AppModel: AutomationEnvironment {
    var profile: ControlProfile { settings.profile }
    var automationEnabled: Bool { settings.automationEnabled }
    var privilegedHelperIsReadyForWrites: Bool { privilegedHelperStatus.isReadyForWrites }
    var resolvedFanCLIPath: String? { fanCLIPath() }
}

private enum RuntimePressureState {
    case normal
    case warning
    case critical
}
