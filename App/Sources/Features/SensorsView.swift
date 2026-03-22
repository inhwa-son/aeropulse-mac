import SwiftUI

struct SensorsView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(String.tr("sensors.title"))
                    .font(.title2.bold())
                Spacer()
                Button(String.tr("common.refresh")) {
                    model.requestRefresh(forceDetailed: true)
                }
            }

            Table(model.sensors) {
                TableColumn(String.tr("sensors.column.name")) { sensor in
                    Text(sensor.name)
                }

                TableColumn(String.tr("sensors.column.key")) { sensor in
                    Text(sensor.key)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                TableColumn(String.tr("sensors.column.source")) { sensor in
                    let sourceTint = sensor.source == .hid ? APColor.statusInfo : APColor.statusNeutral
                    Text(sensor.source.rawValue.uppercased())
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(sourceTint.opacity(0.12), in: Capsule())
                        .foregroundStyle(sourceTint)
                }

                TableColumn(String.tr("sensors.column.temp")) { sensor in
                    Text(String(format: "%.2f °C", sensor.celsius))
                        .monospacedDigit()
                        .foregroundStyle(APColor.thermalAccent(for: sensor.celsius))
                }
            }
            .overlay {
                if model.sensors.isEmpty {
                    Text(String.tr("sensors.empty"))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
