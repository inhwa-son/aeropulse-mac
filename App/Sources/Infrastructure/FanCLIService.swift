import Foundation

enum FanCLIError: LocalizedError, Equatable {
    case invalidResponse(String)
    case commandFailed(String)
    case emptyFanSelection

    var errorDescription: String? {
        switch self {
        case let .invalidResponse(payload):
            "Unexpected fan CLI response: \(payload)"
        case let .commandFailed(message):
            message
        case .emptyFanSelection:
            "No fan IDs were selected for control."
        }
    }
}

actor FanCLIService {
    private let runner: CommandRunning

    init(runner: CommandRunning) {
        self.runner = runner
    }

    func availability(for executablePath: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: executablePath)
    }

    func listFans(executablePath: String) async throws -> [FanSnapshot] {
        let result = try await runner.run(executable: URL(fileURLWithPath: executablePath), arguments: ["-l"])
        guard result.exitCode == 0 else {
            throw FanCLIError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }

        return try parseFanList(result.stdout)
    }

    func setAuto(executablePath: String, fanIDs: [Int], allFansSelected: Bool = false) async throws {
        if allFansSelected {
            let result = try await runner.run(
                executable: URL(fileURLWithPath: executablePath),
                arguments: ["auto"]
            )

            guard result.exitCode == 0 else {
                throw FanCLIError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
            }
            return
        }

        guard !fanIDs.isEmpty else {
            throw FanCLIError.emptyFanSelection
        }

        for fanID in fanIDs {
            let result = try await runner.run(
                executable: URL(fileURLWithPath: executablePath),
                arguments: ["-id", "\(fanID)", "auto"]
            )

            guard result.exitCode == 0 else {
                throw FanCLIError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
            }
        }
    }

    func setManualRPM(executablePath: String, fanIDs: [Int], rpm: Int, allFansSelected: Bool = false) async throws {
        if allFansSelected {
            let result = try await runner.run(
                executable: URL(fileURLWithPath: executablePath),
                arguments: ["\(rpm)"]
            )

            guard result.exitCode == 0 else {
                throw FanCLIError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
            }
            return
        }

        guard !fanIDs.isEmpty else {
            throw FanCLIError.emptyFanSelection
        }

        for fanID in fanIDs {
            let result = try await runner.run(
                executable: URL(fileURLWithPath: executablePath),
                arguments: ["-id", "\(fanID)", "\(rpm)"]
            )

            guard result.exitCode == 0 else {
                throw FanCLIError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
            }
        }
    }

    private func parseFanList(_ raw: String) throws -> [FanSnapshot] {
        let lines = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let payloadLines = lines.dropFirst()
        var snapshots: [FanSnapshot] = []

        for line in payloadLines {
            let columns = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard columns.count >= 6,
                  let fanID = Int(columns[0]),
                  let currentRPM = Int(columns[2]),
                  let targetRPM = Int(columns[3]),
                  let minRPM = Int(columns[4]),
                  let maxRPM = Int(columns[5]) else {
                throw FanCLIError.invalidResponse(raw)
            }

            snapshots.append(
                FanSnapshot(
                    id: fanID,
                    mode: FanMode(rawValue: columns[1]) ?? .unknown,
                    currentRPM: currentRPM,
                    targetRPM: targetRPM,
                    minRPM: minRPM,
                    maxRPM: maxRPM
                )
            )
        }

        return snapshots.sorted { $0.id < $1.id }
    }
}
