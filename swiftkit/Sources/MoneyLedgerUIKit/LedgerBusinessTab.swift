import AppKit
import Foundation
import MoneyLedgerKit
import SwiftUI
import UniformTypeIdentifiers

// 사업자 탭 — 사업자등록 정보 + 첨부(사업자등록증 이미지·PDF).
// business scope 앱에만 노출된다(개인 앱은 탭 자체가 없다). CLI `biz` 와 같은 경로.

extension LedgerModel {
    public func saveBusiness(_ business: BusinessProfile) async -> String? {
        do {
            let store = try LedgerStore(context: context)
            try await store.save(business: business)
            await refresh()
            return nil
        } catch {
            return String(describing: error)
        }
    }

    public func setBusinessArchived(_ business: BusinessProfile, _ archived: Bool) async {
        var updated = business
        updated.archived = archived
        _ = await saveBusiness(updated)
    }

    public func attachmentList(for business: BusinessProfile) async -> [(record: AttachmentRecord, url: URL)] {
        guard let store = try? LedgerStore(context: context) else { return [] }
        let files = AttachmentStore(context: context)
        let records = (try? await store.attachments(ownerKind: .business, ownerID: business.id)) ?? []
        return records.map { ($0, files.fileURL(for: $0)) }
    }

    public func addAttachment(to business: BusinessProfile, from sourceURL: URL) async -> String? {
        do {
            let store = try LedgerStore(context: context)
            let files = AttachmentStore(context: context)
            let record = try files.importFile(
                ownerKind: .business, ownerID: business.id, sourceURL: sourceURL
            )
            try await store.insert(attachment: record)
            await refresh()
            return nil
        } catch {
            return String(describing: error)
        }
    }

    /// 서류 금고 — CLI `biz docs` 와 같은 경로(우리 Vaultwarden Client 앱 창구).
    public func vaultDocsBox(for business: BusinessProfile) -> String {
        "서류: \(business.name) [business-ledger]"
    }

    public func vaultDocs(for business: BusinessProfile) async -> (
        status: VaultDocsGateway.Status, files: [VaultDocsGateway.DocumentFile]
    ) {
        let vault = VaultDocsGateway()
        let status = await vault.status()
        guard status == .ready else { return (status, []) }
        let files = (try? await vault.list(box: vaultDocsBox(for: business))) ?? []
        return (status, files)
    }

    public func uploadVaultDoc(box: String, from url: URL) async -> String? {
        do {
            try await VaultDocsGateway().upload(fileURL: url, box: box)
            return nil
        } catch { return String(describing: error) }
    }

    public func downloadVaultDoc(box: String, file: VaultDocsGateway.DocumentFile) async -> URL? {
        let out = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/\(file.fileName)")
        do {
            try await VaultDocsGateway().download(file: file, box: box, to: out)
            return out
        } catch { return nil }
    }

    public func deleteVaultDoc(box: String, file: VaultDocsGateway.DocumentFile) async {
        try? await VaultDocsGateway().delete(file: file, box: box)
    }

    public func removeAttachment(_ record: AttachmentRecord) async {
        guard let store = try? LedgerStore(context: context) else { return }
        try? await store.deleteAttachment(id: record.id)
        AttachmentStore(context: context).removeFile(for: record)
        await refresh()
    }
}

struct BusinessTab: View {
    let model: LedgerModel
    @State private var editing: BusinessProfile?
    @State private var showingAdd = false
    @State private var managingFiles: BusinessProfile?
    @State private var managingVaultDocs: BusinessProfile?

