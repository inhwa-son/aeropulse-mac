// NOTE: This file uses undocumented Apple IOKit HID APIs loaded via dlopen/dlsym.
// These private symbols are community-documented and used by similar open-source projects
// (Stats.app, iStats, etc.) but may change across macOS versions. Not suitable for
// Mac App Store distribution.

import Darwin
import Foundation
import IOKit.hidsystem

final class HIDTemperatureService: @unchecked Sendable {
    @objc protocol IOHIDEvent: NSObjectProtocol {}

    typealias CreateClientFn = @convention(c) (CFAllocator?) -> IOHIDEventSystemClient?
    typealias SetMatchingFn = @convention(c) (IOHIDEventSystemClient?, CFDictionary?) -> Void
    typealias CopyEventFn = @convention(c) (IOHIDServiceClient?, Int64, Int32, Int64) -> IOHIDEvent?
    typealias EventFloatFn = @convention(c) (IOHIDEvent?, UInt32) -> Double
    typealias CopyPropertyFn = @convention(c) (IOHIDServiceClient?, CFString?) -> CFTypeRef?

    private let createClient: CreateClientFn
    private let setMatching: SetMatchingFn
    private let copyEvent: CopyEventFn
    private let eventFloatValue: EventFloatFn
    private let copyProperty: CopyPropertyFn

    init?() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else {
            return nil
        }

        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let ptr = dlsym(handle, name) else { return nil }
            return unsafeBitCast(ptr, to: type)
        }

        guard
            let _createClient = symbol("IOHIDEventSystemClientCreate", as: CreateClientFn.self),
            let _setMatching = symbol("IOHIDEventSystemClientSetMatching", as: SetMatchingFn.self),
            let _copyEvent = symbol("IOHIDServiceClientCopyEvent", as: CopyEventFn.self),
            let _eventFloatValue = symbol("IOHIDEventGetFloatValue", as: EventFloatFn.self),
            let _copyProperty = symbol("IOHIDServiceClientCopyProperty", as: CopyPropertyFn.self)
        else {
            return nil
        }

        createClient = _createClient
        setMatching = _setMatching
        copyEvent = _copyEvent
        eventFloatValue = _eventFloatValue
        copyProperty = _copyProperty
    }

    func readSensors() -> [TemperatureSensor] {
        guard let client = createClient(kCFAllocatorDefault) else {
            return []
        }

        setMatching(client, ["PrimaryUsage": 5, "PrimaryUsagePage": 65280] as CFDictionary)
        guard let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else {
            return []
        }

        var grouped: [String: [Double]] = [:]

        for service in services {
            let name = normalizedSensorName(serviceName(service) ?? "Sensor")
            guard let event = copyEvent(service, 15, 0, 0) else {
                continue
            }

            let celsius = eventFloatValue(event, 983040)
            guard celsius > 0, celsius < 200 else {
                continue
            }

            grouped[name, default: []].append(celsius)
        }

        let sensors = grouped.map { name, samples in
            let average = samples.reduce(0, +) / Double(samples.count)
            let key = "hid.\(normalized(name))"
            return TemperatureSensor(
                id: key,
                key: key,
                name: name,
                celsius: average,
                source: .hid
            )
        }

        return sensors.sorted { lhs, rhs in
            if lhs.celsius == rhs.celsius {
                return lhs.name < rhs.name
            }
            return lhs.celsius > rhs.celsius
        }
    }

    private func serviceName(_ service: IOHIDServiceClient) -> String? {
        if let raw = copyProperty(service, "Product" as CFString) as? String, !raw.isEmpty {
            return raw
        }

        guard let raw = copyProperty(service, "LocationID" as CFString) as? NSNumber else {
            return nil
        }

        return "Unknown-\(raw.uint64Value)"
    }

    private func normalizedSensorName(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        if lowercased == "gas gauge battery" {
            return "Battery"
        }

        if lowercased == "pmu tcal" {
            return "GPU Package"
        }

        if lowercased.hasPrefix("pmu tdie") {
            let suffix = trimmed.drop { !$0.isNumber }
            if suffix.isEmpty {
                return "CPU Die"
            }
            return "CPU Core \(suffix)"
        }

        return trimmed
    }

    private func normalized(_ input: String) -> String {
        input
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
