import Foundation

public enum GameUIManifestValidator {
    public static func validate(
        _ manifest: GameUIScreenManifest,
        assetRoot: URL
    ) -> [GameUIManifestDiagnostic] {
        var diagnostics: [GameUIManifestDiagnostic] = []

        if manifest.schemaVersion != GameUIAssetKit.schemaVersion {
            diagnostics.append(
                diagnostic(
                    .unsupportedSchema,
                    "Schema \(manifest.schemaVersion) is unsupported; expected \(GameUIAssetKit.schemaVersion).",
                    subjectID: manifest.id
                )
            )
        }

        let componentsByID = Dictionary(
            manifest.components.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var componentIDByHash: [String: String] = [:]

        for component in manifest.components {
            guard let asset = component.asset else { continue }

            if asset.provenance.classification == .referenceOnly {
                diagnostics.append(
                    diagnostic(
                        .referenceInRuntime,
                        "Reference-only assets cannot appear in a runtime manifest.",
                        subjectID: component.id
                    )
                )
            }

            if let firstID = componentIDByHash[asset.sha256], firstID != component.id {
                diagnostics.append(
                    diagnostic(
                        .duplicateComponentHash,
                        "Asset hash is already owned by component '\(firstID)'; reuse it through instances.",
                        subjectID: component.id
                    )
                )
            } else {
                componentIDByHash[asset.sha256] = component.id
            }

            if asset.bakedDynamicContent == true {
                diagnostics.append(
                    diagnostic(
                        .dynamicValueBaked,
                        "Dynamic values must be rendered from bindings instead of baked into the asset.",
                        subjectID: component.id
                    )
                )
            }

            if escapesAssetRoot(asset.path, assetRoot: assetRoot) {
                diagnostics.append(
                    diagnostic(
                        .pathEscape,
                        "Asset path escapes the declared asset root.",
                        subjectID: component.id
                    )
                )
            }
        }

        let interactionsByInstanceID = Dictionary(
            grouping: manifest.interactions,
            by: \.instanceID
        )
        let instanceIDs = Set(manifest.instances.map(\.id))

        for instance in manifest.instances {
            guard let component = componentsByID[instance.componentID] else {
                diagnostics.append(
                    diagnostic(
                        .missingComponent,
                        "Instance references undefined component '\(instance.componentID)'.",
                        subjectID: instance.id
                    )
                )
                continue
            }

            if !instance.allowsOverflow && isOutOfBounds(instance.frame, canvas: manifest.canvas) {
                diagnostics.append(
                    diagnostic(
                        .outOfBounds,
                        "Instance frame exceeds the design canvas.",
                        subjectID: instance.id
                    )
                )
            }

            if component.kind == .buttonSkin {
                let hasAction = interactionsByInstanceID[instance.id]?.contains {
                    !$0.actionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                } == true
                if !hasAction {
                    diagnostics.append(
                        diagnostic(
                            .missingAction,
                            "Button instances require a non-empty action ID.",
                            subjectID: instance.id
                        )
                    )
                }
            }
        }

        for binding in manifest.bindings {
            if let targetID = binding.targetInstanceID, !instanceIDs.contains(targetID) {
                diagnostics.append(
                    diagnostic(
                        .missingComponent,
                        "Binding targets undefined instance '\(targetID)'.",
                        subjectID: binding.id
                    )
                )
            }
        }

        for interaction in manifest.interactions {
            if !instanceIDs.contains(interaction.instanceID) {
                diagnostics.append(
                    diagnostic(
                        .missingComponent,
                        "Interaction targets undefined instance '\(interaction.instanceID)'.",
                        subjectID: interaction.instanceID
                    )
                )
            }
            if interaction.actionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                diagnostics.append(
                    diagnostic(
                        .missingAction,
                        "Interactive instances require a non-empty action ID.",
                        subjectID: interaction.instanceID
                    )
                )
            }
            if interaction.accessibilityLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                diagnostics.append(
                    diagnostic(
                        .missingAccessibilityLabel,
                        "Interactive instances require an accessibility label.",
                        subjectID: interaction.instanceID
                    )
                )
            }
        }

        return diagnostics
    }

    private static func diagnostic(
        _ code: GameUIManifestDiagnostic.Code,
        _ message: String,
        subjectID: String?
    ) -> GameUIManifestDiagnostic {
        GameUIManifestDiagnostic(code: code, message: message, subjectID: subjectID)
    }

    private static func escapesAssetRoot(_ path: String, assetRoot: URL) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/") else { return true }
        let components = NSString(string: path).pathComponents
        guard !components.contains("..") else { return true }

        let root = assetRoot.standardizedFileURL.path
        let candidate = assetRoot.appendingPathComponent(path).standardizedFileURL.path
        return candidate != root && !candidate.hasPrefix(root + "/")
    }

    private static func isOutOfBounds(_ frame: GameUIRect, canvas: GameUICanvas) -> Bool {
        frame.x < 0
            || frame.y < 0
            || frame.width < 0
            || frame.height < 0
            || frame.x + frame.width > canvas.width
            || frame.y + frame.height > canvas.height
    }
}
