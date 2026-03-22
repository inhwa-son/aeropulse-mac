import Foundation

struct PrivilegedFanSnapshotPayload: Codable, Sendable {
    let identifier: Int
    let currentRPM: Int
    let targetRPM: Int
    let minRPM: Int
    let maxRPM: Int
    let modeHint: Int
}

struct PrivilegedFanReadResponse: Codable, Sendable {
    let snapshots: [PrivilegedFanSnapshotPayload]?
    let errorMessage: String?
}

struct PrivilegedStringResponse: Codable, Sendable {
    let value: String?
    let errorMessage: String?
}
