import Foundation
import Testing
@testable import AeroPulse

struct AeroPulseTests {
    @Test
    func profileFallsBackToAutoBelowThreshold() {
        let profile = ControlProfile(
            id: "test-light",
            presetID: .performanceLight,
            nameKey: "profile.performance_light.title",
            descriptionKey: "profile.performance_light.description",
            strategy: .curve,
            sensorSelection: .cpuAverage,
            fanIDs: [1, 2],
            hysteresis: 2,
            minimumHoldSeconds: 2,
            curve: [
                CurvePoint(temperature: 50, rpm: 2400),
                CurvePoint(temperature: 70, rpm: 4000)
            ]
        )

        #expect(profile.evaluate(temperature: 46) == .auto)
    }

    @Test
    func profileInterpolatesBetweenCurvePoints() {
        let profile = ControlProfile(
            id: "test-medium",
            presetID: .performanceMedium,
            nameKey: "profile.performance_medium.title",
            descriptionKey: "profile.performance_medium.description",
            strategy: .curve,
            sensorSelection: .cpuAverage,
            fanIDs: [1],
            hysteresis: 1,
            minimumHoldSeconds: 2,
            curve: [
                CurvePoint(temperature: 60, rpm: 3000),
                CurvePoint(temperature: 80, rpm: 5000)
            ]
        )

        #expect(profile.evaluate(temperature: 70) == .manual(rpm: 4000))
    }

    @Test
    func profileKeepsFirstCurveRPMInsideEntryHysteresisBand() {
        let profile = ControlProfile(
            id: "test-entry-band",
            presetID: .performanceMedium,
            nameKey: "profile.performance_medium.title",
            descriptionKey: "profile.performance_medium.description",
            strategy: .curve,
            sensorSelection: .cpuAverage,
            fanIDs: [1, 2],
            hysteresis: 2,
            minimumHoldSeconds: 2,
            curve: [
                CurvePoint(temperature: 50, rpm: 2600),
                CurvePoint(temperature: 70, rpm: 4200)
            ]
        )

        #expect(profile.evaluate(temperature: 49) == .manual(rpm: 2600))
        #expect(profile.evaluate(temperature: 47.5) == .auto)
    }

    @Test
    func performancePresetsBecomeMoreAggressiveInOrder() {
        let light = ControlProfile.preset(.performanceLight)
        let medium = ControlProfile.preset(.performanceMedium)
        let strong = ControlProfile.preset(.performanceStrong)

        let lightRPM = rpm(for: light.evaluate(temperature: 60))
        let mediumRPM = rpm(for: medium.evaluate(temperature: 60))
        let strongRPM = rpm(for: strong.evaluate(temperature: 60))

        #expect(lightRPM < mediumRPM)
        #expect(mediumRPM < strongRPM)
    }

    @Test
    func filteredTemperatureFallsMoreGraduallyThanItRises() {
        let profile = ControlProfile.preset(.performanceMedium)
        let warmed = profile.filteredTemperature(previous: 50, current: 60)
        let cooled = profile.filteredTemperature(previous: 60, current: 50)

        #expect(warmed > 56)
        #expect(cooled > 56)
        #expect(cooled > 52)
    }

    @Test
    func manualRPMRampLimitsSuddenDrops() {
        let profile = ControlProfile.preset(.performanceStrong)
        let ramped = profile.rampedManualRPM(from: 7600, toward: 3200, elapsed: 0.5)

        #expect(ramped < 7600)
        #expect(ramped > 6500)
    }

    @Test
    func manualRPMRampCapsVeryLongElapsed() {
        let profile = ControlProfile.preset(.performanceMedium)
        let ramped = profile.rampedManualRPM(from: 3200, toward: 7800, elapsed: 12.0)

        #expect(ramped < 7800)
        #expect(ramped <= 6000)
    }

    @Test
    func strongerProfileRampsUpFasterThanLightProfile() {
        let light = ControlProfile.preset(.performanceLight)
        let strong = ControlProfile.preset(.performanceStrong)

        let lightRamped = light.rampedManualRPM(from: 3200, toward: 7800, elapsed: 0.5)
        let strongRamped = strong.rampedManualRPM(from: 3200, toward: 7800, elapsed: 0.5)

        #expect(strongRamped > lightRamped)
    }

