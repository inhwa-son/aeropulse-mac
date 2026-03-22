import Foundation

let currentAppCommand = AppCommand.current()

enum AppCommand: String {
    case helperStatus = "--helper-status"
    case helperRegister = "--helper-register"
    case helperUnregister = "--helper-unregister"
    case helperProbe = "--helper-probe"
    case helperDoctor = "--helper-doctor"
    case sensorDump = "--sensor-dump"
    case fanDump = "--fan-dump"
    case fanDumpDirect = "--fan-dump-direct"
    case fanModeDump = "--fan-mode-dump"
    case fanModeDumpHelper = "--fan-mode-dump-helper"
    case fanSetAuto = "--fan-set-auto"
    case fanSetManual = "--fan-set-manual"
    case fanSetAutoDirect = "--fan-set-auto-direct"
    case fanSetManualDirect = "--fan-set-manual-direct"
    case prepareTermination = "--prepare-termination"
    case openLoginItems = "--open-login-items"

    static func current() -> AppCommand? {
        CommandLine.arguments.dropFirst().compactMap(AppCommand.init(rawValue:)).first
    }
}

@MainActor
enum AppCommandRunner {
    static func run(_ command: AppCommand) async -> Int32 {
        let helperManager = PrivilegedHelperManager()

        switch command {
        case .helperStatus:
            write("""
            helper_status=\(statusName(helperManager.status()))
            """)
            return 0

        case .helperRegister:
            let status = (try? helperManager.register()) ?? .failed("register_failed")
            write("""
            helper_register=\(statusName(status))
            """)
            return (status == .enabled || status == .requiresApproval) ? 0 : 1

        case .helperUnregister:
            let status = (try? helperManager.unregister()) ?? .failed("unregister_failed")
            write("""
            helper_unregister=\(statusName(status))
            """)
            return status == .notRegistered ? 0 : 1

        case .helperProbe:
            let client = PrivilegedFanControlClient()
            do {
                try await client.probe()
                write("helper_probe=ok")
                return 0
            } catch {
                write("helper_probe=failed(\(error.localizedDescription))")
                return 1
            }

        case .helperDoctor:
            let status = helperManager.status()
            let diagnostics = helperManager.diagnostics()
            let notes = helperManager.preflightNotes()
            let guidance = notes.isEmpty ? "-" : notes.joined(separator: "\n- ")

            write("""
            helper_status=\(statusName(status))
            bundle_path=\(diagnostics.bundlePath)
            team_id=\(diagnostics.teamIdentifier ?? "missing")
            install_state=\(diagnostics.isInstalledInApplications ? "applications" : "external")
            helper_tool=\(diagnostics.helperToolEmbedded ? "embedded" : "missing")
            launch_daemon=\(diagnostics.launchDaemonEmbedded ? "embedded" : "missing")
            release_ready=\(diagnostics.isReadyForReleaseRegistration ? "yes" : "no")
            guidance:
            - \(guidance)
            """)
            return 0

        case .sensorDump:
            guard let hid = HIDTemperatureService() else {
                write("sensor_dump=unavailable")
                return 1
            }

            let sensors = hid.readSensors()
            let summary = sensors.dashboardSummary()
            let top = sensors.prefix(12).map { sensor in
                "\(sensor.name)=\(String(format: "%.1f", sensor.celsius))"
            }.joined(separator: ", ")

            write("""
            sensor_count=\(sensors.count)
            cpu_average=\(summary.cpuAverage.map { String(format: "%.1f", $0) } ?? "nil")
            gpu_average=\(summary.gpuAverage.map { String(format: "%.1f", $0) } ?? "nil")
            battery_average=\(summary.batteryAverage.map { String(format: "%.1f", $0) } ?? "nil")
            hottest=\(summary.hottest.map { "\($0.name)=\(String(format: "%.1f", $0.celsius))" } ?? "nil")
            sensors=\(top)
            """)
            return 0

        case .fanDump:
            let helperStatus = helperManager.status()
            let client = PrivilegedFanControlClient()

            if helperStatus.isReadyForWrites {
                do {
                    let fans = try await client.readFans()
                    let lines = fans.map { fan in
                        "fan\(fan.id)=\(fan.currentRPM)/\(fan.targetRPM)/\(fan.maxRPM) mode=\(fan.mode.rawValue)"
                    }.joined(separator: "\n")
                    write("""
                    fan_backend=privileged_helper
                    fan_count=\(fans.count)
                    \(lines)
                    """)
                    return 0
                } catch {
                    write("fan_dump=failed(\(error.localizedDescription))")
                    return 1
                }
            }

            let reader = SMCFanReader()
            do {
                let fans = try reader.readFans()
                let lines = fans.map { fan in
                    "fan\(fan.id)=\(fan.currentRPM)/\(fan.targetRPM)/\(fan.maxRPM) mode=\(fan.mode.rawValue)"
                }.joined(separator: "\n")
                write("""
                fan_backend=direct_smc
                fan_count=\(fans.count)
                \(lines)
                """)
                return 0
            } catch {
                write("fan_dump=failed(\(error.localizedDescription))")
                return 1
            }

        case .fanDumpDirect:
            let reader = SMCFanReader()
            do {
                let fans = try reader.readFans()
                let lines = fans.map { fan in
                    "fan\(fan.id)=\(fan.currentRPM)/\(fan.targetRPM)/\(fan.maxRPM) mode=\(fan.mode.rawValue)"
                }.joined(separator: "\n")
                write("""
                fan_backend=direct_smc
                fan_count=\(fans.count)
                \(lines)
                """)
                return 0
            } catch {
                write("fan_dump=failed(\(error.localizedDescription))")
                return 1
            }

        case .fanModeDump:
            var outputBuffer = [CChar](repeating: 0, count: 4096)
            var errorBuffer = [CChar](repeating: 0, count: Int(AEROPULSE_SMC_ERROR_BUFFER_LENGTH))

            let status = outputBuffer.withUnsafeMutableBufferPointer { outputBuffer in
                errorBuffer.withUnsafeMutableBufferPointer { errorBuffer in
                    AeroPulseSMCDumpFanModeKeys(
                        outputBuffer.baseAddress,
                        UInt32(outputBuffer.count),
                        errorBuffer.baseAddress,
                        UInt32(errorBuffer.count)
                    )
                }
            }

            guard status == 0 else {
                let message = String(decoding: errorBuffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                write("fan_mode_dump=failed(\(message.isEmpty ? "AppleSMC mode dump failed." : message))")
                return 1
            }

            let output = String(decoding: outputBuffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            write(output.isEmpty ? "fan_mode_dump=empty" : output)
            return 0

        case .fanModeDumpHelper:
            let client = PrivilegedFanControlClient()
            do {
                let output = try await client.dumpFanModeKeys().trimmingCharacters(in: .whitespacesAndNewlines)
                write(output.isEmpty ? "fan_mode_dump=empty" : output)
                return 0
            } catch {
                write("fan_mode_dump=failed(\(error.localizedDescription))")
                return 1
            }

        case .fanSetAuto:
            let client = PrivilegedFanControlClient()
            let fanIDs = parseFanIDs(Array(CommandLine.arguments.dropFirst()))
            guard !fanIDs.isEmpty else {
                write("fan_set_auto=failed(missing_fan_ids)")
                return 1
            }

            do {
                try await client.setAuto(fanIDs: fanIDs)
                write("fan_set_auto=ok fan_ids=\(fanIDs.map(String.init).joined(separator: ","))")
                return 0
            } catch {
                if await verifyAutoWrite(for: fanIDs) {
                    write("fan_set_auto=ok fan_ids=\(fanIDs.map(String.init).joined(separator: ",")) verified=smc")
                    return 0
                }
                write("fan_set_auto=failed(\(error.localizedDescription))")
                return 1
            }

        case .fanSetManual:
            let client = PrivilegedFanControlClient()
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard let commandIndex = arguments.firstIndex(of: AppCommand.fanSetManual.rawValue) else {
                write("fan_set_manual=failed(missing_command)")
                return 1
            }

            let payload = Array(arguments.dropFirst(commandIndex + 1))
            guard payload.count >= 2 else {
                write("fan_set_manual=failed(expected_fan_ids_and_rpm)")
                return 1
            }

            let fanIDs = parseFanIDs([payload[0]])
            guard !fanIDs.isEmpty else {
                write("fan_set_manual=failed(missing_fan_ids)")
                return 1
            }

            guard let rpm = Int(payload[1]), rpm > 0 else {
                write("fan_set_manual=failed(invalid_rpm)")
                return 1
            }

            do {
                try await client.setManualRPM(fanIDs: fanIDs, rpm: rpm)
                write("fan_set_manual=ok fan_ids=\(fanIDs.map(String.init).joined(separator: ",")) rpm=\(rpm)")
                return 0
            } catch {
                if await verifyManualWrite(for: fanIDs, rpm: rpm) {
                    write("fan_set_manual=ok fan_ids=\(fanIDs.map(String.init).joined(separator: ",")) rpm=\(rpm) verified=smc")
                    return 0
                }
                write("fan_set_manual=failed(\(error.localizedDescription))")
                return 1
            }

        case .fanSetAutoDirect:
            let fanIDs = parseFanIDs(Array(CommandLine.arguments.dropFirst()))
            guard !fanIDs.isEmpty else {
                write("fan_set_auto_direct=failed(missing_fan_ids)")
                return 1
            }

            do {
                try fanIDs.forEach { fanID in
                    var errorBuffer = [CChar](repeating: 0, count: Int(AEROPULSE_SMC_ERROR_BUFFER_LENGTH))
                    let status = errorBuffer.withUnsafeMutableBufferPointer { errorBuffer in
                        AeroPulseSMCSetFanAuto(
                            UInt32(fanID),
                            errorBuffer.baseAddress,
                            UInt32(errorBuffer.count)
                        )
                    }

                    guard status == 0 else {
                        let message = String(decoding: errorBuffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        throw PrivilegedFanControlClientError.remote(message.isEmpty ? "Direct SMC auto write failed." : message)
                    }
                }

                write("fan_set_auto_direct=ok fan_ids=\(fanIDs.map(String.init).joined(separator: ","))")
                return 0
            } catch {
                write("fan_set_auto_direct=failed(\(error.localizedDescription))")
                return 1
            }

        case .fanSetManualDirect:
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard let commandIndex = arguments.firstIndex(of: AppCommand.fanSetManualDirect.rawValue) else {
                write("fan_set_manual_direct=failed(missing_command)")
                return 1
            }

            let payload = Array(arguments.dropFirst(commandIndex + 1))
            guard payload.count >= 2 else {
                write("fan_set_manual_direct=failed(expected_fan_ids_and_rpm)")
                return 1
            }

            let fanIDs = parseFanIDs([payload[0]])
            guard !fanIDs.isEmpty else {
                write("fan_set_manual_direct=failed(missing_fan_ids)")
                return 1
            }

            guard let rpm = Int(payload[1]), rpm > 0 else {
                write("fan_set_manual_direct=failed(invalid_rpm)")
                return 1
            }

            do {
                try fanIDs.forEach { fanID in
                    var errorBuffer = [CChar](repeating: 0, count: Int(AEROPULSE_SMC_ERROR_BUFFER_LENGTH))
                    let status = errorBuffer.withUnsafeMutableBufferPointer { errorBuffer in
                        AeroPulseSMCSetFanTargetRPM(
                            UInt32(fanID),
                            UInt32(rpm),
                            errorBuffer.baseAddress,
                            UInt32(errorBuffer.count)
                        )
                    }

                    guard status == 0 else {
                        let message = String(decoding: errorBuffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        throw PrivilegedFanControlClientError.remote(message.isEmpty ? "Direct SMC manual write failed." : message)
                    }
                }

                write("fan_set_manual_direct=ok fan_ids=\(fanIDs.map(String.init).joined(separator: ",")) rpm=\(rpm)")
                return 0
            } catch {
                write("fan_set_manual_direct=failed(\(error.localizedDescription))")
                return 1
            }

        case .prepareTermination:
            let model = AppModel()
            await model.prepareForTermination()
            write("prepare_termination=ok")
            return 0

        case .openLoginItems:
            helperManager.openLoginItemsSettings()
            write("opened_login_items=1")
            return 0
        }
    }

    private static func statusName(_ status: PrivilegedHelperStatus) -> String {
        switch status {
        case .unsupported:
            "unsupported"
        case .notRegistered:
            "not_registered"
        case .enabled:
            "enabled"
        case .requiresApproval:
            "requires_approval"
        case .notFound:
            "not_found"
        case let .failed(reason):
            "failed(\(reason))"
        }
    }

    private static func write(_ string: String) {
        guard let data = (string + "\n").data(using: .utf8) else {
            return
        }
        FileHandle.standardOutput.write(data)
    }

    private static func parseFanIDs(_ arguments: [String]) -> [Int] {
        if arguments.contains("all") {
            return [1, 2]
        }

        return arguments
            .filter { $0 != AppCommand.fanSetAuto.rawValue && $0 != AppCommand.fanSetManual.rawValue }
            .flatMap { $0.split(separator: ",") }
            .compactMap { Int($0) }
            .filter { $0 > 0 }
    }

    private static func verifyAutoWrite(for fanIDs: [Int]) async -> Bool {
        await verifyWrite(timeoutSeconds: 4.0) { snapshots in
            fanIDs.allSatisfy { fanID in
                guard let snapshot = snapshots.first(where: { $0.id == fanID }) else {
                    return false
                }

                return snapshot.mode == .auto && snapshot.targetRPM == 0
            }
        }
    }

    private static func verifyManualWrite(for fanIDs: [Int], rpm: Int) async -> Bool {
        await verifyWrite(timeoutSeconds: 4.0) { snapshots in
            fanIDs.allSatisfy { fanID in
                guard let snapshot = snapshots.first(where: { $0.id == fanID }) else {
                    return false
                }

                return snapshot.mode == .manual && abs(snapshot.targetRPM - rpm) <= 120
            }
        }
    }

    private static func verifyWrite(
        timeoutSeconds: Double,
        condition: @escaping ([FanSnapshot]) -> Bool
    ) async -> Bool {
        let reader = SMCFanReader()
        let deadline = Date().addingTimeInterval(timeoutSeconds)

        while Date() < deadline {
            if let snapshots = try? reader.readFans(),
               condition(snapshots) {
                return true
            }

            try? await Task.sleep(for: .milliseconds(200))
        }

        return false
    }
}
