import SwiftUI

struct MenuBarPanel: View {
    @Bindable var model: AppModel
    @State private var isShowingCPUCores = false
    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    CompactToolbarButton(
                        title: String.tr("tab.dashboard"),
                        icon: "rectangle.grid.2x2.fill"
                    ) {
                        model.showTab(.dashboard)
                    }

                    CompactToolbarButton(
                        title: String.tr("tab.sensors"),
                        icon: "thermometer.medium"
                    ) {
                        model.showTab(.sensors)
                    }

                    CompactToolbarButton(
                        title: String.tr("tab.settings"),
                        icon: "gearshape.fill"
                    ) {
                        model.showTab(.settings)
                    }

                    CompactToolbarButton(
                        title: model.settings.automationEnabled
                            ? String.tr("menu.disable_automation")
                            : String.tr("menu.enable_automation"),
                        icon: model.settings.automationEnabled ? "pause.circle.fill" : "play.circle.fill",
                        accent: model.settings.automationEnabled ? APColor.statusSuccess : .secondary,
                        isProminent: model.settings.automationEnabled
                    ) {
                        Task {
                            await model.toggleAutomationFromMenuBar()
                        }
                    }

                    CompactToolbarButton(
                        title: String.tr("common.refresh"),
                        icon: "arrow.clockwise"
                    ) {
                        model.requestRefresh(forceDetailed: true)
                    }
                    .keyboardShortcut("r", modifiers: .command)

