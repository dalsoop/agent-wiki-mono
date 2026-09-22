import XCTest
@testable import FileIdentityKit

final class UUIDv7Tests: XCTestCase {

    // MARK: - 1. 단조 증가 (Monotonicity) 검증

    func testMonotonicOrdering() {
        let uuid1 = UUIDv7()
        let uuid2 = UUIDv7()
        let uuid3 = UUIDv7()

        XCTAssertLessThan(uuid1, uuid2)
        XCTAssertLessThan(uuid2, uuid3)
        XCTAssertLessThan(uuid1, uuid3)
    }

    // MARK: - 2. 대량 생성 (10,000건) 무충돌 및 순차 정렬 검증

    func testMassGenerationNoCollisionsAndStrictMonotonicity() {
        let count = 10_000
        var uuids = [UUIDv7]()
        uuids.reserveCapacity(count)

        for _ in 0..<count {
            uuids.append(UUIDv7())
        }

        // 1) 10,000건 생성 확인
        XCTAssertEqual(uuids.count, count)

        // 2) 충돌 0건 확인 (Set 크기가 10,000)
        let uniqueSet = Set(uuids)
        XCTAssertEqual(uniqueSet.count, count, "10,000건 생성 중 충돌 발생!")

        // 3) 엄격한 단조 증가 검증 (모든 연속 쌍 uuid[i] < uuid[i+1])
        for i in 0..<(count - 1) {
            XCTAssertLessThan(uuids[i], uuids[i + 1], "단조 증가 역전 발생: 인덱스 \(i)")
        }

        // 4) 정렬 결과와 원본 순서 100% 일치 확인
        let sorted = uuids.sorted()
        XCTAssertEqual(uuids, sorted)
    }

    // MARK: - 3. 문자열 파싱 및 라운드트립 검증

    func testStringParsingRoundtrip() {
        for _ in 0..<100 {
            let original = UUIDv7()
            let str = original.uuidString

            // 길이 36자리 검증
            XCTAssertEqual(str.count, 36)

            // 하이픈 위치 검증
            let chars = Array(str)
            XCTAssertEqual(chars[8], "-")
            XCTAssertEqual(chars[13], "-")
            XCTAssertEqual(chars[18], "-")
            XCTAssertEqual(chars[23], "-")

            // 버전 7 (index 14는 '7')
            XCTAssertEqual(chars[14], "7")

            // 변형 1 (index 19는 '8', '9', 'a', 'b' 중 하나)
            XCTAssertTrue(["8", "9", "a", "b"].contains(chars[19]))

            // init?(uuidString:) 라운드트립
            let parsed = UUIDv7(uuidString: str)
            XCTAssertNotNil(parsed)
            XCTAssertEqual(parsed, original)

            // LosslessStringConvertible (init?(_:)) 라운드트립
            let losslessParsed = UUIDv7(str)
            XCTAssertEqual(losslessParsed, original)

            // 대문자 파싱 지원 검증
            let upperParsed = UUIDv7(uuidString: str.uppercased())
            XCTAssertEqual(upperParsed, original)
        }
    }

    // MARK: - 4. Foundation UUID 상호 변환 검증

    func testFoundationUUIDInteroperability() {
        for _ in 0..<100 {
            let v7 = UUIDv7()

            // toUUID() 변환
            let foundationUUID = v7.toUUID()
            XCTAssertEqual(v7.uuidString.lowercased(), foundationUUID.uuidString.lowercased())

            // init(uuid:) 복원
            let restored = UUIDv7(uuid: foundationUUID)
            XCTAssertEqual(restored, v7)
            XCTAssertEqual(restored.uuidString, v7.uuidString)
            XCTAssertEqual(restored.high, v7.high)
            XCTAssertEqual(restored.low, v7.low)
        }
    }

    // MARK: - 5. RFC 9562 구조 및 명시적 타임스탬프/난수 주입 생성자 검증

