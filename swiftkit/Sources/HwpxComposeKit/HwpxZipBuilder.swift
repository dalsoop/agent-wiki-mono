import Foundation

/// HWPX 패키지를 메모리에서 zip 으로 직렬화한다.
/// mimetype 엔트리를 비압축(STORE) 첫 엔트리로 보장한다.
enum HwpxZipBuilder {
    struct Entry {
        let name: String
        let data: Data
    }

    static func build(entries: [Entry]) -> Data {
        var output = Data()
        var centralDirectory = Data()
        var recordCount: UInt16 = 0

        for entry in entries {
            let localOffset = UInt32(output.count)
            let nameData = Data(entry.name.utf8)
            let crc = crc32(entry.data)

            var local = Data()
            appendU32(&local, 0x0403_4B50) // local file header signature
            appendU16(&local, 20)
            appendU16(&local, 0)
            appendU16(&local, 0) // STORE
            appendU16(&local, 0)
            appendU16(&local, 0)
            appendU32(&local, crc)
            appendU32(&local, UInt32(entry.data.count))
            appendU32(&local, UInt32(entry.data.count))
            appendU16(&local, UInt16(nameData.count))
            appendU16(&local, 0)
            local.append(nameData)
            output.append(local)
            output.append(entry.data)

            var central = Data()
            appendU32(&central, 0x0201_4B50) // central directory signature
            appendU16(&central, 20)
            appendU16(&central, 20)
            appendU16(&central, 0)
            appendU16(&central, 0) // STORE
            appendU16(&central, 0)
            appendU16(&central, 0)
            appendU32(&central, crc)
            appendU32(&central, UInt32(entry.data.count))
            appendU32(&central, UInt32(entry.data.count))
            appendU16(&central, UInt16(nameData.count))
            appendU16(&central, 0)
            appendU16(&central, 0)
            appendU16(&central, 0)
            appendU16(&central, 0)
            appendU32(&central, 0)
            appendU32(&central, localOffset)
            central.append(nameData)
            centralDirectory.append(central)
            recordCount += 1
        }

        let cdOffset = UInt32(output.count)
        output.append(centralDirectory)

        var eocd = Data()
        appendU32(&eocd, 0x0605_4B50)
        appendU16(&eocd, 0)
        appendU16(&eocd, 0)
        appendU16(&eocd, recordCount)
        appendU16(&eocd, recordCount)
        appendU32(&eocd, UInt32(centralDirectory.count))
        appendU32(&eocd, cdOffset)
        appendU16(&eocd, 0)
        output.append(eocd)

        return output
    }

    private static func appendU16(_ data: inout Data, _ v: UInt16) {
        data.append(UInt8(v & 0xFF))
        data.append(UInt8((v >> 8) & 0xFF))
    }

    private static func appendU32(_ data: inout Data, _ v: UInt32) {
        data.append(UInt8(v & 0xFF))
        data.append(UInt8((v >> 8) & 0xFF))
        data.append(UInt8((v >> 16) & 0xFF))
        data.append(UInt8((v >> 24) & 0xFF))
    }

    private static let crcTable: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1 != 0) ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}
