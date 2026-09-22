import Foundation

/// 첨부파일 메타(복호화된 표시용).
public struct VaultAttachment: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let fileName: String
    public let size: Int
    public let sizeName: String
    /// 첨부 전용 키(EncString) — 다운로드 복호화에 필요.
    public let key: String?
    public let url: String?

    public init(id: String, fileName: String, size: Int, sizeName: String, key: String?, url: String?) {
        self.id = id
        self.fileName = fileName
        self.size = size
        self.sizeName = sizeName
        self.key = key
        self.url = url
    }
}

/// 서버 응답 DTO — fileName 은 EncString.
public struct AttachmentDTO: Codable, Sendable {
    public var id: String?
    public var fileName: String?
    public var size: String?
    public var sizeName: String?
    public var key: String?
    public var url: String?

    public init(
        id: String? = nil, fileName: String? = nil, size: String? = nil,
        sizeName: String? = nil, key: String? = nil, url: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.size = size
        self.sizeName = sizeName
        self.key = key
        self.url = url
    }
}

/// POST /ciphers/{id}/attachment/v2 응답.
public struct AttachmentUploadTicket: Codable, Sendable {
    public let attachmentId: String
    public let url: String
    /// 0 = Direct(서버로 multipart), 1 = Azure(사전서명 URL).
    public let fileUploadType: Int
}

/// 첨부 본문 암호화 형식(EncArrayBuffer):
/// `[encType(1)] [iv(16)] [mac(32)] [ciphertext…]`
/// 공식 웹·모바일 클라이언트와 같은 바이트 레이아웃이라 서로 열람된다.
public enum VaultAttachmentCrypto {
    public enum CryptoError: Error, Equatable, CustomStringConvertible {
        case malformedBuffer
        case unsupportedType(Int)

        public var description: String {
            switch self {
            case .malformedBuffer: "첨부 데이터 형식이 올바르지 않습니다"
            case let .unsupportedType(type): "지원하지 않는 첨부 암호화 형식: \(type)"
            }
        }
    }

    /// 헤더 크기: type(1) + iv(16) + mac(32).
    static let headerSize = 49

    public static func encrypt(_ plaintext: Data, key: BitwardenCrypto.SymmetricKeySet) throws -> Data {
        let enc = try BitwardenCrypto.encrypt(plaintext, key: key)
        var buffer = Data([UInt8(enc.type)])
        buffer.append(enc.iv)
        buffer.append(enc.mac ?? Data())
        buffer.append(enc.data)
        return buffer
    }

    public static func decrypt(_ buffer: Data, key: BitwardenCrypto.SymmetricKeySet) throws -> Data {
        guard let first = buffer.first else { throw CryptoError.malformedBuffer }
        let type = Int(first)
        guard type == 2 else { throw CryptoError.unsupportedType(type) }
        guard buffer.count > headerSize else { throw CryptoError.malformedBuffer }
        let iv = buffer.subdata(in: 1..<17)
        let mac = buffer.subdata(in: 17..<headerSize)
        let ciphertext = buffer.subdata(in: headerSize..<buffer.count)
        let enc = BitwardenCrypto.EncString(type: 2, iv: iv, data: ciphertext, mac: mac)
        return try BitwardenCrypto.decrypt(enc, key: key)
    }

    /// 첨부 전용 랜덤 키(64바이트: enc 32 | mac 32).
    public static func makeAttachmentKey() -> BitwardenCrypto.SymmetricKeySet {
        var raw = Data(count: 64)
        _ = raw.withUnsafeMutableBytes { pointer in
            SecRandomCopyBytes(kSecRandomDefault, 64, pointer.baseAddress!)
        }
        return BitwardenCrypto.SymmetricKeySet(raw: raw) ?? BitwardenCrypto.stretchedKey(masterKey: raw)
    }

    public static func humanSize(_ bytes: Int) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        return index == 0 ? "\(bytes) B" : String(format: "%.1f %@", value, units[index])
    }
}