    @Test
    func tinyManualRPMChangesAreHeldInsideMinimumWindow() {
        let profile = ControlProfile.preset(.performanceMedium)

        #expect(profile.shouldHoldManualRPMTransition(from: 5200, to: 5350, elapsed: 1.0))
        #expect(profile.shouldHoldManualRPMTransition(from: 5200, to: 5600, elapsed: 1.0) == false)
        #expect(profile.shouldHoldManualRPMTransition(from: 5200, to: 5350, elapsed: 4.0) == false)
    }

    @Test
    func duplicateCurveTemperaturesPreferTheHigherRPM() {
        let profile = ControlProfile(
            id: "duplicate-temp",
            presetID: .performanceMedium,
            nameKey: "profile.performance_medium.title",
            descriptionKey: "profile.performance_medium.description",
            strategy: .curve,
            sensorSelection: .cpuAverage,
            fanIDs: [1, 2],
            hysteresis: 1.0,
            minimumHoldSeconds: 2.0,
            curve: [
                CurvePoint(temperature: 50, rpm: 3200),
                CurvePoint(temperature: 50, rpm: 4600),
                CurvePoint(temperature: 65, rpm: 6200)
            ]
        )

        #expect(profile.evaluate(temperature: 50) == .manual(rpm: 4600))
    }

    @Test
    func appSettingsDefaultDoesNotDependOnLegacyFanControlPaths() {
        #expect(AppSettings.default.fanExecutablePath.isEmpty)
        #expect(AppSettings.default.iSMCExecutablePath.isEmpty)
    }

    @MainActor
    @Test
    func helperChecklistShowsPendingApprovalWhenApprovalIsRequired() throws {
        let model = AppModel(runner: StubCommandRunner(), hidService: nil)
        model.privilegedHelperDiagnostics = PrivilegedHelperDiagnostics(
            bundlePath: "/Applications/AeroPulse.app",
            teamIdentifier: "Y9TRXFZMR5",
            isInstalledInApplications: true,
            helperToolEmbedded: true,
            launchDaemonEmbedded: true
        )
        model.privilegedHelperStatus = .requiresApproval

        let approval = try #require(model.privilegedHelperChecklist.first(where: { $0.id == "approval" }))
        let install = try #require(model.privilegedHelperChecklist.first(where: { $0.id == "install" }))
        let payload = try #require(model.privilegedHelperChecklist.first(where: { $0.id == "payload" }))

        #expect(approval.state == .pendingApproval)
        #expect(install.state == .complete)
        #expect(payload.state == .complete)
        #expect(model.shouldShowHelperApprovalBanner)
    }

    @MainActor
    @Test
    func quitProgressUsesStageSpecificLocalizedKey() {
        let model = AppModel(runner: StubCommandRunner(), hidService: nil)

        model.quitPreparationStage = .restoringFans
        #expect(model.quitBannerDetail == String.tr("quit.banner.progress.restore"))

        model.quitPreparationStage = .closingConnections
        #expect(model.quitBannerDetail == String.tr("quit.banner.progress.connections"))

        model.quitPreparationStage = .finalizing
        #expect(model.quitBannerDetail == String.tr("quit.banner.progress.finalize"))
    }

    @Test
    @MainActor
    func safeQuitRestoresAllFansToAutoViaFallbackCLI() async {
        let runner = RecordingCommandRunner()
        let model = AppModel(runner: runner, hidService: nil)

        model.settings.fanExecutablePath = "/tmp/fan"
        model.settings.automationEnabled = true
        model.privilegedHelperStatus = .requiresApproval
        model.fans = [
            FanSnapshot(id: 1, mode: .manual, currentRPM: 4200, targetRPM: 4200, minRPM: 2000, maxRPM: 8000),
            FanSnapshot(id: 2, mode: .auto, currentRPM: 3900, targetRPM: 3900, minRPM: 2000, maxRPM: 8000)
        ]

        await model.prepareForTermination()

        let commands = await runner.commands
        #expect(commands.count == 1)
        #expect(commands.first?.arguments == ["auto"])
        #expect(model.fans.allSatisfy { $0.mode == .auto })
        #expect(model.isPreparingToQuit == false)
        #expect(model.quitPreparationStage == .finalizing)
    }

