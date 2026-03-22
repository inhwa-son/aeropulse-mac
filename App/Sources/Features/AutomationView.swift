import Charts
import SwiftUI

struct AutomationView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(String.tr("automation.title"))
                        .font(.title2.bold())
                    Spacer()
                    Toggle(String.tr("automation.enabled"), isOn: $model.settings.automationEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                Form {
                    Picker(
                        String.tr("automation.profile"),
                        selection: Binding(
                            get: { model.settings.selectedPresetID },
                            set: { model.applyPreset($0) }
                        )
                    ) {
                        ForEach(model.availablePresets) { presetID in
                            Text(String.tr(presetID.titleKey))
                                .tag(presetID)
                        }
                    }

                    Text(String.tr(model.settings.profile.descriptionKey))
                        .foregroundStyle(.secondary)

                    if model.isSelectedPresetCustomized {
                        Text(String.tr("profile.custom_notice"))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(APColor.statusWarning)
                    }

                    Picker(
                        String.tr("automation.sensor"),
                        selection: Binding(
                            get: { model.settings.profile.sensorSelection.kind },
                            set: { newKind in
                                switch newKind {
                                case .cpuAverage:
                                    model.settings.profile.sensorSelection = .cpuAverage
                                case .hottestCPUCore:
                                    model.settings.profile.sensorSelection = .hottestCPUCore
                                case .hottest:
                                    model.settings.profile.sensorSelection = .hottest
                                case .gpuAverage:
                                    model.settings.profile.sensorSelection = .gpuAverage
                                case .batteryAverage:
                                    model.settings.profile.sensorSelection = .batteryAverage
                                case .specific:
                                    model.settings.profile.sensorSelection = .specific(model.settings.profile.sensorSelection.key ?? model.sensors.first?.key)
                                }
                            }
                        )
                    ) {
                        Text(String.tr("settings.menu_bar_option.cpu_average")).tag(SensorSelectionKind.cpuAverage)
                        Text(String.tr("settings.menu_bar_option.hottest_cpu_core")).tag(SensorSelectionKind.hottestCPUCore)
                        Text(String.tr("settings.menu_bar_option.hottest_sensor")).tag(SensorSelectionKind.hottest)
                        Text(String.tr("sensor.gpu_average")).tag(SensorSelectionKind.gpuAverage)
                        Text(String.tr("sensor.battery_average")).tag(SensorSelectionKind.batteryAverage)
                        Text(String.tr("settings.menu_bar_option.specific_sensor")).tag(SensorSelectionKind.specific)
                    }

                    if model.settings.profile.sensorSelection.kind == .specific {
                        Picker(
                            String.tr("settings.menu_bar_specific_sensor"),
                            selection: Binding(
                                get: { model.settings.profile.sensorSelection.key ?? model.sensors.first?.key ?? "" },
                                set: { newKey in
                                    model.settings.profile.sensorSelection = .specific(newKey.isEmpty ? nil : newKey)
                                }
                            )
                        ) {
                            ForEach(model.sensors) { sensor in
                                Text(sensor.name).tag(sensor.key)
                            }
                        }
                    }

                    LabeledContent(String.tr(model.automationControlLabelKey)) {
                        Text(model.automationControlSummary)
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent(String.tr("automation.fans")) {
                        if model.fans.isEmpty {
                            Text(String.tr("automation.no_fans"))
                                .foregroundStyle(.secondary)
                        } else {
                            HStack {
                                ForEach(model.fans) { fan in
                                    Toggle(
                                        fan.name,
                                        isOn: Binding(
                                            get: { model.settings.profile.fanIDs.contains(fan.id) },
                                            set: { model.toggleFanSelection(fan.id, enabled: $0) }
                                        )
                                    )
                                    .toggleStyle(.checkbox)
                                }
                            }
                        }
                    }

                    if model.settings.profile.strategy == .curve {
                        Stepper(value: $model.settings.profile.hysteresis, in: 0...10, step: 0.5) {
                            Text("\(String.tr("automation.hysteresis")): \(String(format: "%.1f", model.settings.profile.hysteresis))°C")
                        }

                        Stepper(value: $model.settings.profile.minimumHoldSeconds, in: 1...20, step: 1) {
                            Text("\(String.tr("automation.minimum_hold")): \(Int(model.settings.profile.minimumHoldSeconds))s")
                        }
                    }
                }
                .formStyle(.grouped)

                if model.settings.profile.strategy == .curve {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(String.tr("automation.curve"))
                                .font(.headline)
                            Spacer()
                            Button(String.tr("automation.add_point")) {
                                model.addCurvePoint()
                            }
                            Button(String.tr("automation.reset")) {
                                model.resetProfile()
                            }
                        }

                        Chart(model.settings.profile.sortedCurve) { point in
                            LineMark(
                                x: .value("Temperature", point.temperature),
                                y: .value("RPM", point.rpm)
                            )
                            .interpolationMethod(.cardinal)
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [APColor.thermalCool, APColor.thermalNormal, APColor.thermalWarm, APColor.thermalHot],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .lineStyle(StrokeStyle(lineWidth: 2.5))

                            AreaMark(
                                x: .value("Temperature", point.temperature),
                                y: .value("RPM", point.rpm)
                            )
                            .interpolationMethod(.cardinal)
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [
                                        APColor.thermalCool.opacity(0.18),
                                        APColor.thermalNormal.opacity(0.14),
                                        APColor.thermalWarm.opacity(0.10),
                                        APColor.thermalHot.opacity(0.06)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )

                            PointMark(
                                x: .value("Temperature", point.temperature),
                                y: .value("RPM", point.rpm)
                            )
                            .foregroundStyle(APColor.thermalAccent(for: point.temperature))
                            .symbolSize(48)
                        }
                        .chartXAxisLabel(String.tr("automation.temp_threshold"))
                        .chartYAxisLabel(String.tr("automation.rpm_label"))
                        .frame(height: 220)

                        ForEach($model.settings.profile.curve) { $point in
                            HStack {
                                Stepper(
                                    value: $point.temperature,
                                    in: 30...105,
                                    step: 1
                                ) {
                                    Text("\(String.tr("automation.temp_threshold")): \(Int(point.temperature.rounded()))°C")
                                }

                                Stepper(
                                    value: $point.rpm,
                                    in: 2000...8000,
                                    step: 100
                                ) {
                                    Text("\(String.tr("automation.rpm_target")): \(point.rpm)")
                                }

                                Button(role: .destructive) {
                                    model.removeCurvePoint(point.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .accessibilityLabel(String.tr("automation.delete_point"))
                            }
                        }
                    }
                    .cardStyle()
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String.tr("automation.curve"))
                            .font(.headline)
                        Text(String.tr("automation.profile_static"))
                            .foregroundStyle(.secondary)
                    }
                    .cardStyle()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(String.tr("automation.live_state"))
                        .font(.headline)
                    Text(model.automationSnapshot.reason)
                    if let controlTemperature = model.automationSnapshot.controlTemperature {
                        HStack(spacing: 6) {
                            Text(model.automationSnapshot.controlDetail ?? String.tr("automation.control_detail.raw"))
                                .foregroundStyle(.secondary)
                            Text("\(String(format: "%.2f", controlTemperature))°C")
                                .font(.system(.body, design: .monospaced).weight(.semibold))
                                .foregroundStyle(APColor.thermalAccent(for: controlTemperature))
                        }
                    } else if let sensor = model.automationSnapshot.sensor {
                        HStack(spacing: 6) {
                            Text(sensor.name)
                                .foregroundStyle(.secondary)
                            Text("\(String(format: "%.2f", sensor.celsius))°C")
                                .font(.system(.body, design: .monospaced).weight(.semibold))
                                .foregroundStyle(APColor.thermalAccent(for: sensor.celsius))
                        }
                    }
                    Text(model.automationSnapshot.decision.summary)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .foregroundStyle(model.automationSnapshot.decision.isAuto ? .secondary : APColor.statusInfo)
                }
                .cardStyle()

                HStack {
                    Button(String.tr("common.save_now")) {
                        model.saveConfiguration()
                    }

                    Button(String.tr("common.refresh")) {
                        model.requestRefresh(forceDetailed: true)
                    }
                }
            }
        }
        .onChange(of: model.settings.automationEnabled) { _, _ in
            model.persistAutomationConfiguration()
        }
        .onChange(of: model.settings.profile) { _, _ in
            model.persistAutomationConfiguration()
        }
    }
}
