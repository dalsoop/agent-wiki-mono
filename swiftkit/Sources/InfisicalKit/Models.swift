import Foundation

public struct ServerStatus: Sendable, Equatable {
    public let reachable: Bool
    public let message: String
    public init(reachable: Bool, message: String) {
        self.reachable = reachable
        self.message = message
    }
}

public struct ProjectEnvironment: Sendable, Equatable, Hashable {
    public let name: String
    public let slug: String
    public init(name: String, slug: String) {
        self.name = name
        self.slug = slug
    }
}

public struct Workspace: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let orgId: String
    public let environments: [ProjectEnvironment]
    public init(id: String, name: String, orgId: String, environments: [ProjectEnvironment]) {
        self.id = id
        self.name = name
        self.orgId = orgId
        self.environments = environments
    }
}

public struct Folder: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct Secret: Sendable, Equatable, Identifiable {
    // 재귀 보기에서 같은 key 가 다른 경로에 존재할 수 있어 path+key 로 식별.
    public var id: String { path + "|" + key }
    public let key: String
    public let value: String
    public let comment: String
    public let path: String
    public init(key: String, value: String, comment: String = "", path: String = "/") {
        self.key = key
        self.value = value
        self.comment = comment
        self.path = path
    }
}

public struct Identity: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let role: String
    public init(id: String, name: String, role: String) {
        self.id = id
        self.name = name
        self.role = role
    }
}

public struct ClientSecretInfo: Sendable, Equatable, Identifiable {
    public let id: String
    public let description: String
    public let createdAt: String
    public init(id: String, description: String, createdAt: String) {
        self.id = id
        self.description = description
        self.createdAt = createdAt
    }
}