    @Test
    @MainActor
    func fanStateMatchesRequiresManualModeAndTargetTolerance() {
        let model = AppModel(runner: StubCommandRunner(), hidService: nil)
        let snapshots = [
            FanSnapshot(id: 1, mode: .manual, currentRPM: 7700, targetRPM: 7826, minRPM: 2000, maxRPM: 7826),
            FanSnapshot(id: 2, mode: .manual, currentRPM: 7680, targetRPM: 7780, minRPM: 2000, maxRPM: 7826)
        ]

        #expect(model.fanStateMatches(decision: .manual(rpm: 7826), fanIDs: [1, 2], snapshots: snapshots))
        #expect(model.fanStateMatches(decision: .manual(rpm: 7600), fanIDs: [1, 2], snapshots: snapshots) == false)
    }

    @Test
    @MainActor
    func fanStateMatchesDetectsAutoDriftForManualDecision() {
        let model = AppModel(runner: StubCommandRunner(), hidService: nil)
        let snapshots = [
            FanSnapshot(id: 1, mode: .auto, currentRPM: 3200, targetRPM: 0, minRPM: 2000, maxRPM: 7826),
            FanSnapshot(id: 2, mode: .manual, currentRPM: 7800, targetRPM: 7826, minRPM: 2000, maxRPM: 7826)
        ]

        #expect(model.fanStateMatches(decision: .manual(rpm: 7826), fanIDs: [1, 2], snapshots: snapshots) == false)
        #expect(model.fanStateMatches(decision: .auto, fanIDs: [1, 2], snapshots: snapshots) == false)
    }

    @Test
    @MainActor
    func enforceSettingsInvariantsRestoresCanonicalMaxCoolingProfile() {
        let model = AppModel(runner: StubCommandRunner(), hidService: nil)
        model.settings.selectedPresetID = .maxCooling
        model.settings.profile = ControlProfile(
            id: "broken-max",
            presetID: .maxCooling,
            nameKey: "broken",
            descriptionKey: "broken",
            strategy: .curve,
            sensorSelection: .gpuAverage,
            fanIDs: [2],
            hysteresis: 9,
            minimumHoldSeconds: 9,
            curve: [CurvePoint(temperature: 88, rpm: 3200)]
        )

        model.enforceSettingsInvariants()

        #expect(model.settings.profile == ControlProfile.preset(.maxCooling))
    }

    @Test
    @MainActor
    func enforceSettingsInvariantsKeepsSelectedPresetAsSourceOfTruth() {
        let model = AppModel(runner: StubCommandRunner(), hidService: nil)
        model.settings.selectedPresetID = .performanceLight
        model.settings.profile = ControlProfile.preset(.performanceStrong)

        model.enforceSettingsInvariants()

        #expect(model.settings.selectedPresetID == .performanceLight)
        #expect(model.settings.profile.presetID == .performanceLight)
        #expect(model.settings.profile.nameKey == ProfilePresetID.performanceLight.titleKey)
    }

    @Test
    @MainActor
    func applyPresetPreservesCustomizedCurrentPresetUntilReset() {
        let model = AppModel(runner: StubCommandRunner(), hidService: nil)
        model.settings.selectedPresetID = .performanceStrong
        model.settings.profile = ControlProfile.preset(.performanceStrong)
        model.settings.profile.curve[0].rpm = 4100

        let customized = model.settings.profile
        model.applyPreset(.performanceStrong, persist: false)

        #expect(model.settings.profile == customized)
        #expect(model.isSelectedPresetCustomized)

        model.resetProfile()
        #expect(model.settings.profile == ControlProfile.preset(.performanceStrong))
        #expect(model.isSelectedPresetCustomized == false)
    }

    @Test
    @MainActor
    func selectedProfileDisplayNameMarksCustomizedPreset() {
        let model = AppModel(runner: StubCommandRunner(), hidService: nil)
        model.settings.selectedPresetID = .performanceMedium
        model.settings.profile = ControlProfile.preset(.performanceMedium)
        #expect(model.selectedProfileDisplayName == String.tr(ProfilePresetID.performanceMedium.titleKey))

        model.settings.profile.curve[0].rpm += 400
        #expect(model.selectedProfileDisplayName.contains(String.tr("profile.custom_suffix")))
    }

