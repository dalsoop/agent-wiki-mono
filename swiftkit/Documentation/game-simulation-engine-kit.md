# Game Simulation Engine Kit

> 게임 관련 swiftkit 모듈 전체 지도와 선택 가이드는 [`game-module-map.md`](game-module-map.md) 를 먼저 본다.

국가 경영 게임별 상태와 규칙은 앱에 두고, 엔티티·결정적 실행·저장·UI/CLI/에이전트 공용 명령·클릭 판정만 패키지에서 재사용한다.

## 패키지 경계

| product | 역할 |
|---|---|
| `game-simulation-state-kit` | Codable 상태, 엔티티 계층·태그, 컴포넌트 정리 |
| `game-simulation-reducer-kit` | tick/action/entity event reducer와 FIFO effect |
| `game-simulation-protocol-kit` | UI·CLI·에이전트 공용 handshake와 versioned command |
| `game-simulation-runtime-kit` | 직렬 actor, revision, pause/speed/step, snapshot |
| `game-ui-runtime-tree-kit` | 렌더러 독립 UI 트리, hit-test, pointer focus |

앱의 `Package.swift`에서는 필요한 product만 의존한다.

```swift
.package(path: "../../swiftkit")

.target(
    name: "GameKingdomApp",
    dependencies: [
        .product(name: "game-simulation-runtime-kit", package: "swiftkit"),
        .product(name: "game-ui-runtime-tree-kit", package: "swiftkit"),
    ]
)
```

## 최소 실행 예제

아래 예제는 앱 고유 상태·컴포넌트·reducer를 정의하고, UI와 CLI/에이전트가 공유하는 명령 경로로 행동을 실행한 뒤 snapshot을 복구한다.

```swift
import GameSimulationStateKit
import GameSimulationReducerKit
import GameSimulationProtocolKit
import GameSimulationRuntimeKit
import GameUIRuntimeTreeKit

struct Health: GameSimulationComponent {
    static let componentID = "health"
    var entityID: GameEntityID
    var value: Int

    init(entityID: GameEntityID) {
        self.entityID = entityID
        value = 100
    }
}

struct KingdomState: GameSimulationState {
    static let schemaVersion = 1
    var entities = GameEntityRepository()
    var health: [GameEntityID: Health] = [:]
    var food = 0
}

enum KingdomAction: Codable, Equatable, Sendable {
    case harvest
}

struct KingdomReducer: GameSimulationReducer, Sendable {
    func reduceAction(
        state: inout KingdomState,
        action: KingdomAction,
        environment: Void
    ) -> GameSimulationEffect<KingdomAction> {
        switch action {
        case .harvest:
            state.food += 1
            return .none
        }
    }
}

func makeComponents() throws -> GameComponentRegistry<KingdomState> {
    var components = GameComponentRegistry<KingdomState>()
    try components.register(.init(Health.self, at: \KingdomState.health))
    return components
}

func play() async throws {
    var state = KingdomState()
    try state.entities.add(.init(id: "hero", tags: ["ruler"]))
    state.health["hero"] = Health(entityID: "hero")

    let runtime = GameSimulationRuntime(
        machine: .init(
            state: state,
            environment: (),
            reducer: KingdomReducer(),
            componentRegistry: try makeComponents(),
            seed: 42
        ),
        protocolVersion: 1
    )

    // UI, CLI, agent는 clientKind만 다르고 같은 handshake와 command를 사용한다.
    let session = try await runtime.connect(.init(
        protocolVersion: 1,
        clientKind: .ui,
        clientVersion: "1.0.0"
    ))
    let harvest = await runtime.submit(
        .init(
            commandID: "harvest-1",
            expectedRevision: 0,
            payload: .dispatch(.harvest)
        ),
        sessionID: session
    )

    let snapshot = await runtime.submit(
        .init(
            commandID: "snapshot-1",
            expectedRevision: harvest.result.revision,
            payload: .requestSnapshot
        ),
        sessionID: session
    )
    guard let snapshotData = snapshot.snapshotData else { return }

    var restored = GameSimulationMachine(
        state: KingdomState(),
        environment: (),
        reducer: KingdomReducer(),
        componentRegistry: try makeComponents(),
        seed: 0
    )
    try restored.restoreSnapshot(from: snapshotData)
    print(restored.state.food) // 1

    let ui = GameUIRuntimeNode(
        id: "root",
        frame: .init(x: 0, y: 0, width: 1920, height: 1080),
        children: [
            .init(
                id: "harvest-button",
                frame: .init(x: 1600, y: 900, width: 240, height: 96),
                interaction: .init(upActionID: "harvest")
            ),
        ]
    )
    let hit = ui.hitTest(.init(x: 1700, y: 940))
    print(hit?.actionID as Any) // Optional("harvest")
}
```

`clientKind`는 권한이 아니다. 디버그·치트 권한은 runtime의 서버 소유 `capabilityPolicy`가 부여하고, payload별 필수 권한은 `commandCapability`가 결정한다. 클라이언트의 `requiredCapability`는 서버 요구 권한을 낮출 수 없다. 모든 변경 명령에는 고유 `commandID`와 `expectedRevision`을 반드시 넣는다. 따라서 응답 캐시가 비워지거나 재접속한 뒤 같은 명령이 와도 이미 revision이 진행됐다면 다시 실행되지 않는다.

```swift
let securedRuntime = GameSimulationRuntime(
    machine: GameSimulationMachine(
        state: KingdomState(),
        environment: (),
        reducer: KingdomReducer()
    ),
    protocolVersion: 1,
    capabilityPolicy: { _ in [] }, // 기본은 모든 debug/cheat 권한 거부
    commandCapability: { command in
        guard case .dispatch = command else { return nil }
        return .cheat
    }
)
```

## 저장과 재현성

- 게임 로직에는 wall clock이나 화면 frame delta 대신 정수 tick을 전달한다.
- 같은 초기 snapshot, seed, tick, action 순서는 같은 canonical snapshot을 만든다.
- 공통 repository는 entity와 tag를 안정 순서로 encode한다. 앱 상태의 `Set`도 custom Codable로 정렬해야 한다.
- snapshot은 checksum과 game-state schema version을 검증한 뒤 한 번에 복구한다.
- 파일 저장은 `GameSimulationSnapshotStore`를 사용한다. schema 변경 시 연속된 `GameSimulationSnapshotMigration`을 등록한다.

## UI 입력 규칙

- 노드는 1920×1080 같은 design canvas에서 계산된 frame을 보유할 수 있지만 렌더러를 소유하지 않는다.
- hit-test는 높은 `zIndex`, 같은 z에서는 나중에 그린 자식을 먼저 검사한다.
- 경계는 half-open이므로 맞닿은 두 버튼이 같은 점을 동시에 차지하지 않는다.
- 모달 backdrop은 `blocksLowerLayers: true`로 아래 화면 클릭을 막고, 닫기를 허용할 때만 `upActionID`를 둔다.
- 반복 리스트는 `repeatedKey`를 넣어 재정렬 뒤에도 pressed/hover identity를 유지한다.
- world-space 체력바는 `GameUIWorldProjection` adapter로 화면 좌표를 공급한다.

렌더링, `screen.json` adapter, nine-slice, 에셋 로딩은 이 패키지의 책임이 아니다. 해당 계층은 정규화된 `GameUIRuntimeNode`를 만들고 동일 트리를 화면 표시와 입력 판정에 함께 사용해야 한다.
