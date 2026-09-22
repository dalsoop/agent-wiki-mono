import Foundation

enum CLISourceBalance {
    static func consume(maskedLines: [String], start: Int) -> Int? {
        var walk = Walk(depth: 0, index: start, sawOpener: false)
        while walk.index < maskedLines.count {
            switch applyGrouping(to: &walk, lines: maskedLines, start: start) {
            case .failed:
                return nil
            case .finished(let end):
                return end
            case .continueWalk:
                break
            }
        }
        return walk.depth == 0 ? walk.index : nil
    }
}

private extension CLISourceBalance {
    struct Walk {
        var depth: Int
        var index: Int
        var sawOpener: Bool
    }

    enum Result {
        case failed
        case finished(Int)
        case continueWalk
    }

    static func applyGrouping(to walk: inout Walk, lines: [String], start: Int) -> Result {
        let delta = groupingDelta(in: lines[walk.index])
        walk.sawOpener = walk.sawOpener || delta != 0
        walk.depth += delta
        guard walk.depth >= 0 else { return .failed }
        walk.index += 1
        return finishOrContinue(walk, lines: lines, start: start)
    }

    static func finishOrContinue(_ walk: Walk, lines: [String], start: Int) -> Result {
        if walk.sawOpener && walk.depth == 0 {
            return .finished(walk.index)
        }
        return continueWithoutOpener(walk, lines: lines, start: start)
    }

    static func continueWithoutOpener(_ walk: Walk, lines: [String], start: Int) -> Result {
        guard !walk.sawOpener else { return .continueWalk }
        if hasOpeningBraceAhead(maskedLines: lines, from: walk.index) {
            return .continueWalk
        }
        return .finished(start + 1)
    }

    static func hasOpeningBraceAhead(maskedLines: [String], from index: Int) -> Bool {
        var cursor = index
        while cursor < maskedLines.count {
            let trimmed = maskedLines[cursor].trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                cursor += 1
                continue
            }
            return trimmed.hasPrefix("{")
        }
        return false
    }

    static func groupingDelta(in maskedLine: String) -> Int {
        var delta = 0
        for ch in maskedLine {
            delta += groupingWeight(ch)
        }
        return delta
    }

    static func groupingWeight(_ ch: Character) -> Int {
        switch ch {
        case "(", "[", "{":
            return 1
        case ")", "]", "}":
            return -1
        default:
            return 0
        }
    }
}
