import XCTest
@testable import FileIdentityKit

final class Base62Tests: XCTestCase {
    func testIntegerBoundaryValuesRoundTrip() {
        let boundaries: [UInt64] = [
            0,
            1,
            61,
            62,
            UInt64(UInt32.max),
            UInt64.max
        ]

        for value in boundaries {
            let encoded = Base62.encode(value)
            let decoded: UInt64? = Base62.decode(encoded)
            XCTAssertEqual(decoded, value, "Roundtrip failed for \(value) (encoded: \(encoded))")
        }

        // UInt64.max must produce exactly 11 characters
        let encodedMax = Base62.encode(UInt64.max)
        XCTAssertEqual(encodedMax.count, 11)
        let decodedMax: UInt64? = Base62.decode(encodedMax)
        XCTAssertEqual(decodedMax, UInt64.max)

        // Specific expected values
        XCTAssertEqual(Base62.encode(0), "0")
        XCTAssertEqual(Base62.encode(1), "1")
        XCTAssertEqual(Base62.encode(61), "z")
        XCTAssertEqual(Base62.encode(62), "10")
    }

    func testDataRoundTripAndLeadingZerosPreservation() {
        let testCases: [Data] = [
            Data(),
            Data([0]),
            Data([0, 0, 0]),
            Data([0, 1]),
            Data([0, 0, 255, 42]),
            Data((0..<256).map { UInt8($0) }),
            Data("Hello, Base62 World!".utf8),
            Data([0, 0, 0, 0]) + Data("LeadingZeroData".utf8)
        ]

        for data in testCases {
            let encoded = Base62.encode(data)
            let decoded: Data? = Base62.decode(encoded)
            XCTAssertEqual(decoded, data, "Data roundtrip failed for \(data) (encoded: \(encoded))")
        }

        // Leading zero padding check
        XCTAssertEqual(Base62.encode(Data()), "")
        XCTAssertEqual(Base62.encode(Data([0])), "0")
        XCTAssertEqual(Base62.encode(Data([0, 0])), "00")
        XCTAssertEqual(Base62.encode(Data([0, 0, 0])), "000")
        XCTAssertEqual(Base62.decode("") as Data?, Data())
        XCTAssertEqual(Base62.decode("0") as Data?, Data([0]))
        XCTAssertEqual(Base62.decode("00") as Data?, Data([0, 0]))
        XCTAssertEqual(Base62.decode("000") as Data?, Data([0, 0, 0]))
    }

    func testIntegerInvalidCharactersAndOverflow() {
        // Empty string
        let emptyDecoded: UInt64? = Base62.decode("")
        XCTAssertNil(emptyDecoded)

        // Invalid characters
        let invalidStrings = ["-", "_", "!", "abc-123", "test_value", "hello world", "@123", "a+b", "1/2"]
        for invalid in invalidStrings {
            let decoded: UInt64? = Base62.decode(invalid)
            XCTAssertNil(decoded, "Expected nil for invalid string: \(invalid)")
        }

        // Overflow: 11 'z' characters = 62^11 - 1 > UInt64.max
        let overflow11z: UInt64? = Base62.decode("zzzzzzzzzzz")
        XCTAssertNil(overflow11z)
        // 12 characters always overflows UInt64
        let overflow12: UInt64? = Base62.decode("100000000000")
        XCTAssertNil(overflow12)
        // UInt64.max + 1 representation
        let maxEncoded = Base62.encode(UInt64.max)
        let maxDecoded: UInt64? = Base62.decode(maxEncoded)
        XCTAssertNotNil(maxDecoded)
        let maxPlusZero: UInt64? = Base62.decode(maxEncoded + "0")
        XCTAssertNil(maxPlusZero)
    }

    func testDataInvalidCharacters() {
        let invalidStrings = ["-", "_", "!", "00abc!", "data_stream", "bad char"]
        for invalid in invalidStrings {
            let decoded: Data? = Base62.decode(invalid)
            XCTAssertNil(decoded, "Expected nil for invalid data string: \(invalid)")
        }
    }
}
