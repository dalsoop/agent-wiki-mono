import XCTest
@testable import MoneyRevenueRecognitionKit

final class MoneyRevenueRecognitionKitTests: XCTestCase {
    
    func testDailyRevenueRecognition() {
        let engine = RevenueRecognitionEngine()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        
        // 2026-01-01 to 2026-02-01 (31일)
        let startDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let endDate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        
        let schedule = engine.generateSchedule(
            totalAmount: 3100,
            startDate: startDate,
            endDate: endDate,
            method: .daily,
            calendar: calendar
        )
        
        XCTAssertEqual(schedule.count, 1)
        XCTAssertEqual(schedule[0].recognizedRevenue, 3100)
        XCTAssertEqual(schedule[0].remainingDeferredRevenue, 0)
    }
    
    func testMonthlyRevenueRecognitionAnnualSubscription() {
        let engine = RevenueRecognitionEngine()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        
        let startDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let endDate = calendar.date(from: DateComponents(year: 2027, month: 1, day: 1))!
        
        let schedule = engine.generateSchedule(
            totalAmount: 12000,
            startDate: startDate,
            endDate: endDate,
            method: .monthly,
            calendar: calendar
        )
        
        XCTAssertEqual(schedule.count, 12)
        XCTAssertEqual(schedule[0].recognizedRevenue, 1000)
        XCTAssertEqual(schedule[11].recognizedRevenue, 1000)
        XCTAssertEqual(schedule[11].remainingDeferredRevenue, 0)
    }
    
    func testCancellationAndRefund() {
        let engine = RevenueRecognitionEngine()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        
        let startDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let endDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))!
        
        let schedule = engine.generateSchedule(
            totalAmount: 9000, // 3개월
            startDate: startDate,
            endDate: endDate,
            method: .monthly,
            calendar: calendar
        )
        
        XCTAssertEqual(schedule.count, 3)
        XCTAssertEqual(schedule[0].recognizedRevenue, 3000)
        
        // 2월 15일에 취소 (1.5개월치)
        let cancelDate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 15))!
        
        let result = engine.processCancellation(
            schedule: schedule,
            cancellationDate: cancelDate,
            calendar: calendar
        )
        
        XCTAssertEqual(result.adjustedSchedule.count, 2)
        XCTAssertEqual(result.adjustedSchedule[0].recognizedRevenue, 3000)
        
        // 두번째 달은 2월 1일 ~ 3월 1일 (28일), 취소는 15일 (14일 경과)
        // 3000 * (14/28) = 1500
        XCTAssertEqual(result.adjustedSchedule[1].recognizedRevenue, 1500)
        
        // 남은 잔여: 3월치 3000 + 2월치 남은 1500 = 4500
        XCTAssertEqual(result.writtenOffAmount, 4500)
    }
}
