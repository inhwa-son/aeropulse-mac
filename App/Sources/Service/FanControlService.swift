import Foundation

private enum ServiceFanError: LocalizedError {
    case executableMissing(String)
    case invalidResponse(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case let .executableMissing(path):
            "Executable not found at \(path)"
        case let .invalidResponse(payload):
            "Unexpected fan response: \(payload)"
        case let .commandFailed(message):
            message
        }
    }
}

private struct SynchronousFanCLI {
    func setAuto(executablePath: String, fanIDs: [Int]) throws {
        for fanID in fanIDs {
            let result = try run(executablePath: executablePath, arguments: ["-id", "\(fanID)", "auto"])
            guard result.exitCode == 0 else {
                throw ServiceFanError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
            }
        }
    }

    func setManualRPM(executablePath: String, fanIDs: [Int], rpm: Int) throws {
        for fanID in fanIDs {
            let result = try run(executablePath: executablePath, arguments: ["-id", "\(fanID)", "\(rpm)"])
            guard result.exitCode == 0 else {
                throw ServiceFanError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
            }
        }
    }

    private func run(executablePath: String, arguments: [String]) throws -> CommandResult {
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw ServiceFanError.executableMissing(executablePath)
        }

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading

        var stdoutData = Data()
        var stderrData = Data()
        let readGroup = DispatchGroup()

        readGroup.enter()
        DispatchQueue.global().async {
            stdoutData = stdoutHandle.readDataToEndOfFile()
            readGroup.leave()
        }
        readGroup.enter()
        DispatchQueue.global().async {
            stderrData = stderrHandle.readDataToEndOfFile()
            readGroup.leave()
        }

        let timeoutSeconds: Double = 5
        let workItem = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
            }
            try? stdoutHandle.close()
            try? stderrHandle.close()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: workItem)
        process.waitUntilExit()
        workItem.cancel()

        readGroup.wait()

        guard let stdout = String(data: stdoutData, encoding: .utf8),
              let stderr = String(data: stderrData, encoding: .utf8) else {
            throw ServiceFanError.commandFailed("Command output was not valid UTF-8.")
        }

        return CommandResult(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
    }
}

final class FanControlService: NSObject, FanControlXPCProtocol {
    private let fanCLI = SynchronousFanCLI()

    func probeBackend(executablePath: String, withReply reply: @escaping (String?) -> Void) {
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            reply(ServiceFanError.executableMissing(executablePath).localizedDescription)
            return
        }

        reply(nil)
    }

    func setAuto(executablePath: String, fanIDs: [NSNumber], withReply reply: @escaping (String?) -> Void) {
        do {
            try fanCLI.setAuto(executablePath: executablePath, fanIDs: fanIDs.map(\.intValue))
            reply(nil)
        } catch {
            reply(error.localizedDescription)
        }
    }

    func setManualRPM(executablePath: String, fanIDs: [NSNumber], rpm: NSNumber, withReply reply: @escaping (String?) -> Void) {
        do {
            try fanCLI.setManualRPM(executablePath: executablePath, fanIDs: fanIDs.map(\.intValue), rpm: rpm.intValue)
            reply(nil)
        } catch {
            reply(error.localizedDescription)
        }
    }
}
