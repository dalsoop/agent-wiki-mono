import XCTest
import Foundation
@testable import ISO8601DateCodecKit

final class ISO8601DateCodecKitTests: XCTestCase {
    // MARK: - Parse Tests

    func testParseStandardISO8601() throws {
        let string = "2026-09-13T23:42:27Z"
        let parsed = try XCTUnwrap(ISO8601DateCodec.parse(string))

        let calendar = Calendar(identifier: .gregorian)
        var utcCalendar = calendar
        utcCalendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        let components = utcCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: parsed)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 9)
        XCTAssertEqual(components.day, 13)
        XCTAssertEqual(components.hour, 23)
        XCTAssertEqual(components.minute, 42)
        XCTAssertEqual(components.second, 27)
    }

    func testParseWithFractionalSeconds() throws {
        let string = "2026-09-13T23:42:27.123Z"
        let parsed = try XCTUnwrap(ISO8601DateCodec.parse(string))

        let timeInterval = parsed.timeIntervalSince1970
        let fractionalPart = timeInterval - floor(timeInterval)
        XCTAssertEqual(fractionalPart, 0.123, accuracy: 0.001)
    }

    func testParseWithTimezoneOffset() throws {
        let kstString = "2026-09-13T23:42:27+09:00"
        let utcString = "2026-09-13T14:42:27Z"

        let kstDate = try XCTUnwrap(ISO8601DateCodec.parse(kstString))
        let utcDate = try XCTUnwrap(ISO8601DateCodec.parse(utcString))

        XCTAssertEqual(kstDate.timeIntervalSince1970, utcDate.timeIntervalSince1970, accuracy: 0.001)

        let kstFracString = "2026-09-13T23:42:27.500+09:00"
        let utcFracString = "2026-09-13T14:42:27.500Z"
        let kstFracDate = try XCTUnwrap(ISO8601DateCodec.parse(kstFracString))
        let utcFracDate = try XCTUnwrap(ISO8601DateCodec.parse(utcFracString))

        XCTAssertEqual(kstFracDate.timeIntervalSince1970, utcFracDate.timeIntervalSince1970, accuracy: 0.001)
    }

    func testParseNilAndEmptyAndWhitespace() {
        XCTAssertNil(ISO8601DateCodec.parse(nil))
        XCTAssertNil(ISO8601DateCodec.parse(""))
        XCTAssertNil(ISO8601DateCodec.parse("   \n\t  "))
    }

    func testParseInvalidStrings() {
        XCTAssertNil(ISO8601DateCodec.parse("not-a-date"))
        XCTAssertNil(ISO8601DateCodec.parse("2026-13-45"))
        XCTAssertNil(ISO8601DateCodec.parse("2026/09/13 23:42:27"))
    }

    // MARK: - Format Tests

    func testFormatStandard() throws {
        let original = "2026-09-13T23:42:27Z"
        let date = try XCTUnwrap(ISO8601DateCodec.parse(original))
        let formatted = ISO8601DateCodec.format(date, includeFractionalSeconds: false)
        XCTAssertEqual(formatted, original)
        XCTAssertFalse(formatted.contains("."))
    }

    func testFormatFractional() throws {
        let original = "2026-09-13T23:42:27.123Z"
        let date = try XCTUnwrap(ISO8601DateCodec.parse(original))
        let formatted = ISO8601DateCodec.format(date, includeFractionalSeconds: true)
        XCTAssertTrue(formatted.contains("2026-09-13T23:42:27"))
        XCTAssertTrue(formatted.contains(".123") || formatted.contains(".122"))
    }

    // MARK: - JSONDecoder & JSONEncoder Tests

    private struct Payload: Codable, Equatable {
        let eventDate: Date
    }

    func testJSONDecoderFlexibleWithStandardISO8601() throws {
        let json = try XCTUnwrap(#"{"eventDate":"2026-09-13T23:42:27Z"}"#.data(using: .utf8))
        let payload = try JSONDecoder.iso8601Flexible.decode(Payload.self, from: json)
        XCTAssertEqual(ISO8601DateCodec.format(payload.eventDate), "2026-09-13T23:42:27Z")
    }

    func testJSONDecoderFlexibleWithFractionalSeconds() throws {
        let json = try XCTUnwrap(#"{"eventDate":"2026-09-13T23:42:27.456Z"}"#.data(using: .utf8))
        let payload = try JSONDecoder.iso8601Flexible.decode(Payload.self, from: json)

        let timeInterval = payload.eventDate.timeIntervalSince1970
        let fractionalPart = timeInterval - floor(timeInterval)
        XCTAssertEqual(fractionalPart, 0.456, accuracy: 0.001)
    }

    func testJSONDecoderStrategyDirectUse() throws {
        let json = try XCTUnwrap(#"{"eventDate":"2026-09-13T23:42:27.789Z"}"#.data(using: .utf8))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601Flexible
        let payload = try decoder.decode(Payload.self, from: json)
        XCTAssertNotNil(payload.eventDate)
    }

    func testJSONDecoderFailureOnInvalidDate() throws {
        let json = try XCTUnwrap(#"{"eventDate":"invalid-date-string"}"#.data(using: .utf8))
        XCTAssertThrowsError(try JSONDecoder.iso8601Flexible.decode(Payload.self, from: json)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                XCTFail("Expected dataCorrupted error but got \(error)")
                return
            }
            XCTAssertTrue(context.debugDescription.contains("Expected date string to be ISO8601-formatted"))
        }
    }

    func testJSONEncoderAndDecoderRoundtrip() throws {
        let originalDate = Date(timeIntervalSince1970: 1789429347.500)
        let payload = Payload(eventDate: originalDate)

        let encodedData = try JSONEncoder.iso8601Flexible.encode(payload)
        let decodedPayload = try JSONDecoder.iso8601Flexible.decode(Payload.self, from: encodedData)

        XCTAssertEqual(originalDate.timeIntervalSince1970, decodedPayload.eventDate.timeIntervalSince1970, accuracy: 0.001)
    }

    func testJSONEncoderWithoutFractionalSeconds() throws {
        let originalDate = Date(timeIntervalSince1970: 1789429347.0)
        let payload = Payload(eventDate: originalDate)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601(includeFractionalSeconds: false)
        let encodedData = try encoder.encode(payload)
        let jsonString = try XCTUnwrap(String(data: encodedData, encoding: .utf8))
        XCTAssertFalse(jsonString.contains("."))

        let decodedPayload = try JSONDecoder.iso8601Flexible.decode(Payload.self, from: encodedData)
        XCTAssertEqual(originalDate.timeIntervalSince1970, decodedPayload.eventDate.timeIntervalSince1970, accuracy: 1.0)
    }

    func testConcurrentParsingAndFormatting() {
        let iterations = 1_000
        let dateString = "2026-09-13T23:42:27.321Z"
        let date = Date()

        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            if i % 2 == 0 {
                let parsed = ISO8601DateCodec.parse(dateString)
                XCTAssertNotNil(parsed)
            } else {
                let formatted = ISO8601DateCodec.format(date, includeFractionalSeconds: true)
                XCTAssertFalse(formatted.isEmpty)
            }
        }
    }

    // MARK: - DateCodec Tests

    func testDateCodecISO8601FormatAndParse() throws {
        let original = "2026-09-16T10:30:00Z"
        let date = try XCTUnwrap(DateCodec.parseISO8601(original))
        let formatted = DateCodec.formatISO8601(date)
        XCTAssertEqual(formatted, original)

        let now = DateCodec.isoNow()
        XCTAssertTrue(now.contains("T"))
        XCTAssertTrue(now.hasSuffix("Z"))
    }

    func testDateCodecPatternFormattingAndParsing() throws {
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let dateString = "2026-09-16 12:34:56"
        let format = "yyyy-MM-dd HH:mm:ss"

        let date = try XCTUnwrap(DateCodec.parse(dateString, format: format, timeZone: utc))
        let formatted = DateCodec.format(date, format: format, timeZone: utc)
        XCTAssertEqual(formatted, dateString)

        let timeOnly = DateCodec.format(date, format: "HH:mm:ss", timeZone: utc)
        XCTAssertEqual(timeOnly, "12:34:56")

        let dateOnly = DateCodec.format(date, format: "yyyy-MM-dd", timeZone: utc)
        XCTAssertEqual(dateOnly, "2026-09-16")
    }

    func testDateCodecTimestampFormatting() {
        let timestamp = 1789429347.123
        let utc = TimeZone(secondsFromGMT: 0) ?? .current
        let formatted = DateCodec.formatTimestamp(timestamp, format: "HH:mm:ss.SSS", timeZone: utc)
        XCTAssertTrue(formatted.contains(".123") || formatted.contains(".122"))
    }

    func testDateCodecStyleFormatting() {
        let date = Date(timeIntervalSince1970: 1789429347)
        let utc = TimeZone(secondsFromGMT: 0) ?? .current
        let formatted = DateCodec.format(date, dateStyle: .none, timeStyle: .medium, timeZone: utc)
        XCTAssertFalse(formatted.isEmpty)
    }

    func testDateCodecConcurrentCacheSafety() {
        let iterations = 2_000
        let date = Date()
        let utc = TimeZone(secondsFromGMT: 0) ?? .current

        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            let pattern = (i % 3 == 0) ? "yyyy-MM-dd" : ((i % 3 == 1) ? "HH:mm:ss" : "yyyy-MM-dd HH:mm:ss")
            let formatted = DateCodec.format(date, format: pattern, timeZone: utc)
            XCTAssertFalse(formatted.isEmpty)

            let parsed = DateCodec.parse(formatted, format: pattern, timeZone: utc)
            XCTAssertNotNil(parsed)
        }
    }

    func testMakeFormatterDefensiveCopy() {
        let originalFormat = "yyyy-MM-dd"
        let formatter1 = DateCodec.makeFormatter(format: originalFormat)
        formatter1.dateFormat = "HH:mm:ss"

        let formatter2 = DateCodec.makeFormatter(format: originalFormat)
        XCTAssertEqual(formatter2.dateFormat, originalFormat)
    }

    func testMakeStyleFormatterDefensiveCopy() {
        let formatter1 = DateCodec.makeStyleFormatter(dateStyle: .short, timeStyle: .none)
        formatter1.dateStyle = .long

        let formatter2 = DateCodec.makeStyleFormatter(dateStyle: .short, timeStyle: .none)
        XCTAssertEqual(formatter2.dateStyle, .short)
    }
}

