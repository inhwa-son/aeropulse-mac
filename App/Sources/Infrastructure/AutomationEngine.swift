import Foundation

/// Protocol that provides the AutomationEngine with read access to the app's
/// live sensor, fan and configuration state, plus callbacks for fan writes.
@MainActor
protocol AutomationEnvironment: AnyObject {
    var summary: DashboardSummary { get }
    var sensors: [TemperatureSensor] { get }
    var fans: [FanSnapshot] { get set }
    var automationSnapshot: AutomationSnapshot { get set }
    var lastErrorMessage: String? { get set }
    var profile: ControlProfile { get }
    var automationEnabled: Bool { get }
    var integrationState: IntegrationState { get }
    var hasPreparedForTermination: Bool { get }
    var fanWriteBackendState: FanWriteBackendState { get }
    var privilegedHelperIsReadyForWrites: Bool { get }
    var resolvedFanCLIPath: String? { get }

    func selectedSensor() -> TemperatureSensor?
    func hottestCPUSensor() -> TemperatureSensor?
    func setFansAuto(_ fanIDs: [Int]) async throws
    func setFansManual(_ fanIDs: [Int], rpm: Int) async throws
    func restoreFansToAutoIfNeeded() async
    func refreshFanSnapshotsFromSMCIfPossible() async
}

// MARK: - AutomationEngine

@MainActor
final class AutomationEngine {

    // MARK: - Published / Readable State

    private(set) var lastAppliedDecision: AutomationDecision?
    private(set) var lastAppliedAt: Date = .distantPast
    private(set) var lastHealthyAutomationAt: Date = .distantPast

    // MARK: - Private Smoothing State

    private var smoothedAutomationSensorID: String?
    private var smoothedAutomationTemperature: Double?

    // MARK: - Constants

    let automationInterruptionGraceSeconds = 8.0
    let emergencyCPUThreshold = 82.0
    let emergencyGPUThreshold = 78.0
    let emergencyBatteryThreshold = 40.0
    let automationVerificationToleranceRPM = 180

    // MARK: - Environment

    private weak var environment: AutomationEnvironment?

    init(environment: AutomationEnvironment? = nil) {
        self.environment = environment
    }

    func attach(to environment: AutomationEnvironment) {
        self.environment = environment
    }

    // MARK: - State Reset

    func resetState() {
        lastAppliedDecision = nil
        lastAppliedAt = .distantPast
        lastHealthyAutomationAt = .distantPast
        resetSmoothingState()
    }

    func resetSmoothingState() {
        smoothedAutomationSensorID = nil
        smoothedAutomationTemperature = nil
    }

    // MARK: - Main Entry Point

