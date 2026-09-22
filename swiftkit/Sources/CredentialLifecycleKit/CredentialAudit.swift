import Foundation

/// 판정 — 네트워크·시계에 의존하지 않는 순수 계산. `now` 를 주입받으므로 테스트에서
/// 시간을 고정할 수 있다.
public enum CredentialAudit {

    public static func days(from: Date, to: Date) -> Int {
        Int(to.timeIntervalSince(from) / 86_400)
    }

    /// 자격증명 하나를 판정한다. 폐기된 것은 호출 전에 걸러 넣는다.
    public static func judge(_ credential: ManagedCredential,
                             policy: CredentialPolicy = .default,
                             now: Date = Date(),
                             burstIDs: Set<CredentialID> = []) -> CredentialVerdict {
        var flags: [CredentialFlag] = []

        // 유휴일: 쓰인 적 있으면 마지막 사용 기준, 없으면 발급 기준.
        let idleDays = days(from: credential.lastUsedAt ?? credential.createdAt, to: now)

        if credential.lastUsedAt == nil {
            if days(from: credential.createdAt, to: now) > policy.neverUsedGraceDays {
                flags.append(.neverUsed)
                flags.append(.stale)
            }
        } else if idleDays > policy.staleDays {
            flags.append(.stale)
        }

        var daysUntilExpiry: Int?
        if let expiry = credential.expiresAt {
            let remaining = days(from: now, to: expiry)
            daysUntilExpiry = remaining
            if remaining < 0 {
                flags.append(.expired)
            } else if remaining <= policy.expiringWithinDays {
                flags.append(.expiringSoon)
            }
        }

        if flags.contains(.stale), policy.isWriteCapable(credential) {
            flags.append(.staleWriteCapable)
        }
        if burstIDs.contains(credential.id) {
            flags.append(.burst)
        }

        // 이미 만료됐는데 살아 있는 것과, 방치 + 쓰기권한이 가장 위험하다.
        let severity: CredentialSeverity =
            if flags.contains(.expired) || flags.contains(.staleWriteCapable) { .critical }
            else if flags.contains(.stale) || flags.contains(.expiringSoon) { .warning }
            else if flags.contains(.burst) { .notice }
            else { .ok }

        return CredentialVerdict(credential: credential, flags: flags, severity: severity,
                                 idleDays: idleDays, daysUntilExpiry: daysUntilExpiry)
    }

    /// 같은 소유자에서 짧은 창 안에 무더기로 생성된 무리를 찾는다(슬라이딩 윈도우).
    public static func detectBursts(_ credentials: [ManagedCredential],
                                    policy: CredentialPolicy = .default) -> [BurstGroup] {
        let window = TimeInterval(policy.burstWindowMinutes * 60)
        var out: [BurstGroup] = []

        for (owner, group) in Dictionary(grouping: credentials, by: \.owner) {
            let sorted = group.sorted { $0.createdAt < $1.createdAt }
            var start = 0
            var best: [ManagedCredential] = []
            for end in sorted.indices {
                while sorted[end].createdAt.timeIntervalSince(sorted[start].createdAt) > window {
                    start += 1
                }
                let run = Array(sorted[start...end])
                if run.count > best.count { best = run }
            }
            guard best.count >= policy.burstMinimumCount,
                  let first = best.first, let last = best.last else { continue }
            out.append(BurstGroup(owner: owner, count: best.count,
                                  firstCreated: first.createdAt, lastCreated: last.createdAt,
                                  credentialIDs: best.map(\.id)))
        }
        return out.sorted { $0.count > $1.count }
    }

    public static func report(source: String,
                              credentials: [ManagedCredential],
                              policy: CredentialPolicy = .default,
                              now: Date = Date(),
                              partialScope: Bool = false) -> CredentialAuditReport {
        let active = credentials.filter { !$0.revoked }
        let bursts = detectBursts(active, policy: policy)
        let burstIDs = Set(bursts.flatMap(\.credentialIDs))

        let verdicts = active
            .map { judge($0, policy: policy, now: now, burstIDs: burstIDs) }
            .sorted { ($0.severity, $0.idleDays) > ($1.severity, $1.idleDays) }

        var rollups: [OwnerRollup] = []
        for (owner, group) in Dictionary(grouping: verdicts, by: { $0.credential.owner }) {
            rollups.append(OwnerRollup(
                owner: owner,
                active: group.count,
                stale: group.count { $0.flags.contains(.stale) },
                expiringSoon: group.count { $0.flags.contains(.expiringSoon) },
                worst: group.map(\.severity).max() ?? .ok,
                freshestIdleDays: group.map(\.idleDays).min()
            ))
        }
        rollups.sort { ($0.worst, $0.active) > ($1.worst, $1.active) }

        return CredentialAuditReport(
            origin: .init(source: source, generatedAt: now, partialScope: partialScope),
            counts: .init(
                totalActive: active.count,
                stale: verdicts.count { $0.flags.contains(.stale) },
                expiringSoon: verdicts.count { $0.flags.contains(.expiringSoon) },
                expired: verdicts.count { $0.flags.contains(.expired) },
                staleWriteCapable: verdicts.count { $0.flags.contains(.staleWriteCapable) }
            ),
            rows: .init(owners: rollups, verdicts: verdicts, bursts: bursts)
        )
    }
}

extension Array {
    func count(where predicate: (Element) -> Bool) -> Int {
        reduce(0) { predicate($1) ? $0 + 1 : $0 }
    }
}
