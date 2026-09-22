import Foundation
import LocalizationKit

// MARK: - URLError Classifier

enum UniversalURLErrorClassifier: Sendable {
    static func classify(_ urlError: URLError, taskCancelled: Bool) -> AnyAppError {
        var context: [String: String] = [
            "ns_domain": NSURLErrorDomain,
            "ns_code": String(urlError.errorCode),
            "url_error_code": String(urlError.errorCode)
        ]

        if let failingURL = urlError.failureURLString {
            context["url"] = failingURL
        }
        if taskCancelled {
            context["task_cancelled"] = "true"
        }

        let isCancelled = urlError.code == .cancelled
        let category: ErrorCategory = isCancelled ? .cancelled : .network
        let severity: ErrorSeverity = isCancelled ? .info : determineSeverity(urlError.code)
        let errorCode = codeName(urlError.code)

        return AnyAppError(
            errorCode: errorCode,
            category: category,
            severity: severity,
            isSilent: isCancelled,
            context: context,
            underlyingErrorDescription: urlError.localizedDescription,
            rawL10nKey: nil
        )
    }

    private static func determineSeverity(_ code: URLError.Code) -> ErrorSeverity {
        switch code {
        case .timedOut:
            return .warning
        default:
            return .error
        }
    }

    private static func codeName(_ code: URLError.Code) -> String {
        switch code {
        case .cancelled:
            return "NETWORK.CANCELLED"
        case .timedOut:
            return "NETWORK.TIMEOUT"
        case .notConnectedToInternet, .networkConnectionLost:
            return "NETWORK.NO_CONNECTION"
        case .cannotFindHost, .dnsLookupFailed:
            return "NETWORK.DNS_FAILURE"
        case .cannotConnectToHost:
            return "NETWORK.CONNECTION_REFUSED"
        case .secureConnectionFailed, .serverCertificateUntrusted,
             .serverCertificateHasBadDate, .serverCertificateNotYetValid,
             .serverCertificateHasUnknownRoot:
            return "NETWORK.SSL_FAILURE"
        case .badURL, .unsupportedURL:
            return "NETWORK.BAD_URL"
        case .resourceUnavailable, .zeroByteResource:
            return "NETWORK.RESOURCE_UNAVAILABLE"
        default:
            return "NETWORK.URL_ERROR_\(abs(code.rawValue))"
        }
    }
}

// MARK: - POSIXError Classifier

enum UniversalPOSIXErrorClassifier: Sendable {
    private static let permissionCodes: Set<POSIXError.Code> = [
        .EACCES, .EPERM, .EROFS
    ]

    private static let fileSystemCodes: Set<POSIXError.Code> = [
        .ENOENT, .EEXIST, .ENOSPC, .EISDIR, .ENOTDIR, .EMFILE,
        .ENFILE, .EIO, .EBADF, .ENOTEMPTY, .ELOOP, .EFBIG, .ENAMETOOLONG
    ]

    private static let networkCodes: Set<POSIXError.Code> = [
        .ECONNREFUSED, .ETIMEDOUT, .ENETUNREACH, .EHOSTUNREACH,
        .ECONNRESET, .ENOTCONN, .EADDRINUSE
    ]

    static func classify(_ posixError: POSIXError, taskCancelled: Bool) -> AnyAppError {
        var context: [String: String] = [
            "ns_domain": NSPOSIXErrorDomain,
            "ns_code": String(posixError.errorCode),
            "posix_code": String(posixError.code.rawValue)
        ]

        if taskCancelled {
            context["task_cancelled"] = "true"
        }

        let isCancelled = posixError.code == .ECANCELED
        let category = determineCategory(code: posixError.code, isCancelled: isCancelled)
        let severity: ErrorSeverity = isCancelled ? .info : .error
        let codeLabel = posixCodeName(posixError.code)

        return AnyAppError(
            errorCode: "POSIX.\(codeLabel)",
            category: category,
            severity: severity,
            isSilent: isCancelled,
            context: context,
            underlyingErrorDescription: posixError.localizedDescription,
            rawL10nKey: nil
        )
    }

    private static func determineCategory(code: POSIXError.Code, isCancelled: Bool) -> ErrorCategory {
        guard !isCancelled else {
            return .cancelled
        }
        switch code {
        case _ where permissionCodes.contains(code):
            return .permission
        case _ where fileSystemCodes.contains(code):
            return .fileSystem
        case _ where networkCodes.contains(code):
            return .network
        default:
            return .system
        }
    }

