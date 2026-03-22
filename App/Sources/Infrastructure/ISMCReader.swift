import Foundation

struct ISMCSensorPayload: Decodable {
    let key: String
    let type: String
    let value: String
    let quantity: Double?
    let unit: String?
}

struct ISMCReader: Sendable {
    private let runner: CommandRunning

    init(runner: CommandRunning) {
        self.runner = runner
    }

    func readTemperatures(executablePath: String) async throws -> [TemperatureSensor] {
        let result = try await runner.run(executable: URL(fileURLWithPath: executablePath), arguments: ["temp", "-o", "json"])
        guard result.exitCode == 0 else {
            throw NSError(domain: "AeroPulse.iSMC", code: Int(result.exitCode), userInfo: [NSLocalizedDescriptionKey: result.stderr])
        }

        let data = Data(result.stdout.utf8)
        let decoded = try JSONDecoder().decode([String: ISMCSensorPayload].self, from: data)

        return decoded.map { name, payload in
            TemperatureSensor(
                id: payload.key,
                key: payload.key,
                name: name,
                celsius: payload.quantity ?? parseNumericPrefix(from: payload.value),
                source: .ismc
            )
        }
        .sorted { lhs, rhs in
            if lhs.celsius == rhs.celsius {
                return lhs.name < rhs.name
            }
            return lhs.celsius > rhs.celsius
        }
    }

    private func parseNumericPrefix(from raw: String) -> Double {
        let cleaned = raw.replacingOccurrences(of: "[^0-9.\\-]", with: "", options: .regularExpression)
        return Double(cleaned) ?? 0
    }
}
