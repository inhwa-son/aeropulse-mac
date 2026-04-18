import Foundation

/// Strongly-typed representation of the 4-character keys exposed by `AppleSMC`.
/// Centralises the magic strings that were previously scattered across the C
/// bridge, the privileged helper, and the diagnostic CLI paths.
enum SMCKey: Hashable, CustomStringConvertible {
    /// Number of fans (`FNum`, ui8).
    case fanCount
    /// Fan enable bitmask (`FEna`, hex_).
    case fanEnable
    /// Current RPM readback (`F<i>Ac`, flt ).
    case currentRPM(fanIndex: Int)
    /// Target RPM setpoint (`F<i>Tg`, flt ).
    case targetRPM(fanIndex: Int)
    /// Minimum supported RPM (`F<i>Mn`, flt ).
    case minimumRPM(fanIndex: Int)
    /// Maximum supported RPM (`F<i>Mx`, flt ).
    case maximumRPM(fanIndex: Int)
    /// Legacy mode byte, uppercase (`F<i>Md`, ui8) — absent on M5+.
    case modeUppercase(fanIndex: Int)
    /// Mode byte, lowercase (`F<i>md`, ui8) — the key that actually takes writes on Apple Silicon.
    case mode(fanIndex: Int)
    /// Per-fan firmware state byte (`F<i>St`, ui8).
    case firmwareState(fanIndex: Int)
    /// Total number of SMC keys (`#KEY`, ui32) — used for enumeration.
    case keyIndexCount
    /// Raw escape hatch for keys not explicitly modelled.
    case raw(String)

    var rawString: String {
        switch self {
        case .fanCount: return "FNum"
        case .fanEnable: return "FEna"
        case let .currentRPM(i): return fanKey(prefix: "F", suffix: "Ac", index: i)
        case let .targetRPM(i): return fanKey(prefix: "F", suffix: "Tg", index: i)
        case let .minimumRPM(i): return fanKey(prefix: "F", suffix: "Mn", index: i)
        case let .maximumRPM(i): return fanKey(prefix: "F", suffix: "Mx", index: i)
        case let .modeUppercase(i): return fanKey(prefix: "F", suffix: "Md", index: i)
        case let .mode(i): return fanKey(prefix: "F", suffix: "md", index: i)
        case let .firmwareState(i): return fanKey(prefix: "F", suffix: "St", index: i)
        case .keyIndexCount: return "#KEY"
        case let .raw(s): return s
        }
    }

    var description: String { rawString }

    private func fanKey(prefix: String, suffix: String, index: Int) -> String {
        precondition((0...9).contains(index), "fan index must be a single digit (0-9), got \(index)")
        return "\(prefix)\(index)\(suffix)"
    }
}

/// 4-character type tag describing the byte layout of a `SMCKey`'s value.
enum SMCType: String, CustomStringConvertible {
    case ui8 = "ui8 "
    case ui16 = "ui16"
    case ui32 = "ui32"
    case sp78 = "sp78"   // signed fixed-point 8.8, temperature
    case fpe2 = "fpe2"   // legacy RPM fixed-point, still appears on some sensors
    case float32 = "flt "
    case hex = "hex_"
    case flag = "flag"

    var description: String { rawValue }
}
