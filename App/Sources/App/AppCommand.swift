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
#if DEBUG
    // Compiled into Debug builds only. Raw SMC access and the multi-key
    // experimental unlock sequence are diagnostic surface area and must
    // never ship in a Release build of the app.
    case fanDiag = "--fan-diag"
    case smcEnumerate = "--smc-enumerate"
    case smcReadRaw = "--smc-read"
    case smcWriteRaw = "--smc-write"
    case smcWriteHelper = "--smc-write-helper"
    case smcReadHelper = "--smc-read-helper"
    case fanExperiment = "--fan-experiment"
#endif

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
            var diagnostics = helperManager.diagnostics()
            diagnostics.registeredProgramPath = await helperManager.loadRegisteredProgramPath()
            let forceReregister = helperManager.status() != .notRegistered || diagnostics.hasRegistrationPathMismatch
            var status = (try? await helperManager.registerForCurrentBundle(forceUnregister: forceReregister)) ?? .failed("register_failed")
            diagnostics.registeredProgramPath = await helperManager.loadRegisteredProgramPath()
            if status == .enabled, diagnostics.hasRegistrationPathMismatch {
                status = .failed("stale_registration")
            }
            write("""
            helper_register=\(statusName(status))
            registered_program=\(diagnostics.registeredProgramPath ?? "unknown")
            """)
            return (status == .enabled || status == .requiresApproval) ? 0 : 1

        case .helperUnregister:
            let status = (try? await helperManager.unregisterAndWait()) ?? .failed("unregister_failed")
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
            var diagnostics = helperManager.diagnostics()
            diagnostics.registeredProgramPath = await helperManager.loadRegisteredProgramPath()
            var notes = helperManager.preflightNotes(for: diagnostics)
            if diagnostics.hasRegistrationPathMismatch {
                notes.append(String.tr("helper.guidance.registration_mismatch"))
            }
            let guidance = notes.isEmpty ? "-" : notes.joined(separator: "\n- ")

            write("""
            helper_status=\(statusName(status))
            registered_program=\(diagnostics.registeredProgramPath ?? "unknown")
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

#if DEBUG
        case .fanDiag:
            // Diagnostic: set manual RPM, hold XPC open, verify, probe fan response, report, restore auto.
            // Usage: AeroPulse --fan-diag <fanIDs-csv> <rpm> [holdSeconds]
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard let commandIndex = arguments.firstIndex(of: AppCommand.fanDiag.rawValue) else {
                write("fan_diag=failed(missing_command)")
                return 1
            }
            let payload = Array(arguments.dropFirst(commandIndex + 1))
            guard payload.count >= 2 else {
                write("fan_diag=failed(expected fanIDs and rpm)")
                return 1
            }
            let fanIDs = parseFanIDs([payload[0]])
            guard !fanIDs.isEmpty else {
                write("fan_diag=failed(missing_fan_ids)")
                return 1
            }
            guard let rpm = Int(payload[1]), rpm > 0 else {
                write("fan_diag=failed(invalid_rpm)")
                return 1
            }
            let holdSeconds = payload.count >= 3 ? (Double(payload[2]) ?? 5.0) : 5.0

            let client = PrivilegedFanControlClient()
            do {
                // Call setManualRPM ONCE — helper should start its own reassertion timer.
                try await client.setManualRPM(fanIDs: fanIDs, rpm: rpm)
                write("fan_diag=setManualRPM_once rpm=\(rpm)")

                // Just hold XPC open via low-frequency reads; helper handles reassertion.
                let startedAt = Date()
                var lastSample: [FanSnapshot] = []
                var iteration = 0
                while Date().timeIntervalSince(startedAt) < holdSeconds {
                    lastSample = try await client.readFans(previousSnapshots: lastSample)
                    let t = Date().timeIntervalSince(startedAt)
                    write("fan_diag=sample t=\(String(format: "%.1f", t))s \(lastSample.map { "fan\($0.id)=\($0.currentRPM)rpm/tg=\($0.targetRPM) mode=\($0.mode.rawValue)" }.joined(separator: " | "))")
                    FileHandle.standardOutput.synchronizeFile()
                    iteration += 1
                    try? await Task.sleep(for: .milliseconds(2000))
                }

                try? await client.setAuto(fanIDs: fanIDs)
                write("fan_diag=restored_auto")
                return 0
            } catch {
                write("fan_diag=failed(\(error.localizedDescription))")
                return 1
            }

        case .smcEnumerate:
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard let idx = arguments.firstIndex(of: AppCommand.smcEnumerate.rawValue) else {
                write("smc_enumerate=failed(missing_command)"); return 1
            }
            let payload = Array(arguments.dropFirst(idx + 1))
            let prefix = payload.first ?? "F"

            var output = [CChar](repeating: 0, count: 65536)
            var errbuf = [CChar](repeating: 0, count: Int(AEROPULSE_SMC_ERROR_BUFFER_LENGTH))
            let status = prefix.withCString { prefixPtr in
                output.withUnsafeMutableBufferPointer { outPtr in
                    errbuf.withUnsafeMutableBufferPointer { errPtr in
                        AeroPulseSMCEnumerateKeysWithPrefix(
                            prefixPtr,
                            outPtr.baseAddress, UInt32(outPtr.count),
                            errPtr.baseAddress, UInt32(errPtr.count)
                        )
                    }
                }
            }
            let out = String(cString: output)
            let err = String(cString: errbuf)
            if status != 0 {
                write("smc_enumerate=failed(\(err)) status=\(status)")
                return 1
            }
            write("smc_enumerate prefix=\(prefix) ----")
            FileHandle.standardOutput.write(out.data(using: .utf8) ?? Data())
            write("---- end")
            return 0

        case .smcReadRaw:
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard let idx = arguments.firstIndex(of: AppCommand.smcReadRaw.rawValue),
                  arguments.count > idx + 1 else {
                write("smc_read=failed(missing_key)"); return 1
            }
            let keyStr = arguments[idx + 1]
            guard keyStr.utf8.count == 4 else {
                write("smc_read=failed(key_must_be_4_chars)"); return 1
            }

            var outbuf = [CChar](repeating: 0, count: 256)
            var errbuf = [CChar](repeating: 0, count: Int(AEROPULSE_SMC_ERROR_BUFFER_LENGTH))
            let status = keyStr.withCString { kp in
                outbuf.withUnsafeMutableBufferPointer { op in
                    errbuf.withUnsafeMutableBufferPointer { ep in
                        AeroPulseSMCReadRawKey(kp, op.baseAddress, UInt32(op.count), ep.baseAddress, UInt32(ep.count))
                    }
                }
            }
            write(status == 0 ? String(cString: outbuf) : "smc_read=failed(\(String(cString: errbuf))) status=\(status)")
            return status == 0 ? 0 : 1

        case .smcWriteRaw:
            // usage: --smc-write <KEY4> <TYPE4> <hexbytes>   (direct, root required)
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard let idx = arguments.firstIndex(of: AppCommand.smcWriteRaw.rawValue),
                  arguments.count >= idx + 4 else {
                write("smc_write=failed(usage: --smc-write KEY TYPE HEX)"); return 1
            }
            let keyStr = arguments[idx + 1]
            let typeStr = arguments[idx + 2]
            guard keyStr.utf8.count == 4, typeStr.utf8.count == 4 else {
                write("smc_write=failed(key_and_type_must_be_4_chars)"); return 1
            }
            let bytes: [UInt8]
            do {
                bytes = try SMCHex.bytes(from: arguments[idx + 3])
            } catch {
                write("smc_write=failed(\(error.localizedDescription))"); return 1
            }
            guard !bytes.isEmpty, bytes.count <= 32 else {
                write("smc_write=failed(bad_bytes_size)"); return 1
            }
            var errbuf = [CChar](repeating: 0, count: Int(AEROPULSE_SMC_ERROR_BUFFER_LENGTH))
            let status = keyStr.withCString { kp in
                typeStr.withCString { tp in
                    bytes.withUnsafeBufferPointer { bp in
                        errbuf.withUnsafeMutableBufferPointer { ep in
                            AeroPulseSMCWriteRawKey(kp, tp, bp.baseAddress, UInt32(bp.count), ep.baseAddress, UInt32(ep.count))
                        }
                    }
                }
            }
            if status == 0 {
                write("smc_write=ok key=\(keyStr) type=\(typeStr) size=\(bytes.count)")
                return 0
            }
            write("smc_write=failed(\(String(cString: errbuf))) status=\(status)")
            return 1

        case .smcWriteHelper:
            // usage: --smc-write-helper <KEY4> <TYPE4> <HEX>   (via privileged XPC)
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard let idx = arguments.firstIndex(of: AppCommand.smcWriteHelper.rawValue),
                  arguments.count >= idx + 4 else {
                write("smc_write_helper=failed(usage)"); return 1
            }
            let rawKey = arguments[idx + 1]
            let rawType = arguments[idx + 2]
            let rawHex = arguments[idx + 3]
            guard let type = SMCType(rawValue: rawType) else {
                write("smc_write_helper=failed(unknown_type=\(rawType))"); return 1
            }
            let bytes: [UInt8]
            do {
                bytes = try SMCHex.bytes(from: rawHex)
            } catch {
                write("smc_write_helper=failed(\(error.localizedDescription))"); return 1
            }
            let value: SMCValue
            switch type {
            case .ui8 where bytes.count == 1: value = .uint8(bytes[0])
            case .ui16 where bytes.count == 2: value = .uint16(UInt16(bytes[0]) | (UInt16(bytes[1]) << 8))
            case .ui32 where bytes.count == 4:
                value = .uint32(
                    UInt32(bytes[0]) |
                    (UInt32(bytes[1]) << 8) |
                    (UInt32(bytes[2]) << 16) |
                    (UInt32(bytes[3]) << 24)
                )
            case .float32 where bytes.count == 4:
                var f: Float = 0
                withUnsafeMutableBytes(of: &f) { out in bytes.withUnsafeBytes { out.copyMemory(from: $0) } }
                value = .float32(f)
            default: value = .hex(Data(bytes))
            }
            let client = PrivilegedFanControlClient()
            do {
                try await client.writeRawKey(key: .raw(rawKey), value: value)
                write("smc_write_helper=ok key=\(rawKey) value=\(value)")
                return 0
            } catch {
                write("smc_write_helper=failed(\(error.localizedDescription))")
                return 1
            }

        case .smcReadHelper:
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard let idx = arguments.firstIndex(of: AppCommand.smcReadHelper.rawValue),
                  arguments.count >= idx + 2 else {
                write("smc_read_helper=failed(usage)"); return 1
            }
            let client = PrivilegedFanControlClient()
            do {
                let result = try await client.readRawKey(key: .raw(arguments[idx + 1]))
                write(result)
                return 0
            } catch {
                write("smc_read_helper=failed(\(error.localizedDescription))")
                return 1
            }

        case .fanExperiment:
            // Experimental M-series fan unlock sequence, held open over XPC.
            // usage: --fan-experiment <rpm> <holdSeconds>
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard let idx = arguments.firstIndex(of: AppCommand.fanExperiment.rawValue) else {
                write("fan_experiment=failed(missing)"); return 1
            }
            let payload = Array(arguments.dropFirst(idx + 1))
            guard payload.count >= 2,
                  let rpm = UInt32(payload[0]), rpm > 0,
                  let hold = Double(payload[1]), hold > 0 else {
                write("fan_experiment=failed(usage: --fan-experiment RPM HOLD_SECONDS)")
                return 1
            }

            let client = PrivilegedFanControlClient()
            let targetValue = SMCValue.float32(Float(rpm))

            do {
                // Step 1: enable user fan control (FEna bitmask 0x03 = both fans).
                // FEna isn't writable on M5+ but we issue the request for parity
                // with earlier Apple Silicon generations; failures are ignored.
                do {
                    try await client.writeRawKey(key: .fanEnable, value: .hex(Data([0x03])))
                    write("fan_experiment=FEna_set_03")
                } catch {
                    write("fan_experiment=FEna_failed(\(error.localizedDescription))")
                }

                // Step 2: probe F<i>St values (0..2) to find whichever the firmware accepts.
                for stateValue: UInt8 in [0, 1, 2] {
                    do {
                        try await client.writeRawKey(key: .firmwareState(fanIndex: 0), value: .uint8(stateValue))
                        try await client.writeRawKey(key: .firmwareState(fanIndex: 1), value: .uint8(stateValue))
                        write("fan_experiment=FxSt_set_\(String(format: "%02x", stateValue))_ok")
                    } catch {
                        write("fan_experiment=FxSt_set_\(String(format: "%02x", stateValue))_failed(\(error.localizedDescription))")
                    }
                }

                // Step 3: flip both fans to Manual mode.
                try await client.writeRawKey(key: .mode(fanIndex: 0), value: .uint8(1))
                try await client.writeRawKey(key: .mode(fanIndex: 1), value: .uint8(1))
                write("fan_experiment=Fxmd_set_01")

                // Step 4: write the target RPM as IEEE 754 LE float.
                try await client.writeRawKey(key: .targetRPM(fanIndex: 0), value: targetValue)
                try await client.writeRawKey(key: .targetRPM(fanIndex: 1), value: targetValue)
                write("fan_experiment=FxTg_set_\(rpm)_hex=\(targetValue.hexString)")

                // Step 5: hold — re-assert every 600ms.
                let started = Date()
                var iter = 0
                while Date().timeIntervalSince(started) < hold {
                    try? await client.writeRawKey(key: .fanEnable, value: .hex(Data([0x03])))
                    try? await client.writeRawKey(key: .mode(fanIndex: 0), value: .uint8(1))
                    try? await client.writeRawKey(key: .mode(fanIndex: 1), value: .uint8(1))
                    try? await client.writeRawKey(key: .targetRPM(fanIndex: 0), value: targetValue)
                    try? await client.writeRawKey(key: .targetRPM(fanIndex: 1), value: targetValue)

                    if iter % 3 == 0 {
                        let actual = (try? await client.readRawKey(key: .currentRPM(fanIndex: 0))) ?? "?"
                        let state = (try? await client.readRawKey(key: .firmwareState(fanIndex: 0))) ?? "?"
                        let mode = (try? await client.readRawKey(key: .mode(fanIndex: 0))) ?? "?"
                        let target = (try? await client.readRawKey(key: .targetRPM(fanIndex: 0))) ?? "?"
                        let t = Date().timeIntervalSince(started)
                        write("fan_experiment=sample t=\(String(format: "%.1f", t))s | \(actual) | \(target) | \(mode) | \(state)")
                        FileHandle.standardOutput.synchronizeFile()
                    }
                    iter += 1
                    try? await Task.sleep(for: .milliseconds(600))
                }

                // Cleanup — restore auto.
                try? await client.writeRawKey(key: .mode(fanIndex: 0), value: .uint8(0))
                try? await client.writeRawKey(key: .mode(fanIndex: 1), value: .uint8(0))
                try? await client.writeRawKey(key: .fanEnable, value: .hex(Data([0x00])))
                write("fan_experiment=cleanup_done")
                return 0
            } catch {
                write("fan_experiment=failed(\(error.localizedDescription))")
                return 1
            }
#endif

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