    @Test
    @MainActor
    func applyPresetRestoresStoredCustomizedVariantAfterSwitchingAway() {
        let model = AppModel(runner: StubCommandRunner(), hidService: nil)
        model.settings.selectedPresetID = .performanceStrong
        model.settings.profile = ControlProfile.preset(.performanceStrong)
        model.settings.profile.curve[0].rpm += 500

        model.applyPreset(.performanceMedium, persist: false)
        #expect(model.settings.selectedPresetID == .performanceMedium)

        model.applyPreset(.performanceStrong, persist: false)
        #expect(model.settings.selectedPresetID == .performanceStrong)
        #expect(model.settings.profile.curve[0].rpm == ControlProfile.preset(.performanceStrong).curve[0].rpm + 500)
        #expect(model.isSelectedPresetCustomized)
    }

    @Test
    func appSettingsPersistCustomizedProfilesByPreset() throws {
        var settings = AppSettings.default
        var customMedium = ControlProfile.preset(.performanceMedium)
        customMedium.curve[0].rpm += 400
        settings.selectedPresetID = .performanceMedium
        settings.profile = customMedium
        settings.customProfiles[.performanceMedium] = customMedium

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(decoded.customProfiles[.performanceMedium] == customMedium)
        #expect(decoded.profile == customMedium)
    }

    @Test
    @MainActor
    func toggleFanSelectionKeepsAtLeastOneFanSelected() {
        let model = AppModel(runner: StubCommandRunner(), hidService: nil)
        model.settings.profile.fanIDs = [1]

        model.toggleFanSelection(1, enabled: false)

        #expect(model.settings.profile.fanIDs == [1])
        #expect(model.lastNoticeMessage == String.tr("automation.fans.minimum_one"))
    }

