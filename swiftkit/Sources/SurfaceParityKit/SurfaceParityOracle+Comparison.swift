import Foundation

extension SurfaceParityOracle {
    static func compareValues(
        cli: Any,
        gui: Any,
        currentPath: String,
        configuration: Configuration,
        differences: inout [ParityDiff],
        nodeCount: inout Int
    ) {
        nodeCount += 1

        guard !compareNulls(cli: cli, gui: gui, currentPath: currentPath, differences: &differences) else { return }
        guard !compareContainers(
            cli: cli,
            gui: gui,
            currentPath: currentPath,
            configuration: configuration,
            differences: &differences,
            nodeCount: &nodeCount
        ) else { return }
        guard !compareBooleans(cli: cli, gui: gui, currentPath: currentPath, differences: &differences) else { return }
        guard !compareNumbers(cli: cli, gui: gui, currentPath: currentPath, configuration: configuration, differences: &differences) else { return }
        guard !compareStrings(cli: cli, gui: gui, currentPath: currentPath, differences: &differences) else { return }

        differences.append(
            ParityDiff(
                path: currentPath,
                kind: .typeMismatch,
                cliValue: String(describing: type(of: cli)),
                guiValue: String(describing: type(of: gui)),
                message: "Incompatible types at \(currentPath)"
            )
        )
    }

    private static func compareNulls(cli: Any, gui: Any, currentPath: String, differences: inout [ParityDiff]) -> Bool {
        let cliNull = cli is NSNull
        let guiNull = gui is NSNull
        guard cliNull || guiNull else { return false }
        if cliNull != guiNull {
            differences.append(
                ParityDiff(
                    path: currentPath,
                    kind: .typeMismatch,
                    cliValue: String(describing: cli),
                    guiValue: String(describing: gui),
                    message: "Nullability mismatch at \(currentPath)"
                )
            )
        }
        return true
    }

    private static func compareContainers(
        cli: Any,
        gui: Any,
        currentPath: String,
        configuration: Configuration,
        differences: inout [ParityDiff],
        nodeCount: inout Int
    ) -> Bool {
        if let dictCLI = cli as? [String: Any], let dictGUI = gui as? [String: Any] {
            compareDictionaries(
                cli: dictCLI,
                gui: dictGUI,
                currentPath: currentPath,
                configuration: configuration,
                differences: &differences,
                nodeCount: &nodeCount
            )
            return true
        }
        if let arrCLI = cli as? [Any], let arrGUI = gui as? [Any] {
            compareArrays(
                cli: arrCLI,
                gui: arrGUI,
                currentPath: currentPath,
                configuration: configuration,
                differences: &differences,
                nodeCount: &nodeCount
            )
            return true
        }
        return false
    }

    private static func compareBooleans(cli: Any, gui: Any, currentPath: String, differences: inout [ParityDiff]) -> Bool {
        let isBoolCLI = isBoolean(cli)
        let isBoolGUI = isBoolean(gui)
        guard isBoolCLI || isBoolGUI else { return false }
        guard isBoolCLI && isBoolGUI else {
            differences.append(
                ParityDiff(
                    path: currentPath,
                    kind: .typeMismatch,
                    cliValue: String(describing: cli),
                    guiValue: String(describing: gui),
                    message: "Type mismatch boolean at \(currentPath)"
                )
            )
            return true
        }
        let bCLI = (cli as? Bool) ?? false
        let bGUI = (gui as? Bool) ?? false
        if bCLI != bGUI {
            differences.append(
                ParityDiff(
                    path: currentPath,
                    kind: .valueMismatch,
                    cliValue: String(bCLI),
                    guiValue: String(bGUI),
                    message: "Boolean mismatch at \(currentPath)"
                )
            )
        }
        return true
    }

    private static func compareNumbers(
        cli: Any,
        gui: Any,
        currentPath: String,
        configuration: Configuration,
        differences: inout [ParityDiff]
    ) -> Bool {
        guard let numCLI = cli as? NSNumber, let numGUI = gui as? NSNumber else { return false }
        let dCLI = numCLI.doubleValue
        let dGUI = numGUI.doubleValue
        let diff = abs(dCLI - dGUI)
        let tol = configuration.floatingPointTolerance ?? 0.0
        if diff > tol {
            differences.append(
                ParityDiff(
                    path: currentPath,
                    kind: .valueMismatch,
                    cliValue: numCLI.stringValue,
                    guiValue: numGUI.stringValue,
                    message: "Number mismatch at \(currentPath)"
                )
            )
        }
        return true
    }

    private static func compareStrings(cli: Any, gui: Any, currentPath: String, differences: inout [ParityDiff]) -> Bool {
        guard let strCLI = cli as? String, let strGUI = gui as? String else { return false }
        if strCLI != strGUI {
            differences.append(
                ParityDiff(
                    path: currentPath,
                    kind: .valueMismatch,
                    cliValue: strCLI,
                    guiValue: strGUI,
                    message: "String mismatch at \(currentPath)"
                )
            )
        }
        return true
    }

