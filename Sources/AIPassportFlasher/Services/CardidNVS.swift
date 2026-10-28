import Foundation

/// Builds the 16 KB `cardid` NVS partition that carries the device identity
/// (SN / KEY) for the AI Passport default firmware. Byte-for-byte equivalent
/// to the generator used by the official factory-restore web page.
enum CardidNVS {
    static let partitionSize = 0x4000
    static let pageSize = 4096
    static let entrySize = 32
    static let entriesPerPage = 126

    enum ValidationError: LocalizedError {
        case invalidSN
        case invalidField(String, Int)

        var errorDescription: String? {
            switch self {
            case .invalidSN:
                return "SN 必须是 12 位小写十六进制字符（设备 MAC 地址）"
            case let .invalidField(name, max):
                return "\(name) 长度必须为 1–\(max) 字节，且不能包含 NUL 字符"
            }
        }
    }

    static func build(sn: String, deviceSecret: String, productKey: String, hardwareVersion: String) throws -> Data {
        guard sn.range(of: "^[0-9a-f]{12}$", options: .regularExpression) != nil else {
            throw ValidationError.invalidSN
        }
        for (name, value, max) in [("DeviceSecret", deviceSecret, 64), ("ProductKey", productKey, 16), ("HardwareVersion", hardwareVersion, 8)] {
            let count = value.utf8.count
            if count == 0 || count > max || value.contains("\0") {
                throw ValidationError.invalidField(name, max)
            }
        }

        var page = Page(sequence: 0)
        page.writeNamespace("folotoy-key", id: 1)
        page.writeString(namespace: 1, key: "DeviceKey", value: sn)
        page.writeString(namespace: 1, key: "DeviceSecret", value: deviceSecret)
        page.writeString(namespace: 1, key: "ProductKey", value: productKey)
        page.writeString(namespace: 1, key: "HardwareVersion", value: hardwareVersion)

        var out = [UInt8](repeating: 0xFF, count: partitionSize)
        out.replaceSubrange(0..<pageSize, with: page.data)
        return Data(out)
    }

    /// ESP-IDF NVS flavour of CRC-32 (zlib polynomial, initial value 0).
    static func crc32(_ bytes: some Sequence<UInt8>) -> UInt32 {
        var crc: UInt32 = 0
        for b in bytes {
            crc = crcTable[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    private struct Page {
        var data = [UInt8](repeating: 0xFF, count: CardidNVS.pageSize)
        var bitmap = [UInt8](repeating: 0xFF, count: 32)
        var entryCount = 0

        init(sequence: UInt32) {
            putU32(&data, 0, 0xFFFF_FFFE)
            putU32(&data, 4, sequence)
            data[8] = 0xFE
            putU32(&data, 28, CardidNVS.crc32(data[4..<28]))
        }

        mutating func append(_ bytes: [UInt8], span: Int) {
            precondition(entryCount + span <= CardidNVS.entriesPerPage, "cardid NVS page is full")
            let start = 64 + entryCount * CardidNVS.entrySize
            data.replaceSubrange(start..<(start + bytes.count), with: bytes)
            for _ in 0..<span {
                let bit = entryCount * 2
                bitmap[bit >> 3] &= ~UInt8(1 << (bit & 7))
                data.replaceSubrange(32..<64, with: bitmap)
                entryCount += 1
            }
        }

        func baseEntry(ns: UInt8, type: UInt8, span: UInt8, key: String) -> [UInt8] {
            let keyBytes = Array(key.utf8)
            precondition(keyBytes.count <= 15, "NVS key is too long: \(key)")
            var e = [UInt8](repeating: 0xFF, count: CardidNVS.entrySize)
            e[0] = ns; e[1] = type; e[2] = span; e[3] = 0xFF
            for i in 8..<24 { e[i] = 0 }
            e.replaceSubrange(8..<(8 + keyBytes.count), with: keyBytes)
            return e
        }

        static func entryCRC(_ e: [UInt8]) -> UInt32 {
            CardidNVS.crc32(Array(e[0..<4]) + Array(e[8..<32]))
        }

        mutating func writeNamespace(_ name: String, id: UInt8) {
            var e = baseEntry(ns: 0, type: 0x01, span: 1, key: name)
            e[24] = id
            putU32(&e, 4, Page.entryCRC(e))
            append(e, span: 1)
        }

        mutating func writeString(namespace: UInt8, key: String, value: String) {
            let bytes = Array(value.utf8) + [0]
            let dataEntries = (bytes.count + CardidNVS.entrySize - 1) / CardidNVS.entrySize
            var e = baseEntry(ns: namespace, type: 0x21, span: UInt8(dataEntries + 1), key: key)
            putU16(&e, 24, UInt16(bytes.count))
            putU32(&e, 28, CardidNVS.crc32(bytes))
            putU32(&e, 4, Page.entryCRC(e))
            append(e, span: 1)
            var payload = [UInt8](repeating: 0xFF, count: dataEntries * CardidNVS.entrySize)
            payload.replaceSubrange(0..<bytes.count, with: bytes)
            append(payload, span: dataEntries)
        }
    }
}

private func putU16(_ buf: inout [UInt8], _ offset: Int, _ value: UInt16) {
    buf[offset] = UInt8(value & 0xFF)
    buf[offset + 1] = UInt8(value >> 8)
}

private func putU32(_ buf: inout [UInt8], _ offset: Int, _ value: UInt32) {
    for i in 0..<4 { buf[offset + i] = UInt8((value >> (8 * UInt32(i))) & 0xFF) }
}
