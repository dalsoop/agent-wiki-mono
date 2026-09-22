import Foundation

public actor CLISessionStatusRefresher {
    public typealias Loader = @Sendable () async -> [CLISessionStatus]

    private let loader: Loader
    private var inFlight: Task<[CLISessionStatus], Never>?

    public init(loader: @escaping Loader = {
        await CLISessionProbe().statuses()
    }) {
        self.loader = loader
    }

    public func statuses() async -> [CLISessionStatus] {
        if let inFlight { return await inFlight.value }

        let loader = self.loader
        let task = Task { await loader() }
        inFlight = task
        let statuses = await task.value
        inFlight = nil
        return statuses
    }
}
