import Foundation

public enum LaunchAgentSchedule: Equatable {
    case interval(seconds: Int)
    case calendar(hour: Int, minute: Int)
    case none
}

public struct LaunchAgentStatus: Equatable {
    public var isInstalled: Bool
    public var isLoaded: Bool
    public var pid: Int32?
    
    public init(isInstalled: Bool, isLoaded: Bool, pid: Int32? = nil) {
        self.isInstalled = isInstalled
        self.isLoaded = isLoaded
        self.pid = pid
    }
}

public struct LaunchAgentConfiguration: Equatable {
    public var label: String
    public var executablePath: String
    public var arguments: [String]
    public var schedule: LaunchAgentSchedule
    public var standardOutPath: String?
    public var standardErrorPath: String?
    public var keepAlive: Bool
    public var processType: String
    public var caffeinate: Bool
    
    public init(
        label: String,
        executablePath: String,
        arguments: [String] = [],
        schedule: LaunchAgentSchedule = .none,
        standardOutPath: String? = nil,
        standardErrorPath: String? = nil,
        keepAlive: Bool = false,
        processType: String = "Background",
        caffeinate: Bool = false
    ) {
        self.label = label
        self.executablePath = executablePath
        self.arguments = arguments
        self.schedule = schedule
        self.standardOutPath = standardOutPath ?? ("~/Library/Logs/host-agents/" + label + ".stdout.log" as NSString).expandingTildeInPath
        self.standardErrorPath = standardErrorPath ?? ("~/Library/Logs/host-agents/" + label + ".stderr.log" as NSString).expandingTildeInPath
        self.keepAlive = keepAlive
        self.processType = processType
        self.caffeinate = caffeinate
    }
}
