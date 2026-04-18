import Foundation

private typealias PrivilegedFanControlRequestGate = ContinuationGate<Void>

enum PrivilegedFanControlClientError: LocalizedError {
    case unavailable(String)
    case remote(String)
    case timeout(Double)

    var errorDescription: String? {
        switch self {
        case let .unavailable(message):
            message
        case let .remote(message):
            message
        case let .timeout(seconds):
            "Privileged helper timed out after \(String(format: "%.1f", seconds))s."
        }
    }
}

actor PrivilegedFanControlClient {
    private let probeTimeoutSeconds = 3.5
    private let readTimeoutSeconds = 4.0
    private let writeTimeoutSeconds = 3.0
    private let machServiceName = PrivilegedHelperConstants.machServiceName
    private var connection: NSXPCConnection?

    func probe() async throws {
        try await requestVoid(timeoutSeconds: probeTimeoutSeconds) { proxy, reply in
            proxy.probe(withReply: reply)
        }
    }

    func readFans(previousSnapshots: [FanSnapshot] = []) async throws -> [FanSnapshot] {
        let response: PrivilegedFanReadResponse = try await requestValue(timeoutSeconds: readTimeoutSeconds) { proxy, reply in
            proxy.readFans(withReply: reply)
        }
        if let errorMessage = response.errorMessage {
            throw PrivilegedFanControlClientError.remote(errorMessage)
        }
        let payloads = response.snapshots ?? []
        let previousModes = Dictionary(uniqueKeysWithValues: previousSnapshots.map { ($0.id, $0.mode) })

        return payloads.map { payload in
            let mode: FanMode
            switch payload.modeHint {
            case 1:
                mode = .auto
            case 2:
                mode = .manual
            default:
                mode = previousModes[payload.identifier] ?? (payload.targetRPM > 0 ? .manual : .unknown)
            }

            return FanSnapshot(
                id: payload.identifier,
                mode: mode,
                currentRPM: payload.currentRPM,
                targetRPM: payload.targetRPM,
                minRPM: payload.minRPM,
                maxRPM: payload.maxRPM
            )
        }
    }

    func dumpFanModeKeys() async throws -> String {
        let response: PrivilegedStringResponse = try await requestValue(timeoutSeconds: readTimeoutSeconds) { proxy, reply in
            proxy.dumpFanModeKeys(withReply: reply)
        }
        if let errorMessage = response.errorMessage {
            throw PrivilegedFanControlClientError.remote(errorMessage)
        }
        return response.value ?? ""
    }

    func setAuto(fanIDs: [Int]) async throws {
        let fanIDsCSV = fanIDs.map(String.init).joined(separator: ",") as NSString
        try await requestVoid(timeoutSeconds: writeTimeoutSeconds) { proxy, reply in
            proxy.setAuto(fanIDsCSV: fanIDsCSV, withReply: reply)
        }
    }

    func setManualRPM(fanIDs: [Int], rpm: Int) async throws {
        let fanIDsCSV = fanIDs.map(String.init).joined(separator: ",") as NSString
        try await requestVoid(timeoutSeconds: writeTimeoutSeconds) { proxy, reply in
            proxy.setManualRPM(fanIDsCSV: fanIDsCSV, rpm: NSNumber(value: rpm), withReply: reply)
        }
    }

#if DEBUG
    // Diagnostic raw-SMC XPC methods are only wired up in Debug so Release
    // builds of the app cannot reach the writeRawKey/readRawKey surface even
    // if the helper binary somehow shipped with those methods.
    func writeRawKey(key: SMCKey, value: SMCValue) async throws {
        try await requestVoid(timeoutSeconds: writeTimeoutSeconds) { proxy, reply in
            proxy.writeRawKey(
                key: key.rawString as NSString,
                type: value.smcType.rawValue as NSString,
                hexBytes: value.hexString as NSString,
                withReply: reply
            )
        }
    }

    func readRawKey(key: SMCKey) async throws -> String {
        let connection = activeConnection()
        let connectionID = ObjectIdentifier(connection)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let gate = ContinuationGate<String>(continuation)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + readTimeoutSeconds) { [weak self] in
                Self.handleTimeout(self, gate: gate, connectionID: connectionID, timeoutSeconds: self?.readTimeoutSeconds ?? 4.0)
            }
            let errorHandler: @Sendable (Error) -> Void = { [weak self] error in
                Self.handleRemoteError(self, gate: gate, connectionID: connectionID, message: error.localizedDescription)
            }
            let proxy = connection.remoteObjectProxyWithErrorHandler(errorHandler) as? PrivilegedFanControlProtocol
            guard let proxy else {
                Self.handleUnavailableProxy(self, gate: gate, connectionID: connectionID)
                return
            }
            proxy.readRawKey(key: key.rawString as NSString) { result, errorText in
                if let errorText {
                    gate.resume(throwing: PrivilegedFanControlClientError.remote(errorText))
                } else {
                    gate.resume(returning: (result as String?) ?? "")
                }
            }
        }
    }
