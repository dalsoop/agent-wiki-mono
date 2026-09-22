import Foundation

/// 설치본이 소스 대비 최신인지 판정하는 **공용** 로직(app-build-manager·store 공유).
///
/// 이 워크스페이스는 로컬 소스빌드 구조라 설치본이 자동 갱신되지 않는다 — 소스는 계속
/// 커밋되는데 `/Applications` 설치본은 마지막 ship 시점(`CFBundleVersion` = ship epoch)에
/// 멈춘다. semantic 버전(`CFBundleShortVersionString`)만 보면 코드를 고쳐도 버전 문자열을
/// 안 올리면 "최신"으로 오판한다. 그래서 **소스 파일 최종 수정시각 vs ship epoch** 를 본다.
public struct SourceFreshness: Sendable, Equatable {
    public enum State: String, Sendable {
        case upToDate      // 설치본이 소스만큼 최신
        case stale         // 소스가 설치본보다 최신(재ship 필요)
        case notInstalled
        case unknown       // 판정 불가(build 없음 등)
    }

    public var state: State
    public var installedBuild: Int?   // 설치본 build epoch(=마지막 ship). 미설치/불명이면 nil.
    public var sourceMTime: Int?      // 소스 최종 수정 epoch.

    public init(state: State, installedBuild: Int?, sourceMTime: Int?) {
        self.state = state
        self.installedBuild = installedBuild
        self.sourceMTime = sourceMTime
    }

    /// 소스가 설치본보다 며칠 앞서는지(stale 일 때만 의미). build 미봉인(2001년 이전) 옛
    /// 빌드면 epoch 차이가 수만 일로 튀므로 -1(="아주 오래됨")로 표시해 오해를 막는다.
    public var staleDays: Int {
        guard let s = sourceMTime, let b = installedBuild, s > b else { return 0 }
        if b < 1_000_000_000 { return -1 }
        return (s - b) / 86400
    }

    public var installedDate: Date? { installedBuild.map { Date(timeIntervalSince1970: Double($0)) } }
    public var sourceDate: Date? { sourceMTime.map { Date(timeIntervalSince1970: Double($0)) } }
}

/// 앱별 source freshness 를 계산한다. 순수 파일시스템 읽기(테스트 가능).
public struct SourceFreshnessScanner: Sendable {
    private var fm: FileManager { .default }
    public init() {}

    /// - Parameters:
    ///   - appDir: 소스 디렉터리(apps/<app>).
    ///   - installedBundlePath: 설치본 .app 경로(없으면 nil).
    public func evaluate(appDir: String, installedBundlePath: String?) -> SourceFreshness {
        let src = latestSourceMTime(appDir: appDir)
        guard let bundle = installedBundlePath else {
            return SourceFreshness(state: .notInstalled, installedBuild: nil, sourceMTime: src)
        }
        guard let build = installedBuild(bundlePath: bundle) else {
            return SourceFreshness(state: .unknown, installedBuild: nil, sourceMTime: src)
        }
        guard let s = src else {
            return SourceFreshness(state: .unknown, installedBuild: build, sourceMTime: nil)
        }
        // build 가 epoch(초, 2001년 이후)이 아니면 판정 불가로 본다. 일부 앱은 자체 make-app.sh 로
        // 조립하며 CFBundleVersion=1 을 그대로 둬 항상 소스보다 작아 '영구 stale + 재설치해도 안
        // 바뀜' 무한 루프에 빠진다 → .unknown 으로 빼 update-stale 대상에서 제외한다(증상 차단).
        // 근본은 그 앱들 make 스크립트가 epoch 를 찍게 하는 것(별도 수정).
        if build < 1_000_000_000 {
            return SourceFreshness(state: .unknown, installedBuild: build, sourceMTime: s)
        }
        // 빌드 자체에 수 초~수십 초 걸리므로 60초 여유(막 ship 한 건 최신 취급).
        let state: SourceFreshness.State = (s > build + 60) ? .stale : .upToDate
        return SourceFreshness(state: state, installedBuild: build, sourceMTime: s)
    }

