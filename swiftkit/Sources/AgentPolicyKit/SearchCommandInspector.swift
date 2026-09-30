import Foundation

struct SearchCommandInspector: Sendable {
    /// 경로 문자열이 HOME 루트 자체인지 판정한다. 끝의 '/'는 무시하며, 하위 경로는 false.
    static func isHomeRootPath(_ rawPath: String, home: String) -> Bool {
        var p = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        guard !p.isEmpty else { return false }

        while p.count > 1 && p.hasSuffix("/") {
            p.removeLast()
        }

        let homeSymbols: Set<String> = ["~", "$HOME", "${HOME}"]
        if homeSymbols.contains(p) { return true }

        let homeStd = (home as NSString).standardizingPath
        let expanded = (p as NSString).expandingTildeInPath
        let std = (expanded as NSString).standardizingPath
        return std == homeStd
    }

    /// 명령 문자열 내의 find, grep, rg 호출이 HOME 루트를 검색 대상으로 삼는지 검사한다.
    static func isHomeRootSearch(command: String, home: String) -> Bool {
        let cmdStrings = ShellCommandSplitter.split(command)
        for rawCmd in cmdStrings {
            let argv = stripCommandWrappers(ShellArgvLexer.parseArgv(rawCmd))
            if inspectCommandForHomeRoot(argv: argv, home: home) {
                return true
            }
        }
        return false
    }

    private static func inspectCommandForHomeRoot(argv: [String], home: String) -> Bool {
        guard let argv0 = argv.first else { return false }
        let exe = (argv0 as NSString).lastPathComponent

        if exe == "find" {
            let paths = findPathOperands(argv: argv)
            return paths.contains(where: { isHomeRootPath($0, home: home) })
        }
        if grepTools.contains(exe) {
            let paths = grepOrRgPathOperands(argv: argv, optionsTakingArg: grepOptionsTakingArg)
            return paths.contains(where: { isHomeRootPath($0, home: home) })
        }
        if exe == "rg" {
            let paths = grepOrRgPathOperands(argv: argv, optionsTakingArg: rgOptionsTakingArg)
            return paths.contains(where: { isHomeRootPath($0, home: home) })
        }
        return false
    }

    private static let grepTools: Set<String> = ["grep", "egrep", "fgrep", "ggrep"]

    /// `timeout 10 rg x ~` 처럼 앞에 붙어 검색 명령을 실행만 하는 래퍼를 벗긴다.
    /// `command -v rg` 같은 조회는 실행이 아니므로 빈 argv 를 돌려준다.
    static func stripCommandWrappers(_ argv: [String]) -> [String] {
        var rest = argv[...]
        while let argv0 = rest.first {
            let exe = (argv0 as NSString).lastPathComponent
            guard let skipped = wrapperOperandStart(exe: exe, args: Array(rest.dropFirst())) else {
                break
            }
            rest = rest.dropFirst(1 + skipped)
        }
        return Array(rest)
    }

    /// 래퍼 이름 뒤에서 건너뛸 인자 수. 래퍼가 아니면 nil, 실행이 아닌 조회면 인자 전부.
    private static func wrapperOperandStart(exe: String, args: [String]) -> Int? {
        switch exe {
        case "timeout", "gtimeout":
            var i = skipOptions(args, takingArg: ["-s", "-k", "--signal", "--kill-after"])
            if i < args.count { i += 1 }  // DURATION
            return i
        case "env":
            var i = skipOptions(args, takingArg: ["-u", "-C", "-P", "-S", "--unset", "--chdir"])
            while i < args.count, args[i].contains("="), !args[i].hasPrefix("-") { i += 1 }
            return i
        case "nice":
            return skipOptions(args, takingArg: ["-n", "--adjustment"])
        case "stdbuf":
            return skipOptions(args, takingArg: ["-i", "-o", "-e"])
        case "sudo":
            return skipOptions(args, takingArg: ["-u", "-g", "-C", "-D", "-h", "-p", "-U", "-r", "-t"])
        case "exec":
            return skipOptions(args, takingArg: ["-a"])
        case "command":
            if args.contains(where: { $0 == "-v" || $0 == "-V" }) { return args.count }
            return skipOptions(args, takingArg: [])
        case "nohup", "time", "builtin":
            return skipOptions(args, takingArg: [])
        default:
            return nil
        }
    }

    /// 앞쪽 옵션을 건너뛴 첫 피연산자 위치. `--` 는 옵션 끝.
    private static func skipOptions(_ args: [String], takingArg: Set<String>) -> Int {
        var i = 0
        while i < args.count, args[i].hasPrefix("-"), args[i] != "-" {
            if args[i] == "--" { return i + 1 }
            i += takingArg.contains(args[i]) ? 2 : 1
        }
        return min(i, args.count)
    }

    private static func findPathOperands(argv: [String]) -> [String] {
        guard argv.count > 1 else { return [] }
        var paths: [String] = []
        let nonOptions = collectFindPaths(argv: argv, outPaths: &paths)
        return nonOptions
    }

    private static func collectFindPaths(argv: [String], outPaths: inout [String]) -> [String] {
        var i = 1
        while i < argv.count {
            let arg = argv[i]
            if arg == "-f", i + 1 < argv.count {
                outPaths.append(argv[i + 1])
                i += 2
                continue
            }
            if arg.hasPrefix("-") {
                if isFindPrimary(arg) { break }
                i += 1
                continue
            }
            break
        }

        while i < argv.count {
            let arg = argv[i]
            if arg.hasPrefix("-") { break }
            let isTerminator = arg == "!" || arg == "("
            if isTerminator { break }
            outPaths.append(arg)
            i += 1
        }
        return outPaths
    }

