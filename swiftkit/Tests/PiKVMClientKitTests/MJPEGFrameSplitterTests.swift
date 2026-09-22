import Foundation
import Testing

@testable import PiKVMClientKit

/// 실측 스트림 형식으로 만든 multipart 조각.
/// PiKVM 4.121 의 `/streamer/stream` 은 경계 `--boundarydonotcross` 에
/// `Content-Type`/`Content-Length`/`X-Timestamp` 헤더를 붙여 보낸다.
private func multipartPart(payload: Data) -> Data {
    var out = Data(
        """
        --boundarydonotcross\r
        Content-Type: image/jpeg\r
        Content-Length: \(payload.count)\r
        X-Timestamp: 1786361515.793000\r
        \r

        """.utf8)
    out.append(payload)
    out.append(Data("\r\n".utf8))
    return out
}

/// 최소한의 "JPEG 처럼 보이는" 바이트 — SOI…EOI.
private func fakeJPEG(marker: UInt8, size: Int = 32) -> Data {
    var data = Data([0xFF, 0xD8])
    data.append(Data(repeating: marker, count: size))
    data.append(Data([0xFF, 0xD9]))
    return data
}

@Suite("MJPEG 프레임 분리")
struct MJPEGFrameSplitterTests {

    @Test("멀티파트 헤더를 걷어내고 프레임만 돌려준다")
    func extractsFrameFromRealFraming() {
        let payload = fakeJPEG(marker: 0xAA)
        var splitter = MJPEGFrameSplitter()
        let frames = splitter.append(multipartPart(payload: payload))

        #expect(frames.count == 1)
        #expect(frames.first == payload)
        // 프레임을 내보낸 뒤 버퍼에 꼬리(\r\n)만 남고 계속 자라지 않아야 한다.
        #expect(splitter.bufferedByteCount <= 2)
    }

    @Test("한 번에 여러 프레임이 도착해도 순서대로 모두 꺼낸다")
    func handlesMultipleFramesInOneChunk() {
        let a = fakeJPEG(marker: 0x11)
        let b = fakeJPEG(marker: 0x22)
        var chunk = multipartPart(payload: a)
        chunk.append(multipartPart(payload: b))

        var splitter = MJPEGFrameSplitter()
        let frames = splitter.append(chunk)
        #expect(frames == [a, b])
    }

    @Test("프레임이 여러 콜백에 쪼개져 와도 붙여서 낸다")
    func reassemblesFrameSplitAcrossChunks() {
        let payload = fakeJPEG(marker: 0x33, size: 200)
        let whole = multipartPart(payload: payload)
        var splitter = MJPEGFrameSplitter()

        // 실제 URLSession 은 임의 크기로 잘라 준다. 도중엔 아무것도 나오면 안 된다.
        var produced: [Data] = []
        var index = whole.startIndex
        while index < whole.endIndex {
            let end = min(index + 37, whole.endIndex)
            produced += splitter.append(Data(whole[index..<end]))
            index = end
        }
        #expect(produced == [payload])
    }

    @Test("덜 온 프레임은 버리지 않고 기다린다")
    func keepsPartialFrameBuffered() {
        var splitter = MJPEGFrameSplitter()
        var partial = Data([0xFF, 0xD8])
        partial.append(Data(repeating: 0x44, count: 100))

        // EOI 가 아직 안 왔다 — 여기서 버리면 매 프레임 한 장씩 잃는다.
        #expect(splitter.append(partial).isEmpty)
        #expect(splitter.bufferedByteCount == partial.count)

        let frames = splitter.append(Data([0xFF, 0xD9]))
        #expect(frames.count == 1)
        #expect(frames[0].count == partial.count + 2)
    }

    @Test("SOI 앞의 잡음은 버퍼를 무한히 키우지 않는다")
    func discardsLeadingNoise() {
        var splitter = MJPEGFrameSplitter()
        for _ in 0..<10 {
            _ = splitter.append(Data(repeating: 0x5A, count: 4096))
        }
        // 경계에 걸친 SOI 를 놓치지 않으려 1바이트만 남긴다.
        #expect(splitter.bufferedByteCount <= 1)
    }

    @Test("SOI 가 청크 경계에 걸쳐 와도 프레임을 놓치지 않는다")
    func findsSOISplitAcrossChunkBoundary() {
        var splitter = MJPEGFrameSplitter()
        // 잡음이 0xFF 로 끝나고 다음 청크가 0xD8 로 시작한다 — 잡음을 통째로 버리면 영영 못 찾는다.
        var noise = Data(repeating: 0x5A, count: 64)
        noise.append(0xFF)
        #expect(splitter.append(noise).isEmpty)

        var rest = Data([0xD8])
        rest.append(Data(repeating: 0x99, count: 16))
        rest.append(Data([0xFF, 0xD9]))
        let frames = splitter.append(rest)
        #expect(frames.count == 1)
        #expect(frames[0].prefix(2) == Data([0xFF, 0xD8]))
    }

    /// 실장비에서 받아 둔 스트림 덤프로 검증한다. 덤프는 크기 때문에 저장소에 넣지 않으므로
    /// 경로를 환경변수로 준다(없으면 건너뛴다):
    ///   curl -sk --max-time 6 -H 'X-KVMD-User: …' -H 'X-KVMD-Passwd: …' \
    ///     https://<장비>/streamer/stream > /tmp/live.mjpeg
    ///   PIKVM_MJPEG_FIXTURE=/tmp/live.mjpeg swift test --filter MJPEG
    @Test("실장비 스트림 덤프에서 Content-Length 와 같은 길이로 프레임을 뽑는다")
    func matchesRealDeviceDump() throws {
        guard let path = ProcessInfo.processInfo.environment["PIKVM_MJPEG_FIXTURE"] else { return }
        let dump = try Data(contentsOf: URL(fileURLWithPath: path))

        // 덤프의 첫 파트 헤더가 광고하는 길이 — 이게 정답지다.
        let header = String(decoding: dump.prefix(200), as: UTF8.self)
        let advertised = header
            .split(separator: "\r\n")
            .first { $0.hasPrefix("Content-Length:") }
            .flatMap { Int($0.dropFirst("Content-Length:".count).trimmingCharacters(in: .whitespaces)) }

        var splitter = MJPEGFrameSplitter()
        var frames: [Data] = []
        var index = dump.startIndex
        while index < dump.endIndex {
            // 임의 크기로 흘려 넣어 실제 소켓 도착 패턴을 흉내낸다.
            let end = min(index + 4096, dump.endIndex)
            frames += splitter.append(Data(dump[index..<end]))
            index = end
        }

        #expect(!frames.isEmpty, "덤프에서 프레임을 하나도 못 뽑았다")
        if let advertised { #expect(frames[0].count == advertised) }
        // 모든 프레임이 JPEG 마커로 시작하고 끝나야 한다.
        for frame in frames {
            #expect(frame.prefix(2) == Data([0xFF, 0xD8]))
            #expect(frame.suffix(2) == Data([0xFF, 0xD9]))
        }
    }

    @Test("버퍼 상한을 넘으면 버리고 다음 프레임부터 회복한다")
    func recoversAfterOverflow() {
        var splitter = MJPEGFrameSplitter(maxBufferBytes: 1024)
        var runaway = Data([0xFF, 0xD8])
        runaway.append(Data(repeating: 0x66, count: 4096))  // EOI 없이 커지기만 한다
        #expect(splitter.append(runaway).isEmpty)
        #expect(splitter.bufferedByteCount == 0)

        let payload = fakeJPEG(marker: 0x77)
        #expect(splitter.append(multipartPart(payload: payload)) == [payload])
    }
}