    func runAutomationIfNeeded() async {
        guard let env = environment else { return }
        let now = Date()

        guard !env.hasPreparedForTermination else {
            await env.restoreFansToAutoIfNeeded()
            env.automationSnapshot = AutomationSnapshot(
                decision: .auto,
                sensor: env.selectedSensor(),
                reason: String.tr("automation.reason.disabled"),
                timestamp: now,
                controlTemperature: nil,
                controlDetail: nil
            )
            return
        }

        guard env.integrationState.isOperational else {
            await handleAutomationInterruption(
                sensor: env.selectedSensor(),
                reason: String.tr("automation.reason.integration_missing"),
                now: now
            )
            return
        }

        guard !env.fans.isEmpty else {
            await handleAutomationInterruption(
                sensor: env.selectedSensor(),
                reason: String.tr("automation.reason.no_fans"),
                now: now
            )
            return
        }

        let sensor = env.selectedSensor()
        guard let sensor else {
            await handleAutomationInterruption(
                sensor: nil,
                reason: String.tr("automation.reason.no_sensor"),
                now: now
            )
            return
        }

        let controlTemperature = filteredAutomationTemperature(for: sensor)
        let evaluation = effectiveAutomationDecision(for: sensor, controlTemperature: controlTemperature)
        let activeFanIDs = activeFanIDs()
        let targetDecision = normalizedAutomationDecision(evaluation.decision)
        let decision = smoothedAutomationDecision(
            targetDecision,
            now: now,
            bypassRamp: evaluation.reason != nil || env.profile.strategy == .maximumCooling
        )

        guard !activeFanIDs.isEmpty else {
            await handleAutomationInterruption(
                sensor: sensor,
                reason: String.tr("automation.reason.no_selected_fans"),
                now: now
            )
            return
        }

        let currentFanStateMatchesDecision = fanStateMatches(
            decision: decision,
            fanIDs: activeFanIDs,
            snapshots: env.fans
        )

        if decision == lastAppliedDecision, currentFanStateMatchesDecision {
            lastHealthyAutomationAt = now
            env.automationSnapshot = AutomationSnapshot(
                decision: decision,
                sensor: sensor,
                reason: evaluation.reason ?? String.tr("automation.reason.steady"),
                timestamp: now,
                controlTemperature: controlTemperature,
                controlDetail: controlTemperatureDetail(for: sensor, controlTemperature: controlTemperature)
            )
            return
        }

        if currentFanStateMatchesDecision,
           now.timeIntervalSince(lastAppliedAt) < env.profile.minimumHoldSeconds {
            lastHealthyAutomationAt = now
            env.automationSnapshot = AutomationSnapshot(
                decision: decision,
                sensor: sensor,
                reason: String.tr("automation.reason.holding"),
                timestamp: now,
                controlTemperature: controlTemperature,
                controlDetail: controlTemperatureDetail(for: sensor, controlTemperature: controlTemperature)
            )
            return
        }

        do {
            switch decision {
            case .auto:
                try await env.setFansAuto(activeFanIDs)
            case let .manual(rpm):
                try await env.setFansManual(activeFanIDs, rpm: rpm)
            }

            await env.refreshFanSnapshotsFromSMCIfPossible()
            lastAppliedDecision = decision
            lastAppliedAt = now
            lastHealthyAutomationAt = now
            env.automationSnapshot = AutomationSnapshot(
                decision: decision,
                sensor: sensor,
                reason: currentFanStateMatchesDecision
                    ? (evaluation.reason ?? String.tr("automation.reason.applied"))
                    : String.tr("automation.reason.recovered"),
                timestamp: now,
                controlTemperature: controlTemperature,
                controlDetail: controlTemperatureDetail(for: sensor, controlTemperature: controlTemperature)
            )
        } catch {
            env.lastErrorMessage = error.localizedDescription
            env.automationSnapshot = AutomationSnapshot(
                decision: decision,
                sensor: sensor,
                reason: error.localizedDescription,
                timestamp: now,
                controlTemperature: controlTemperature,
                controlDetail: controlTemperatureDetail(for: sensor, controlTemperature: controlTemperature)
            )
        }
    }

    // MARK: - Interruption Handling

    private func handleAutomationInterruption(
        sensor: TemperatureSensor?,
        reason: String,
        now: Date
    ) async {
        guard let env = environment else { return }
        let activeFanIDs = activeFanIDs()
        if let heldDecision = Self.interruptionDecision(
            lastAppliedDecision: lastAppliedDecision,
            lastHealthyAt: lastHealthyAutomationAt,
            now: now,
            fanIDs: activeFanIDs,
            snapshots: env.fans,
            graceSeconds: automationInterruptionGraceSeconds
        ) {
            let fallbackFanCLIPath = env.resolvedFanCLIPath
            let shouldReapply = Self.shouldReapplyHeldDecision(
                heldDecision,
                fanIDs: activeFanIDs,
                snapshots: env.fans,
                writableBackendAvailable: env.privilegedHelperIsReadyForWrites || fallbackFanCLIPath != nil
            )

            if shouldReapply {
                do {
                    switch heldDecision {
                    case .auto:
                        try await env.setFansAuto(activeFanIDs)
                    case let .manual(rpm):
                        try await env.setFansManual(activeFanIDs, rpm: rpm)
                    }
                    await env.refreshFanSnapshotsFromSMCIfPossible()
                    lastAppliedDecision = heldDecision
                    lastAppliedAt = now
                } catch {
                    let message = error.localizedDescription
                    if fallbackFanCLIPath != nil,
                       message.localizedCaseInsensitiveContains("privileged helper timed out") {
                        env.lastErrorMessage = nil
                    } else {
                        env.lastErrorMessage = message
                    }
                }
            }

            env.automationSnapshot = AutomationSnapshot(
                decision: heldDecision,
                sensor: sensor,
                reason: shouldReapply
                    ? "\(String.tr("automation.reason.degraded_reapplied")) \(reason)"
                    : "\(String.tr("automation.reason.degraded_hold")) \(reason)",
                timestamp: now,
                controlTemperature: smoothedAutomationTemperature,
                controlDetail: env.automationSnapshot.controlDetail
            )
            return
        }

        await env.restoreFansToAutoIfNeeded()
        env.automationSnapshot = AutomationSnapshot(
            decision: .auto,
            sensor: sensor,
            reason: reason,
            timestamp: now,
            controlTemperature: nil,
            controlDetail: nil
        )
    }

