import SwiftUI

final class AeroPulseApplicationDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private let automaticTerminationReason = "Keep AeroPulse resident for menu bar controls and thermal automation."
    private var automaticTerminationDisabled = false

    func install(model: AppModel) {
        self.model = model
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let command = currentAppCommand else {
            if !automaticTerminationDisabled {
                ProcessInfo.processInfo.disableAutomaticTermination(automaticTerminationReason)
                automaticTerminationDisabled = true
            }

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                NSApp.activate()
                NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
            }
            return
        }

        Task { @MainActor in
            let exitCode = await AppCommandRunner.run(command)
            fflush(stdout)
            NSApp.terminate(nil)
            Darwin.exit(exitCode)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if automaticTerminationDisabled {
            ProcessInfo.processInfo.enableAutomaticTermination(automaticTerminationReason)
            automaticTerminationDisabled = false
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if currentAppCommand != nil {
            return .terminateNow
        }

        guard let model else {
            return .terminateNow
        }

        Task { @MainActor in
            await model.prepareForTermination()
            sender.reply(toApplicationShouldTerminate: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                Darwin.exit(EXIT_SUCCESS)
            }
        }
        return .terminateLater
    }
}

@main
struct AeroPulseApp: App {
    @NSApplicationDelegateAdaptor(AeroPulseApplicationDelegate.self) private var appDelegate
    @State private var model = AppModel()

    init() {
        if currentAppCommand != nil {
            NSApplication.shared.setActivationPolicy(.prohibited)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 720, minHeight: 560)
                .environment(\.locale, model.preferredLocale)
                .preferredColorScheme(preferredColorScheme)
                .onAppear {
                    AppLocalization.setLanguage(model.settings.language)
                    appDelegate.install(model: model)
                }
                .onChange(of: model.settings) { _, _ in
                    model.scheduleConfigurationSave()
                }
        }

        MenuBarExtra {
            MenuBarPanel(model: model)
                .padding(12)
                .frame(width: 500)
                .environment(\.locale, model.preferredLocale)
                .preferredColorScheme(preferredColorScheme)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "fanblades")
                    .font(.system(size: 14, weight: .semibold))

                VStack(alignment: .leading, spacing: -1) {
                    Text(menuBarTemperatureTitle)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)

                    Text(menuBarRPMTitle)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
        }
        .menuBarExtraStyle(.window)
    }

    private var preferredColorScheme: ColorScheme? {
        switch model.settings.theme {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    private var menuBarTemperatureTitle: String {
        if let temperature = model.menuBarSensor() {
            return "\(Int(temperature.celsius.rounded()))°"
        }
        if let hottest = model.summary.hottest {
            return "\(Int(hottest.celsius.rounded()))°"
        }
        return "--°"
    }

    private var menuBarRPMTitle: String {
        if let rpm = model.menuBarFanRPM() {
            return "\(rpm)"
        }
        return "--"
    }
}
