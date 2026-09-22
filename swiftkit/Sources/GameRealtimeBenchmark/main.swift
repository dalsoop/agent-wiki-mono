#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation
import LocalizationKit
@_spi(GameRealtimeBenchmark) import GameRealtimeDebugKit
import GameRealtimeEngineKit
import GameRealtimeProtocolKit

enum BenchmarkCommandError: Error {
    case missingArgument(String)
    case missingFixtureResource
}

func argument(
    _ name: String,
    in arguments: [String]
) throws -> String {
    guard let position = arguments.firstIndex(of: name),
          arguments.indices.contains(position + 1)
    else {
        throw BenchmarkCommandError.missingArgument(name)
    }
    return arguments[position + 1]
}

func writeJSON<Value: Encodable>(_ value: Value) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    guard let output = String(data: data, encoding: .utf8) else {
        throw BenchmarkCommandError.missingFixtureResource
    }
    print(output)
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.contains("--determinism-input") {
        let inputPath = try argument("--determinism-input", in: arguments)
        let tickText = try argument("--ticks", in: arguments)
        guard let ticks = Int(tickText) else {
            throw BenchmarkCommandError.missingArgument("--ticks")
        }
        let input = try JSONDecoder().decode(
            CombatInputFrame.self,
            from: Data(
                contentsOf: URL(fileURLWithPath: inputPath)
            )
        )
        let fixture = try HeadlessFixture(
            configuration: GameRealtimeConfiguration(),
            inputMode: .manual
        )
        try writeJSON(fixture.run(ticks: ticks, input: input))
        exit(0)
    }

    let hostProfile = try argument("--host-profile", in: arguments)
    let fixtureID = try argument("--fixture", in: arguments)
    let baselinePath = try argument("--baseline", in: arguments)
    let sampleText = try argument("--samples", in: arguments)
    guard let samples = Int(sampleText) else {
        throw BenchmarkCommandError.missingArgument("--samples")
    }
    guard let fixtureURL = ResourceBundle.named("swiftkit_GameRealtimeBenchmark").url(
        forResource: "fixture",
        withExtension: "json",
        subdirectory: "GameRealtimeBenchmarkV1"
    ) else {
        throw BenchmarkCommandError.missingFixtureResource
    }

    let fixtureData = try Data(contentsOf: fixtureURL)
    let fixture = try JSONDecoder().decode(
        BenchmarkFixtureManifest.self,
        from: fixtureData
    )
    guard fixture.fixtureID == fixtureID else {
        throw BenchmarkError.fixtureIDMismatch(
            expected: fixture.fixtureID,
            actual: fixtureID
        )
    }
    let baselineData = try Data(
        contentsOf: URL(fileURLWithPath: baselinePath)
    )
    let baseline = try BenchmarkBaseline.decodeQualified(baselineData)
    let harness = try BenchmarkHarness(
        hostProfileID: hostProfile,
        fixtureManifest: fixture,
        baseline: baseline,
        samples: samples
    )
    try writeJSON(harness.run())
} catch {
    let message = "game-realtime-benchmark: \(error)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}
