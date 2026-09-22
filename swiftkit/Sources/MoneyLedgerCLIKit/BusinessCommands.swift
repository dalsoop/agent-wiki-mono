import Foundation
import MoneyLedgerKit

/// biz(사업자) 서브커맨드 — 등록 정보 + 첨부파일(사업자등록증 이미지 등).
enum BusinessCommands {
    static func run(
        context: LedgerContext, sub: [String], scanner: ArgScanner, json: Bool, output: CLIOutput
    ) async throws {
        let store = try LedgerStore(context: context)
        let files = AttachmentStore(context: context)
        let action = sub.first ?? "list"
        switch action {
        case "add":
            guard let name = scanner.value("name") else {
                throw UsageError("biz add 는 --name(상호)이 필요합니다")
            }
            let regNo = scanner.value("reg-no") ?? ""
            try validateRegistrationNumber(regNo, force: scanner.has("force"))
            if let opened = scanner.value("opened"), !LedgerDate.isValid(opened) {
                throw UsageError("--opened 는 yyyy-MM-dd 형식입니다: \(opened)")
            }
            let business = BusinessProfile(
                identity: .init(
                    name: name,
                    registrationNumber: regNo,
                    representative: scanner.value("rep"),
                    openedDate: scanner.value("opened")
                ),
                trade: .init(
                    businessType: scanner.value("type"),
                    businessItem: scanner.value("item"),
                    taxationType: scanner.value("tax"),
                    address: scanner.value("address")
                ),
                note: scanner.value("note")
            )
            try await store.save(business: business)
            emit(business, json: json, output: output)
        case "list":
            let businesses = try await store.businesses(includeArchived: scanner.has("all"))
            if json {
                var objects: [[String: Any]] = []
                for business in businesses {
                    var object = businessObject(business)
                    object["attachmentCount"] = try await store.attachments(
                        ownerKind: .business, ownerID: business.id
                    ).count
                    objects.append(object)
                }
                output.okJSON(["businesses": objects])
            } else if businesses.isEmpty {
                output.out("사업자 없음 — biz add --name <상호> --reg-no <사업자등록번호>")
            } else {
                for business in businesses {
                    let regNo = business.registrationNumber.isEmpty
                        ? "미입력" : BusinessNumber.format(business.registrationNumber)
                    let archived = business.archived ? " [보관]" : ""
                    output.out("\(CLIFormat.shortID(business.id))  \(business.name) — \(regNo)\(archived)")
                }
            }
        case "show":
            let business = try await store.resolveBusiness(try ref(sub, action))
            if json {
                var object = businessObject(business)
                object["attachments"] = try await store.attachments(ownerKind: .business, ownerID: business.id)
                    .map { attachmentObject($0, files: files) }
                output.okJSON(["business": object])
            } else {
                output.out(render(business))
                let attachments = try await store.attachments(ownerKind: .business, ownerID: business.id)
                for attachment in attachments {
                    output.out("  📎 \(CLIFormat.shortID(attachment.id))  \(attachment.originalName)")
                }
            }
        case "update":
            var business = try await store.resolveBusiness(try ref(sub, action))
            if let name = scanner.value("name") { business.name = name }
            if let regNo = scanner.value("reg-no") {
                try validateRegistrationNumber(regNo, force: scanner.has("force"))
                business.registrationNumber = BusinessNumber.digits(regNo)
            }
            if let rep = scanner.value("rep") { business.representative = rep }
            if let opened = scanner.value("opened") {
                guard LedgerDate.isValid(opened) else {
                    throw UsageError("--opened 는 yyyy-MM-dd 형식입니다: \(opened)")
                }
                business.openedDate = opened
            }
            if let type = scanner.value("type") { business.businessType = type }
            if let item = scanner.value("item") { business.businessItem = item }
            if let tax = scanner.value("tax") { business.taxationType = tax }
            if let address = scanner.value("address") { business.address = address }
            if let note = scanner.value("note") { business.note = note }
            try await store.save(business: business)
            emit(business, json: json, output: output)
        case "archive", "unarchive":
            var business = try await store.resolveBusiness(try ref(sub, action))
            business.archived = action == "archive"
            try await store.save(business: business)
            emit(business, json: json, output: output)
        case "remove":
            let business = try await store.resolveBusiness(try ref(sub, action))
            guard scanner.has("purge") else {
                throw UsageError("완전 삭제(첨부 포함)는 --purge 를 명시하세요 (보통은 archive)")
            }
            let removed = try await store.deleteBusiness(id: business.id)
            for record in removed { files.removeFile(for: record) }
            if json {
                output.okJSON(["removed": business.id, "attachmentsRemoved": removed.count])
            } else {
                output.out("삭제됨: \(business.name) (첨부 \(removed.count)건 포함)")
            }
        case "attach":
            guard sub.count >= 3 else { throw UsageError("biz attach <id|상호> <파일경로> [--name 표시명]") }
            let business = try await store.resolveBusiness(sub[1])
            let record = try files.importFile(
                ownerKind: .business,
                ownerID: business.id,
                sourceURL: URL(fileURLWithPath: (sub[2] as NSString).expandingTildeInPath),
                originalName: scanner.value("name")
            )
            try await store.insert(attachment: record)
            if json {
                output.okJSON(["attachment": attachmentObject(record, files: files)])
            } else {
                output.out("첨부됨: \(record.originalName) → \(files.fileURL(for: record).path)")
            }
        case "files":
            let business = try await store.resolveBusiness(try ref(sub, action))
            let attachments = try await store.attachments(ownerKind: .business, ownerID: business.id)
            if json {
                output.okJSON(["attachments": attachments.map { attachmentObject($0, files: files) }])
            } else if attachments.isEmpty {
                output.out("첨부 없음 — biz attach \(CLIFormat.shortID(business.id)) <파일>")
            } else {
                for attachment in attachments {
                    output.out(
                        "\(CLIFormat.shortID(attachment.id))  \(attachment.originalName)  "
                        + files.fileURL(for: attachment).path
                    )
                }
            }
        case "docs":
            // 서류 원본의 소유 앱은 business-documents(GitLab 저장소)다 — 여기서 중복 구현하지 않는다.
            let hint = """
                사업 서류(도장·사업자등록증·통신판매업 신고증)는 business-documents 앱이 소유합니다.
                  business-documents repo setup                       # 최초 1회
                  business-documents add <파일> --kind 사업자등록증
                  business-documents list | expiring | sync
                (금고 앱 Vaultwarden 은 카드·계좌번호 같은 '비밀값' 전용입니다 — biz vault 참고)
                """
            if json { output.okJSON(["movedTo": "business-documents", "hint": hint]) } else { output.out(hint) }
        case "detach":
            guard sub.count >= 2 else { throw UsageError("biz detach <첨부id>") }
            let record = try await store.attachment(idPrefix: sub[1])
            try await store.deleteAttachment(id: record.id)
            files.removeFile(for: record)
            if json {
                output.okJSON(["detached": record.id])
            } else {
                output.out("첨부 삭제됨: \(record.originalName)")
            }
        default:
            throw UsageError("unknown: biz \(action)")
        }
    }

