import Foundation

/// $O(M + Z)$ 복잡도로 수백 개의 금지 키워드/패턴을 단 1회의 텍스트 순회로 일괄 검출하는 초고속 오토마톤.
public struct AhoCorasickMatcher: Sendable {

    public struct Match: Sendable, Equatable {
        public let patternIndex: Int
        public let pattern: String
        public let range: Range<Int>

        public init(patternIndex: Int, pattern: String, range: Range<Int>) {
            self.patternIndex = patternIndex
            self.pattern = pattern
            self.range = range
        }
    }

    private struct State: Sendable {
        var next: [UInt8: Int] = [:]
        var fail: Int = 0
        var outputs: [Int] = []
    }

    private let states: [State]
    private let patterns: [String]

    public init(patterns: [String]) {
        self.patterns = patterns
        var builtStates = [State()]
        Self.buildTrie(patterns: patterns, states: &builtStates)
        Self.buildFailureLinks(states: &builtStates)
        self.states = builtStates
    }

    private static func buildTrie(patterns: [String], states: inout [State]) {
        for (idx, pattern) in patterns.enumerated() {
            var curr = 0
            for byte in pattern.utf8 {
                if let next = states[curr].next[byte] {
                    curr = next
                } else {
                    let next = states.count
                    states.append(State())
                    states[curr].next[byte] = next
                    curr = next
                }
            }
            states[curr].outputs.append(idx)
        }
    }

    private static func buildFailureLinks(states: inout [State]) {
        var queue: [Int] = []
        for (_, next) in states[0].next {
            queue.append(next)
            states[next].fail = 0
        }

        var head = 0
        while head < queue.count {
            let curr = queue[head]
            head += 1

            for (byte, next) in states[curr].next {
                var f = states[curr].fail
                while f > 0 && states[f].next[byte] == nil {
                    f = states[f].fail
                }
                let failureState = states[f].next[byte] ?? 0
                states[next].fail = failureState
                states[next].outputs.append(contentsOf: states[failureState].outputs)
                queue.append(next)
            }
        }
    }

    public func match(in text: String) -> [Match] {
        var matches: [Match] = []
        var curr = 0
        let bytes = Array(text.utf8)

        for (idx, byte) in bytes.enumerated() {
            while curr > 0 && states[curr].next[byte] == nil {
                curr = states[curr].fail
            }
            curr = states[curr].next[byte] ?? 0

            for pIdx in states[curr].outputs {
                let patLen = patterns[pIdx].utf8.count
                let start = idx - patLen + 1
                matches.append(Match(patternIndex: pIdx, pattern: patterns[pIdx], range: start..<(start + patLen)))
            }
        }
        return matches
    }
}