#endif

    private func requestVoid(
        timeoutSeconds: Double,
        _ operation: @escaping (_ proxy: PrivilegedFanControlProtocol, _ reply: @escaping (String?) -> Void) -> Void
    ) async throws {
        let connection = activeConnection()
        let connectionID = ObjectIdentifier(connection)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = PrivilegedFanControlRequestGate(continuation)

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds) { [weak self] in
                Self.handleTimeout(self, gate: gate, connectionID: connectionID, timeoutSeconds: timeoutSeconds)
            }

            let errorHandler: @Sendable (Error) -> Void = { [weak self] error in
                Self.handleRemoteError(self, gate: gate, connectionID: connectionID, message: error.localizedDescription)
            }

            let proxy = connection.remoteObjectProxyWithErrorHandler(errorHandler) as? PrivilegedFanControlProtocol

            guard let proxy else {
                Self.handleUnavailableProxy(self, gate: gate, connectionID: connectionID)
                return
            }

            let reply: @Sendable (String?) -> Void = { errorText in
                Self.handleReply(gate: gate, errorText: errorText)
            }
            operation(proxy, reply)
        }
    }

    private func requestValue<T: Decodable & Sendable>(
        timeoutSeconds: Double,
        _ operation: @escaping (_ proxy: PrivilegedFanControlProtocol, _ reply: @escaping (NSData?) -> Void) -> Void
    ) async throws -> T {
        let connection = activeConnection()
        let connectionID = ObjectIdentifier(connection)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let gate = PrivilegedFanControlValueGate(continuation)

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds) { [weak self] in
                Self.handleTimeout(self, gate: gate, connectionID: connectionID, timeoutSeconds: timeoutSeconds)
            }

            let errorHandler: @Sendable (Error) -> Void = { [weak self] error in
                Self.handleRemoteError(self, gate: gate, connectionID: connectionID, message: error.localizedDescription)
            }

            let proxy = connection.remoteObjectProxyWithErrorHandler(errorHandler) as? PrivilegedFanControlProtocol

            guard let proxy else {
                Self.handleUnavailableProxy(self, gate: gate, connectionID: connectionID)
                return
            }

            let reply: @Sendable (NSData?) -> Void = { data in
                Self.handleValueReply(gate: gate, data: data as Data?)
            }
            operation(proxy, reply)
        }
    }

    private func activeConnection() -> NSXPCConnection {
        if let connection {
            return connection
        }

        let connection = NSXPCConnection(
            machServiceName: machServiceName,
            options: .privileged
        )
        let connectionID = ObjectIdentifier(connection)
        connection.remoteObjectInterface = makePrivilegedFanControlInterface()
        connection.invalidationHandler = { [weak self] in
            Self.scheduleDiscard(self, matching: connectionID)
        }
        connection.interruptionHandler = { [weak self] in
            Self.scheduleDiscard(self, matching: connectionID)
        }
        connection.resume()
        self.connection = connection
        return connection
    }

    func shutdown() {
        guard let current = connection else {
            return
        }

        current.invalidationHandler = nil
        current.interruptionHandler = nil
        current.invalidate()
        connection = nil
    }

    private func discardConnection(matching identifier: ObjectIdentifier) {
        guard let current = connection, ObjectIdentifier(current) == identifier else {
            return
        }

        current.invalidationHandler = nil
        current.interruptionHandler = nil
        current.invalidate()
        connection = nil
    }

    nonisolated private static func handleReply(gate: PrivilegedFanControlRequestGate, errorText: String?) {
        if let errorText {
            gate.resume(throwing: PrivilegedFanControlClientError.remote(errorText))
        } else {
            gate.resume(returning: ())
        }
    }

    nonisolated private static func handleValueReply<T: Decodable>(
        gate: PrivilegedFanControlValueGate<T>,
        data: Data?
    ) {
        if let data {
            do {
                let value = try JSONDecoder().decode(T.self, from: data)
                gate.resume(returning: value)
            } catch {
                gate.resume(throwing: PrivilegedFanControlClientError.remote("Failed to decode privileged helper response."))
            }
        } else {
            gate.resume(throwing: PrivilegedFanControlClientError.remote("Privileged helper returned an empty response."))
        }
    }

    nonisolated private static func handleTimeout(
        _ client: PrivilegedFanControlClient?,
        gate: PrivilegedFanControlRequestGate,
        connectionID: ObjectIdentifier,
        timeoutSeconds: Double
    ) {
        // Only discard the connection if the gate wasn't already satisfied by an
        // on-time reply. Otherwise we tear down a healthy XPC channel because a
        // follow-up timeout fires after the reply already arrived.
        let didFire = gate.tryResume(throwing: PrivilegedFanControlClientError.timeout(timeoutSeconds))
        if didFire {
            scheduleDiscard(client, matching: connectionID)
        }
    }

    nonisolated private static func handleRemoteError(
        _ client: PrivilegedFanControlClient?,
        gate: PrivilegedFanControlRequestGate,
        connectionID: ObjectIdentifier,
        message: String
    ) {
        scheduleDiscard(client, matching: connectionID)
        gate.resume(throwing: PrivilegedFanControlClientError.unavailable(message))
    }

    nonisolated private static func handleUnavailableProxy(
        _ client: PrivilegedFanControlClient?,
        gate: PrivilegedFanControlRequestGate,
        connectionID: ObjectIdentifier
    ) {
        scheduleDiscard(client, matching: connectionID)
        gate.resume(throwing: PrivilegedFanControlClientError.unavailable("Failed to create privileged helper proxy."))
    }

    nonisolated private static func handleTimeout<T>(
        _ client: PrivilegedFanControlClient?,
        gate: PrivilegedFanControlValueGate<T>,
        connectionID: ObjectIdentifier,
        timeoutSeconds: Double
    ) {
        // Only discard the connection if the gate wasn't already satisfied by an
        // on-time reply. Otherwise we tear down a healthy XPC channel because a
        // follow-up timeout fires after the reply already arrived.
        let didFire = gate.tryResume(throwing: PrivilegedFanControlClientError.timeout(timeoutSeconds))
        if didFire {
            scheduleDiscard(client, matching: connectionID)
        }
    }

    nonisolated private static func handleRemoteError<T>(
        _ client: PrivilegedFanControlClient?,
        gate: PrivilegedFanControlValueGate<T>,
        connectionID: ObjectIdentifier,
        message: String
    ) {
        scheduleDiscard(client, matching: connectionID)
        gate.resume(throwing: PrivilegedFanControlClientError.unavailable(message))
    }

    nonisolated private static func handleUnavailableProxy<T>(
        _ client: PrivilegedFanControlClient?,
        gate: PrivilegedFanControlValueGate<T>,
        connectionID: ObjectIdentifier
    ) {
        scheduleDiscard(client, matching: connectionID)
        gate.resume(throwing: PrivilegedFanControlClientError.unavailable("Failed to create privileged helper proxy."))
    }

    nonisolated private static func scheduleDiscard(
        _ client: PrivilegedFanControlClient?,
        matching connectionID: ObjectIdentifier
    ) {
        Task.detached {
            await client?.discardConnection(matching: connectionID)
        }
    }
}

private typealias PrivilegedFanControlValueGate<T> = ContinuationGate<T> where T: Sendable
