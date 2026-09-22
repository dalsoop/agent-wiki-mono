import Foundation
import FastDiskIOKit

/// 공용 에러 투명성 보장 영속성 계층 에러.
/// 에러를 조용히 삼키지(swallow) 않고, 실패 원인과 경로를 명시적으로 드러냅니다.
public enum AppPersistenceError: LocalizedError, CustomStringConvertible, Sendable {
    case fileNotFound(path: String)
    case readFailed(path: String, underlyingDescription: String)
    case decodeFailed(path: String, typeName: String, underlyingDescription: String)
    case encodeFailed(path: String, typeName: String, underlyingDescription: String)
    case writeFailed(path: String, underlyingDescription: String)

    public var description: String {
        switch self {
        case .fileNotFound(let path):
            return "AppPersistenceError.fileNotFound(path: \"\(path)\")"
        case .readFailed(let path, let underlying):
            return "AppPersistenceError.readFailed(path: \"\(path)\", underlying: \(underlying))"
        case .decodeFailed(let path, let typeName, let underlying):
            return "AppPersistenceError.decodeFailed(path: \"\(path)\", type: \(typeName), underlying: \(underlying))"
        case .encodeFailed(let path, let typeName, let underlying):
            return "AppPersistenceError.encodeFailed(path: \"\(path)\", type: \(typeName), underlying: \(underlying))"
        case .writeFailed(let path, let underlying):
            return "AppPersistenceError.writeFailed(path: \"\(path)\", underlying: \(underlying))"
        }
    }

    public var errorDescription: String? {
        description
    }
}

/// 단일화된 앱 상태/원장 영속성 및 SafeJSON 파싱 공용 API.
/// `FastAtomicWriter` 기반 원자적 저장 및 에러 투명성(Zero Error Swallow)을 일관되게 제공합니다.
public struct AppPersistence: Sendable {
    /// 기본 정렬 및 무이스케이프 슬래시가 적용된 JSONEncoder SSOT.
    public static let defaultEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    /// ISO8601 기본 지원 JSONDecoder SSOT.
    public static let defaultDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Safe Data Decoding & Encoding

    /// Data로부터 모델을 안전하게 디코딩합니다 (디코딩 에러 발생 시 상세 에러를 명시적으로 던짐).
    public static func decode<T: Decodable>(
        _ type: T.Type = T.self,
        from data: Data,
        decoder: JSONDecoder = defaultDecoder
    ) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw AppPersistenceError.decodeFailed(
                path: "<in-memory data>",
                typeName: String(describing: T.self),
                underlyingDescription: String(describing: error)
            )
        }
    }

    /// 모델을 JSON Data로 안전하게 인코딩합니다.
    public static func encode<T: Encodable>(
        _ value: T,
        encoder: JSONEncoder = defaultEncoder
    ) throws -> Data {
        do {
            return try encoder.encode(value)
        } catch {
            throw AppPersistenceError.encodeFailed(
                path: "<in-memory data>",
                typeName: String(describing: T.self),
                underlyingDescription: String(describing: error)
            )
        }
    }

    // MARK: - File Loading

    /// 파일로부터 모델을 로드합니다.
    /// 파일이 없고 `fallback`이 지정되어 있으면 기본값을 반환합니다.
    /// 파일이 존재하지만 디코딩에 실패하면 절대 삼키지 않고 `AppPersistenceError.decodeFailed`를 던집니다.
    public static func load<T: Decodable>(
        from url: URL,
        as type: T.Type = T.self,
        default fallback: T? = nil,
        decoder: JSONDecoder = defaultDecoder
    ) throws -> T {
        try load(from: url.path, as: type, default: fallback, decoder: decoder)
    }

    /// 경로 문자열로부터 모델을 로드합니다.
    public static func load<T: Decodable>(
        from path: String,
        as type: T.Type = T.self,
        default fallback: T? = nil,
        decoder: JSONDecoder = defaultDecoder
    ) throws -> T {
        guard FileManager.default.fileExists(atPath: path) else {
            if let fallback { return fallback }
            throw AppPersistenceError.fileNotFound(path: path)
        }

        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw AppPersistenceError.readFailed(
                path: path,
                underlyingDescription: String(describing: error)
            )
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AppPersistenceError.decodeFailed(
                path: path,
                typeName: String(describing: T.self),
                underlyingDescription: String(describing: error)
            )
        }
    }

    /// 파일이 존재할 경우에만 모델을 로드하고, 파일이 없으면 `nil`을 반환합니다.
    /// 파일이 존재하는데 손상되었을 때는 `nil`로 덮지 않고 에러를 던집니다.
    public static func loadIfExists<T: Decodable>(
        from url: URL,
        as type: T.Type = T.self,
        decoder: JSONDecoder = defaultDecoder
    ) throws -> T? {
        try loadIfExists(from: url.path, as: type, decoder: decoder)
    }

    /// 파일이 존재할 경우에만 모델을 로드하고, 파일이 없으면 `nil`을 반환합니다.
    public static func loadIfExists<T: Decodable>(
        from path: String,
        as type: T.Type = T.self,
        decoder: JSONDecoder = defaultDecoder
    ) throws -> T? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return try load(from: path, as: type, default: nil, decoder: decoder)
    }

    // MARK: - File Saving

    /// `FastAtomicWriter`를 통해 원자적(atomic rename)으로 안전하게 저장합니다.
    @discardableResult
    public static func save<T: Encodable>(
        _ value: T,
        to url: URL,
        encoder: JSONEncoder = defaultEncoder,
        onlyIfChanged: Bool = true
    ) throws -> Bool {
        try save(value, to: url.path, encoder: encoder, onlyIfChanged: onlyIfChanged)
    }

    /// `FastAtomicWriter`를 통해 원자적(atomic rename)으로 안전하게 저장합니다.
    @discardableResult
    public static func save<T: Encodable>(
        _ value: T,
        to path: String,
        encoder: JSONEncoder = defaultEncoder,
        onlyIfChanged: Bool = true
    ) throws -> Bool {
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw AppPersistenceError.encodeFailed(
                path: path,
                typeName: String(describing: T.self),
                underlyingDescription: String(describing: error)
            )
        }

        do {
            if onlyIfChanged {
                return try FastAtomicWriter.writeIfChanged(to: path, data: data)
            } else {
                try FastAtomicWriter.writeAtomic(to: path, data: data)
                return true
            }
        } catch {
            throw AppPersistenceError.writeFailed(
                path: path,
                underlyingDescription: String(describing: error)
            )
        }
    }
}

/// 에러 투명성 플레이북(위키 032c81b6) 규약에 따른 SafeJSON 별칭.
public typealias SafeJSON = AppPersistence
