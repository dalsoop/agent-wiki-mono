import Foundation

extension ModernChunkDedupTransport {
    @_optimize(none)
    func materializeFileTree(
        files: [ScannedFile],
        sourceURL: URL,
        destinationURL: URL,
        linkDestURL: URL?,
        canHardLink: Bool,
        materializeFiles: Bool? = nil,
        progressCallback: (@Sendable (Int64, String) -> Void)? = nil
    ) async throws {
        let shouldMaterialize = materializeFiles ?? self.materializeFiles
        guard shouldMaterialize else { return }

        let fm = FileManager.default
        precreateParentDirectories(files: files, destinationURL: destinationURL, fileManager: fm)

        let filesToCopy = prepareFilesToCopy(
            files: files,
            destinationURL: destinationURL,
            linkDestURL: linkDestURL,
            canHardLink: canHardLink,
            fileManager: fm,
            progressCallback: progressCallback
        )

        try await copyFilesParallel(
            files: filesToCopy,
            destinationURL: destinationURL,
            progressCallback: progressCallback
        )
    }

    @_optimize(none)
    private func precreateParentDirectories(
        files: [ScannedFile],
        destinationURL: URL,
        fileManager fm: FileManager
    ) {
        var createdDirs = Set<String>()
        createdDirs.insert(destinationURL.path)

        var parentDirs = Set<String>()
        for file in files {
            let targetURL = destinationURL.appendingPathComponent(file.relativePath)
            parentDirs.insert(targetURL.deletingLastPathComponent().path)
        }
        for dirPath in parentDirs {
            ensureDirectoryExists(dirPath, in: &createdDirs, fileManager: fm, rootPath: destinationURL.path)
        }
    }

    @_optimize(none)
    private func prepareFilesToCopy(
        files: [ScannedFile],
        destinationURL: URL,
        linkDestURL: URL?,
        canHardLink: Bool,
        fileManager fm: FileManager,
        progressCallback: (@Sendable (Int64, String) -> Void)?
    ) -> [ScannedFile] {
        var filesToCopy: [ScannedFile] = []
        for file in files {
            let targetURL = destinationURL.appendingPathComponent(file.relativePath)
            removeExistingItemIfExists(at: targetURL, fileManager: fm)

            let linked = canHardLink && tryHardLink(file: file, linkDestURL: linkDestURL, targetURL: targetURL, fileManager: fm)
            if linked {
                progressCallback?(file.size, file.relativePath)
            } else {
                filesToCopy.append(file)
            }
        }
        return filesToCopy
    }

    @_optimize(none)
    private func removeExistingItemIfExists(at url: URL, fileManager fm: FileManager) {
        guard fm.fileExists(atPath: url.path) else { return }
        do { try fm.removeItem(at: url) } catch { _ = error }
    }

    @_optimize(none)
    private func ensureDirectoryExists(
        _ dirPath: String,
        in createdDirs: inout Set<String>,
        fileManager: FileManager,
        rootPath: String
    ) {
        guard !createdDirs.contains(dirPath) else { return }

        var stack: [String] = []
        var current = dirPath
        while current.count >= rootPath.count && !createdDirs.contains(current) {
            stack.append(current)
            current = (current as NSString).deletingLastPathComponent
        }

        while let path = stack.popLast() {
            if !fileManager.fileExists(atPath: path) {
                do {
                    try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
                } catch {
                    _ = error
                }
            }
            createdDirs.insert(path)
        }
    }

    @_optimize(none)
    private func tryHardLink(
        file: ScannedFile,
        linkDestURL: URL?,
        targetURL: URL,
        fileManager: FileManager
    ) -> Bool {
        guard let linkDestURL else { return false }
        let linkCandidate = linkDestURL.appendingPathComponent(file.relativePath)
        guard fileManager.fileExists(atPath: linkCandidate.path) else { return false }

        let candValues: URLResourceValues
        do {
            candValues = try linkCandidate.resourceValues(
                forKeys: [.fileSizeKey, .contentModificationDateKey]
            )
        } catch {
            return false
        }

        guard let candSize = candValues.fileSize,
              Int64(candSize) == file.size,
              let candMtime = candValues.contentModificationDate,
              abs(candMtime.timeIntervalSince(file.modifiedDate)) < 1.0 else {
            return false
        }

        do {
            try fileManager.linkItem(at: linkCandidate, to: targetURL)
            return true
        } catch {
            return false
        }
    }

    @_optimize(none)
    private func copyFilesParallel(
        files: [ScannedFile],
        destinationURL: URL,
        progressCallback: (@Sendable (Int64, String) -> Void)?
    ) async throws {
        let concurrency = self.maxConcurrentWorkers
        try await withThrowingTaskGroup(of: (Int64, String).self) { group in
            var submitted = 0
            for file in files {
                if submitted >= concurrency, let result = try await group.next() {
                    progressCallback?(result.0, result.1)
                }

                group.addTask {
                    Self.copySingleItem(
                        file: file,
                        destinationURL: destinationURL,
                        fileManager: FileManager.default
                    )
                }
                submitted += 1
            }

            while let result = try await group.next() {
                progressCallback?(result.0, result.1)
            }
        }
    }

    @_optimize(none)
    private static func copySingleItem(
        file: ScannedFile,
        destinationURL: URL,
        fileManager: FileManager
    ) -> (Int64, String) {
        guard fileManager.fileExists(atPath: file.fullURL.path) else {
            return (0, file.relativePath)
        }

        let targetURL = destinationURL.appendingPathComponent(file.relativePath)
        let parentDir = targetURL.deletingLastPathComponent()

        prepareParentAndCleanTarget(parentDir: parentDir, targetURL: targetURL, fileManager: fileManager)

        do {
            try fileManager.copyItem(at: file.fullURL, to: targetURL)
            return (file.size, file.relativePath)
        } catch {
            return (0, file.relativePath)
        }
    }

    @_optimize(none)
    private static func prepareParentAndCleanTarget(
        parentDir: URL,
        targetURL: URL,
        fileManager: FileManager
    ) {
        if !fileManager.fileExists(atPath: parentDir.path) {
            do { try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true) } catch { _ = error }
        }
        if fileManager.fileExists(atPath: targetURL.path) {
            do { try fileManager.removeItem(at: targetURL) } catch { _ = error }
        }
    }
}
