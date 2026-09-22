import XCTest
@testable import LoanScheduleKit

final class LoanScheduleKitTests: XCTestCase {

    func testBulletRepayment() {
        let contract = LoanContract(
            principal: 10_000_000,
            annualInterestRate: 0.05,
            termInMonths: 12,
            gracePeriodInMonths: 0,
            executionDate: Date(),
            repaymentMethod: .bullet
        )
        
        let engine = LoanAmortizationEngine()
        let schedule = engine.generateSchedule(for: contract)
        
        XCTAssertEqual(schedule.count, 12)
        
        for item in schedule.dropLast() {
            XCTAssertEqual(item.principalPaid, 0)
            XCTAssertEqual(item.remainingBalance, 10_000_000)
        }
        
        if let lastItem = schedule.last {
            XCTAssertEqual(lastItem.principalPaid, 10_000_000)
            XCTAssertEqual(lastItem.remainingBalance, 0)
        }
    }

    func testEqualPrincipalRepayment() {
        let contract = LoanContract(
            principal: 12_000_000,
            annualInterestRate: 0.06,
            termInMonths: 12,
            gracePeriodInMonths: 0,
            executionDate: Date(),
            repaymentMethod: .equalPrincipal
        )
        
        let engine = LoanAmortizationEngine()
        let schedule = engine.generateSchedule(for: contract)
        
        XCTAssertEqual(schedule.count, 12)
        
        var totalPrincipalPaid: Decimal = 0
        for item in schedule {
            XCTAssertEqual(item.principalPaid, 1_000_000)
            totalPrincipalPaid += item.principalPaid
        }
        XCTAssertEqual(totalPrincipalPaid, 12_000_000)
        XCTAssertEqual(schedule.last?.remainingBalance, 0)
    }

    func testEqualPrincipalAndInterestRepayment() {
        let contract = LoanContract(
            principal: 10_000_000,
            annualInterestRate: 0.05, // 5%
            termInMonths: 12,
            gracePeriodInMonths: 0,
            executionDate: Date(),
            repaymentMethod: .equalPrincipalAndInterest
        )
        
        let engine = LoanAmortizationEngine()
        let schedule = engine.generateSchedule(for: contract)
        
        XCTAssertEqual(schedule.count, 12)
        
        var totalPrincipalPaid: Decimal = 0
        for (index, item) in schedule.enumerated() {
            totalPrincipalPaid += item.principalPaid
            if index < schedule.count - 1 {
                // Payment should be mostly equal, but can vary by small rounding amounts
                XCTAssertEqual(item.totalPayment, schedule[0].totalPayment, accuracy: NSDecimalNumber(value: 2).decimalValue) // max 2 KRW difference
            }
        }
        XCTAssertEqual(totalPrincipalPaid, 10_000_000)
        XCTAssertEqual(schedule.last?.remainingBalance, 0)
    }

    func testGracePeriod() {
        let contract = LoanContract(
            principal: 12_000_000,
            annualInterestRate: 0.06,
            termInMonths: 12,
            gracePeriodInMonths: 6,
            executionDate: Date(),
            repaymentMethod: .equalPrincipal
        )
        
        let engine = LoanAmortizationEngine()
        let schedule = engine.generateSchedule(for: contract)
        
        XCTAssertEqual(schedule.count, 12)
        
        for item in schedule.prefix(6) {
            XCTAssertEqual(item.principalPaid, 0)
            XCTAssertEqual(item.remainingBalance, 12_000_000)
        }
        
        var totalPrincipalPaid: Decimal = 0
        for item in schedule.dropFirst(6) {
            XCTAssertEqual(item.principalPaid, 2_000_000)
            totalPrincipalPaid += item.principalPaid
        }
        XCTAssertEqual(totalPrincipalPaid, 12_000_000)
        XCTAssertEqual(schedule.last?.remainingBalance, 0)
    }
}