    private static func validateRegistrationNumber(_ raw: String, force: Bool) throws {
        let digits = BusinessNumber.digits(raw)
        guard !digits.isEmpty else { return }  // 미입력 허용
        if !BusinessNumber.isValid(digits), !force {
            throw UsageError(
                "사업자등록번호 검증 실패: \(BusinessNumber.format(raw)) — 오타 확인, 맞는 번호면 --force"
            )
        }
    }

    private static func emit(_ business: BusinessProfile, json: Bool, output: CLIOutput) {
        if json {
            output.okJSON(["business": businessObject(business)])
        } else {
            output.out(render(business))
        }
    }

    private static func render(_ business: BusinessProfile) -> String {
        let regNo = business.registrationNumber.isEmpty
            ? "미입력" : BusinessNumber.format(business.registrationNumber)
        var line = "\(CLIFormat.shortID(business.id))  \(business.name) — \(regNo)"
        if let rep = business.representative { line += " · 대표 \(rep)" }
        if let type = business.businessType { line += " · \(type)" }
        if let item = business.businessItem { line += "/\(item)" }
        return line
    }

    private static func businessObject(_ business: BusinessProfile) -> [String: Any] {
        var object: [String: Any] = [
            "id": business.id,
            "name": business.name,
            "registrationNumber": business.registrationNumber,
            "registrationNumberFormatted": BusinessNumber.format(business.registrationNumber),
            "archived": business.archived,
        ]
        if let rep = business.representative { object["representative"] = rep }
        if let opened = business.openedDate { object["openedDate"] = opened }
        if let type = business.businessType { object["businessType"] = type }
        if let item = business.businessItem { object["businessItem"] = item }
        if let tax = business.taxationType { object["taxationType"] = tax }
        if let address = business.address { object["address"] = address }
        if let note = business.note { object["note"] = note }
        return object
    }

    private static func attachmentObject(_ record: AttachmentRecord, files: AttachmentStore) -> [String: Any] {
        [
            "id": record.id,
            "originalName": record.originalName,
            "path": files.fileURL(for: record).path,
            "addedAt": ISO8601DateFormatter().string(from: record.addedAt),
        ]
    }

    private static func ref(_ sub: [String], _ action: String) throws -> String {
        guard sub.count >= 2 else { throw UsageError("biz \(action) <id|상호>") }
        return sub[1]
    }
}
