import SwiftUI

/// 첫 실행 온보딩 — **앱이 선언한 권한을 그대로** 순회하며 요청한다.
///
/// 앱마다 온보딩 화면을 새로 만들면서 요청 목록을 코드에 다시 적었고, 그래서 선언과
/// 실제 요청이 어긋났다(실측 2026-08-07~08). 이 화면은 목록을 받지 않고
/// `PermissionRequirements.declared()` 를 읽는다 — 선언을 고치면 온보딩이 따라온다.
///
/// 상태는 매번 preflight 로 다시 읽는다. 사용자가 설정 창에서 토글하고 돌아왔을 때
/// 화면이 낡아 있으면 "허용했는데 계속 요구한다" 가 된다.
public struct PermissionOnboardingView: View {
    private let appName: String
    private let declaration: PermissionRequirements.Declaration
    private let onFinish: (() -> Void)?

    @State private var granted: Set<Permission> = []
    @State private var busy: Permission?

    public init(
        appName: String,
        declaration: PermissionRequirements.Declaration = PermissionRequirements.declared(),
        onFinish: (() -> Void)? = nil
    ) {
        self.appName = appName
        self.declaration = declaration
        self.onFinish = onFinish
    }

    private var korean: Bool {
        Locale.current.language.languageCode?.identifier == "ko"
    }

    /// 필수가 다 허용됐는가 — 선택 권한은 진행을 막지 않는다.
    private var requiredSatisfied: Bool {
        declaration.required.allSatisfy { granted.contains($0) }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(korean ? "\(appName) 권한 설정" : "\(appName) permissions")
                .font(.title2.bold())
            Text(korean
                 ? "이 앱이 동작하려면 아래 권한이 필요합니다. 각 항목의 버튼을 누르면 시스템 프롬프트가 뜹니다."
                 : "The app needs these permissions. Each button triggers the system prompt.")
                .font(.callout).foregroundStyle(.secondary)

            if declaration.isEmpty {
                // 선언이 비었는데 온보딩을 띄운 것 자체가 배선 실수다 — 조용히 빈 화면을 보이지 않는다.
                Label(korean
                      ? "선언된 권한이 없습니다 — Info.plist 의 \(PermissionRequirements.requiredKey) 를 확인하세요."
                      : "No declared permissions — check \(PermissionRequirements.requiredKey) in Info.plist.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            ForEach(declaration.all, id: \.self) { permission in
                row(permission, isOptional: declaration.optional.contains(permission))
            }

            if !declaration.unknown.isEmpty {
                // 오타는 곧 미요청이다 — 조용히 버리면 아무도 못 찾는다.
                Label(korean
                      ? "알 수 없는 권한 이름: \(declaration.unknown.joined(separator: ", "))"
                      : "Unknown permission names: \(declaration.unknown.joined(separator: ", "))",
                      systemImage: "questionmark.circle")
                    .font(.caption).foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button(requiredSatisfied
                       ? (korean ? "시작하기" : "Continue")
                       : (korean ? "나중에" : "Later")) { onFinish?() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
        .onAppear { refresh() }
        // 설정 창을 다녀오면 앱이 다시 활성화된다 — 그때 상태를 새로 읽는다.
        .onReceive(NSApplication.didBecomeActiveNotification) { refresh() }
    }

    @ViewBuilder
    private func row(_ permission: Permission, isOptional: Bool) -> some View {
        let isGranted = granted.contains(permission)
        HStack(spacing: 10) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(isGranted ? .green : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(korean ? permission.tccService.labelKorean : permission.tccService.labelEnglish)
                    .font(.callout)
                if isOptional {
                    Text(korean ? "선택 — 없어도 앱은 동작합니다" : "Optional — the app works without it")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if isGranted {
                Text(korean ? "허용됨" : "Granted").font(.caption).foregroundStyle(.green)
            } else {
                Button(korean ? "허용 요청" : "Request") {
                    Task { await request(permission) }
                }
                .disabled(busy != nil)
            }
        }
    }

    private func request(_ permission: Permission) async {
        busy = permission
        defer { busy = nil }
        // 정본 게이트를 쓴다 — 여기서 원시 API 를 부르면 앱마다 판정이 갈린다.
        _ = await permission.ensureGranted(appName: appName)
        refresh(includingFDA: permission == .fullDiskAccess)
    }

    private func refresh(includingFDA: Bool = false) {
        var next = Set<Permission>()
        for permission in declaration.all {
            if permission == .fullDiskAccess {
                if includingFDA {
                    if permission.isGranted { next.insert(permission) }
                } else if granted.contains(.fullDiskAccess) {
                    next.insert(.fullDiskAccess)
                }
                continue
            }
            if permission.isGranted { next.insert(permission) }
        }
        granted = next
    }
}

private extension View {
    /// `onReceive(Notification.Name)` 한 줄 — NotificationCenter publisher 를 매번 조립하지 않게.
    func onReceive(_ name: Notification.Name, perform action: @escaping () -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: name)) { _ in action() }
    }
}
