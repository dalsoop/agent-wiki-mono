import Foundation

public enum RepaymentMethod: String, Codable, Equatable {
    case equalPrincipalAndInterest
    case equalPrincipal
    case bullet
}

public struct LoanContract: Codable, Equatable {
    public var principal: Decimal
    public var annualInterestRate: Decimal // e.g. 0.05 for 5%
    public var termInMonths: Int
    public var gracePeriodInMonths: Int
    public var executionDate: Date
    public var repaymentMethod: RepaymentMethod
    
    public init(
        principal: Decimal,
        annualInterestRate: Decimal,
        termInMonths: Int,
        gracePeriodInMonths: Int,
        executionDate: Date,
        repaymentMethod: RepaymentMethod
    ) {
        self.principal = principal
        self.annualInterestRate = annualInterestRate
        self.termInMonths = termInMonths
        self.gracePeriodInMonths = gracePeriodInMonths
        self.executionDate = executionDate
        self.repaymentMethod = repaymentMethod
    }
}

public struct RepaymentScheduleItem: Codable, Equatable {
    public var installment: Int
    public var date: Date
    public var principalPaid: Decimal
    public var interestPaid: Decimal
    public var totalPayment: Decimal
    public var remainingBalance: Decimal
    
    public init(
        installment: Int,
        date: Date,
        principalPaid: Decimal,
        interestPaid: Decimal,
        totalPayment: Decimal,
        remainingBalance: Decimal
    ) {
        self.installment = installment
        self.date = date
        self.principalPaid = principalPaid
        self.interestPaid = interestPaid
        self.totalPayment = totalPayment
        self.remainingBalance = remainingBalance
    }
}

public struct LoanAmortizationEngine {
    
    public init() {}
    
    public func generateSchedule(for contract: LoanContract) -> [RepaymentScheduleItem] {
        var schedule: [RepaymentScheduleItem] = []
        
        let monthlyInterestRate = contract.annualInterestRate / 12.0
        var remainingBalance = contract.principal
        
        let calendar = Calendar.current
        var currentDate = contract.executionDate
        
        // Pmt double calculation for accuracy then rounded
        let principalDouble = NSDecimalNumber(decimal: contract.principal).doubleValue
        let rDouble = NSDecimalNumber(decimal: monthlyInterestRate).doubleValue
        let remainingMonths = contract.termInMonths - contract.gracePeriodInMonths
        
        var equalPrincipalAndInterestAmount: Decimal = 0
        if contract.repaymentMethod == .equalPrincipalAndInterest && remainingMonths > 0 {
            if monthlyInterestRate > 0 {
                let nDouble = Double(remainingMonths)
                let pmtDouble = principalDouble * rDouble * pow(1 + rDouble, nDouble) / (pow(1 + rDouble, nDouble) - 1)
                equalPrincipalAndInterestAmount = Decimal(pmtDouble)
            } else {
                equalPrincipalAndInterestAmount = contract.principal / Decimal(remainingMonths)
            }
        }
        
        for month in 1...contract.termInMonths {
            currentDate = calendar.date(byAdding: .month, value: 1, to: currentDate) ?? currentDate
            let isGracePeriod = month <= contract.gracePeriodInMonths
            
            var interestPayment: Decimal = remainingBalance * monthlyInterestRate
            var roundedInterest = Decimal()
            NSDecimalRound(&roundedInterest, &interestPayment, 0, .plain)
            
            var principalPayment: Decimal = 0
            
            if !isGracePeriod {
                switch contract.repaymentMethod {
                case .bullet:
                    if month == contract.termInMonths {
                        principalPayment = remainingBalance
                    }
                case .equalPrincipal:
                    if remainingMonths > 0 {
                        principalPayment = contract.principal / Decimal(remainingMonths)
                    }
                case .equalPrincipalAndInterest:
                    principalPayment = equalPrincipalAndInterestAmount - roundedInterest
                }
            }
            
            var roundedPrincipal = Decimal()
            NSDecimalRound(&roundedPrincipal, &principalPayment, 0, .plain)
            
            // Adjust for last month or overpayment
            if month == contract.termInMonths || roundedPrincipal > remainingBalance {
                roundedPrincipal = remainingBalance
            }
            // In equal principal method, if it's the last payment of principal, adjust it
            if contract.repaymentMethod == .equalPrincipal && month == contract.termInMonths {
                 roundedPrincipal = remainingBalance
            }
            
            let totalPayment = roundedPrincipal + roundedInterest
            remainingBalance -= roundedPrincipal
            
            schedule.append(RepaymentScheduleItem(
                installment: month,
                date: currentDate,
                principalPaid: roundedPrincipal,
                interestPaid: roundedInterest,
                totalPayment: totalPayment,
                remainingBalance: remainingBalance
            ))
        }
        
        return schedule
    }
}
