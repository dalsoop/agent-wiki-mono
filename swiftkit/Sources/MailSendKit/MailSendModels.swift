import Foundation

public struct MailSendRequest: Sendable, Equatable {
    public var to: String
    public var fromEmail: String
    public var fromName: String
    public var replyTo: String?
    public var subject: String
    public var html: String
    public var text: String
    public var templateId: String
    public var data: [String: String]
    public var messageId: String
    public var headers: [String: String]
    public var campaignId: String
    public var variantId: String?

    public struct Tracking: Sendable, Equatable {
        public var templateId: String
        public var data: [String: String]
        public var messageId: String
        public var headers: [String: String]
        public var campaignId: String
        public var variantId: String?

        public init(
            templateId: String,
            data: [String: String] = [:],
            messageId: String,
            headers: [String: String] = [:],
            campaignId: String = "",
            variantId: String? = nil
        ) {
            self.templateId = templateId
            self.data = data
            self.messageId = messageId
            self.headers = headers
            self.campaignId = campaignId
            self.variantId = variantId
        }
    }

    public init(
        to: String,
        fromEmail: String,
        fromName: String,
        replyTo: String? = nil,
        subject: String,
        html: String,
        text: String,
        tracking: Tracking
    ) {
        self.to = to
        self.fromEmail = fromEmail
        self.fromName = fromName
        self.replyTo = replyTo
        self.subject = subject
        self.html = html
        self.text = text
        self.templateId = tracking.templateId
        self.data = tracking.data
        self.messageId = tracking.messageId
        self.headers = tracking.headers
        self.campaignId = tracking.campaignId
        self.variantId = tracking.variantId
    }

    /// `templateId`·`data`·`messageId` 를 최상위로 넘기던 호출부용. 값은 `tracking` 으로만 저장한다.
    @_disfavoredOverload
    public init(
        to: String,
        fromEmail: String,
        fromName: String,
        replyTo: String? = nil,
        subject: String,
        html: String,
        text: String,
        templateId: String,
        data: [String: String] = [:],
        messageId: String,
        headers: [String: String] = [:],
        campaignId: String = "",
        variantId: String? = nil
    ) {
        self.init(
            to: to,
            fromEmail: fromEmail,
            fromName: fromName,
            replyTo: replyTo,
            subject: subject,
            html: html,
            text: text,
            tracking: Tracking(
                templateId: templateId,
                data: data,
                messageId: messageId,
                headers: headers,
                campaignId: campaignId,
                variantId: variantId
            )
        )
    }
}

public struct MailSendReceipt: Sendable, Equatable {
    public var providerMessageId: String
    public var provider: String

    public init(providerMessageId: String, provider: String) {
        self.providerMessageId = providerMessageId
        self.provider = provider
    }
}

public struct RenderedMail: Sendable, Equatable {
    public var subject: String
    public var html: String
    public var text: String

    public init(subject: String, html: String, text: String) {
        self.subject = subject
        self.html = html
        self.text = text
    }
}

public struct RetryPolicy: Sendable, Equatable {
    public var maxAttempts: Int
    public var baseDelay: TimeInterval

    public static let standard = RetryPolicy(maxAttempts: 3, baseDelay: 1)

    public init(maxAttempts: Int = 3, baseDelay: TimeInterval = 1) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
    }

    public func delayAfter(attempt: Int) -> TimeInterval? {
        guard attempt < maxAttempts else { return nil }
        return baseDelay * pow(2, Double(attempt - 1))
    }
}