    var body: some View {
        VStack(spacing: 0) {
            EntryHeader(addLabel: model.korean ? "사업자 추가" : "Add business") { showingAdd = true }
            Table(model.snapshot.businesses) {
                TableColumn(model.korean ? "상호" : "Name", value: \.name)
                TableColumn(model.korean ? "등록번호" : "Reg. no") { business in
                    Text(
                        business.registrationNumber.isEmpty
                            ? "—" : BusinessNumber.format(business.registrationNumber)
                    )
                }
                TableColumn(model.korean ? "대표자" : "Representative") { business in
                    Text(business.representative ?? "")
                }
                TableColumn(model.korean ? "업태/종목" : "Type/Item") { business in
                    Text([business.businessType, business.businessItem].compactMap(\.self).joined(separator: "/"))
                }
                TableColumn(model.korean ? "첨부" : "Files") { business in
                    let count = model.snapshot.businessAttachmentCounts[business.id] ?? 0
                    Label("\(count)", systemImage: count > 0 ? "paperclip" : "paperclip")
                        .foregroundStyle(count > 0 ? .primary : .secondary)
                }
                .width(60)
                TableColumn("") { business in
                    Menu {
                        Button(model.korean ? "정보 수정" : "Edit") { editing = business }
                        Button(model.korean ? "이미지·파일 관리 (로컬)" : "Manage local files") { managingFiles = business }
                        Button(model.korean ? "서류 금고 (Vaultwarden)" : "Document vault") {
                            managingVaultDocs = business
                        }
                        Button(model.korean ? "보관 (목록에서 숨김)" : "Archive") {
                            Task { await model.setBusinessArchived(business, true) }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .width(40)
            }
        }
        .sheet(isPresented: $showingAdd) { BusinessEditorSheet(model: model, editing: nil) }
        .sheet(item: $editing) { business in BusinessEditorSheet(model: model, editing: business) }
        .sheet(item: $managingFiles) { business in BusinessFilesSheet(model: model, business: business) }
        .sheet(item: $managingVaultDocs) { business in
            BusinessVaultDocsSheet(model: model, business: business)
        }
        .overlay {
            if model.snapshot.businesses.isEmpty {
                ContentUnavailableView(
                    model.korean ? "사업자 없음" : "No business",
                    systemImage: "building.2",
                    description: Text(
                        model.korean
                        ? "위 '사업자 추가' 버튼 또는 CLI: \(model.context.scope.slug) biz add"
                        : "Use 'Add business' above or CLI: \(model.context.scope.slug) biz add"
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))   // 표 헤더·줄무늬까지 가린다
            }
        }
    }
}

struct BusinessEditorSheet: View {
    let model: LedgerModel
    let editing: BusinessProfile?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var regNo = ""
    @State private var representative = ""
    @State private var opened = ""
    @State private var businessType = ""
    @State private var businessItem = ""
    @State private var taxationType = ""
    @State private var address = ""
    @State private var note = ""
    @State private var forceInvalidRegNo = false
    @State private var errorMessage: String?

    var body: some View {
        EditorSheet(
            title: editing == nil
                ? (model.korean ? "사업자 추가" : "Add business")
                : (model.korean ? "사업자 수정" : "Edit business"),
            korean: model.korean,
            errorMessage: errorMessage,
            onSave: save,
            onCancel: { dismiss() }
        ) {
            TextField(model.korean ? "상호 (필수)" : "Name (required)", text: $name)
            TextField(model.korean ? "사업자등록번호 (123-45-67890)" : "Registration number", text: $regNo)
            if !regNo.isEmpty, !BusinessNumber.isValid(regNo) {
                Toggle(
                    model.korean ? "검증 실패지만 이 번호가 맞음" : "Checksum fails but number is correct",
                    isOn: $forceInvalidRegNo
                )
                .tint(.orange)
            }
            TextField(model.korean ? "대표자" : "Representative", text: $representative)
            TextField(model.korean ? "개업일 (yyyy-MM-dd)" : "Opened date", text: $opened)
            TextField(model.korean ? "업태" : "Business type", text: $businessType)
            TextField(model.korean ? "종목" : "Business item", text: $businessItem)
            TextField(model.korean ? "과세 유형 (일반과세/간이과세 등)" : "Taxation type", text: $taxationType)
            TextField(model.korean ? "사업장 주소" : "Address", text: $address)
            TextField(model.korean ? "메모" : "Note", text: $note)
        }
        .onAppear {
            guard let editing else { return }
            name = editing.name
            regNo = BusinessNumber.format(editing.registrationNumber)
            representative = editing.representative ?? ""
            opened = editing.openedDate ?? ""
            businessType = editing.businessType ?? ""
            businessItem = editing.businessItem ?? ""
            taxationType = editing.taxationType ?? ""
            address = editing.address ?? ""
            note = editing.note ?? ""
        }
    }

    private func save() {
        guard !name.isEmpty else {
            errorMessage = model.korean ? "상호는 필수입니다" : "Name is required"
            return
        }
        if !regNo.isEmpty, !BusinessNumber.isValid(regNo), !forceInvalidRegNo {
            errorMessage = model.korean
                ? "사업자등록번호 검증 실패 — 오타를 확인하세요. 맞는 번호면 위 토글을 켜세요."
                : "Registration number checksum failed — check for typos or enable the toggle."
            return
        }
        if !opened.isEmpty, !LedgerDate.isValid(opened) {
            errorMessage = model.korean ? "개업일은 yyyy-MM-dd 형식입니다" : "Opened date must be yyyy-MM-dd"
            return
        }
        var business = editing ?? BusinessProfile(name: name)
        business.name = name
        business.registrationNumber = BusinessNumber.digits(regNo)
        business.representative = representative.isEmpty ? nil : representative
        business.openedDate = opened.isEmpty ? nil : opened
        business.businessType = businessType.isEmpty ? nil : businessType
        business.businessItem = businessItem.isEmpty ? nil : businessItem
        business.taxationType = taxationType.isEmpty ? nil : taxationType
        business.address = address.isEmpty ? nil : address
        business.note = note.isEmpty ? nil : note
        let toSave = business
        Task {
            if let error = await model.saveBusiness(toSave) {
                errorMessage = error
            } else {
                dismiss()
            }
        }
    }
}

/// 첨부 관리 — 사업자등록증 등 이미지·PDF 업로드/열람/삭제.
struct BusinessFilesSheet: View {
    let model: LedgerModel
    let business: BusinessProfile
    @Environment(\.dismiss) private var dismiss
    @State private var attachments: [(record: AttachmentRecord, url: URL)] = []
    @State private var showingImporter = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(business.name) — " + (model.korean ? "첨부" : "Files"))
                    .font(.headline)
                Spacer()
                Button {
                    showingImporter = true
                } label: {
                    Label(model.korean ? "이미지·파일 추가" : "Add file", systemImage: "plus")
                }
            }
            if attachments.isEmpty {
                ContentUnavailableView(
                    model.korean ? "첨부 없음" : "No files",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text(
                        model.korean
                        ? "사업자등록증 사진·스캔본을 올려두세요 (이미지/PDF)"
                        : "Upload registration certificate images or PDFs"
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))   // 표 헤더·줄무늬까지 가린다
                .frame(maxHeight: 220)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                        ForEach(attachments, id: \.record.id) { item in
                            VStack(spacing: 4) {
                                thumbnail(for: item.url)
                                    .frame(width: 140, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .onTapGesture { NSWorkspace.shared.open(item.url) }
                                Text(item.record.originalName)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .contextMenu {
                                Button(model.korean ? "열기" : "Open") { NSWorkspace.shared.open(item.url) }
                                Button(model.korean ? "Finder 에서 보기" : "Show in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                                }
                                Button(model.korean ? "삭제" : "Delete", role: .destructive) {
                                    Task {
                                        await model.removeAttachment(item.record)
                                        await reload()
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(minHeight: 220)
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Text(model.korean ? "썸네일 클릭 = 열기 · 우클릭 = 삭제" : "Click to open · right-click to delete")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(model.korean ? "닫기" : "Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(width: 520, height: 380)
        .task { await reload() }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.image, .pdf],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                Task {
                    for url in urls {
                        let accessing = url.startAccessingSecurityScopedResource()
                        if let error = await model.addAttachment(to: business, from: url) {
                            errorMessage = error
                        }
                        if accessing { url.stopAccessingSecurityScopedResource() }
                    }
                    await reload()
                }
            case let .failure(error):
                errorMessage = String(describing: error)
            }
        }
    }

    private func reload() async {
        attachments = await model.attachmentList(for: business)
    }

    @ViewBuilder
    private func thumbnail(for url: URL) -> some View {
        if let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                Image(systemName: "doc.richtext")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
    }
}


/// 서류 금고 — 사업자등록증·통신판매업 신고증 등 정본 파일을 Vaultwarden 첨부로 보관.
struct BusinessVaultDocsSheet: View {
    let model: LedgerModel
    let business: BusinessProfile
    @Environment(\.dismiss) private var dismiss
    @State private var status = VaultDocsGateway.Status.unavailable
    @State private var files: [VaultDocsGateway.DocumentFile] = []
    @State private var showingImporter = false
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(business.name) — " + (model.korean ? "서류 금고" : "Document vault"))
                    .font(.headline)
                Spacer()
                Button {
                    showingImporter = true
                } label: {
                    Label(model.korean ? "서류 업로드" : "Upload", systemImage: "arrow.up.doc")
                }
                .disabled(status != .ready || busy)
            }
            Text(
                model.korean
                ? "사업자등록증·통신판매업 신고증 등 정본은 Vaultwarden(암호화)에 보관됩니다"
                : "Documents are stored encrypted in Vaultwarden"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if status != .ready {
                ContentUnavailableView(
                    model.korean ? "금고 연결 안 됨" : "Vault not connected",
                    systemImage: "lock.trianglebadge.exclamationmark",
                    description: Text(status.korean)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))   // 표 헤더·줄무늬까지 가린다
                .frame(maxHeight: 200)
            } else if files.isEmpty {
                ContentUnavailableView(
                    model.korean ? "보관된 서류 없음" : "No documents",
                    systemImage: "doc.badge.plus",
                    description: Text(
                        model.korean
                        ? "위 '서류 업로드' 또는 CLI: \(model.context.scope.slug) biz docs upload"
                        : "Use 'Upload' above or CLI: biz docs upload"
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))   // 표 헤더·줄무늬까지 가린다
                .frame(maxHeight: 200)
            } else {
                List(files, id: \.id) { file in
                    HStack {
                        Image(systemName: "doc.fill").foregroundStyle(.secondary)
                        Text(file.fileName)
                        Text(file.sizeName).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(model.korean ? "내려받기" : "Download") {
                            Task {
                                busy = true
                                if let url = await model.downloadVaultDoc(
                                    box: model.vaultDocsBox(for: business), file: file
                                ) {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                    message = model.korean ? "다운로드 폴더에 저장됨" : "Saved to Downloads"
                                } else {
                                    message = model.korean ? "내려받기 실패" : "Download failed"
                                }
                                busy = false
                            }
                        }
                        Button(model.korean ? "삭제" : "Delete", role: .destructive) {
                            Task {
                                busy = true
                                await model.deleteVaultDoc(box: model.vaultDocsBox(for: business), file: file)
                                await reload()
                                busy = false
                            }
                        }
                    }
                }
                .frame(minHeight: 200)
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button(model.korean ? "닫기" : "Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(width: 520, height: 400)
        .task { await reload() }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.image, .pdf, .data],
            allowsMultipleSelection: true
        ) { result in
            guard case let .success(urls) = result else { return }
            Task {
                busy = true
                let box = model.vaultDocsBox(for: business)
                for url in urls {
                    let accessing = url.startAccessingSecurityScopedResource()
                    if let error = await model.uploadVaultDoc(box: box, from: url) {
                        message = error
                    }
                    if accessing { url.stopAccessingSecurityScopedResource() }
                }
                await reload()
                busy = false
            }
        }
    }

    private func reload() async {
        let result = await model.vaultDocs(for: business)
        status = result.status
        files = result.files
    }
}
