import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    private let menuBarSelectionKinds: [SensorSelectionKind] = [.cpuAverage, .hottestCPUCore, .hottest, .specific]

    var body: some View {
        Form {
            Section(String.tr("settings.experience")) {
                Picker(String.tr("settings.language"), selection: $model.settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(String.tr(language.titleKey))
                            .tag(language)
                    }
                }

                Picker(String.tr("settings.theme"), selection: $model.settings.theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(String.tr(theme.titleKey))
                            .tag(theme)
                    }
                }

                Text(String.tr("settings.experience_hint"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(String.tr("settings.telemetry")) {
                Stepper(value: $model.settings.pollingInterval, in: 0.5...10, step: 0.5) {
                    Text("\(String.tr("settings.poll_interval")): \(String(format: "%.1f", model.settings.pollingInterval))s")
                }

                Text(String.tr("settings.telemetry_hint"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if case .fallbackCLI = model.fanWriteBackendState {
                Section(String.tr("settings.executables")) {
                    Label {
                        Text(String.tr("settings.executables_fallback_hint"))
                            .font(.footnote)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(APColor.statusWarning)
                    }

                    TextField(String.tr("settings.fan_path"), text: $model.settings.fanExecutablePath)
                        .textFieldStyle(.roundedBorder)

                    TextField(String.tr("settings.ismc_path"), text: $model.settings.iSMCExecutablePath)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section(String.tr("settings.menu_bar")) {
                Picker(
                    String.tr("settings.menu_bar_sensor"),
                    selection: Binding(
                        get: { model.settings.menuBarSensorSelection.kind },
                        set: { newKind in
                            switch newKind {
                            case .cpuAverage:
                                model.settings.menuBarSensorSelection = .cpuAverage
                            case .hottestCPUCore:
                                model.settings.menuBarSensorSelection = .hottestCPUCore
                            case .hottest:
                                model.settings.menuBarSensorSelection = .hottest
                            case .specific:
                                model.settings.menuBarSensorSelection = .specific(model.settings.menuBarSensorSelection.key ?? model.sensors.first?.key)
                            case .gpuAverage, .batteryAverage:
                                model.settings.menuBarSensorSelection = .cpuAverage
                            }
                        }
                    )
                ) {
                    ForEach(menuBarSelectionKinds, id: \.self) { kind in
                        Text(title(for: kind))
                            .tag(kind)
                    }
                }

                if model.settings.menuBarSensorSelection.kind == .specific {
                    Picker(
                        String.tr("settings.menu_bar_specific_sensor"),
                        selection: Binding(
                            get: { model.settings.menuBarSensorSelection.key ?? model.sensors.first?.key ?? "" },
                            set: { newKey in
                                model.settings.menuBarSensorSelection = .specific(newKey.isEmpty ? nil : newKey)
                            }
                        )
                    ) {
                        ForEach(model.sensors) { sensor in
                            Text(sensor.name)
                                .tag(sensor.key)
                        }
                    }
                }

                Text(String.tr("settings.menu_bar_hint"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(String.tr("settings.backend")) {
                let backendTint = APColor.backendAccent(for: model.fanWriteBackendState)
                HStack {
                    Text(String.tr(model.fanWriteBackendState.titleKey))
                    Spacer()
                    Text(String.tr(model.fanWriteBackendState.detailKey))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(backendTint.opacity(0.12), in: Capsule())
                        .foregroundStyle(backendTint)
                }
                if let backendReason = model.fanWriteBackendState.reason, !backendReason.isEmpty {
                    Text(backendReason)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section(String.tr("settings.privileged_helper")) {
                Text(String.tr(model.privilegedHelperStatus.titleKey))
                Text(String.tr(model.privilegedHelperStatus.detailKey))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [
                    GridItem(.flexible(minimum: 180), spacing: 12),
                    GridItem(.flexible(minimum: 180), spacing: 12)
                ], spacing: 12) {
                    ForEach(model.privilegedHelperChecklist) { checkpoint in
                        helperCheckpointCard(checkpoint)
                    }
                }
                .padding(.vertical, 4)

                if let failureReason = model.privilegedHelperStatus.failureReason, !failureReason.isEmpty {
                    Text(failureReason)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let notice = model.lastNoticeMessage, !notice.isEmpty {
                    Label(notice, systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(APColor.statusSuccess)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .tintedCard(APColor.statusSuccess, cornerRadius: 10)
                }

                if !model.privilegedHelperGuidance.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.privilegedHelperGuidance, id: \.self) { note in
                            Label(note, systemImage: "info.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                diagnosticsCard

                HStack(spacing: 8) {
                    Button(String.tr("settings.privileged_helper.register")) {
                        Task {
                            await model.registerPrivilegedHelper()
                        }
                    }
                    .disabled(model.privilegedHelperStatus == .enabled || model.privilegedHelperStatus == .unsupported)

                    Button(String.tr("settings.privileged_helper.unregister")) {
                        Task {
                            await model.unregisterPrivilegedHelper()
                        }
                    }
                    .disabled(model.privilegedHelperStatus == .notRegistered || model.privilegedHelperStatus == .unsupported)

                    Spacer()

                    Button(String.tr("settings.privileged_helper.run_doctor")) {
                        Task {
                            await model.runPrivilegedHelperDoctor()
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button(String.tr("settings.privileged_helper.reveal_app")) {
                        model.revealCurrentAppInFinder()
                    }

                    Button(String.tr("settings.privileged_helper.open_applications")) {
                        model.openApplicationsFolder()
                    }

                    Button(String.tr("settings.privileged_helper.open_login_items")) {
                        model.openLoginItemsSettings()
                    }
                }

                HStack(spacing: 8) {
                    Button(String.tr("settings.privileged_helper.install_to_applications")) {
                        model.installCurrentAppToApplications()
                    }

                    Button(String.tr("settings.privileged_helper.install_and_relaunch")) {
                        model.installAndRelaunchFromApplications()
                    }

                    Spacer()

                    Button(String.tr("settings.privileged_helper.copy_diagnostics")) {
                        model.copyPrivilegedHelperDiagnostics()
                    }

                    Button(String.tr("settings.privileged_helper.copy_doctor")) {
                        model.copyPrivilegedHelperDoctorReport()
                    }
                }

                if !model.privilegedHelperDoctorReport.isEmpty {
                    ScrollView {
                        Text(model.privilegedHelperDoctorReport)
                            .font(.footnote.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 160, maxHeight: 220)
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
                }

                Text(String.tr("settings.privileged_helper.hint"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(String.tr("settings.integration")) {
                Text(String.tr("settings.integration.line1"))
                Text(String.tr("settings.integration.line2"))
                Text(String.tr("settings.integration.line3"))
            }

            Section {
                HStack {
                    Button(String.tr("common.save")) {
                        model.saveConfiguration()
                    }

                    Button(String.tr("common.refresh")) {
                        model.requestRefresh(forceDetailed: true)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func title(for kind: SensorSelectionKind) -> String {
        switch kind {
        case .cpuAverage:
            return String.tr("settings.menu_bar_option.cpu_average")
        case .hottestCPUCore:
            return String.tr("settings.menu_bar_option.hottest_cpu_core")
        case .hottest:
            return String.tr("settings.menu_bar_option.hottest_sensor")
        case .specific:
            return String.tr("settings.menu_bar_option.specific_sensor")
        case .gpuAverage:
            return String.tr("sensor.gpu_average")
        case .batteryAverage:
            return String.tr("sensor.battery_average")
        }
    }

    @ViewBuilder
    private var diagnosticsCard: some View {
        let diag = model.privilegedHelperDiagnostics
        VStack(spacing: 0) {
            diagnosticRow(label: String.tr("settings.diag.bundle_path"), value: diag.bundlePath.isEmpty ? "-" : diag.bundlePath, status: nil)
            Divider().opacity(0.3)
            diagnosticRow(label: String.tr("settings.diag.team_id"), value: diag.teamIdentifier ?? String.tr("settings.diag.unsigned"), status: diag.teamIdentifier != nil ? .ok : .warn)
            Divider().opacity(0.3)
            diagnosticRow(label: String.tr("settings.diag.install_state"), value: diag.isInstalledInApplications ? "/Applications" : String.tr("settings.diag.outside_applications"), status: diag.isInstalledInApplications ? .ok : .warn)
            Divider().opacity(0.3)
            diagnosticRow(label: String.tr("settings.diag.detected_fans"), value: model.detectedFanCountLabel, status: model.hasDetectedNoFans ? .warn : .ok)
            Divider().opacity(0.3)
            diagnosticRow(label: String.tr("settings.diag.registered_program"), value: diag.registeredProgramPath ?? String.tr("settings.diag.unknown"), status: diag.hasRegistrationPathMismatch ? .warn : (diag.registeredProgramPath == nil ? .warn : .ok))
            Divider().opacity(0.3)
            diagnosticRow(label: String.tr("settings.diag.helper_tool"), value: diag.helperToolEmbedded ? String.tr("settings.diag.embedded") : String.tr("settings.diag.missing"), status: diag.helperToolEmbedded ? .ok : .error)
            Divider().opacity(0.3)
            diagnosticRow(label: String.tr("settings.diag.launch_daemon"), value: diag.launchDaemonEmbedded ? String.tr("settings.diag.embedded") : String.tr("settings.diag.missing"), status: diag.launchDaemonEmbedded ? .ok : .error)
            Divider().opacity(0.3)
            diagnosticRow(label: String.tr("settings.diag.release_readiness"), value: diag.isReadyForReleaseRegistration ? String.tr("settings.diag.ready") : String.tr("settings.diag.needs_work"), status: diag.isReadyForReleaseRegistration ? .ok : .warn)
        }
        .padding(2)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private enum DiagStatus { case ok, warn, error }

    private func diagnosticRow(label: String, value: String, status: DiagStatus?) -> some View {
        HStack {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 5) {
                Text(value)
                    .font(.footnote.monospaced())
                    .foregroundStyle(statusColor(status))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let status {
                    Image(systemName: statusIcon(status))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(statusColor(status))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func statusColor(_ status: DiagStatus?) -> Color {
        switch status {
        case .ok: APColor.statusSuccess
        case .warn: APColor.statusWarning
        case .error: APColor.statusError
        case nil: .secondary
        }
    }

    private func statusIcon(_ status: DiagStatus) -> String {
        switch status {
        case .ok: "checkmark.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .error: "xmark.circle.fill"
        }
    }

    @ViewBuilder
    private func helperCheckpointCard(_ checkpoint: HelperSetupCheckpoint) -> some View {
        let tint = APColor.helperCheckpointAccent(for: checkpoint.state)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(String.tr(checkpoint.titleKey))
                    .font(.headline)
                Spacer(minLength: 8)
                Text(String.tr(checkpoint.state.titleKey))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.12), in: Capsule())
                    .foregroundStyle(tint)
            }

            Text(String.tr(checkpoint.detailKey))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tintedCard(tint, cornerRadius: 14)
    }
}