    private static func isFindPrimary(_ arg: String) -> Bool {
        let primaries: Set<String> = [
            "-name", "-iname", "-path", "-ipath", "-regex", "-iregex",
            "-type", "-maxdepth", "-mindepth", "-exec", "-execdir",
            "-ok", "-okdir", "-print", "-print0", "-delete", "-prune",
            "-mtime", "-atime", "-ctime", "-mmin", "-amin", "-cmin",
            "-size", "-perm", "-user", "-group", "-newer", "-empty"
        ]
        return primaries.contains(arg)
    }

    /// grep 계열에서 값을 받는 옵션. `-r`·`-R` 은 재귀 스위치라 값을 받지 않는다.
    private static let grepOptionsTakingArg: Set<String> = [
        "-e", "-f", "-m", "-A", "-B", "-C", "-d", "-D",
        "--regexp", "--file", "--max-count", "--context", "--after-context",
        "--before-context", "--devices", "--directories", "--exclude", "--include",
        "--exclude-dir", "--exclude-from", "--label", "--binary-files"
    ]

    /// rg 에서 값을 받는 옵션. rg 의 `-r` 은 `--replace` 라 값을 받는다.
    private static let rgOptionsTakingArg: Set<String> = [
        "-e", "-f", "-g", "-t", "-T", "-m", "-M", "-A", "-B", "-C", "-d", "-r", "-j", "-E",
        "--regexp", "--file", "--glob", "--iglob", "--type", "--type-not", "--type-add",
        "--type-clear", "--max-count", "--max-columns", "--max-depth", "--context",
        "--after-context", "--before-context", "--replace", "--sort", "--sortr",
        "--ignore-file", "--threads", "--encoding", "--max-filesize", "--pre", "--pre-glob",
        "--path-separator", "--context-separator", "--colors", "--color", "--engine"
    ]

    private static func grepOrRgPathOperands(argv: [String], optionsTakingArg: Set<String>) -> [String] {
        guard argv.count > 1 else { return [] }
        var nonOptions: [String] = []
        var patternProvided = false
        scanGrepArguments(
            argv: argv,
            optionsTakingArg: optionsTakingArg,
            nonOptions: &nonOptions,
            patternProvided: &patternProvided
        )

        if patternProvided {
            return nonOptions
        }
        guard nonOptions.count > 1 else { return [] }
        return Array(nonOptions.dropFirst())
    }

    private static func scanGrepArguments(
        argv: [String],
        optionsTakingArg: Set<String>,
        nonOptions: inout [String],
        patternProvided: inout Bool
    ) {
        var i = 1
        let patternFlags: Set<String> = ["-e", "-f", "--regexp", "--file"]
        let prefixFlags: [String] = ["-e", "--regexp=", "--file="]

        while i < argv.count {
            let arg = argv[i]
            if arg == "--" {
                nonOptions.append(contentsOf: argv.dropFirst(i + 1))
                break
            }
            if arg.hasPrefix("-") {
                if patternFlags.contains(arg) {
                    patternProvided = true
                    i += skipOptionValue(argv, from: i)
                    continue
                }
                if prefixFlags.contains(where: { arg.hasPrefix($0) }) {
                    patternProvided = true
                    i += 1
                    continue
                }
                if optionsTakingArg.contains(arg) {
                    i += skipOptionValue(argv, from: i)
                    continue
                }
                i += 1
                continue
            }
            nonOptions.append(arg)
            i += 1
        }
    }

    private static func skipOptionValue(_ argv: [String], from index: Int) -> Int {
        index + 1 < argv.count ? 2 : 1
    }

    /// 검색 명령(find, grep, rg)의 인자가 세션 디렉터리 루트를 동시에 몇 개나 가리키는지 센다.
    static func countSessionHuntHits(command: String, sessionRoots: [String], home: String) -> Int {
        let cmdStrings = ShellCommandSplitter.split(command)
        let homeStd = (home as NSString).standardizingPath
        var maxHits = 0
        let searchTools: Set<String> = ["find", "grep", "rg"]

        for rawCmd in cmdStrings {
            let argv = stripCommandWrappers(ShellArgvLexer.parseArgv(rawCmd))
            guard let argv0 = argv.first else { continue }
            let exe = (argv0 as NSString).lastPathComponent
            guard searchTools.contains(exe) || grepTools.contains(exe) else { continue }

            let hits = countRootHits(in: Array(argv.dropFirst()), sessionRoots: sessionRoots, homeStd: homeStd)
            if hits > maxHits { maxHits = hits }
        }
        return maxHits
    }

    private static func countRootHits(in args: [String], sessionRoots: [String], homeStd: String) -> Int {
        var matchedRoots = Set<String>()
        for root in sessionRoots {
            let rel = root.hasPrefix(".") ? root : "." + root
            if argsMatchRoot(args, rel: rel, homeStd: homeStd) {
                matchedRoots.insert(root)
            }
        }
        return matchedRoots.count
    }

    private static func argsMatchRoot(_ args: [String], rel: String, homeStd: String) -> Bool {
        let pHome = homeStd + "/" + rel
        let pDollar = "$HOME/" + rel
        let pBraced = "${HOME}/" + rel
        let pTilde = "~/" + rel

        for arg in args {
            let matchesLiteral = arg.contains(pHome) || arg.contains(pDollar)
            if matchesLiteral { return true }
            let matchesTildeOrBrace = arg.contains(pBraced) || arg.contains(pTilde)
            if matchesTildeOrBrace { return true }

            let std = ((arg as NSString).expandingTildeInPath as NSString).standardizingPath
            let stdMatch = std == pHome || std.hasPrefix(pHome + "/")
            if stdMatch { return true }
        }
        return false
    }
}