    func testRFC9562ExplicitInitializers() {
        let ts: UInt64 = 0x018F_2D5E_6F80 // 1714457735040 ms
        let r10: UUIDv7.RandomBytes10 = (0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0, 0x11, 0x22)

        let uuid = UUIDv7(timestamp: ts, randomBytes: r10)

        // 48비트 타임스탬프 일치 확인
        XCTAssertEqual(uuid.timestamp, ts)

        // 버전 7 확인
        XCTAssertEqual(uuid.version, 7)

        // 12비트 rand_a 시퀀스 확인: r10.0의 하위 4비트(0x2) + r10.1(0x34) = 0x234
        XCTAssertEqual(uuid.sequence, 0x0234)

        // 변형 확인: RFC 9562/4122 Variant 1 = 2 (0b10)
        XCTAssertEqual(uuid.variant, 2)

        // 16바이트 튜플 생성자 라운드트립 확인
        let r16: UUIDv7.RandomBytes16 = (
            0, 0, 0, 0, 0, 0,
            0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0, 0x11, 0x22
        )
        let uuidFrom16 = UUIDv7(timestamp: ts, randomBytes: r16)
        XCTAssertEqual(uuidFrom16, uuid)
    }

    // MARK: - 6. 유효하지 않은 문자열 파싱 거부 검증

    func testInvalidUUIDStringRejection() {
        // 길이 부족/초과
        XCTAssertNil(UUIDv7(uuidString: ""))
        XCTAssertNil(UUIDv7(uuidString: "018f2d5e-6f80-7a1b-9c3d"))
        XCTAssertNil(UUIDv7(uuidString: "018f2d5e-6f80-7a1b-9c3d-4e5f6a7b8c9d00"))

        // 하이픈 위치 오류
        XCTAssertNil(UUIDv7(uuidString: "018f2d5e6f80-7a1b-9c3d-4e5f6a7b8c9d"))
        XCTAssertNil(UUIDv7(uuidString: "018f2d5e-6f807a1b-9c3d-4e5f6a7b8c9d"))

        // 16진수 아닌 문자 포함
        XCTAssertNil(UUIDv7(uuidString: "018f2d5e-6f80-7a1b-9c3d-4e5f6a7b8c9z"))
        XCTAssertNil(UUIDv7(uuidString: "018f2d5e-6f80-7a1b-9c3d-4e5f6a7b8c9!"))

        // UUIDv4 (버전 4) 문자열 거부
        let v4String = "f47ac10b-58cc-4372-a567-0e02b2c3d479"
        XCTAssertNil(UUIDv7(uuidString: v4String), "v4 UUID는 UUIDv7으로 파싱되면 안 됩니다")

        // 변형(variant) 비트가 10(0b10)이 아닌 경우 거부 (예: 'c' = 0b1100)
        let invalidVariant = "018f2d5e-6f80-7a1b-c000-4e5f6a7b8c9d"
        XCTAssertNil(UUIDv7(uuidString: invalidVariant))
    }

    // MARK: - 7. Codable 검증

    func testCodableSerialization() throws {
        let original = UUIDv7()

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        // JSON 문자열이 표준 UUID 문자열 형식인지 확인
        let jsonString = String(data: data, encoding: .utf8)
        XCTAssertEqual(jsonString, "\"\(original.uuidString)\"")

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(UUIDv7.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    // MARK: - 8. 다중 스레드 동시 생성 안전성 및 무충돌 검증

    private final class SafeCollector: @unchecked Sendable {
        private let lock = NSLock()
        var items: [UUIDv7] = []

        func append(contentsOf newItems: [UUIDv7]) {
            lock.lock()
            defer { lock.unlock() }
            items.append(contentsOf: newItems)
        }
    }

    func testConcurrentGenerationNoCollisions() {
        let threadCount = 8
        let perThread = 1_000
        let total = threadCount * perThread

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = threadCount

        let collector = SafeCollector()
        let expectation = expectation(description: "Concurrent generation")
        expectation.expectedFulfillmentCount = threadCount

        for _ in 0..<threadCount {
            queue.addOperation {
                var local = [UUIDv7]()
                local.reserveCapacity(perThread)
                for _ in 0..<perThread {
                    local.append(UUIDv7())
                }
                collector.append(contentsOf: local)
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)

        let allUUIDs = collector.items
        XCTAssertEqual(allUUIDs.count, total)

        let uniqueSet = Set(allUUIDs)
        XCTAssertEqual(uniqueSet.count, total, "동시 생성 중 \(total - uniqueSet.count)건의 충돌 발생")
    }
}
