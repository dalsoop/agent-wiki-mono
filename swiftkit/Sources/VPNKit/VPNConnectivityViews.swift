import SwiftUI

public struct VPNConnectionCard: View {
    private let diagnosis: VPNConnectivityDiagnosis
    private let presentation: VPNPresentation
    private let compact: Bool
    @State private var isExpanded = false

    public init(
        diagnosis: VPNConnectivityDiagnosis,
        language: VPNPresentationLanguage = .system,
        compact: Bool = false
    ) {
        self.diagnosis = diagnosis
        self.presentation = VPNPresentation(language: language)
        self.compact = compact
    }

    public var body: some View {
        if compact {
            Label {
                Text(
                    "\(presentation.title(for: diagnosis)) · "
                        + presentation.summary(for: diagnosis)
                )
                .lineLimit(1)
                .frame(minWidth: 20)
            } icon: {
                Image(systemName: pathSymbol)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text(presentation.localized("card.target"))
                            .foregroundStyle(.secondary)
                        Text(targetAddress)
                            .textSelection(.enabled)
                    }
                    GridRow {
                        Text(presentation.localized("card.last_checked"))
                            .foregroundStyle(.secondary)
                        Text(presentation.checkedAt(diagnosis.checkedAt))
                    }
                }
                .font(.caption)
                .padding(.top, 6)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: pathSymbol)
                        .foregroundStyle(diagnosis.reachable ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(presentation.title(for: diagnosis))
                            .font(.headline)
                        Text(presentation.summary(for: diagnosis))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(minWidth: 20)
                    }
                }
            }
            .accessibilityLabel(
                "\(presentation.title(for: diagnosis)), "
                    + presentation.summary(for: diagnosis)
            )
        }
    }

    private var targetAddress: String {
        guard diagnosis.target.port > 0 else {
            return diagnosis.target.host
        }
        return "\(diagnosis.target.host):\(diagnosis.target.port)"
    }

    private var pathSymbol: String {
        switch diagnosis.path {
        case .direct:
            return "network"
        case .vpn:
            return "checkmark.shield"
        case .unidentifiedTunnel:
            return "questionmark.shield"
        case .unavailable:
            return "network.slash"
        }
    }
}

public struct VPNRecoveryView: View {
    @Bindable private var model: VPNConnectivityModel
    private let presentation: VPNPresentation
    private let compact: Bool
    private let onRetry: () -> Void
    private let onConnected: () -> Void
    private let connectAction: ((String) async -> Void)?
    private let diagnoseAction: (() async -> Void)?
    @State private var selectedServiceID: String?
    @State private var actionState = VPNRecoveryActionState()

    public init(
        model: VPNConnectivityModel,
        language: VPNPresentationLanguage = .system,
        compact: Bool = false
    ) {
        self.init(
            model: model,
            language: language,
            compact: compact,
            onRetry: {},
            onConnected: {},
            connectAction: nil,
            diagnoseAction: nil
        )
    }

    public init(
        model: VPNConnectivityModel,
        language: VPNPresentationLanguage = .system,
        compact: Bool = false,
        onRetry: @escaping () -> Void,
        onConnected: @escaping () -> Void
    ) {
        self.init(
            model: model,
            language: language,
            compact: compact,
            onRetry: onRetry,
            onConnected: onConnected,
            connectAction: nil,
            diagnoseAction: nil
        )
    }

    init(
        model: VPNConnectivityModel,
        language: VPNPresentationLanguage,
        compact: Bool,
        onRetry: @escaping () -> Void,
        onConnected: @escaping () -> Void,
        connectAction: ((String) async -> Void)?,
        diagnoseAction: (() async -> Void)?
    ) {
        self.model = model
        self.presentation = VPNPresentation(language: language)
        self.compact = compact
        self.onRetry = onRetry
        self.onConnected = onConnected
        self.connectAction = connectAction
        self.diagnoseAction = diagnoseAction
        self._selectedServiceID = State(initialValue: nil)
    }

    public var body: some View {
        Group {
            switch model.phase {
            case .idle:
                initialView
            case .diagnosing:
                checkingView
            case .connected(let diagnosis):
                VPNConnectionCard(
                    diagnosis: diagnosis,
                    language: presentation.language,
                    compact: compact
                )
            case .recovery(let context):
                recoveryPanel(context: context)
            case .failed(let diagnosis):
                recoveryPanel(
                    context: VPNRecoveryContext(
                        diagnosis: diagnosis,
                        services: model.availableServices,
                        preferred: model.preferred,
                        selectedServiceID: nil,
                        message: nil
                    )
                )
            }
        }
        .controlSize(compact ? .small : .regular)
    }

