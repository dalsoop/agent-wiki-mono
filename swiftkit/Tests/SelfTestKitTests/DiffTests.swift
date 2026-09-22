import XCTest
@testable import SelfTestKit

final class DiffTests: XCTestCase {
    
    // MARK: - Test Models
    
    struct Address: Equatable {
        let street: String
        let city: String
        let zipCode: Int
    }
    
    struct UserProfile: Equatable {
        let id: Int
        let name: String
        let address: Address
        let hobbies: [String]
        let metadata: [String: String]
        let nickname: String?
    }
    
    enum Role: Equatable {
        case guest
        case member(level: Int)
        case admin(permissions: [String])
    }
    
    // MARK: - Nested Struct Tests
    
    func testNestedStructEqual() {
        let user1 = UserProfile(
            id: 1,
            name: "Alice",
            address: Address(street: "Teheran-ro", city: "Seoul", zipCode: 12345),
            hobbies: ["reading", "coding"],
            metadata: ["plan": "pro", "tier": "gold"],
            nickname: "ally"
        )
        let user2 = UserProfile(
            id: 1,
            name: "Alice",
            address: Address(street: "Teheran-ro", city: "Seoul", zipCode: 12345),
            hobbies: ["reading", "coding"],
            metadata: ["plan": "pro", "tier": "gold"],
            nickname: "ally"
        )
        
        let diff = MiniDiff.diff(user1, user2)
        XCTAssertNil(diff, "동일한 중첩 구조체 간의 diff는 nil이어야 합니다.")
        
        // 단언 헬퍼 검증 (성공 케이스)
        assertNoDifference(user1, user2)
        XCTAssertNoDifference(user1, user2)
    }
    
    func testNestedStructDifference() {
        let expected = UserProfile(
            id: 1,
            name: "Alice",
            address: Address(street: "Teheran-ro", city: "Seoul", zipCode: 12345),
            hobbies: ["reading", "coding"],
            metadata: ["plan": "pro"],
            nickname: nil
        )
        let actual = UserProfile(
            id: 1,
            name: "Alice",
            address: Address(street: "Gangnam-daero", city: "Seoul", zipCode: 99999),
            hobbies: ["reading", "coding"],
            metadata: ["plan": "pro"],
            nickname: "ally"
        )
        
        let diff = MiniDiff.diff(expected, actual)
        XCTAssertNotNil(diff, "중첩 구조체 내부의 값이 다르면 diff가 생성되어야 합니다.")
        
        guard let diffText = diff else { return }
        XCTAssertTrue(diffText.contains("-     street: \"Teheran-ro\","))
        XCTAssertTrue(diffText.contains("+     street: \"Gangnam-daero\","))
        XCTAssertTrue(diffText.contains("-     zipCode: 12345,"))
        XCTAssertTrue(diffText.contains("+     zipCode: 99999,"))
        XCTAssertTrue(diffText.contains("-   nickname: nil,"))
        XCTAssertTrue(diffText.contains("+   nickname: \"ally\","))
    }
    
    // MARK: - Array Tests
    
    func testArrayEqual() {
        let array1 = [1, 2, 3, 4, 5]
        let array2 = [1, 2, 3, 4, 5]
        
        let diff = MiniDiff.diff(array1, array2)
        XCTAssertNil(diff)
        assertNoDifference(array1, array2)
        XCTAssertNoDifference(array1, array2)
    }
    
    func testArrayDifference() {
        let expected = ["apple", "banana", "cherry"]
        let actual = ["apple", "blueberry", "cherry", "durian"]
        
        let diff = MiniDiff.diff(expected, actual)
        XCTAssertNotNil(diff)
        
        guard let diffText = diff else { return }
        XCTAssertTrue(diffText.contains("-   \"banana\","))
        XCTAssertTrue(diffText.contains("+   \"blueberry\","))
        XCTAssertTrue(diffText.contains("+   \"durian\","))
        XCTAssertTrue(diffText.contains("    \"apple\","))
        XCTAssertTrue(diffText.contains("    \"cherry\","))
    }
    
    // MARK: - Dictionary Tests
    
