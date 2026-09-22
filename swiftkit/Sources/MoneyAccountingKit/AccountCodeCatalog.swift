import Foundation

/// 계정과목 하나의 구획과 ko/en 표시명.
public struct AccountCodeDescriptor: Sendable, Equatable {
    public let section: AccountSection
    public let korean: String
    public let english: String

    public init(section: AccountSection, korean: String, english: String) {
        self.section = section
        self.korean = korean
        self.english = english
    }
}

/// 계정과목 → 구획·표시명 표. switch 대신 표로 두는 이유: 케이스가 37개라 한 함수의 switch 는
/// 복잡도 상한(20)을 넘고, 표는 케이스 추가 시 테스트(`testEveryCodeHasDescriptor`)가 누락을 잡는다.
enum AccountCodeCatalog {
    static func descriptor(for code: AccountCode) -> AccountCodeDescriptor {
        guard let found = table[code] else {
            preconditionFailure("AccountCodeCatalog 에 \(code.rawValue) 항목이 없다 — 케이스를 추가했으면 표도 갱신한다")
        }
        return found
    }

    private static func entry(_ section: AccountSection, _ korean: String, _ english: String) -> AccountCodeDescriptor {
        AccountCodeDescriptor(section: section, korean: korean, english: english)
    }

    private static let table: [AccountCode: AccountCodeDescriptor] = [
        .sales: entry(.revenue, "매출액", "Sales"),

        .purchases: entry(.costOfSales, "당기매입", "Purchases"),
        .aiApiUsage: entry(.costOfSales, "AI API 사용료", "AI API usage"),
        .hostingAndCloud: entry(.costOfSales, "서버·클라우드", "Hosting and cloud"),

        .salaries: entry(.sellingAndAdministrative, "급여", "Salaries"),
        .employeeBenefits: entry(.sellingAndAdministrative, "복리후생비", "Employee benefits"),
        .travelAndTransportation: entry(.sellingAndAdministrative, "여비교통비", "Travel and transportation"),
        .entertainment: entry(.sellingAndAdministrative, "접대비(기업업무추진비)", "Entertainment"),
        .communication: entry(.sellingAndAdministrative, "통신비", "Communication"),
        .utilities: entry(.sellingAndAdministrative, "수도광열비", "Utilities"),
        .taxesAndDues: entry(.sellingAndAdministrative, "세금과공과", "Taxes and dues"),
        .depreciation: entry(.sellingAndAdministrative, "감가상각비", "Depreciation"),
        .rent: entry(.sellingAndAdministrative, "임차료", "Rent"),
        .insurance: entry(.sellingAndAdministrative, "보험료", "Insurance"),
        .repairs: entry(.sellingAndAdministrative, "수선비", "Repairs"),
        .vehicleMaintenance: entry(.sellingAndAdministrative, "차량유지비", "Vehicle maintenance"),
        .educationAndTraining: entry(.sellingAndAdministrative, "교육훈련비", "Education and training"),
        .booksAndPrinting: entry(.sellingAndAdministrative, "도서인쇄비", "Books and printing"),
        .supplies: entry(.sellingAndAdministrative, "소모품비", "Supplies"),
        .fees: entry(.sellingAndAdministrative, "지급수수료", "Fees and commissions"),
        .advertising: entry(.sellingAndAdministrative, "광고선전비", "Advertising"),
        .outsourcing: entry(.sellingAndAdministrative, "외주비", "Outsourcing"),
        .intangibleAmortization: entry(.sellingAndAdministrative, "무형자산상각비", "Intangible amortization"),
        .miscellaneousExpense: entry(.sellingAndAdministrative, "잡비", "Miscellaneous expenses"),

        .interestIncome: entry(.nonOperatingIncome, "이자수익", "Interest income"),
        .foreignExchangeGain: entry(.nonOperatingIncome, "외환차익", "Foreign exchange gain"),
        .miscellaneousIncome: entry(.nonOperatingIncome, "잡이익", "Miscellaneous income"),

        .interestExpense: entry(.nonOperatingExpense, "이자비용", "Interest expense"),
        .foreignExchangeLoss: entry(.nonOperatingExpense, "외환차손", "Foreign exchange loss"),
        .donations: entry(.nonOperatingExpense, "기부금", "Donations"),
        .miscellaneousLoss: entry(.nonOperatingExpense, "잡손실", "Miscellaneous loss"),

        .ownerDrawing: entry(.capitalTransaction, "대표 인출", "Owner drawing"),
        .ownerContribution: entry(.capitalTransaction, "대표 투입", "Owner contribution"),
        .loanProceeds: entry(.capitalTransaction, "차입", "Loan proceeds"),
        .loanRepayment: entry(.capitalTransaction, "차입금 상환", "Loan repayment"),
    ]
}
