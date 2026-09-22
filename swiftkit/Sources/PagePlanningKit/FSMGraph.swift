import Foundation

/// FSM Transition representation between two states
public struct FSMTransition: Hashable, Sendable, CustomStringConvertible {
    public let source: String
    public let target: String
    public let trigger: String
    public let type: String  // "fault", "recovery", "action", "identity"

    public init(source: String, target: String, trigger: String, type: String = "action") {
        self.source = source
        self.target = target
        self.trigger = trigger
        self.type = type
    }

    public var description: String {
        "\(source) --(\(trigger))--> \(target) [\(type)]"
    }
}

/// FSM Directed Graph Engine for mathematical reachability and dead-end proof
public struct FSMGraph: Sendable {
    public static let faultStates: Set<String> = ["error", "expired", "unsupported", "unauthorized"]
    public static let safeState: String = "ready"

    public private(set) var states: [String]
    public private(set) var stateToIndex: [String: Int]
    public private(set) var transitions: [FSMTransition]
    public private(set) var forwardAdj: [String: [(target: String, trigger: String)]]
    public private(set) var reverseAdj: [String: [(source: String, trigger: String)]]

    public init(states: [String]) {
        var ordered: [String] = []
        if states.contains(Self.safeState) {
            ordered.append(Self.safeState)
        }
        for s in states.sorted() where !ordered.contains(s) {
            ordered.append(s)
        }

        self.states = ordered
        var map: [String: Int] = [:]
        var fwd: [String: [(target: String, trigger: String)]] = [:]
        var rev: [String: [(source: String, trigger: String)]] = [:]

        for (idx, state) in ordered.enumerated() {
            map[state] = idx
            fwd[state] = []
            rev[state] = []
        }

        self.stateToIndex = map
        self.transitions = []
        self.forwardAdj = fwd
        self.reverseAdj = rev
    }

    public mutating func addTransition(source: String, target: String, trigger: String, type: String = "action") {
        if stateToIndex[source] == nil {
            let idx = states.count
            states.append(source)
            stateToIndex[source] = idx
            forwardAdj[source] = []
            reverseAdj[source] = []
        }
        if stateToIndex[target] == nil {
            let idx = states.count
            states.append(target)
            stateToIndex[target] = idx
            forwardAdj[target] = []
            reverseAdj[target] = []
        }

        let transition = FSMTransition(source: source, target: target, trigger: trigger, type: type)
        transitions.append(transition)
        forwardAdj[source]?.append((target: target, trigger: trigger))
        reverseAdj[target]?.append((source: source, trigger: trigger))
    }

    /// O(V+E) Reverse Graph Coreachability BFS:
    /// Returns all states that can reach the target state.
    public func coreachableStates(to target: String) -> Set<String> {
        guard stateToIndex[target] != nil else { return [] }
        var visited: Set<String> = [target]
        var queue: [String] = [target]

        while !queue.isEmpty {
            let curr = queue.removeFirst()
            guard let incoming = reverseAdj[curr] else { continue }
            for edge in incoming {
                if !visited.contains(edge.source) {
                    visited.insert(edge.source)
                    queue.append(edge.source)
                }
            }
        }
        return visited
    }

    /// Forward BFS shortest path proof
    public func findPathBFS(from start: String, to goal: String) -> [FSMTransition]? {
        guard stateToIndex[start] != nil, stateToIndex[goal] != nil else { return nil }
        if start == goal {
            return [FSMTransition(source: start, target: goal, trigger: "identity", type: "identity")]
        }

        var visited: Set<String> = [start]
        var queue: [(current: String, path: [FSMTransition])] = [(start, [])]

        while !queue.isEmpty {
            let (curr, path) = queue.removeFirst()
            guard let outgoing = forwardAdj[curr] else { continue }
            for edge in outgoing {
                let nextTransition = FSMTransition(source: curr, target: edge.target, trigger: edge.trigger)
                if edge.target == goal {
                    return path + [nextTransition]
                }
                if !visited.contains(edge.target) {
                    visited.insert(edge.target)
                    queue.append((edge.target, path + [nextTransition]))
                }
            }
        }
        return nil
    }

    public func outDegree(of state: String) -> Int {
        forwardAdj[state]?.count ?? 0
    }

    public func inDegree(of state: String) -> Int {
        reverseAdj[state]?.count ?? 0
    }

    /// Detect sink nodes (out-degree == 0) excluding allowed terminal states
    public func findSinkNodes(allowedTerminals: Set<String> = ["destroyed", "closed"]) -> [String] {
        states.filter { state in
            !allowedTerminals.contains(state) && outDegree(of: state) == 0
        }
    }

    // MARK: - Factory from PageSpec

    /// Build an FSMGraph from a PageSpec model
    public static func build(from spec: PageSpec) -> FSMGraph {
        let stateNames = Array(spec.states.keys)
        var graph = FSMGraph(states: stateNames)

        for (stateName, stateDef) in spec.states {
            // Fault transitions: ready -> fault states
            if stateName != safeState && faultStates.contains(stateName) {
                graph.addTransition(source: safeState, target: stateName, trigger: "fault:\(stateName)", type: "fault")
            }

            // Recovery transitions: fault state -> recovery target/action -> ready
            if let recovery = stateDef.recovery {
                let trigger = recovery.action ?? recovery.label ?? "recover"
                graph.addTransition(source: stateName, target: safeState, trigger: trigger, type: "recovery")
            }

            // Actions in state
            if let actions = stateDef.actions {
                for (actionKey, status) in actions where status == "ENABLED" {
                    graph.addTransition(source: stateName, target: stateName, trigger: actionKey, type: "self")
                }
            }
        }

        return graph
    }

    /// Verification Result
    public struct VerificationResult: Sendable {
        public let isCompliant: Bool
        public let deadEnds: [String]
        public let unrecoverableStates: [String]
        public let recoveryProofs: [String: [FSMTransition]]
    }

    /// Mathematically prove reachability and recovery
    public func verify(allowedTerminals: Set<String> = []) -> VerificationResult {
        let sinks = findSinkNodes(allowedTerminals: allowedTerminals)
        let coreachable = coreachableStates(to: Self.safeState)

        var unrecoverable: [String] = []
        var proofs: [String: [FSMTransition]] = [:]

        for state in states where Self.faultStates.contains(state) {
            if coreachable.contains(state) {
                if let proof = findPathBFS(from: state, to: Self.safeState) {
                    proofs[state] = proof
                }
            } else {
                unrecoverable.append(state)
            }
        }

        let passed = sinks.isEmpty && unrecoverable.isEmpty
        return VerificationResult(
            isCompliant: passed,
            deadEnds: sinks,
            unrecoverableStates: unrecoverable,
            recoveryProofs: proofs
        )
    }
}