    private static let knownPOSIXNames: [POSIXError.Code: String] = [
        .EPERM: "EPERM",
        .ENOENT: "ENOENT",
        .ESRCH: "ESRCH",
        .EINTR: "EINTR",
        .EIO: "EIO",
        .ENXIO: "ENXIO",
        .E2BIG: "E2BIG",
        .ENOEXEC: "ENOEXEC",
        .EBADF: "EBADF",
        .ECHILD: "ECHILD",
        .EDEADLK: "EDEADLK",
        .ENOMEM: "ENOMEM",
        .EACCES: "EACCES",
        .EFAULT: "EFAULT",
        .EBUSY: "EBUSY",
        .EEXIST: "EEXIST",
        .EXDEV: "EXDEV",
        .ENODEV: "ENODEV",
        .ENOTDIR: "ENOTDIR",
        .EISDIR: "EISDIR",
        .EINVAL: "EINVAL",
        .ENFILE: "ENFILE",
        .EMFILE: "EMFILE",
        .ENOTTY: "ENOTTY",
        .EFBIG: "EFBIG",
        .ENOSPC: "ENOSPC",
        .ESPIPE: "ESPIPE",
        .EROFS: "EROFS",
        .EMLINK: "EMLINK",
        .EPIPE: "EPIPE",
        .EDOM: "EDOM",
        .ERANGE: "ERANGE",
        .EAGAIN: "EAGAIN",
        .EINPROGRESS: "EINPROGRESS",
        .EALREADY: "EALREADY",
        .ENOTSOCK: "ENOTSOCK",
        .EDESTADDRREQ: "EDESTADDRREQ",
        .EMSGSIZE: "EMSGSIZE",
        .EPROTOTYPE: "EPROTOTYPE",
        .ENOPROTOOPT: "ENOPROTOOPT",
        .EPROTONOSUPPORT: "EPROTONOSUPPORT",
        .ENOTSUP: "ENOTSUP",
        .EAFNOSUPPORT: "EAFNOSUPPORT",
        .EADDRINUSE: "EADDRINUSE",
        .EADDRNOTAVAIL: "EADDRNOTAVAIL",
        .ENETDOWN: "ENETDOWN",
        .ENETUNREACH: "ENETUNREACH",
        .ENETRESET: "ENETRESET",
        .ECONNABORTED: "ECONNABORTED",
        .ECONNRESET: "ECONNRESET",
        .ENOBUFS: "ENOBUFS",
        .EISCONN: "EISCONN",
        .ENOTCONN: "ENOTCONN",
        .ETIMEDOUT: "ETIMEDOUT",
        .ECONNREFUSED: "ECONNREFUSED",
        .ELOOP: "ELOOP",
        .ENAMETOOLONG: "ENAMETOOLONG",
        .EHOSTUNREACH: "EHOSTUNREACH",
        .ENOTEMPTY: "ENOTEMPTY",
        .ECANCELED: "ECANCELED"
    ]

    private static func posixCodeName(_ code: POSIXError.Code) -> String {
        guard let name = knownPOSIXNames[code] else {
            return "ERRNO_\(code.rawValue)"
        }
        return name
    }
}

// MARK: - CocoaError Classifier

enum UniversalCocoaErrorClassifier: Sendable {
    static func classify(_ cocoaError: CocoaError, taskCancelled: Bool) -> AnyAppError {
        var context: [String: String] = [
            "ns_domain": NSCocoaErrorDomain,
            "ns_code": String(cocoaError.errorCode)
        ]

        if let path = cocoaError.userInfo[NSFilePathErrorKey] as? String {
            context["file_path"] = path
        }
        if taskCancelled {
            context["task_cancelled"] = "true"
        }

        let isCancelled = cocoaError.code == .userCancelled
        let meta = resolveMeta(cocoaError: cocoaError, isCancelled: isCancelled)

        return AnyAppError(
            errorCode: meta.errorCode,
            category: meta.category,
            severity: meta.severity,
            isSilent: isCancelled,
            context: context,
            underlyingErrorDescription: cocoaError.localizedDescription,
            rawL10nKey: nil
        )
    }

    private struct CocoaErrorMeta {
        let errorCode: String
        let category: ErrorCategory
        let severity: ErrorSeverity
    }

    private static func resolveMeta(cocoaError: CocoaError, isCancelled: Bool) -> CocoaErrorMeta {
        guard !isCancelled else {
            return CocoaErrorMeta(errorCode: "COCOA.USER_CANCELLED", category: .cancelled, severity: .info)
        }
        guard !isPermission(cocoaError.code) else {
            return CocoaErrorMeta(errorCode: "COCOA.PERMISSION_DENIED", category: .permission, severity: .error)
        }
        if cocoaError.isFileError || isFileSystemCode(cocoaError.code) {
            return CocoaErrorMeta(errorCode: fileErrorCode(cocoaError.code), category: .fileSystem, severity: .error)
        }
        if cocoaError.isValidationError {
            return CocoaErrorMeta(errorCode: "COCOA.VALIDATION_ERROR", category: .validation, severity: .warning)
        }
        return CocoaErrorMeta(errorCode: "COCOA.\(cocoaError.code.rawValue)", category: .system, severity: .error)
    }

    private static func isPermission(_ code: CocoaError.Code) -> Bool {
        code == .fileReadNoPermission || code == .fileWriteNoPermission
    }