    func testDictionaryEqualWithDifferentKeyOrder() {
        // Swift Dictionary는 순서가 비결정적이지만, MiniDiff는 키를 정렬하므로 동일한 덤프를 생성해야 함.
        var dict1: [String: Int] = [:]
        dict1["z"] = 100
        dict1["a"] = 1
        dict1["m"] = 50
        
        var dict2: [String: Int] = [:]
        dict2["a"] = 1
        dict2["m"] = 50
        dict2["z"] = 100
        
        let diff = MiniDiff.diff(dict1, dict2)
        XCTAssertNil(diff, "키 삽입 순서가 달라도 내용이 같으면 diff는 nil이어야 합니다.")
        assertNoDifference(dict1, dict2)
        XCTAssertNoDifference(dict1, dict2)
    }
    
    func testDictionaryDifference() {
        let expected: [String: Any] = [
            "name": "ServiceA",
            "port": 8080,
            "active": true
        ]
        let actual: [String: Any] = [
            "name": "ServiceA",
            "port": 9000,
            "active": false
        ]
        
        let diff = MiniDiff.diff(expected, actual)
        XCTAssertNotNil(diff)
        
        guard let diffText = diff else { return }
        XCTAssertTrue(diffText.contains("-   \"port\": 8080,"))
        XCTAssertTrue(diffText.contains("+   \"port\": 9000,"))
        XCTAssertTrue(diffText.contains("-   \"active\": true,"))
        XCTAssertTrue(diffText.contains("+   \"active\": false,"))
        XCTAssertTrue(diffText.contains("    \"name\": \"ServiceA\","))
    }
    
    // MARK: - Enum Tests
    
    func testEnumDifferences() {
        let role1 = Role.guest
        let role2 = Role.member(level: 2)
        let role3 = Role.member(level: 3)
        let role4 = Role.admin(permissions: ["read", "write"])
        
        XCTAssertNil(MiniDiff.diff(role1, Role.guest))
        XCTAssertNil(MiniDiff.diff(role2, Role.member(level: 2)))
        
        let diffMember = MiniDiff.diff(role2, role3)
        XCTAssertNotNil(diffMember)
        XCTAssertTrue(diffMember?.contains("- .member(level: 2)") == true)
        XCTAssertTrue(diffMember?.contains("+ .member(level: 3)") == true)
        
        let diffRole = MiniDiff.diff(role1, role4)
        XCTAssertNotNil(diffRole)
        XCTAssertTrue(diffRole?.contains("- .guest") == true)
        XCTAssertTrue(diffRole?.contains("+ .admin") == true)
    }
    
    // MARK: - String LCS Diff Direct Tests
    
    func testStringLCSDiff() {
        let expected = """
        line 1
        line 2
        line 3
        """
        let actual = """
        line 1
        line 2 modified
        line 3
        line 4 added
        """
        
        let diff = MiniDiff.diff(expected: expected, actual: actual)
        XCTAssertNotNil(diff)
        
        guard let diffText = diff else { return }
        XCTAssertTrue(diffText.contains("  line 1"))
        XCTAssertTrue(diffText.contains("- line 2"))
        XCTAssertTrue(diffText.contains("+ line 2 modified"))
        XCTAssertTrue(diffText.contains("  line 3"))
        XCTAssertTrue(diffText.contains("+ line 4 added"))
    }
    
    // MARK: - SelfTestCase Helper Integration
    
    func testSelfTestCaseIntegration() {
        let passCase = SelfTestCase.diff(
            "User Check Pass",
            expected: Address(street: "A", city: "B", zipCode: 1),
            actual: Address(street: "A", city: "B", zipCode: 1)
        )
        XCTAssertTrue(passCase.passed)
        
        let failCase = SelfTestCase.diff(
            "User Check Fail",
            expected: Address(street: "A", city: "B", zipCode: 1),
            actual: Address(street: "A", city: "B", zipCode: 2)
        )
        XCTAssertFalse(failCase.passed)
        XCTAssertTrue(failCase.detail.contains("-   zipCode: 1,"))
        XCTAssertTrue(failCase.detail.contains("+   zipCode: 2,"))
    }
}
