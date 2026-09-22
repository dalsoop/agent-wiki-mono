import Foundation

/// Gujo 스태프 인증 계약 v1 §2 — abilities 문자열 enum(PascalCase).
/// 서버(laravel-mono `platform-gujo-core`)와 이름이 1:1 이다. 한쪽만 바꾸지 말 것.
public enum StaffAbility: String, Codable, CaseIterable, Sendable, Hashable {
    case customersRead = "CustomersRead"
    case customersWrite = "CustomersWrite"
    case ordersRead = "OrdersRead"
    case ordersCancel = "OrdersCancel"
    case ordersRefund = "OrdersRefund"
    case subscriptionsRead = "SubscriptionsRead"
    case subscriptionsWrite = "SubscriptionsWrite"
    case subscriptionsRefund = "SubscriptionsRefund"
    case entitlementsGrant = "EntitlementsGrant"
    case entitlementsRevoke = "EntitlementsRevoke"
    case devicesRevoke = "DevicesRevoke"
    case invoicesRead = "InvoicesRead"
    case creditNotesWrite = "CreditNotesWrite"
    case inquiriesRead = "InquiriesRead"
    case inquiriesWrite = "InquiriesWrite"
    case opsHealth = "OpsHealth"
    case opsPackages = "OpsPackages"
    case opsDevices = "OpsDevices"
    case opsInstallJobs = "OpsInstallJobs"
    case opsRunners = "OpsRunners"
    case opsReceipts = "OpsReceipts"
    case opsAudit = "OpsAudit"
    case releaseIntake = "ReleaseIntake"
    case skillPublish = "SkillPublish"
    case assetsWrite = "AssetsWrite"
    case productsWrite = "ProductsWrite"
    case offersWrite = "OffersWrite"
    case mailSend = "MailSend"
    case mailConsentsWrite = "MailConsentsWrite"
    /// 예약, 미사용.
    case lectureWrite = "LectureWrite"

    /// 서버가 준 문자열 이름. 계약상 rawValue 와 같다.
    public var name: String { rawValue }
}