    private static func isFileSystemCode(_ code: CocoaError.Code) -> Bool {
        switch code {
        case .fileNoSuchFile, .fileReadNoSuchFile, .fileWriteFileExists,
             .fileWriteOutOfSpace, .fileWriteVolumeReadOnly, .fileWriteInvalidFileName,
             .fileReadCorruptFile, .fileReadTooLarge, .fileReadInapplicableStringEncoding:
            return true
        default:
            return false
        }
    }

    private static func fileErrorCode(_ code: CocoaError.Code) -> String {
        switch code {
        case .fileNoSuchFile, .fileReadNoSuchFile:
            return "COCOA.FILE_NOT_FOUND"
        case .fileWriteFileExists:
            return "COCOA.FILE_EXISTS"
        case .fileWriteOutOfSpace:
            return "COCOA.OUT_OF_SPACE"
        case .fileWriteVolumeReadOnly:
            return "COCOA.VOLUME_READ_ONLY"
        case .fileWriteInvalidFileName:
            return "COCOA.INVALID_FILE_NAME"
        case .fileReadCorruptFile:
            return "COCOA.CORRUPT_FILE"
        case .fileReadTooLarge:
            return "COCOA.FILE_TOO_LARGE"
        case .fileReadInapplicableStringEncoding:
            return "COCOA.INVALID_ENCODING"
        default:
            return "COCOA.FILE_SYSTEM_ERROR"
        }
    }
}

// MARK: - NSError Classifier

enum UniversalNSErrorClassifier: Sendable {
    private static let networkKeywords = ["network", "url", "http", "socket"]
    private static let fileKeywords = ["file", "disk", "storage", "ioerror", ".io", "io."]
    private static let permissionKeywords = ["auth", "permission", "security", "keychain"]
    private static let validationKeywords = ["validation", "parse", "decode"]

    private static let categoryRules: [(keywords: [String], category: ErrorCategory)] = [
        (networkKeywords, .network),
        (fileKeywords, .fileSystem),
        (permissionKeywords, .permission),
        (validationKeywords, .validation)
    ]

    static func classify(
        _ nsError: NSError,
        originalError: any Error,
        defaultCategory: ErrorCategory,
        defaultSeverity: ErrorSeverity,
        taskCancelled: Bool
    ) -> AnyAppError {
        var context = populateContext(from: nsError)
        if taskCancelled {
            context["task_cancelled"] = "true"
        }

        let isCancelled = isCancellation(nsError: nsError)
        let category = resolveCategory(nsError: nsError, isCancelled: isCancelled, fallback: defaultCategory)
        let severity: ErrorSeverity = isCancelled ? .info : defaultSeverity
        let errorCode = formatErrorCode(domain: nsError.domain, code: nsError.code)

        return AnyAppError(
            errorCode: errorCode,
            category: category,
            severity: severity,
            isSilent: isCancelled,
            context: context,
            underlyingErrorDescription: originalError.localizedDescription,
            rawL10nKey: nil
        )
    }

    private static func isCancellation(nsError: NSError) -> Bool {
        let isUserCancelledCode = (nsError.code == 3072) // NSUserCancelledError
        let isCocoaCancelled = (nsError.domain == NSCocoaErrorDomain && nsError.code == CocoaError.userCancelled.rawValue)
        return isUserCancelledCode || isCocoaCancelled
    }

    private static func resolveCategory(
        nsError: NSError,
        isCancelled: Bool,
        fallback: ErrorCategory
    ) -> ErrorCategory {
        guard !isCancelled else {
            return .cancelled
        }
        return inferCategory(from: nsError.domain, fallback: fallback)
    }

    private static func populateContext(from nsError: NSError) -> [String: String] {
        var context: [String: String] = [
            "ns_domain": nsError.domain,
            "ns_code": String(nsError.code)
        ]
        if let reason = nsError.localizedFailureReason {
            context["failure_reason"] = reason
        }
        if let recovery = nsError.localizedRecoverySuggestion {
            context["recovery_suggestion"] = recovery
        }
        return context
    }

    private static func inferCategory(from domain: String, fallback: ErrorCategory) -> ErrorCategory {
        let lower = domain.lowercased()
        for rule in categoryRules {
            if matchesKeyword(in: lower, keywords: rule.keywords) {
                return rule.category
            }
        }
        return fallback
    }

    private static func matchesKeyword(in text: String, keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }

    private static func formatErrorCode(domain: String, code: Int) -> String {
        let sanitized = sanitizeDomain(domain)
        return "\(sanitized).\(code)"
    }

    private static func sanitizeDomain(_ domain: String) -> String {
        let cleaned = domain
            .replacingOccurrences(of: "ErrorDomain", with: "")
            .replacingOccurrences(of: "Domain", with: "")
        var result = ""
        for char in cleaned {
            if isDomainIdentifierChar(char) {
                result.append(char)
            } else {
                result.append("_")
            }
        }
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "._"))
        return trimmed.isEmpty ? "NSERROR" : trimmed.uppercased()
    }

    private static func isDomainIdentifierChar(_ char: Character) -> Bool {
        guard char != "." else {
            return true
        }
        return char.isLetter || char.isNumber
    }
}
