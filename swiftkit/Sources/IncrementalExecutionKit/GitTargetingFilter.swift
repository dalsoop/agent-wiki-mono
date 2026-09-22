import Foundation

/// Git 상태(Staged, Unstaged, Untracked, 브랜치 Diff)를 분석하여 실제 변경된 파일만 타깃팅하는 필터.
public enum GitTargetingFilter {

    /// 워크스페이스 내에서 실제로 변경되었거나 추가된 소스 파일 목록을 추출.
    ///
    /// - Parameters:
    ///   - root: 레포지토리 루트 경로
    ///   - baseBranch: 비교 대상 기준 브랜치 (기본: "origin/main...HEAD")
    /// - Returns: root 기준 상대 경로 목록
    public static func detectChangedFiles(root: String, baseBranch: String = "origin/main...HEAD") -> [String] {
        var rawPaths = Set<String>()

        // 1. git status --porcelain (Staged, Unstaged, Untracked)
        if let statusOutput = runCommand("git status --porcelain", currentDirectory: root) {
            for line in statusOutput.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.count > 3 else { continue }
                // 포맷: "XY filename" 또는 "XY orig -> new"
                let filePart = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if filePart.contains(" -> ") {
                    let parts = filePart.components(separatedBy: " -> ")
                    if let target = parts.last {
                        rawPaths.insert(target.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
                    }
                } else {
                    rawPaths.insert(filePart.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
                }
            }
        }

        // 2. git diff --name-only (기본 브랜치 대비 커밋된 변경사항)
        if let diffOutput = runCommand("git diff --name-only \(baseBranch)", currentDirectory: root) {
            for line in diffOutput.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    rawPaths.insert(trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
                }
            }
        }

        // 3. 실제 파일 실존 및 유효 소스 검증 (디렉터리, .build, DerivedData 배제)
        let fm = FileManager.default
        var validFiles: [String] = []
        for path in rawPaths {
            guard !path.hasPrefix(".build/"),
                  !path.contains("/DerivedData/"),
                  !path.hasPrefix(".git/") else {
                continue
            }
            let fullPath = path.hasPrefix("/") ? path : (root + "/" + path)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue {
                validFiles.append(path)
            }
        }

        return validFiles.sorted()
    }

    private static func runCommand(_ command: String, currentDirectory: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