    // MARK: - Decision Pipeline

    func emergencySafeguardDecision() -> (decision: AutomationDecision, reason: String?)? {
        guard let env = environment else { return nil }

        if let cpuAverage = env.summary.cpuAverage, cpuAverage >= emergencyCPUThreshold {
            return (.manual(rpm: maxSelectedFanRPM()), String.tr("automation.reason.emergency_cpu"))
        }

        if let cpuCore = env.hottestCPUSensor(), cpuCore.celsius >= emergencyCPUThreshold {
            return (.manual(rpm: maxSelectedFanRPM()), String.tr("automation.reason.emergency_cpu"))
        }

        if let gpuAverage = env.summary.gpuAverage, gpuAverage >= emergencyGPUThreshold {
            return (.manual(rpm: maxSelectedFanRPM()), String.tr("automation.reason.emergency_gpu"))
        }

        if let batteryAverage = env.summary.batteryAverage, batteryAverage >= emergencyBatteryThreshold {
            return (.manual(rpm: maxSelectedFanRPM()), String.tr("automation.reason.emergency_battery"))
        }

        return nil
    }

    private func effectiveAutomationDecision(
        for sensor: TemperatureSensor,
        controlTemperature: Double
    ) -> (decision: AutomationDecision, reason: String?) {
        if let safeguard = emergencySafeguardDecision() {
            return safeguard
        }

        guard let env = environment else { return (.auto, nil) }
        return (env.profile.evaluate(temperature: controlTemperature), nil)
    }

    func normalizedAutomationDecision(_ decision: AutomationDecision) -> AutomationDecision {
        switch decision {
        case .auto:
            return .auto
        case let .manual(rpm):
            if rpm == .max {
                return .manual(rpm: maxSelectedFanRPM())
            }
            return .manual(rpm: clamp(rpm: rpm))
        }
    }

    func smoothedAutomationDecision(
        _ decision: AutomationDecision,
        now: Date,
        bypassRamp: Bool = false
    ) -> AutomationDecision {
        guard let env = environment else { return decision }

        switch decision {
        case .auto, .manual(rpm: .max):
            return decision
        case let .manual(targetRPM):
            if bypassRamp {
                return .manual(rpm: clamp(rpm: env.profile.quantizedRPM(targetRPM)))
            }

            let elapsed = max(now.timeIntervalSince(lastAppliedAt), 0)
            let rampElapsed = min(elapsed, 1.0)
            let currentRPM: Int?
            if case let .manual(lastRPM) = lastAppliedDecision {
                currentRPM = lastRPM
            } else {
                currentRPM = env.fans
                    .filter { activeFanIDs().contains($0.id) }
                    .map(\.targetRPM)
                    .filter { $0 > 0 }
                    .max()
            }

            if env.profile.shouldHoldManualRPMTransition(
                from: currentRPM,
                to: targetRPM,
                elapsed: elapsed
            ), let currentRPM {
                return .manual(rpm: clamp(rpm: currentRPM))
            }

            let rampedRPM = env.profile.rampedManualRPM(
                from: currentRPM,
                toward: targetRPM,
                elapsed: rampElapsed
            )
            return .manual(rpm: clamp(rpm: rampedRPM))
        }
    }

    func blendedControlTemperature(for sensor: TemperatureSensor) -> Double {
        guard let env = environment else { return sensor.celsius }

        guard env.profile.sensorSelection.kind == .cpuAverage,
              let hottestCPU = env.hottestCPUSensor() else {
            return sensor.celsius
        }

        return max(sensor.celsius, hottestCPU.celsius - 6.0)
    }

    func filteredAutomationTemperature(for sensor: TemperatureSensor) -> Double {
        guard let env = environment else { return sensor.celsius }

        let controlSample = blendedControlTemperature(for: sensor)

        if smoothedAutomationSensorID != sensor.id {
            smoothedAutomationSensorID = sensor.id
            smoothedAutomationTemperature = controlSample
            return controlSample
        }

        let filtered = env.profile.filteredTemperature(
            previous: smoothedAutomationTemperature,
            current: controlSample
        )
        smoothedAutomationTemperature = filtered
        return filtered
    }

