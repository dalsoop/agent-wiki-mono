#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation
import GameUIAssetKit

private struct ValidationEnvelope: Encodable {
    let valid: Bool
    let diagnostics: [GameUIManifestDiagnostic]
}

@main
struct GameUIManifestCheck {
    static func main() {
        exit(run(arguments: Array(CommandLine.arguments.dropFirst())))
    }

    private static func run(arguments: [String]) -> Int32 {
        guard
            arguments.count == 5,
            arguments[0] == "validate",
            arguments[2] == "--asset-root",
            arguments[4] == "--json"
        else {
            writeError("usage: game-ui-manifest-check validate <screen.json> --asset-root <directory> --json")
            return 64
        }

        let manifestURL = URL(fileURLWithPath: arguments[1])
        let assetRoot = URL(fileURLWithPath: arguments[3], isDirectory: true)
        guard FileManager.default.isReadableFile(atPath: manifestURL.path) else {
            writeError("input file is missing or unreadable: \(manifestURL.path)")
            return 66
        }

        do {
            let data = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(GameUIScreenManifest.self, from: data)
            let diagnostics = GameUIManifestValidator.validate(manifest, assetRoot: assetRoot)
            try writeJSON(ValidationEnvelope(valid: diagnostics.isEmpty, diagnostics: diagnostics))
            return diagnostics.isEmpty ? 0 : 1
        } catch {
            writeError("failed to validate manifest: \(error.localizedDescription)")
            return 1
        }
    }

    private static func writeJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(value)
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