    /// 함대 스캔이 컴파일 게이트를 다시 잠그지 않게, 동시에 걷는 앱 수를 자른다.
    /// 10코에서 429개 Task 를 한꺼번에 띄우면 load1 이 임계(0.8×ncpu)를 넘는다.
    public static let defaultMaxConcurrent = 4

    /// 여러 앱의 최신도를 병렬 계산한다. **입력 순서를 보존**한다.
    /// 번들 경로 조회는 호출측 책임(순수 유지 — SigningService/AppScan 의존 없음).
    public func evaluateAll(
        _ items: [(appDir: String, installedBundlePath: String?)],
        maxConcurrent: Int = defaultMaxConcurrent
    ) async -> [SourceFreshness] {
        await Task.detached(priority: .utility) {
            self.evaluateAllSync(items, maxConcurrent: maxConcurrent)
        }.value
    }

    /// GUI·동기 카탈로그용. `evaluateAll` 과 같은 한도·같은 순서.
    public func evaluateAllSync(
        _ items: [(appDir: String, installedBundlePath: String?)],
        maxConcurrent: Int = defaultMaxConcurrent
    ) -> [SourceFreshness] {
        guard !items.isEmpty else { return [] }
        let limit = max(1, min(maxConcurrent, items.count))
        final class Slots: @unchecked Sendable {
            var out: [SourceFreshness?]
            let lock = NSLock()
            init(count: Int) { out = Array(repeating: nil, count: count) }
        }
        let slots = Slots(count: items.count)
        let sem = DispatchSemaphore(value: limit)
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "freshness.evaluate", qos: .utility, attributes: .concurrent)
        for index in items.indices {
            group.enter()
            queue.async {
                sem.wait()
                let fresh = self.evaluate(
                    appDir: items[index].appDir,
                    installedBundlePath: items[index].installedBundlePath
                )
                slots.lock.lock()
                slots.out[index] = fresh
                slots.lock.unlock()
                sem.signal()
                group.leave()
            }
        }
        group.wait()
        return slots.out.compactMap { $0 }
    }

    /// 소스 디렉터리에서 빌드 산출물에 영향을 주는 파일들의 최종 수정 epoch.
    /// Sources/·Package.swift·Packaging/ 만 본다(.build/.git 등 산출물·VCS 제외).
    public func latestSourceMTime(appDir: String) -> Int? {
        var latest = 0
        for sub in ["Sources", "Package.swift", "Packaging"] {
            walk((appDir as NSString).appendingPathComponent(sub)) { m in if m > latest { latest = m } }
        }
        return latest > 0 ? latest : nil
    }

    private func walk(_ path: String, _ visit: (Int) -> Void) {
        // raw lstat — FileManager.attributesOfItem 은 파일마다 NSDictionary 를 지어 느리다.
        // lstat 은 심링크를 안 따라가므로 사이클도 원천 차단(소스 트리 심링크는 leaf 로 취급).
        var st = stat()
        guard lstat(path, &st) == 0 else { return }
        if (st.st_mode & S_IFMT) != S_IFDIR {
            visit(Int(st.st_mtimespec.tv_sec))
            return
        }
        guard let names = try? fm.contentsOfDirectory(atPath: path) else { return }
        for n in names where n != ".build" && !n.hasPrefix(".") {
            walk((path as NSString).appendingPathComponent(n), visit)
        }
    }

    private func installedBuild(bundlePath: String) -> Int? {
        let plist = (bundlePath as NSString).appendingPathComponent("Contents/Info.plist")
        guard let data = fm.contents(atPath: plist),
              let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = obj as? [String: Any],
              let v = dict["CFBundleVersion"] as? String else { return nil }
        return Int(v)
    }
}
