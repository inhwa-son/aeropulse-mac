import Foundation

struct CommandResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

protocol CommandRunning: Sendable {
    func run(executable: URL, arguments: [String]) async throws -> CommandResult
}

enum CommandRunnerError: LocalizedError {
    case executableMissing(String)
    case invalidUTF8
    case timeout(Double)

    var errorDescription: String? {
        switch self {
        case let .executableMissing(path):
            "Executable not found at \(path)"
        case .invalidUTF8:
            "Command output was not valid UTF-8."
        case let .timeout(seconds):
            "Command timed out after \(String(format: "%.1f", seconds))s."
        }
    }
}

struct ProcessCommandRunner: CommandRunning {
    private let defaultTimeoutSeconds = 2.5

    func run(executable: URL, arguments: [String]) async throws -> CommandResult {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw CommandRunnerError.executableMissing(executable.path)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let timeoutSeconds = defaultTimeoutSeconds
            let box = ContinuationGate<CommandResult>(continuation)
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { finished in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                guard let stdout = String(data: stdoutData, encoding: .utf8),
                      let stderr = String(data: stderrData, encoding: .utf8) else {
                    box.resume(throwing: CommandRunnerError.invalidUTF8)
                    return
                }

                box.resume(
                    returning: CommandResult(
                        stdout: stdout,
                        stderr: stderr,
                        exitCode: finished.terminationStatus
                    )
                )
            }

            do {
                try process.run()
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds) {
                    guard process.isRunning else { return }
                    process.terminate()
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.25) {
                        if process.isRunning {
                            process.interrupt()
                        }
                    }
                    box.resume(throwing: CommandRunnerError.timeout(timeoutSeconds))
                }
            } catch {
                box.resume(throwing: error)
            }
        }
    }
}
