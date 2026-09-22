import Foundation

/// CLI 전역 플래그 peel — **선두(leading)** 의 `--as` / `--world` 만 제거한다.
public struct CLIArgvPeel: Sendable, Equatable {
    public var author: String
    public var world: String?
    public var rest: [String]
    public init(author: String, world: String?, rest: [String]) {
        self.author = author; self.world = world; self.rest = rest
    }
}

public enum CLIArgv {
    public static func isHelpToken(_ value: String) -> Bool {
        value == "help" || value == "--help" || value == "-h"
    }

    public static func peelLeadingGlobals(_ args: [String], defaultAuthor: String) -> CLIArgvPeel {
        var args = args
        var author = defaultAuthor
        var world: String?
        while let first = args.first {
            if first == "--as", args.count >= 2 {
                author = args[1]; args.removeFirst(2); continue
            }
            if first == "--world", args.count >= 2 {
                world = args[1]; args.removeFirst(2); continue
            }
            break
        }
        return CLIArgvPeel(author: author, world: world, rest: args)
    }

    /// 특정 위치 뒤의 positional 값만 꺼낸다. 값이 딸린 옵션은 옵션과 값을 함께 건너뛰어,
    /// `--root /path` 의 `/path` 를 blob SHA 같은 positional 로 오인하지 않는다.
    public static func positionals(
        in args: [String],
        startingAt start: Int = 0,
        optionsWithValues: Set<String> = []
    ) -> [String] {
        var result: [String] = []
        var index = max(0, start)
        while index < args.count {
            let value = args[index]
            if optionsWithValues.contains(value) {
                index += 2
            } else if value.hasPrefix("--") {
                index += 1
            } else {
                result.append(value)
                index += 1
            }
        }
        return result
    }
}
