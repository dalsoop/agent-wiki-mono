import Foundation


public enum SurfaceParityOracle {
    public static func verifyIsomorphism(
        cliData: Data,
        guiData: Data,
        configuration: Configuration = Configuration()
    ) throws -> ParityVerdict {
        let cliParsed = try JSONSerialization.jsonObject(with: cliData, options: [.fragmentsAllowed])
        let guiParsed = try JSONSerialization.jsonObject(with: guiData, options: [.fragmentsAllowed])

        let cliNormalized = normalizeTopLevel(cliParsed, unwrap: configuration.unwrapTopLevelEnvelope)
        let guiNormalized = normalizeTopLevel(guiParsed, unwrap: configuration.unwrapTopLevelEnvelope)

        var differences: [ParityDiff] = []
        var nodeCount = 0

        compareValues(
            cli: cliNormalized,
            gui: guiNormalized,
            currentPath: "$",
            configuration: configuration,
            differences: &differences,
            nodeCount: &nodeCount
        )

        return ParityVerdict(
            isIsomorphic: differences.isEmpty,
            differences: differences,
            comparedNodesCount: nodeCount
        )
    }

    public static func diff(
        cliData: Data,
        guiData: Data,
        configuration: Configuration = Configuration()
    ) throws -> ParityVerdict {
        try verifyIsomorphism(
            cliData: cliData,
            guiData: guiData,
            configuration: configuration
        )
    }

    public static func diff(
        cliJSON: String,
        guiJSON: String,
        configuration: Configuration = Configuration()
    ) throws -> ParityVerdict {
        guard let cliData = cliJSON.data(using: .utf8),
              let guiData = guiJSON.data(using: .utf8) else {
            throw ParityOracleError.invalidJSON
        }
        return try diff(cliData: cliData, guiData: guiData, configuration: configuration)
    }

    public static func assertIsomorphic(
        cliData: Data,
        guiData: Data,
        configuration: Configuration = Configuration()
    ) throws {
        let verdict = try verifyIsomorphism(
            cliData: cliData,
            guiData: guiData,
            configuration: configuration
        )

        if !verdict.isIsomorphic {

            throw ParityOracleError.isomorphismViolation(verdict)
        }
    }

    public static func assertIsomorphic(
        cliJSON: String,
        guiJSON: String,
        configuration: Configuration = Configuration()
    ) throws {
        guard let cliData = cliJSON.data(using: .utf8),
              let guiData = guiJSON.data(using: .utf8) else {
            throw ParityOracleError.invalidJSON
        }
        try assertIsomorphic(
            cliData: cliData,
            guiData: guiData,
            configuration: configuration
        )
    }
}
