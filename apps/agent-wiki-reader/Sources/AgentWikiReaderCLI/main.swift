import SingleInstanceKit
import Foundation
import InteropKit
import AgentWikiReaderCore
import AppScaffoldKit
import AppPathsKit
import LocalizationKit
import CommandKit

SingleInstanceCLI.autoGuard()

@main
enum AgentWikiReaderCLIMain {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        GujoManaged.exitIfNotEntitledSync()
        switch args.first ?? "help" {
        case "help", "-h", "--help":
            printUsage()
        case "version", "-V", "--version":
            print("agent-wiki-reader 0.1.0-report")
        case "status":
            print(await AgentWikiReaderService().status())
        case "capabilities":
            emitCapabilities()
        case "open":
            openGUI()
        default:
            await forwardProxy(args: args)
        }
    }

    private static func printUsage() {
        print(
            """
            agent-wiki-reader — Agent Wiki 보고용 (읽기 전용)

            Built-in: capabilities | version | help | open | status
            Proxy: list show search context path … (publish 거절)

            agent-wiki-reader status
            agent-wiki-reader capabilities
            agent-wiki-reader list
            agent-wiki-reader show e0d0f5f4
            agent-wiki-reader --world person-personal search 키워드
            agent-wiki-reader --world gujo-wiki list

            로컬 1인칭은 person-<테넌트>, 원격 공유는 gujo-wiki.

            쓰기: agent-wiki-studio 또는 agent-wiki
            """
        )
    }

    private static func emitCapabilities() {
        let caps = InteropKit.Capabilities(
            name: "agent-wiki-reader",
            version: CLIMarketingVersion.current(),
            cli: HostPlatform.cliBinPath("agent-wiki-reader"),
            commands: [
                .init(name: "capabilities", summary: "계약", json: true),
                .init(name: "help", summary: "도움말", json: false),
                .init(name: "status", summary: "world list", json: false),
                .init(name: "version", summary: "버전", json: false),
                .init(name: "open", summary: "GUI", json: false),
                .init(name: "blob", summary: "읽기 전용 blob 프록시", json: false),
                .init(name: "event", summary: "읽기 전용 event 프록시", json: false),
                .init(name: "fleet", summary: "읽기 전용 fleet 프록시", json: false),
                .init(name: "graph", summary: "읽기 전용 graph 프록시", json: false),
                .init(name: "gujo", summary: "읽기 전용 gujo 프록시", json: false),
                .init(name: "world", summary: "읽기 전용 world 프록시", json: false),
            ],
            state: [
                .init(
                    path: DurableAppLayout.tildePath(DurableAppLayout.sqliteURL(slug: "agent-wiki-reader")),
                    what: "설정·작업 sqlite (정본)"
                ),
                .init(
                    path: "~/.swift-app-state/agent-wiki-reader.json",
                    what: "보고용 상태"
                ),
            ],
            health: .init(
                command: "\(HostPlatform.cliBinPath("agent-wiki-reader")) capabilities",
                freshness: "~/.swift-app-state/agent-wiki-reader.json"
            ),
            depends: []
        )
        do {
            let data = try Envelope.ok(caps)
            print(String(data: data, encoding: .utf8) ?? "{}")
        } catch {
            fputs(CLILocalization.format("main.fputs", error.localizedDescription), stderr)
            exit(1)
        }
    }

    private static func openGUI() {
        let safeResult = SafeProcessRunner.run(
            "/usr/bin/open",
            ["-a", "Agent Wiki Reader"]
        )
        } catch {
            fputs(CLILocalization.format("main.fputs-2", error.localizedDescription), stderr)
            exit(1)
        }
    }

    private static func forwardProxy(args: [String]) async {
        let r = await AgentWikiReaderService().forward(args: args)
        if !r.stdout.isEmpty {
            fputs(r.stdout.hasSuffix("\n") ? r.stdout : r.stdout + "\n", stdout)
        }
        if !r.stderr.isEmpty { fputs(r.stderr, stderr) }
        if r.exitCode != 0 { exit(r.exitCode) }
    }
}
