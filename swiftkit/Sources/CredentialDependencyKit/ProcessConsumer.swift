import Foundation

private func waitWithTimeout(_ process: Process, seconds: TimeInterval = 30) {
    let item = DispatchWorkItem { process.terminate() }
    DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: item)
    process.waitUntilExit()
    item.cancel()
}

private final class LockedOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ value: Data) { lock.lock(); data.append(value); lock.unlock() }
    func snapshot() -> Data { lock.lock(); defer { lock.unlock() }; return data }
}

/// stdin 또는 환경변수로만 비밀을 전달하는 공통 프로세스 소비자. argv 전달은 지원하지 않는다.
public struct ProcessCredentialConsumer: CredentialConsuming {
    public let descriptor: CredentialConsumerDescriptor

    public init(descriptor: CredentialConsumerDescriptor) {
        self.descriptor = descriptor
    }

    public func consume(
        _ secret: CredentialSecret,
        binding: CredentialBinding
    ) async throws -> CredentialConsumptionResult {
        let executable = (descriptor.executablePath as NSString).expandingTildeInPath
        guard CredentialDependencyPolicy.executableMatches(
            expectedPath: descriptor.executablePath,
            requestedPath: executable) else {
            throw CredentialDependencyError.denied("등록 실행 경로와 다릅니다")
        }
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw CredentialDependencyError.processFailed("실행 파일이 없습니다: \(executable)")
        }
        guard descriptor.supportedDeliveries.contains(binding.delivery.kind) else {
            throw CredentialDependencyError.denied("지원하지 않는 비밀 전달 방식입니다")
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try run(
                        executable: executable,
                        arguments: binding.arguments,
                        delivery: binding.delivery,
                        secret: secret))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private func run(
    executable: String,
    arguments: [String],
    delivery: CredentialDelivery,
    secret: CredentialSecret
) throws -> CredentialConsumptionResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments

    let input = Pipe()
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error

    switch delivery.kind {
    case .stdin:
        process.standardInput = input
    case .environment:
        guard let key = delivery.environmentKey, !key.isEmpty else {
            throw CredentialDependencyError.denied("환경변수 이름이 없습니다")
        }
        var environment = ProcessInfo.processInfo.environment
        environment[key] = secret.value
        process.environment = environment
    }

    let stdout = LockedOutput()
    let stderr = LockedOutput()
    let group = DispatchGroup()
    for (handle, target) in [
        (output.fileHandleForReading, stdout),
        (error.fileHandleForReading, stderr)
    ] {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            target.append(handle.readDataToEndOfFile())
            group.leave()
        }
    }

    do { try process.run() }
    catch { throw CredentialDependencyError.processFailed("\(error)") }

    if delivery.kind == .stdin {
        input.fileHandleForWriting.write(Data((secret.value + "\n").utf8))
        try? input.fileHandleForWriting.close()
    }
    waitWithTimeout(process, seconds: 30)
    group.wait()

    let sensitive = [secret.value, secret.username].compactMap { $0 }.filter { !$0.isEmpty }
        + secret.fields.values.filter { !$0.isEmpty }
    return CredentialConsumptionResult(
        exitCode: process.terminationStatus,
        standardOutput: redact(String(decoding: stdout.snapshot(), as: UTF8.self), values: sensitive),
        standardError: redact(String(decoding: stderr.snapshot(), as: UTF8.self), values: sensitive))
}

private func redact(_ text: String, values: [String]) -> String {
    values.reduce(text) { partial, value in
        partial.replacingOccurrences(of: value, with: "[REDACTED]")
    }
}