                    CompactToolbarButton(
                        title: String.tr("quit.banner.trigger"),
                        icon: "power",
                        accent: APColor.statusWarning,
                        isProminent: true
                    ) {
                        model.requestSafeQuit()
                    }
                }
                .buttonStyle(.plain)

                if model.shouldShowHelperApprovalBanner {
                    HStack(spacing: 10) {
                        Label(String.tr("helper.approval.banner.title"), systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(APColor.statusWarning)
                        Spacer()
                        Button(String.tr("helper.approval.banner.action")) {
                                model.openLoginItemsSettings()
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .tintedCard(APColor.statusWarning, cornerRadius: 14, prominent: true)
                }

                if let error = model.lastErrorMessage, !error.isEmpty {
                    InlineStatusBanner(
                        title: String.tr("menu.error_status"),
                        message: error,
                        tint: APColor.statusError,
                        icon: "exclamationmark.triangle.fill"
                    )
                } else if let notice = model.lastNoticeMessage, !notice.isEmpty {
                    InlineStatusBanner(
                        title: String.tr("menu.notice_status"),
                        message: notice,
                        tint: APColor.statusSuccess,
                        icon: "checkmark.circle.fill"
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("AeroPulse")
                            .font(.headline.weight(.semibold))
                        Spacer()
                        Text(compactSummary)
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    MetricsOverviewBoard(
                        cpuValue: temperatureString(model.summary.cpuAverage),
                        gpuValue: temperatureString(model.summary.gpuAverage),
                        batteryValue: temperatureString(model.summary.batteryAverage),
                        hottestValue: hottestSensorInlineValue,
                        cpuAccent: temperatureAccent(model.summary.cpuAverage),
                        gpuAccent: temperatureAccent(model.summary.gpuAverage),
                        batteryAccent: temperatureAccent(model.summary.batteryAverage),
                        hottestAccent: temperatureAccent(model.summary.hottest?.celsius),
                        openSensors: { model.showTab(.sensors) }
                    )

                    if model.isSensorDataStale {
                        Text(String.tr("dashboard.stale_data"))
                            .font(.caption)
                            .foregroundStyle(APColor.statusWarning)
                    }

                    Divider().opacity(0.5)

                    CompactInfoRow(label: String.tr("menu.active_profile"), value: model.selectedProfileDisplayName)
                    CompactInfoRow(label: String.tr("menu.backend"), value: String.tr(model.fanWriteBackendState.titleKey), valueTint: APColor.backendAccent(for: model.fanWriteBackendState))
                    Button {
                        model.showTab(.sensors)
                    } label: {
                        CompactInfoRow(label: String.tr(model.automationControlLabelKey), value: primarySensorValue, showsChevron: true)
                    }
                    .buttonStyle(.plain)
                }
                .panelSection()

                VStack(alignment: .leading, spacing: 8) {
                    Text(String.tr("menu.quick_profiles"))
                        .font(.subheadline.weight(.semibold))

                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(model.availablePresets) { presetID in
                            Button {
                                Task {
                                    await model.activatePreset(presetID)
                                }
                            } label: {
                                QuickProfileButton(
                                    title: String.tr(presetID.titleKey),
                                    icon: iconName(for: presetID),
                                    isSelected: model.isQuickProfileSelected(presetID)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .panelSection()

                DisclosureGroup(isExpanded: $isShowingCPUCores) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(cpuCoreGroups, id: \.titleKey) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(String.tr(group.titleKey))
                                        .font(.caption.weight(.semibold))
                                    Spacer()
                                    Text(temperatureString(group.average))
                                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                                        .foregroundStyle(temperatureAccent(group.average))
                                }

                                ForEach(group.sensors) { sensor in
                                    HStack {
                                        Text(sensor.name)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(String(format: "%.1f", sensor.celsius))°C")
                                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                                            .foregroundStyle(temperatureAccent(sensor.celsius))
                                    }
                                }
                            }
                            .padding(10)
                            .tintedCard(temperatureAccent(group.average), cornerRadius: 12)
                        }

                        if cpuCoreSensors.isEmpty {
                            Text(String.tr("menu.no_cpu_cores"))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    HStack {
                        Text(String.tr("menu.cpu_cores"))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(cpuCoreSensors.count)")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.12), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                .panelSection()

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.fans) { fan in
                        let fanTint = fan.mode == .manual ? APColor.statusInfo : Color.secondary
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(fan.name)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(fan.mode.localizedTitle)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(fanTint.opacity(0.12), in: Capsule())
                                    .foregroundStyle(fanTint)
                            }

                            HStack(spacing: 12) {
                                FanMetric(label: String.tr("menu.current_rpm"), value: rpmString(fan.currentRPM))
                                FanMetric(label: String.tr("menu.target_rpm"), value: rpmString(fan.targetRPM))
                            }
                        }
                        .padding(10)
                        .tintedCard(fanTint, cornerRadius: 14)
                        .accessibilityElement(children: .combine)
                    }

                    if model.fans.isEmpty {
                        Text(String.tr("menu.no_fans"))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 10) {
                    Toggle(
                        String.tr("automation.enabled"),
                        isOn: Binding(
                            get: { model.settings.automationEnabled },
                            set: { newValue in
                                model.settings.automationEnabled = newValue
                                model.saveConfiguration()
                                model.requestRefresh(forceDetailed: true)
                            }
                        )
                    )
                        .toggleStyle(.switch)

                    Divider().opacity(0.5)

                    HStack(spacing: 10) {
                        Button {
                            model.showTab(.dashboard)
                        } label: {
                            Label(String.tr("menu.open_app"), systemImage: "arrow.up.forward.app")
                        }

                        Spacer()

                        Button {
                            model.requestSafeQuit()
                        } label: {
                            Label(String.tr("quit.banner.trigger"), systemImage: "power")
                        }
                        .foregroundStyle(APColor.statusWarning)
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .panelSection()

                if model.isQuitBannerPresented {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(String.tr("quit.banner.title"))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(model.isPreparingToQuit ? model.quitBannerDetail : String.tr("quit.banner.trigger"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(model.isPreparingToQuit ? model.quitBannerDetail : String.tr("quit.banner.body"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        HStack {
                            Button(String.tr("common.cancel")) {
                                model.dismissQuitBanner()
                            }
                            .disabled(model.isPreparingToQuit)

                            Spacer()

                            Button(String.tr("quit.banner.confirm")) {
                                model.confirmSafeQuit()
                            }
                            .disabled(model.isPreparingToQuit)
                        }
                    }
                    .padding(10)
                    .tintedCard(APColor.statusWarning, cornerRadius: 14, prominent: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .frame(minHeight: 760, maxHeight: 920)
    }

    private var primarySensorValue: String {
        model.automationControlSummary
    }

    private var hottestSensorInlineValue: String {
        guard let sensor = model.summary.hottest else {
            return String.tr("automation.reason.no_sensor")
        }

        return "\(sensor.name) \(String(format: "%.1f", sensor.celsius))°C"
    }

    private var compactSummary: String {
        let cpu = model.summary.cpuAverage.map { "\(Int($0.rounded()))°" } ?? "—"
        let rpm = model.menuBarFanRPM().map { "\($0)" } ?? "—"
        return "\(cpu) · \(rpm)"
    }

    private var cpuCoreSensors: [TemperatureSensor] {
        model.sensors
            .filter { sensor in
                sensor.name.localizedCaseInsensitiveContains("CPU") &&
                sensor.name.localizedCaseInsensitiveContains("Core")
            }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private var cpuCoreGroups: [CPUSensorGroup] {
        let groups = Dictionary(grouping: cpuCoreSensors) { sensor -> String in
            if sensor.name.localizedCaseInsensitiveContains("Super Core") {
                return "menu.cpu_group.super"
            }
            if sensor.name.localizedCaseInsensitiveContains("Performance Core") {
                return "menu.cpu_group.performance"
            }
            return "menu.cpu_group.other"
        }

        let order = ["menu.cpu_group.super", "menu.cpu_group.performance", "menu.cpu_group.other"]

        return order.compactMap { key in
            guard let sensors = groups[key], !sensors.isEmpty else { return nil }
            let average = sensors.map(\.celsius).reduce(0, +) / Double(sensors.count)
            return CPUSensorGroup(titleKey: key, sensors: sensors, average: average)
        }
    }

    private func temperatureString(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(String(format: "%.1f", value))°C"
    }

    private func temperatureAccent(_ value: Double?) -> Color {
        APColor.thermalAccent(for: value)
    }

    private func rpmString(_ value: Int) -> String {
        value == 0 ? "0 RPM" : "\(value) RPM"
    }



    private func iconName(for presetID: ProfilePresetID) -> String {
        switch presetID {
        case .macDefault:
            return "apple.logo"
        case .performanceLight:
            return "speedometer"
        case .performanceMedium:
            return "gauge.with.dots.needle.50percent"
        case .performanceStrong:
            return "bolt.fill"
        case .maxCooling:
            return "fanblades.fill"
        }
    }
}

private struct CPUSensorGroup {
    let titleKey: String
    let sensors: [TemperatureSensor]
    let average: Double
}

private struct CompactToolbarButton: View {
    let title: String
    let icon: String
    var accent: Color = .accentColor
    var isProminent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isProminent ? Color.white : accent)

                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isProminent ? Color.white.opacity(0.9) : Color.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .tintedCard(accent, cornerRadius: 12, prominent: isProminent)
        }
        .accessibilityLabel(title)
    }
}

private struct MetricsOverviewBoard: View {
    let cpuValue: String
    let gpuValue: String
    let batteryValue: String
    let hottestValue: String
    let cpuAccent: Color
    let gpuAccent: Color
    let batteryAccent: Color
    let hottestAccent: Color
    let openSensors: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                OverviewMetricTile(label: String.tr("menu.cpu_average"), value: cpuValue, accent: cpuAccent)
                OverviewMetricTile(label: String.tr("menu.gpu_average"), value: gpuValue, accent: gpuAccent)
            }

            HStack(spacing: 8) {
                OverviewMetricTile(label: String.tr("menu.battery_average"), value: batteryValue, accent: batteryAccent)
                Button(action: openSensors) {
                    OverviewMetricTile(label: String.tr("menu.hottest_sensor"), value: hottestValue, accent: hottestAccent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(String.tr("menu.hottest_sensor")): \(hottestValue)")
            }
        }
    }
}

private struct OverviewMetricTile: View {
    let label: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                .foregroundStyle(accent)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .tintedCard(accent, cornerRadius: 10)
        .accessibilityElement(children: .combine)
    }
}

private struct InlineStatusBanner: View {
    let title: String
    let message: String
    let tint: Color
    let icon: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .tintedCard(tint, cornerRadius: 14)
    }
}

private struct CompactInfoRow: View {
    let label: String
    let value: String
    var valueTint: Color? = nil
    var showsChevron: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 6) {
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(valueTint ?? .primary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct FanMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct QuickProfileButton: View {
    let title: String
    let icon: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(isSelected ? APColor.statusInfo : Color.primary.opacity(0.06))
                )

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tintedCard(isSelected ? APColor.statusInfo : Color.primary.opacity(0.3), cornerRadius: 12, prominent: isSelected)
        .accessibilityLabel(title)
    }
}
