import Foundation

public enum RecognitionMethod: Sendable {
    case daily    // 일할 계산
    case monthly  // 월할 계산
}

public struct RevenueRecognitionEngine {
    
    public init() {}
    
    /// 생성된 계약 기간에 대해 인식될 수익 스케줄을 산출합니다.
    public func generateSchedule(
        totalAmount: Decimal,
        startDate: Date,
        endDate: Date,
        method: RecognitionMethod,
        calendar: Calendar = .current
    ) -> [RevenueScheduleEntry] {
        switch method {
        case .daily:
            return generateDailySchedule(totalAmount: totalAmount, startDate: startDate, endDate: endDate, calendar: calendar)
        case .monthly:
            return generateMonthlySchedule(totalAmount: totalAmount, startDate: startDate, endDate: endDate, calendar: calendar)
        }
    }
    
    private func generateDailySchedule(
        totalAmount: Decimal,
        startDate: Date,
        endDate: Date,
        calendar: Calendar
    ) -> [RevenueScheduleEntry] {
        var entries: [RevenueScheduleEntry] = []
        var deferred = DeferredRevenue(totalAmount: totalAmount)
        
        let startOfStartDay = calendar.startOfDay(for: startDate)
        let endOfEndDay = calendar.startOfDay(for: endDate)
        guard let totalDays = calendar.dateComponents([.day], from: startOfStartDay, to: endOfEndDay).day, totalDays > 0 else {
            return []
        }
        
        var currentDate = startOfStartDay
        while currentDate < endOfEndDay {
            let components = calendar.dateComponents([.year, .month], from: currentDate)
            guard let startOfCurrentMonth = calendar.date(from: components),
                  let startOfNextMonth = calendar.date(byAdding: DateComponents(month: 1), to: startOfCurrentMonth) else {
                break
            }
            
            let periodEnd = min(endOfEndDay, startOfNextMonth)
            guard let daysInPeriod = calendar.dateComponents([.day], from: currentDate, to: periodEnd).day, daysInPeriod > 0 else { break }
            
            let isLastPeriod = periodEnd == endOfEndDay
            let recognized: Decimal
            if isLastPeriod {
                recognized = deferred.remainingAmount
            } else {
                let dailyRate = totalAmount / Decimal(totalDays)
                recognized = (dailyRate * Decimal(daysInPeriod)).rounded(scale: 2, roundingMode: .plain)
            }
            
            deferred.recognizedAmount += recognized
            entries.append(RevenueScheduleEntry(
                periodStart: currentDate,
                periodEnd: periodEnd,
                recognizedRevenue: recognized,
                remainingDeferredRevenue: deferred.remainingAmount
            ))
            currentDate = periodEnd
        }
        return entries
    }
    
    private func generateMonthlySchedule(
        totalAmount: Decimal,
        startDate: Date,
        endDate: Date,
        calendar: Calendar
    ) -> [RevenueScheduleEntry] {
        var entries: [RevenueScheduleEntry] = []
        var deferred = DeferredRevenue(totalAmount: totalAmount)
        
        let totalMonths = calendar.dateComponents([.month], from: startDate, to: endDate).month ?? 1
        let safeTotalMonths = max(1, totalMonths)
        
        var currentDate = startDate
        for i in 0..<safeTotalMonths {
            let isLast = (i == safeTotalMonths - 1)
            let recognized: Decimal
            if isLast {
                recognized = deferred.remainingAmount
            } else {
                let monthlyRate = totalAmount / Decimal(safeTotalMonths)
                recognized = monthlyRate.rounded(scale: 2, roundingMode: .plain)
            }
            
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentDate) ?? endDate
            let periodEnd = isLast ? endDate : nextMonth
            
            deferred.recognizedAmount += recognized
            entries.append(RevenueScheduleEntry(
                periodStart: currentDate,
                periodEnd: periodEnd,
                recognizedRevenue: recognized,
                remainingDeferredRevenue: deferred.remainingAmount
            ))
            currentDate = nextMonth
        }
        return entries
    }
    
    /// 중도 해지 시 이연 수익 정산
    public func processCancellation(
        schedule: [RevenueScheduleEntry],
        cancellationDate: Date,
        calendar: Calendar = .current
    ) -> (adjustedSchedule: [RevenueScheduleEntry], writtenOffAmount: Decimal) {
        var adjusted: [RevenueScheduleEntry] = []
        var writeOff: Decimal = 0
        
        for entry in schedule {
            if entry.periodEnd <= cancellationDate {
                adjusted.append(entry)
            } else if entry.periodStart < cancellationDate {
                // 일할 정산
                if let totalDaysInPeriod = calendar.dateComponents([.day], from: entry.periodStart, to: entry.periodEnd).day,
                   let activeDays = calendar.dateComponents([.day], from: entry.periodStart, to: cancellationDate).day,
                   totalDaysInPeriod > 0 {
                    
                    let dailyRate = entry.recognizedRevenue / Decimal(totalDaysInPeriod)
                    let activeRecognized = (dailyRate * Decimal(activeDays)).rounded(scale: 2, roundingMode: .plain)
                    let cancelledAmount = entry.recognizedRevenue - activeRecognized
                    
                    writeOff += cancelledAmount
                    
                    adjusted.append(RevenueScheduleEntry(
                        periodStart: entry.periodStart,
                        periodEnd: cancellationDate,
                        recognizedRevenue: activeRecognized,
                        remainingDeferredRevenue: entry.remainingDeferredRevenue + cancelledAmount // 잔여금액 보정
                    ))
                }
            } else {
                writeOff += entry.recognizedRevenue
            }
        }
        
        return (adjusted, writeOff)
    }
}

extension Decimal {
    func rounded(scale: Int, roundingMode: NSDecimalNumber.RoundingMode) -> Decimal {
        var result = Decimal()
        var localSelf = self
        NSDecimalRound(&result, &localSelf, scale, roundingMode)
        return result
    }
}
