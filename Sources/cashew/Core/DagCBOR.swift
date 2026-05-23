import Foundation
#if canImport(CoreFoundation)
import CoreFoundation
#endif

public enum DagCBORError: Error {
    case unsupportedType
    case integerOverflow
    case unexpectedEnd
    case invalidCBOR
}

public struct DagCBOR {
    private static let sharedJSONEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let sharedJSONDecoder = JSONDecoder()

    // MARK: - Encode

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let jsonData = try sharedJSONEncoder.encode(value)
        // Pre-allocate output capacity using the JSON length as a proxy.
        // CBOR is typically 10–30% smaller than JSON; this avoids repeated
        // Data reallocations (each realloc doubles capacity and copies).
        var output = Data(capacity: jsonData.count)
        let jsonValue = try JSONSerialization.jsonObject(with: jsonData, options: .fragmentsAllowed)
        try serializeValue(jsonValue, to: &output)
        return output
    }

    // MARK: - Decode

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        var offset = 0
        let value = try parseValue(data, offset: &offset)
        let jsonData = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
        return try sharedJSONDecoder.decode(type, from: jsonData)
    }

    // MARK: - CBOR Parser

    /// Maximum nesting depth for CBOR arrays and maps. Deeper structures are
    /// rejected to prevent stack overflow from recursive parseValue calls.
    private static let maxDepth = 64
    /// Maximum number of elements in a single CBOR array or map. Prevents
    /// Int(UInt64) overflow on reserveCapacity and OOM from huge counts.
    private static let maxCollectionCount: UInt64 = 65_536

    private static func parseValue(_ data: Data, offset: inout Int, depth: Int = 0) throws -> Any {
        guard depth < maxDepth else { throw DagCBORError.invalidCBOR }
        guard offset < data.count else { throw DagCBORError.unexpectedEnd }
        let initial = data[offset]
        let majorType = initial >> 5
        let additional = initial & 0x1f
        offset += 1

        switch majorType {
        case 0:
            return try NSNumber(value: readArgument(additional, data: data, offset: &offset))
        case 1:
            let raw = try readArgument(additional, data: data, offset: &offset)
            return NSNumber(value: ~Int64(bitPattern: raw))
        case 2:
            let len = try readArgument(additional, data: data, offset: &offset)
            // Guard before Int() cast: UInt64 > Int.max traps; also ensure data exists.
            guard len <= UInt64(data.count - offset) else { throw DagCBORError.unexpectedEnd }
            let safeLen = Int(len)
            let end = offset + safeLen
            let bytes = data[offset..<end]
            offset = end
            return bytes.base64EncodedString()
        case 3:
            let len = try readArgument(additional, data: data, offset: &offset)
            guard len <= UInt64(data.count - offset) else { throw DagCBORError.unexpectedEnd }
            let safeLen = Int(len)
            let end = offset + safeLen
            guard let str = String(data: data[offset..<end], encoding: .utf8) else {
                throw DagCBORError.invalidCBOR
            }
            offset = end
            return str
        case 4:
            let count = try readArgument(additional, data: data, offset: &offset)
            guard count <= maxCollectionCount else { throw DagCBORError.invalidCBOR }
            var array: [Any] = []
            array.reserveCapacity(Int(count))
            for _ in 0..<count {
                try array.append(parseValue(data, offset: &offset, depth: depth + 1))
            }
            return array
        case 5:
            let count = try readArgument(additional, data: data, offset: &offset)
            guard count <= maxCollectionCount else { throw DagCBORError.invalidCBOR }
            var dict: [String: Any] = [:]
            for _ in 0..<count {
                let key = try parseValue(data, offset: &offset, depth: depth + 1)
                guard let keyStr = key as? String else { throw DagCBORError.invalidCBOR }
                dict[keyStr] = try parseValue(data, offset: &offset, depth: depth + 1)
            }
            return dict
        case 7:
            switch additional {
            case 20: return NSNumber(value: false)
            case 21: return NSNumber(value: true)
            case 22: return NSNull()
            case 23: return NSNull()
            case 25:
                guard offset + 2 <= data.count else { throw DagCBORError.unexpectedEnd }
                let bits = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
                offset += 2
                return NSNumber(value: float16ToDouble(bits))
            case 26:
                guard offset + 4 <= data.count else { throw DagCBORError.unexpectedEnd }
                var bits: UInt32 = 0
                bits |= UInt32(data[offset]) << 24
                bits |= UInt32(data[offset + 1]) << 16
                bits |= UInt32(data[offset + 2]) << 8
                bits |= UInt32(data[offset + 3])
                offset += 4
                return NSNumber(value: Float(bitPattern: bits))
            case 27:
                guard offset + 8 <= data.count else { throw DagCBORError.unexpectedEnd }
                var bits: UInt64 = 0
                for i in 0..<8 {
                    bits |= UInt64(data[offset + i]) << (56 - i * 8)
                }
                offset += 8
                return NSNumber(value: Double(bitPattern: bits))
            default:
                throw DagCBORError.invalidCBOR
            }
        default:
            throw DagCBORError.invalidCBOR
        }
    }

    private static func readArgument(_ additional: UInt8, data: Data, offset: inout Int) throws -> UInt64 {
        if additional < 24 {
            return UInt64(additional)
        }
        switch additional {
        case 24:
            guard offset < data.count else { throw DagCBORError.unexpectedEnd }
            let val = data[offset]
            offset += 1
            return UInt64(val)
        case 25:
            guard offset + 2 <= data.count else { throw DagCBORError.unexpectedEnd }
            let val = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
            offset += 2
            return UInt64(val)
        case 26:
            guard offset + 4 <= data.count else { throw DagCBORError.unexpectedEnd }
            var val: UInt32 = 0
            for i in 0..<4 {
                val |= UInt32(data[offset + i]) << (24 - i * 8)
            }
            offset += 4
            return UInt64(val)
        case 27:
            guard offset + 8 <= data.count else { throw DagCBORError.unexpectedEnd }
            var val: UInt64 = 0
            for i in 0..<8 {
                val |= UInt64(data[offset + i]) << (56 - i * 8)
            }
            offset += 8
            return val
        default:
            throw DagCBORError.invalidCBOR
        }
    }

    private static func float16ToDouble(_ bits: UInt16) -> Double {
        let sign = (bits >> 15) & 1
        let exp = (bits >> 10) & 0x1f
        let frac = bits & 0x3ff
        let signMultiplier: Double = sign == 0 ? 1.0 : -1.0
        if exp == 0 {
            return signMultiplier * Double(frac) * pow(2.0, -24.0)
        } else if exp == 31 {
            return frac == 0 ? signMultiplier * .infinity : .nan
        }
        return signMultiplier * pow(2.0, Double(Int(exp) - 15)) * (1.0 + Double(frac) / 1024.0)
    }

    // MARK: - CBOR Encoder

    private static func serializeValue(_ value: Any, to output: inout Data) throws {
        switch value {
        case is NSNull:
            output.append(0xf6)
        case let number as NSNumber:
            // Distinguish Bool from numeric NSNumber.
            // On Apple platforms CFGetTypeID reliably identifies kCFBooleanTrue/False
            // singletons that JSONSerialization creates for JSON true/false.
            // objCType alone is "c" for both ObjC BOOL and Swift Bool, so it cannot
            // distinguish them from int8/char on macOS.
            // On Linux (no CoreFoundation) JSONSerialization encodes booleans as "B".
            #if canImport(CoreFoundation)
            let isBool = CFGetTypeID(number) == CFBooleanGetTypeID()
            #else
            let isBool = String(cString: number.objCType) == "B"
            #endif
            if isBool {
                output.append(number.boolValue ? 0xf5 : 0xf4)
            } else if isInteger(number) {
                let int64 = number.int64Value
                if int64 >= 0 {
                    writeUnsigned(UInt64(int64), majorType: 0, to: &output)
                } else {
                    writeUnsigned(UInt64(~int64), majorType: 1, to: &output)
                }
            } else {
                writeFloat64(number.doubleValue, to: &output)
            }
        case let string as String:
            let utf8 = Data(string.utf8)
            writeUnsigned(UInt64(utf8.count), majorType: 3, to: &output)
            output.append(utf8)
        case let array as [Any]:
            writeUnsigned(UInt64(array.count), majorType: 4, to: &output)
            for element in array {
                try serializeValue(element, to: &output)
            }
        case let dict as [String: Any]:
            let sortedKeys = dict.keys.sorted { a, b in
                let aLen = a.utf8.count
                let bLen = b.utf8.count
                if aLen != bLen { return aLen < bLen }
                return a < b
            }
            writeUnsigned(UInt64(sortedKeys.count), majorType: 5, to: &output)
            for key in sortedKeys {
                let keyBytes = Data(key.utf8)
                writeUnsigned(UInt64(keyBytes.count), majorType: 3, to: &output)
                output.append(keyBytes)
                try serializeValue(dict[key]!, to: &output)
            }
        default:
            throw DagCBORError.unsupportedType
        }
    }

    private static func isInteger(_ number: NSNumber) -> Bool {
        let objCType = String(cString: number.objCType)
        switch objCType {
        case "c", "C", "s", "S", "i", "I", "l", "L", "q", "Q":
            return true
        default:
            return false
        }
    }

    private static func writeUnsigned(_ value: UInt64, majorType: UInt8, to output: inout Data) {
        let major = majorType << 5
        if value < 24 {
            output.append(major | UInt8(value))
        } else if value <= UInt8.max {
            output.append(major | 24)
            output.append(UInt8(value))
        } else if value <= UInt16.max {
            output.append(major | 25)
            var be = UInt16(value).bigEndian
            output.append(Data(bytes: &be, count: 2))
        } else if value <= UInt32.max {
            output.append(major | 26)
            var be = UInt32(value).bigEndian
            output.append(Data(bytes: &be, count: 4))
        } else {
            output.append(major | 27)
            var be = value.bigEndian
            output.append(Data(bytes: &be, count: 8))
        }
    }

    private static func writeFloat64(_ value: Double, to output: inout Data) {
        output.append(0xfb)
        var be = value.bitPattern.bigEndian
        output.append(Data(bytes: &be, count: 8))
    }
}
