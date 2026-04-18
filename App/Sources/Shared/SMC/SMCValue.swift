import Foundation

/// Typed representation of a value being written to or read from `AppleSMC`.
/// Knows its own `SMCType` tag and serialises to the raw byte buffer the SMC
/// kernel interface expects — eliminating the class of bugs caused by passing
/// mismatched `type` / `hexBytes` string pairs around.
enum SMCValue: Sendable, CustomStringConvertible {
    case uint8(UInt8)
    case uint16(UInt16)
    case uint32(UInt32)
    case float32(Float)
    case hex(Data)

    var smcType: SMCType {
        switch self {
        case .uint8: return .ui8
        case .uint16: return .ui16
        case .uint32: return .ui32
        case .float32: return .float32
        case .hex: return .hex
        }
    }

    var byteCount: Int {
        switch self {
        case .uint8: return 1
        case .uint16: return 2
        case .uint32: return 4
        case .float32: return 4
        case let .hex(data): return data.count
        }
    }

    /// Raw little-endian byte representation suitable for `AppleSMC` writes.
    var bytes: [UInt8] {
        switch self {
        case let .uint8(v): return [v]
        case var .uint16(v): return withUnsafeBytes(of: &v) { Array($0) }
        case var .uint32(v): return withUnsafeBytes(of: &v) { Array($0) }
        case var .float32(v): return withUnsafeBytes(of: &v) { Array($0) }
        case let .hex(data): return Array(data)
        }
    }

    /// Hex string of `bytes` (lower-case, no separators) — matches the on-wire
    /// format used by the privileged helper's raw XPC method.
    var hexString: String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    var description: String {
        switch self {
        case let .uint8(v): return "ui8(\(v))"
        case let .uint16(v): return "ui16(\(v))"
        case let .uint32(v): return "ui32(\(v))"
        case let .float32(v): return "flt(\(v))"
        case let .hex(d): return "hex(\(d.map { String(format: "%02x", $0) }.joined()))"
        }
    }
}

enum SMCHex {
    /// Parses an even-length ASCII hex string into its raw bytes. Rejects
    /// odd-length input and non-hex characters rather than silently dropping them.
    static func bytes(from hexString: String) throws -> [UInt8] {
        guard hexString.count.isMultiple(of: 2) else {
            throw SMCHexError.oddLength(hexString.count)
        }
        var output: [UInt8] = []
        output.reserveCapacity(hexString.count / 2)
        var i = hexString.startIndex
        while i < hexString.endIndex {
            let next = hexString.index(i, offsetBy: 2)
            guard let byte = UInt8(hexString[i..<next], radix: 16) else {
                throw SMCHexError.nonHexCharacter(String(hexString[i..<next]))
            }
            output.append(byte)
            i = next
        }
        return output
    }
}

enum SMCHexError: Error, CustomStringConvertible {
    case oddLength(Int)
    case nonHexCharacter(String)

    var description: String {
        switch self {
        case let .oddLength(n): return "SMC hex payload has odd length \(n)"
        case let .nonHexCharacter(s): return "SMC hex payload contains non-hex byte '\(s)'"
        }
    }
}
