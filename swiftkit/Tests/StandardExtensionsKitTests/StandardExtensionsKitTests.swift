import Foundation
import Testing
@testable import StandardExtensionsKit

@Suite("StandardExtensionsKit Tests")
struct StandardExtensionsKitTests {

    @Test func arrayUniquedPreservesOrder() {
        let items = [3, 1, 2, 3, 2, 4, 1, 5]
        let unique = items.uniqued()
        #expect(unique == [3, 1, 2, 4, 5])
    }

    @Test func arrayChunked() {
        let items = [1, 2, 3, 4, 5, 6, 7]
        let chunks = items.chunked(into: 3)
        #expect(chunks.count == 3)
        #expect(chunks[0] == [1, 2, 3])
        #expect(chunks[1] == [4, 5, 6])
        #expect(chunks[2] == [7])
    }

    @Test func stringPaddedAndTruncated() {
        let text = "Hello"
        #expect(text.padded(10) == "Hello     ")

        let longText = "This is a very long sentence that needs truncation"
        #expect(longText.truncated(to: 10) == "This is...")
        #expect(longText.truncated(to: 100) == longText)
    }

    @Test func stringFirstLine() {
        let multiline = "\n  \nFirst real line\nSecond line\n"
        #expect(multiline.firstLine == "First real line")
    }

    @Test func sha256HexDigest() {
        let text = "hello world"
        // echo -n "hello world" | shasum -a 256
        // b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9
        let expected = "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"
        #expect(text.sha256Hex == expected)
    }

    @Test func processInfoHelpers() {
        let info = ProcessInfo.processInfo
        // PATH는 통상 항상 존재
        #expect(info.nonEmptyString(for: "PATH") != nil)
        #expect(info.bool(for: "NON_EXISTING_ENV_FLAG_XYZ") == false)
    }

    @Test func urlExtensions() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let testSubdir = home.appendingPathComponent("test-folder")
        #expect(testSubdir.abbreviatingWithTildeInPath.hasPrefix("~"))
    }
}