    // MARK: - Helpers

    func activeFanIDs() -> [Int] {
        guard let env = environment else { return [] }
        let configured = env.profile.fanIDs
        if configured.isEmpty {
            return env.fans.map(\.id)
        }
        return env.fans.map(\.id).filter { configured.contains($0) }
    }

    func fanStateMatches(
        decision: AutomationDecision,
        fanIDs: [Int],
        snapshots: [FanSnapshot]
    ) -> Bool {
        Self.fanStateMatches(
            decision: decision,
            fanIDs: fanIDs,
            snapshots: snapshots,
            verificationToleranceRPM: automationVerificationToleranceRPM
        )
    }

    private func maxSelectedFanRPM() -> Int {
        guard let env = environment else { return 7800 }
        let selectedFans = env.fans.filter { activeFanIDs().contains($0.id) }
        return selectedFans.map(\.maxRPM).max() ?? 7800
    }

    private func clamp(rpm: Int) -> Int {
        guard let env = environment else { return max(rpm, 0) }
        let safeRPM = max(rpm, 0)
        let selectedFans = env.fans.filter { activeFanIDs().contains($0.id) }
        let minRPM = selectedFans.map(\.minRPM).min() ?? safeRPM
        let maxRPM = selectedFans.map(\.maxRPM).max() ?? safeRPM
        return min(max(safeRPM, minRPM), maxRPM)
    }

    private func controlTemperatureDetail(for sensor: TemperatureSensor, controlTemperature: Double) -> String {
        guard let env = environment else { return sensor.name }

        if env.profile.sensorSelection.kind == .cpuAverage,
           let hottestCPU = env.hottestCPUSensor(),
           controlTemperature > sensor.celsius + 0.4,
           hottestCPU.celsius > sensor.celsius + 4.0 {
            return String.tr("automation.control_detail.cpu_blended")
        }

        return sensor.name
    }

    // MARK: - Static Methods

    nonisolated static func interruptionDecision(
        lastAppliedDecision: AutomationDecision?,
        lastHealthyAt: Date,
        now: Date,
        fanIDs: [Int],
        snapshots: [FanSnapshot],
        graceSeconds: Double
    ) -> AutomationDecision? {
        guard now.timeIntervalSince(lastHealthyAt) <= graceSeconds else {
            return nil
        }

        if case let .manual(rpm) = lastAppliedDecision, rpm > 0 {
            return .manual(rpm: rpm)
        }

        let selectedFanIDs = Set(fanIDs)
        let selectedSnapshots = snapshots.filter { selectedFanIDs.isEmpty || selectedFanIDs.contains($0.id) }
        let manualTargets = selectedSnapshots
            .filter { $0.mode == .manual && $0.targetRPM > 0 }
            .map(\.targetRPM)

        guard let heldRPM = manualTargets.max() else {
            return nil
        }

        return .manual(rpm: heldRPM)
    }

    nonisolated static func shouldReapplyHeldDecision(
        _ heldDecision: AutomationDecision,
        fanIDs: [Int],
        snapshots: [FanSnapshot],
        writableBackendAvailable: Bool,
        verificationToleranceRPM: Int = 180
    ) -> Bool {
        guard writableBackendAvailable else { return false }
        return !fanStateMatches(
            decision: heldDecision,
            fanIDs: fanIDs,
            snapshots: snapshots,
            verificationToleranceRPM: verificationToleranceRPM
        )
    }

    nonisolated static func fanStateMatches(
        decision: AutomationDecision,
        fanIDs: [Int],
        snapshots: [FanSnapshot],
        verificationToleranceRPM: Int
    ) -> Bool {
        guard !fanIDs.isEmpty else { return false }

        return fanIDs.allSatisfy { fanID in
            guard let snapshot = snapshots.first(where: { $0.id == fanID }) else {
                return false
            }

            switch decision {
            case .auto:
                return snapshot.mode == .auto
            case let .manual(rpm):
                return snapshot.mode == .manual &&
                    abs(snapshot.targetRPM - rpm) <= verificationToleranceRPM
            }
        }
    }
}
