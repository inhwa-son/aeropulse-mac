// NOTE: This file uses undocumented Apple IOKit HID APIs loaded via dlopen/dlsym.
// These private symbols are community-documented and used by similar open-source projects
// (Stats.app, iStats, etc.) but may change across macOS versions. Not suitable for
// Mac App Store distribution.

import Darwin
import Foundation
import IOKit.hidsystem

final class HIDTemperatureService: @unchecked Sendable {
    // These dlsym'd CF functions follow the Create/Copy ownership rule (they return a +1
    // reference). They are typed to return Unmanaged so every result is balanced with
    // takeRetainedValue(); returning the bridged object directly would leak the +1 on each
    // call — over days of ~2s polling that grew into millions of leaked HID events/objects.
    typealias CreateClientFn = @convention(c) (CFAllocator?) -> Unmanaged<IOHIDEventSystemClient>?
    typealias SetMatchingFn = @convention(c) (IOHIDEventSystemClient?, CFDictionary?) -> Void
    typealias CopyEventFn = @convention(c) (IOHIDServiceClient?, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    typealias EventFloatFn = @convention(c) (AnyObject?, UInt32) -> Double
    typealias CopyPropertyFn = @convention(c) (IOHIDServiceClient?, CFString?) -> Unmanaged<CFTypeRef>?

    private let copyEvent: CopyEventFn
    private let eventFloatValue: EventFloatFn
    private let copyProperty: CopyPropertyFn

    // Single HID event-system client, created once and reused for every poll.
    // See init for why this must NOT be recreated per readSensors() call.
    private let client: IOHIDEventSystemClient

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

        copyEvent = _copyEvent
        eventFloatValue = _eventFloatValue
        copyProperty = _copyProperty

        // Create the IOHIDEventSystemClient exactly once and reuse it for every poll.
        // Previously readSensors() created a fresh client on each call (polling runs ~every
        // 2s) and never released it. Each client is a connection into the HID event system
        // tracked by WindowServer/hidd; the leaked connections accumulated over days of
        // uptime until, on display-sleep, WindowServer's teardown of the bloated connection
        // table burned ~70% CPU for ~2 min and exhausted its dispatch-thread limit (512),
        // triggering a 40s watchdog hang that killed WindowServer.
        guard let sharedClient = _createClient(kCFAllocatorDefault)?.takeRetainedValue() else {
            return nil
        }
        _setMatching(sharedClient, ["PrimaryUsage": 5, "PrimaryUsagePage": 65280] as CFDictionary)
        client = sharedClient
    }

    func readSensors() -> [TemperatureSensor] {
        guard let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else {
            return []
        }

        var grouped: [String: [Double]] = [:]

        for service in services {
            let name = normalizedSensorName(serviceName(service) ?? "Sensor")
            guard let event = copyEvent(service, 15, 0, 0)?.takeRetainedValue() else {
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
        if let raw = copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String, !raw.isEmpty {
            return raw
        }

        guard let raw = copyProperty(service, "LocationID" as CFString)?.takeRetainedValue() as? NSNumber else {
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
