import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            DashboardView(model: model)
                .tag(AppTab.dashboard)
                .tabItem {
                    Label(String.tr("tab.dashboard"), systemImage: "gauge.with.dots.needle.33percent")
                }

            SensorsView(model: model)
                .tag(AppTab.sensors)
                .tabItem {
                    Label(String.tr("tab.sensors"), systemImage: "thermometer.medium")
                }

            AutomationView(model: model)
                .tag(AppTab.automation)
                .tabItem {
                    Label(String.tr("tab.automation"), systemImage: "slider.horizontal.3")
                }

            SettingsView(model: model)
                .tag(AppTab.settings)
                .tabItem {
                    Label(String.tr("tab.settings"), systemImage: "gearshape")
                }
        }
        .padding(20)
        .background(.background.secondary)
        .safeAreaInset(edge: .top) {
            VStack(spacing: 10) {
                if model.shouldShowHelperApprovalBanner {
                    HelperApprovalBanner(openLoginItems: model.openLoginItemsSettings)
                }

                if model.isQuitBannerPresented {
                    SafeQuitBanner(
                        isPreparing: model.isPreparingToQuit,
                        detail: model.quitBannerDetail,
                        cancel: model.dismissQuitBanner,
                        confirm: model.confirmSafeQuit
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.requestSafeQuit()
                } label: {
                    Label(String.tr("quit.banner.trigger"), systemImage: "power")
                }
            }
        }
    }
}

private struct SafeQuitBanner: View {
    let isPreparing: Bool
    let detail: String
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String.tr("quit.banner.title"))
                    .font(.headline)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button(String.tr("common.cancel"), action: cancel)
                .disabled(isPreparing)

            Button(String.tr("quit.banner.confirm"), action: confirm)
                .keyboardShortcut(.defaultAction)
                .disabled(isPreparing)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct HelperApprovalBanner: View {
    let openLoginItems: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String.tr("helper.approval.banner.title"))
                    .font(.headline)
                Text(String.tr("helper.approval.banner.body"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button(String.tr("helper.approval.banner.action")) {
                openLoginItems()
            }
        }
        .padding(14)
        .tintedCard(APColor.statusWarning, cornerRadius: 14, prominent: true)
    }
}