    @Test
    @MainActor
    func interruptionDecisionHoldsManualTargetInsideGraceWindow() {
        let now = Date()
        let decision = AppModel.interruptionDecision(
            lastAppliedDecision: .manual(rpm: 5600),
            lastHealthyAt: now.addingTimeInterval(-3),
            now: now,
            fanIDs: [1, 2],
            snapshots: [],
            graceSeconds: 8
        )

        #expect(decision == .manual(rpm: 5600))
        #expect(
            AppModel.interruptionDecision(
                lastAppliedDecision: .manual(rpm: 5600),
                lastHealthyAt: now.addingTimeInterval(-12),
                now: now,
                fanIDs: [1, 2],
                snapshots: [],
                graceSeconds: 8
            ) == nil
        )
    }

    @Test
    func shouldReapplyHeldDecisionWhenFansDriftBackToAuto() {
        let snapshots = [
            FanSnapshot(id: 1, mode: .auto, currentRPM: 3300, targetRPM: 0, minRPM: 2000, maxRPM: 7800),
            FanSnapshot(id: 2, mode: .manual, currentRPM: 5500, targetRPM: 5600, minRPM: 2000, maxRPM: 7800)
        ]

        #expect(
            AppModel.shouldReapplyHeldDecision(
                .manual(rpm: 5600),
                fanIDs: [1, 2],
                snapshots: snapshots,
                writableBackendAvailable: true
            )
        )
        #expect(
            AppModel.shouldReapplyHeldDecision(
                .manual(rpm: 5600),
                fanIDs: [1, 2],
                snapshots: snapshots,
                writableBackendAvailable: false
            ) == false
        )
    }

    @Test
    func shouldAttemptPrivilegedWriteRespectsFallbackCooldown() {
        let now = Date()

        #expect(
            AppModel.shouldAttemptPrivilegedWrite(
                helperReady: true,
                currentBackendState: .fallbackCLI(reason: "timeout"),
                fallbackAvailable: true,
                now: now,
                retryAfter: now.addingTimeInterval(5)
            ) == false
        )
        #expect(
            AppModel.shouldAttemptPrivilegedWrite(
                helperReady: true,
                currentBackendState: .fallbackCLI(reason: "timeout"),
                fallbackAvailable: true,
                now: now.addingTimeInterval(6),
                retryAfter: now.addingTimeInterval(5)
            )
        )
        #expect(
            AppModel.shouldAttemptPrivilegedWrite(
                helperReady: true,
                currentBackendState: .privilegedDaemon,
                fallbackAvailable: true,
                now: now,
                retryAfter: now.addingTimeInterval(5)
            )
        )
    }

    @Test
    func fanCLIRejectsEmptySelectionForManualWrites() async {
        let service = FanCLIService(runner: StubCommandRunner())

        do {
            try await service.setManualRPM(executablePath: "/tmp/fan", fanIDs: [], rpm: 3200)
            Issue.record("Expected empty fan selection to be rejected.")
        } catch let error as FanCLIError {
            #expect(error == .emptyFanSelection)
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test
    func configurationStoreRecoversFromBackupWhenPrimaryIsCorrupted() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ConfigurationStore(directoryURL: directory)
        let expected = AppSettings.default

        try await store.save(expected)

        let appDirectory = directory.appendingPathComponent("AeroPulse", isDirectory: true)
        let primaryURL = appDirectory.appendingPathComponent("settings.json")
        let corruptedData = try #require("corrupted".data(using: .utf8))
        try corruptedData.write(to: primaryURL, options: [.atomic])

        let recovered = await store.load()

        #expect(recovered.source == .backupRecovered)
        #expect(recovered.settings == expected)
    }

    @Test
    @MainActor
    func automationControlLabelUsesPrimarySensorWhenAutomationIsDisabled() {
        let model = AppModel(runner: StubCommandRunner(), hidService: nil)
        model.settings.automationEnabled = false

        #expect(model.automationControlLabelKey == "automation.sensor")

        model.settings.automationEnabled = true
        #expect(model.automationControlLabelKey == "automation.control_input")
    }

    @Test
    @MainActor
    func quickProfileSelectionRemainsVisibleWhileAutomationIsPaused() {
        let model = AppModel(runner: StubCommandRunner(), hidService: nil)
        model.settings.selectedPresetID = .performanceStrong
        model.settings.automationEnabled = false

        #expect(model.isQuickProfileSelected(.performanceStrong))
        #expect(model.isQuickProfileSelected(.performanceMedium) == false)
    }

    @Test
    @MainActor
    func prepareForTerminationFlushesLatestSettingsSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ConfigurationStore(directoryURL: directory)
        let runner = RecordingCommandRunner()
        let model = AppModel(runner: runner, hidService: nil, configStore: store)

        await model.bootstrap()
        model.settings.language = .english
        model.settings.theme = .dark
        model.settings.automationEnabled = true
        model.settings.fanExecutablePath = "/tmp/fan"
        model.privilegedHelperStatus = .requiresApproval
        model.fans = [
            FanSnapshot(id: 1, mode: .manual, currentRPM: 4200, targetRPM: 4200, minRPM: 2000, maxRPM: 8000)
        ]

        await model.prepareForTermination()

        let persisted = await store.load()
        #expect(persisted.settings.language == .english)
        #expect(persisted.settings.theme == .dark)
        #expect(persisted.settings.automationEnabled)
    }

    // MARK: - TEST-01: Emergency safeguard tests

    @Test @MainActor
    func emergencySafeguardTriggersAtCPUThreshold() {
        let model = AppModel(runner: StubCommandRunner(), hidService: nil)
        model.summary = DashboardSummary(cpuAverage: 82.0, gpuAverage: nil, batteryAverage: nil, hottest: nil)

        let result = model.emergencySafeguardDecision()

        #expect(result != nil)
        #expect(result?.decision == .manual(rpm: 7800))
        #expect(result?.reason == String.tr("automation.reason.emergency_cpu"))
    }

    @Test @MainActor
    func emergencySafeguardTriggersAtGPUThreshold() {
        let model = AppModel(runner: StubCommandRunner(), hidService: nil)
        model.summary = DashboardSummary(cpuAverage: nil, gpuAverage: 78.0, batteryAverage: nil, hottest: nil)

        let result = model.emergencySafeguardDecision()

        #expect(result != nil)
        #expect(result?.decision == .manual(rpm: 7800))
        #expect(result?.reason == String.tr("automation.reason.emergency_gpu"))
    }

    @Test @MainActor
    func emergencySafeguardTriggersAtBatteryThreshold() {
        let model = AppModel(runner: StubCommandRunner(), hidService: nil)
        model.summary = DashboardSummary(cpuAverage: nil, gpuAverage: nil, batteryAverage: 40.0, hottest: nil)

        let result = model.emergencySafeguardDecision()

        #expect(result != nil)
        #expect(result?.decision == .manual(rpm: 7800))
        #expect(result?.reason == String.tr("automation.reason.emergency_battery"))
    }

    @Test @MainActor
    func emergencySafeguardDoesNotTriggerBelowThresholds() {
        let model = AppModel(runner: StubCommandRunner(), hidService: nil)
        model.summary = DashboardSummary(cpuAverage: 81.9, gpuAverage: 77.9, batteryAverage: 39.9, hottest: nil)

        let result = model.emergencySafeguardDecision()

        #expect(result == nil)
    }

    // MARK: - TEST-02: Curve evaluation edge cases

    @Test
    func evaluateReturnsAutoForEmptyCurve() {
        let profile = ControlProfile(
            id: "empty-curve",
            presetID: .performanceMedium,
            nameKey: "profile.performance_medium.title",
            descriptionKey: "profile.performance_medium.description",
            strategy: .curve,
            sensorSelection: .cpuAverage,
            fanIDs: [1, 2],
            hysteresis: 1.0,
            minimumHoldSeconds: 2.0,
            curve: []
        )

        #expect(profile.evaluate(temperature: 60) == .auto)
    }

    @Test
    func evaluateReturnsAutoForSystemDefaultStrategy() {
        let profile = ControlProfile.preset(.macDefault)

        #expect(profile.evaluate(temperature: 60) == .auto)
        #expect(profile.evaluate(temperature: 90) == .auto)
    }

    @Test
    func evaluateReturnsMaxRPMForMaxCoolingStrategy() {
        let profile = ControlProfile.preset(.maxCooling)

        #expect(profile.evaluate(temperature: 30) == .manual(rpm: .max))
        #expect(profile.evaluate(temperature: 90) == .manual(rpm: .max))
    }

    @Test
    func evaluateHandlesSinglePointCurve() {
        let profile = ControlProfile(
            id: "single-point",
            presetID: .performanceMedium,
            nameKey: "profile.performance_medium.title",
            descriptionKey: "profile.performance_medium.description",
            strategy: .curve,
            sensorSelection: .cpuAverage,
            fanIDs: [1],
            hysteresis: 2.0,
            minimumHoldSeconds: 2.0,
            curve: [CurvePoint(temperature: 60, rpm: 4000)]
        )

        #expect(profile.evaluate(temperature: 57.5) == .auto)
        #expect(profile.evaluate(temperature: 59) == .manual(rpm: 4000))
        #expect(profile.evaluate(temperature: 60) == .manual(rpm: 4000))
        #expect(profile.evaluate(temperature: 75) == .manual(rpm: 4000))
    }

    @Test
    func evaluateClipsToLastRPMAboveMaxTemperature() {
        let profile = ControlProfile(
            id: "clip-test",
            presetID: .performanceStrong,
            nameKey: "profile.performance_strong.title",
            descriptionKey: "profile.performance_strong.description",
            strategy: .curve,
            sensorSelection: .cpuAverage,
            fanIDs: [1, 2],
            hysteresis: 1.0,
            minimumHoldSeconds: 2.0,
            curve: [
                CurvePoint(temperature: 50, rpm: 2800),
                CurvePoint(temperature: 80, rpm: 6200)
            ]
        )

        #expect(profile.evaluate(temperature: 95) == .manual(rpm: 6200))
        #expect(profile.evaluate(temperature: 80) == .manual(rpm: 6200))
    }
}

private func rpm(for decision: AutomationDecision) -> Int {
    switch decision {
    case .auto:
        0
    case let .manual(rpm):
        rpm
    }
}

private struct StubCommandRunner: CommandRunning {
    func run(executable: URL, arguments: [String]) async throws -> CommandResult {
        CommandResult(stdout: "", stderr: "", exitCode: 0)
    }
}

private actor RecordingCommandRunner: CommandRunning {
    struct Invocation: Equatable {
        let executablePath: String
        let arguments: [String]
    }

    private(set) var commands: [Invocation] = []

    func run(executable: URL, arguments: [String]) async throws -> CommandResult {
        commands.append(Invocation(executablePath: executable.path, arguments: arguments))
        return CommandResult(stdout: "", stderr: "", exitCode: 0)
    }
}
