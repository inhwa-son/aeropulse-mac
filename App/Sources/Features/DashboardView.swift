import SwiftUI

struct DashboardView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    MetricCard(
                        title: String.tr("dashboard.status"),
                        value: integrationTitle,
                        subtitle: automationTitle,
                        tint: APColor.integrationAccent(for: model.integrationState)
                    )

                    MetricCard(
                        title: String.tr("dashboard.hottest"),
                        value: model.summary.hottest.map { "\($0.name) \(Int($0.celsius.rounded()))°C" } ?? "—",
                        subtitle: String.tr("dashboard.live"),
                        tint: APColor.thermalAccent(for: model.summary.hottest?.celsius)
                    )

                    MetricCard(
                        title: String.tr("dashboard.avg_cpu"),
                        value: format(model.summary.cpuAverage),
                        subtitle: String.tr("dashboard.average"),
                        tint: APColor.thermalAccent(for: model.summary.cpuAverage)
                    )

                    MetricCard(
                        title: String.tr("dashboard.backend"),
                        value: String.tr(model.fanWriteBackendState.titleKey),
                        subtitle: String.tr(model.fanWriteBackendState.detailKey),
                        tint: APColor.backendAccent(for: model.fanWriteBackendState)
                    )
                }

                if model.isSensorDataStale {
                    Text(String.tr("dashboard.stale_data"))
                        .font(.caption)
                        .foregroundStyle(APColor.statusWarning)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(String.tr("dashboard.fans"))
                        .font(.title2.bold())

                    if model.fans.isEmpty {
                        Text(String.tr("dashboard.no_fans"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.fans) { fan in
                            let modeTint = fan.mode == .manual ? APColor.statusInfo : Color.secondary
                            HStack {
                                Text(fan.name)
                                    .fontWeight(.semibold)
                                Text(fan.mode.localizedTitle)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(modeTint.opacity(0.12), in: Capsule())
                                    .foregroundStyle(modeTint)
                                Spacer()
                                Text("\(fan.currentRPM)")
                                    .monospacedDigit()
                                    .fontWeight(.semibold)
                                Text("→")
                                    .foregroundStyle(.tertiary)
                                Text("\(fan.targetRPM) RPM")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                            .accessibilityElement(children: .combine)

                            Divider()
                        }
                    }
                }
                .cardStyle()

                VStack(alignment: .leading, spacing: 12) {
                    Text(String.tr("dashboard.notes"))
                        .font(.title2.bold())

                    Text(String.tr("dashboard.notes.line1"))
                    Text(String.tr("dashboard.notes.line2"))

                    if let backendReason = model.fanWriteBackendState.reason, !backendReason.isEmpty {
                        Text(backendReason)
                            .foregroundStyle(.secondary)
                    }

                    if let error = model.lastErrorMessage, !error.isEmpty {
                        Text(error)
                            .foregroundStyle(APColor.statusError)
                    }
                }
                .cardStyle()
            }
        }
    }

    private var integrationTitle: String {
        switch model.integrationState {
        case .ready:
            return String.tr("integration.ready")
        case .awaitingApproval:
            return String.tr("integration.awaiting_approval")
        case .missingFanCLI:
            return String.tr("integration.missing_fan")
        case .missingISMC:
            return String.tr("integration.missing_ismc")
        case .failed:
            return String.tr("integration.failed")
        }
    }

    private var automationTitle: String {
        model.settings.automationEnabled ? model.automationSnapshot.reason : String.tr("automation.reason.disabled")
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))°C"
    }


}

private struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .tintedCard(tint)
        .accessibilityElement(children: .combine)
    }
}