    private var initialView: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            Label(
                presentation.localized("recovery.heading"),
                systemImage: "network.badge.shield.half.filled"
            )
            .font(compact ? .subheadline.bold() : .headline)
            Text(presentation.localized("recovery.initial"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(presentation.localized("recovery.check_connection")) {
                diagnose()
            }
            .disabled(actionState.isInProgress)
            actionProgress
        }
    }

    private var checkingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(
                    presentation.localized("recovery.checking")
                )
            Text(presentation.localized("recovery.checking"))
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    @ViewBuilder
    private func recoveryPanel(
        context: VPNRecoveryContext
    ) -> some View {
        let diagnosis = context.diagnosis
        let serverCheckOnly = shouldCheckServer(for: diagnosis.failure)
        let policy = VPNRecoverySelectionPolicy(context: context)

        VStack(alignment: .leading, spacing: compact ? 7 : 12) {
            Label {
                Text(presentation.title(for: diagnosis))
            } icon: {
                Image(systemName: serverCheckOnly ? "exclamationmark.triangle" : "lock.shield")
            }
            .font(compact ? .subheadline.bold() : .headline)
            .foregroundStyle(.orange)

            if let failure = diagnosis.failure {
                Text(presentation.recoveryMessage(for: failure))
                    .font(compact ? .caption : .body)
            }

            Text(presentation.summary(for: diagnosis))
                .font(.caption)
                .foregroundStyle(.secondary)

            if let controlMessage = context.message, !controlMessage.isEmpty {
                Text(controlMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if serverCheckOnly {
                Label(
                    presentation.localized("recovery.server_check"),
                    systemImage: "server.rack"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if policy.availability != .available {
                Text(emptyCandidateMessage(for: policy.availability))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker(
                    presentation.localized("recovery.choose_vpn"),
                    selection: $selectedServiceID
                ) {
                    ForEach(policy.candidates) { service in
                        Text(
                            "\(service.name) · "
                                + presentation.serviceStatus(service.status)
                        )
                        .tag(Optional(service.id))
                    }
                }
                .disabled(actionState.isInProgress)

                Button(presentation.localized("recovery.connect_and_check")) {
                    connectSelectedService()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    actionState.isInProgress
                        || !policy.permitsConnection(to: selectedServiceID)
                )
            }

            Button(presentation.localized("recovery.diagnose_again")) {
                diagnose()
            }
            .buttonStyle(.bordered)
            .disabled(actionState.isInProgress)
            actionProgress
        }
        .task(id: policy.snapshot) {
            selectedServiceID = policy.revalidatedSelection(
                selectedServiceID
            )
        }
    }

    @ViewBuilder
    private var actionProgress: some View {
        if actionState.isInProgress {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(
                    presentation.localized("recovery.checking")
                )
        }
    }

    private func connectSelectedService() {
        guard let selectedServiceID,
              let policy = currentRecoveryPolicy,
              policy.permitsConnection(to: selectedServiceID)
        else {
            return
        }
        Task {
            await actionState.perform {
                if let connectAction {
                    await connectAction(selectedServiceID)
                } else {
                    await model.connect(serviceID: selectedServiceID)
                    if case .connected = model.phase {
                        onConnected()
                    }
                }
            }
        }
    }

    private var currentRecoveryPolicy: VPNRecoverySelectionPolicy? {
        switch model.phase {
        case .recovery(let context):
            return VPNRecoverySelectionPolicy(context: context)
        case .failed(let diagnosis):
            return VPNRecoverySelectionPolicy(
                context: VPNRecoveryContext(
                    diagnosis: diagnosis,
                    services: model.availableServices,
                    preferred: model.preferred,
                    selectedServiceID: nil,
                    message: nil
                )
            )
        case .idle, .diagnosing, .connected:
            return nil
        }
    }

    private func diagnose() {
        Task {
            await actionState.perform {
                if let diagnoseAction {
                    await diagnoseAction()
                } else {
                    await model.diagnose()
                    if case .connected = model.phase {
                        onConnected()
                    } else {
                        onRetry()
                    }
                }
            }
        }
    }

    private func emptyCandidateMessage(
        for availability: VPNRecoveryCandidateAvailability
    ) -> String {
        switch availability {
        case .available:
            return ""
        case .noSystemVPN:
            return presentation.localized("recovery.no_vpn")
        case .noAlternativeVPN:
            return presentation.localized(
                "recovery.no_alternative_vpn"
            )
        }
    }

    private func shouldCheckServer(
        for failure: VPNConnectivityFailure?
    ) -> Bool {
        guard case .targetDidNotRespond(let path) = failure else {
            return false
        }
        switch path {
        case .vpn, .unidentifiedTunnel:
            return true
        case .direct, .unavailable:
            return false
        }
    }
}

public struct VPNRecoverySettingsSection: View {
    @Bindable private var model: VPNConnectivityModel
    @Binding private var preferred: VPNServiceReference?
    private let presentation: VPNPresentation
    private let autoDisconnectWhenIdle: Binding<Bool>?

    public init(
        model: VPNConnectivityModel,
        preferred: Binding<VPNServiceReference?>,
        language: VPNPresentationLanguage = .system
    ) {
        self.model = model
        self._preferred = preferred
        self.presentation = VPNPresentation(language: language)
        self.autoDisconnectWhenIdle = nil
    }

    public init(
        model: VPNConnectivityModel,
        preferred: Binding<VPNServiceReference?>,
        autoDisconnectWhenIdle: Binding<Bool>,
        language: VPNPresentationLanguage = .system
    ) {
        self.model = model
        self._preferred = preferred
        self.presentation = VPNPresentation(language: language)
        self.autoDisconnectWhenIdle = autoDisconnectWhenIdle
    }

    public var body: some View {
        Section(presentation.localized("settings.heading")) {
            Picker(
                presentation.localized("settings.preferred"),
                selection: preferredSelection
            ) {
                Text(presentation.localized("settings.none"))
                    .tag("")
                if let unavailablePreference {
                    Text(unavailablePreference.displayName)
                        .foregroundStyle(.secondary)
                        .tag(selectionKey(for: unavailablePreference))
                }
                ForEach(model.availableServices) { service in
                    Text(
                        "\(service.name) · "
                            + presentation.serviceStatus(service.status)
                    )
                    .tag(service.id)
                }
            }

            Button(presentation.localized("settings.connection_test")) {
                Task {
                    await model.diagnose()
                }
            }

            if let autoDisconnectWhenIdle {
                Toggle(
                    presentation.localized("settings.disconnect_when_idle"),
                    isOn: autoDisconnectWhenIdle
                )
            }

            LabeledContent(presentation.localized("settings.last_diagnosis")) {
                if case .diagnosing = model.phase {
                    ProgressView()
                        .controlSize(.small)
                } else if let diagnosis = latestDiagnosis {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(presentation.summary(for: diagnosis))
                        Text(presentation.checkedAt(diagnosis.checkedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(presentation.localized("settings.not_checked"))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            if case .idle = model.phase {
                await model.diagnose()
            }
        }
    }

    private var preferredSelection: Binding<String> {
        Binding(
            get: {
                preferred.map(selectionKey(for:)) ?? ""
            },
            set: { key in
                guard !key.isEmpty else {
                    preferred = nil
                    model.preferred = nil
                    return
                }
                guard let service = model.availableServices.first(
                    where: { $0.id == key }
                ) else {
                    return
                }
                let reference = VPNServiceReference(
                    serviceID: service.id,
                    displayName: service.name
                )
                preferred = reference
                model.preferred = reference
            }
        )
    }

    private var unavailablePreference: VPNServiceReference? {
        guard let preferred else {
            return nil
        }
        let key = selectionKey(for: preferred)
        guard !model.availableServices.contains(where: { $0.id == key }) else {
            return nil
        }
        return preferred
    }

    private func selectionKey(for reference: VPNServiceReference) -> String {
        if let serviceID = reference.serviceID {
            return serviceID
        }
        return "legacy:\(reference.legacyIdentifier ?? reference.displayName)"
    }

    private var latestDiagnosis: VPNConnectivityDiagnosis? {
        switch model.phase {
        case .connected(let diagnosis), .failed(let diagnosis):
            return diagnosis
        case .recovery(let context):
            return context.diagnosis
        case .idle, .diagnosing:
            return nil
        }
    }
}