    private static func compareDictionaries(
        cli: [String: Any],
        gui: [String: Any],
        currentPath: String,
        configuration: Configuration,
        differences: inout [ParityDiff],
        nodeCount: inout Int
    ) {
        let filteredCLIKeys = Set(cli.keys).subtracting(configuration.ignoredKeys)
        let filteredGUIKeys = Set(gui.keys).subtracting(configuration.ignoredKeys)

        for key in filteredCLIKeys.subtracting(filteredGUIKeys).sorted() {
            let itemPath = currentPath == "$" ? key : "\(currentPath).\(key)"
            differences.append(
                ParityDiff(
                    path: itemPath,
                    kind: .missingKeyInGUI,
                    cliValue: String(describing: cli[key] ?? ""),
                    guiValue: nil,
                    message: "Key '\(key)' missing in GUI"
                )
            )
        }

        for key in filteredGUIKeys.subtracting(filteredCLIKeys).sorted() {
            let itemPath = currentPath == "$" ? key : "\(currentPath).\(key)"
            differences.append(
                ParityDiff(
                    path: itemPath,
                    kind: .missingKeyInCLI,
                    cliValue: nil,
                    guiValue: String(describing: gui[key] ?? ""),
                    message: "Key '\(key)' missing in CLI"
                )
            )
        }

        for key in filteredCLIKeys.intersection(filteredGUIKeys).sorted() {
            let itemPath = currentPath == "$" ? key : "\(currentPath).\(key)"
            guard let valCLI = cli[key], let valGUI = gui[key] else { continue }
            compareValues(
                cli: valCLI,
                gui: valGUI,
                currentPath: itemPath,
                configuration: configuration,
                differences: &differences,
                nodeCount: &nodeCount
            )
        }
    }

    private static func compareArrays(
        cli: [Any],
        gui: [Any],
        currentPath: String,
        configuration: Configuration,
        differences: inout [ParityDiff],
        nodeCount: inout Int
    ) {
        guard cli.count == gui.count else {
            differences.append(
                ParityDiff(
                    path: currentPath,
                    kind: .arrayLengthMismatch,
                    cliValue: String(cli.count),
                    guiValue: String(gui.count),
                    message: "Array count mismatch at \(currentPath)"
                )
            )
            return
        }

        switch configuration.arrayMode {
        case .ordered:
            compareOrderedArrays(
                cli: cli,
                gui: gui,
                currentPath: currentPath,
                configuration: configuration,
                differences: &differences,
                nodeCount: &nodeCount
            )
        case .unordered:
            compareUnorderedArrays(
                cli: cli,
                gui: gui,
                currentPath: currentPath,
                configuration: configuration,
                differences: &differences,
                nodeCount: &nodeCount
            )
        }
    }

    private static func compareOrderedArrays(
        cli: [Any],
        gui: [Any],
        currentPath: String,
        configuration: Configuration,
        differences: inout [ParityDiff],
        nodeCount: inout Int
    ) {
        for i in 0..<cli.count {
            compareValues(
                cli: cli[i],
                gui: gui[i],
                currentPath: "\(currentPath)[\(i)]",
                configuration: configuration,
                differences: &differences,
                nodeCount: &nodeCount
            )
        }
    }

    private static func compareUnorderedArrays(
        cli: [Any],
        gui: [Any],
        currentPath: String,
        configuration: Configuration,
        differences: inout [ParityDiff],
        nodeCount: inout Int
    ) {
        var matchedGUIIndices: Set<Int> = []
        for (cliIdx, cliItem) in cli.enumerated() {
            let match = findMatchingIndex(
                item: cliItem,
                candidates: gui,
                excludedIndices: matchedGUIIndices,
                path: "\(currentPath)[\(cliIdx)]",
                configuration: configuration
            )
            guard let matchedIdx = match else {
                differences.append(
                    ParityDiff(
                        path: "\(currentPath)[\(cliIdx)]",
                        kind: .valueMismatch,
                        cliValue: String(describing: cliItem),
                        guiValue: nil,
                        message: "Element had no counterpart in GUI array"
                    )
                )
                continue
            }
            matchedGUIIndices.insert(matchedIdx)
        }
    }

    private static func findMatchingIndex(
        item: Any,
        candidates: [Any],
        excludedIndices: Set<Int>,
        path: String,
        configuration: Configuration
    ) -> Int? {
        for (idx, candidate) in candidates.enumerated() where !excludedIndices.contains(idx) {
            var localDiffs: [ParityDiff] = []
            var localNodes = 0
            compareValues(
                cli: item,
                gui: candidate,
                currentPath: path,
                configuration: configuration,
                differences: &localDiffs,
                nodeCount: &localNodes
            )
            if localDiffs.isEmpty {
                return idx
            }
        }
        return nil
    }

    static func normalizeTopLevel(_ json: Any, unwrap: Bool) -> Any {
        guard unwrap, let dict = json as? [String: Any] else { return json }
        if dict.count == 2 && dict["ok"] != nil && dict["result"] != nil {
            return dict["result"] ?? json
        }
        if dict.count == 2 && dict["ok"] != nil && dict["state"] != nil {
            return dict["state"] ?? json
        }
        return json
    }

    private static func isBoolean(_ value: Any) -> Bool {
        if value is Bool { return true }
        guard let num = value as? NSNumber else { return false }
        return CFGetTypeID(num) == CFBooleanGetTypeID()
    }
}
