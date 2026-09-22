# Game Module Map — swiftkit 게임 모듈 지도

swiftkit 은 모듈이 74개다. 이름만 봐서는 게임에 뭘 써야 할지 알 수 없어서, 실제로
**isekai 게임이 core 6.5k 줄을 척추 없이 처음부터 재구현하는 사고**가 났다.
이 문서는 그 재발을 막기 위한 5분 판단용 지도다. 아래 표의 줄 수·public 타입은
`Sources/` 실측이다(추측 금지).

상세 예제는 [`game-simulation-engine-kit.md`](game-simulation-engine-kit.md) 를 본다.

## 1. 전수 목록

### 1-A. GameSimulation\* — 턴/시간 스텝 시뮬레이션 척추

| 모듈 (product) | 줄 | 무엇을 public 으로 내놓나 |
|---|---|---|
| `GameSimulationStateKit` | 452 | `GameSimulationState`/`GameSimulationBaseState`/`GameSimulationRuntimeParityState` 프로토콜, ECS 저장소 `GameEntityRepository`·`GameEntityID`·`GameEntityRecord`, `GameSimulationComponent`, `GameComponentRegistry` |
| `GameSimulationReducerKit` | 322 | `GameSimulationReducer`(associatedtype State/Action/Environment) + `reduceTick`/`reduceAction`/`reduceEntityEvent`, effect FIFO, `AnyGameSimulationReducer`, `GameSimulationReducerSequence`(결합자) |
| `GameSimulationProtocolKit` | 277 | UI·CLI·에이전트 공용 handshake. `GameSimulationCommandEnvelope`·`GameSimulationEventEnvelope`·`EventChannel`·`EventUrgency`·`EventBuffer`·`RevisionTracker`·`Capability`·`ClientKind`·`ProtocolValidator` |
| `GameSimulationRuntimeKit` | 1137 | `GameSimulationMachine<Reducer>`(`advance(ticks:)`/`step`/`send`/`pause`/`resume`/`setSpeed`/`nextRandom`), 직렬 `actor GameSimulationRuntime`, `SnapshotEnvelope`·`SnapshotStore`·`SnapshotMigration`·`SnapshotChecksum`, `GameSimulationRandomState`, `TraceEntry`, `ScheduledAction` |

### 1-B. GameRealtime\* — 고정 스텝 실시간(전투) 엔진

| 모듈 (product) | 줄 | 무엇을 public 으로 내놓나 |
|---|---|---|
| `game-realtime-state-kit` | 816 | 결정적 월드 상태. `FixedPoint`(정수 고정소수, scale 1024)·`FixedVector2`, `EntityStore`·`EntityHandle`·`ComponentKind`·`StableQuery`, `CanonicalWorldState`, `RealtimeLimits` |
| `game-realtime-protocol-kit` | 276 | `CombatInputFrame`·`CombatInputButtons`·`CombatInputSource`, `TickResult`, `AdvanceReport`, `CanonicalSnapshot`, `RNGStreamSnapshot`, `EngineCapacityError` |
| `game-realtime-simulation-kit` | 1249 | 시스템 스케줄(`SystemSchedule`·`SystemStage`), 충돌(`CollisionWorld`·`SweptCollisionHit`·`CollisionPair`), 지연 명령(`DeferredCommandBuffer`·`DeferredFlushResult`) |
| `game-realtime-runtime-kit` | 1562 | `TickPolicy`(fixedStep/maxCatchUpTicks/maxElapsedClamp/backlogPolicy, `.standardV1`), `GameRealtimeClock` 프로토콜·`ManualGameRealtimeClock`, `FixedTickAccumulator`, `TickTransaction`, `DeterminismProfile`·`DeterministicRNG`·`RNGStreamID`, `CheckpointRing`, `EngineFault` |
| `game-realtime-engine-kit` | 307 | 위를 묶은 조립품. `GameRealtimeEngine.tick(...)`, `actor GameRealtimeEngineSession`(`submit(input)`/`advanceOneTick()`/`consumeElapsed`/`pause`/`snapshot`), `GameRealtimeConfiguration` |
| `game-realtime-debug-kit` | 1500 | `BenchmarkHarness`·`BenchmarkBaseline`·`BenchmarkReport`, `DeterminismRunReport`, `HeadlessFixture`·`HeadlessInputMode` |
| `game-realtime-benchmark` (exe) | 97 | 위 harness 를 도는 CLI |

### 1-C. GameIdleSettlementKit — 방치형 경과시간 정산

| 모듈 | 줄 | 내용 |
|---|---|---|
| `GameIdleSettlementKit` | 875 | `GameIdleWallClock` 프로토콜·`ManualGameIdleWallClock`, `GameIdleSeconds`, 경과시간 정책(`GameIdleOverflowPolicy`·`GameIdleBelowMinimumPolicy`, `settle`/`preview`), 자동저장(`GameIdleAutoSave`, `GameIdleSaveScheduler`·`DebouncingGameIdleSaveScheduler`·`GameIdleSaveCoalescing`) |

### 1-D. UI · 에셋 · 뎁스

| 모듈 | 줄 | 내용 |
|---|---|---|
| `GameUIAssetKit` | 474 | 화면 매니페스트 스키마: `GameUIScreenManifest`·`GameUICanvas`·`GameUIComponent`·`GameUIInstance`·`GameUIBinding`·`GameUIInteraction`·`GameUIHitShape`·`GameUIAssetProvenance` + `GameUIManifestValidator` |
| `game-ui-manifest-check` (exe) | 57 | 위 validator 를 CI 에서 도는 CLI |
| `GameUIRuntimeKit` | 161 | 매니페스트를 런타임에 붙이는 얇은 층: `GameUIBindingStore`·`GameUIValue`·`GameUIStateResolver`·`GameUIButtonState`·`GameUIMeterValue`·`GameUIActionRouter` |
| `GameUIRuntimeTreeKit` | 368 | 렌더러 독립 UI 트리 + 히트테스트: `GameUIRuntimeNode`, `hitTest`, `GameUIPointerInteractionState`·`PointerDispatchResult`, `GameUIIdentityPath`/`IdentityToken`, `GameUIWorldProjection`·`GameUICoordinateSpace` |
| `GameAsset2DKit` | 829 | 2D 스프라이트 **생성 파이프라인**(런타임 아님): `ImageBackend`·`ImageBackendRegistry`·`GodTiboBackend`·`CodexExecBackend`, `SpritePromptRules`, `GenManifest`/`GenHistory`/`GenRecord` |
| `GameDepthEngineKit` | 306 | 뎁스(패럴랙스) 레이어 매니페스트·레지스트리·진단: `GameDepthManifest`·`GameDepthRegistry`·`GameDepthRecord`·`GameDepthDiagnostic`·`GameDepthCanvasPreset` |
| `GameDepthEngineControlKit` | 435 | 뎁스 엔진 명령 서비스: `GameDepthCommand`·`GameDepthCommandService.execute`·`GameDepthRuntimeState`·`GameDepthSimulationSpeed` |

## 2. 선택 가이드

| 만들려는 것 | 쓸 것 |
|---|---|
| 턴제·시간(일/시간) 스텝 경영·전략 시뮬레이션 | `GameSimulationStateKit` + `ReducerKit` + `RuntimeKit` (+ UI/CLI 공유면 `ProtocolKit`) |
| 60Hz 실시간 전투 루프, 리플레이·결정성 필요 | `game-realtime-engine-kit` (하위 state/protocol/simulation/runtime 자동 포함) |
| 방치형: 앱 껐다 켠 사이 경과시간 정산·자동저장 | `GameIdleSettlementKit` |
| 화면을 매니페스트(JSON)로 정의하고 검증 | `GameUIAssetKit` + `game-ui-manifest-check`, 런타임 바인딩은 `GameUIRuntimeKit` |
| 커스텀 렌더러(Canvas/Metal) 위 클릭 판정 | `GameUIRuntimeTreeKit` |
| 패럴랙스 배경 레이어 관리 | `GameDepthEngineKit`(+ 명령 필요 시 `ControlKit`) |
| 스프라이트를 생성해야 함(빌드타임 툴) | `GameAsset2DKit` |

### GameSimulation vs GameRealtime — 둘 다 tick 이 있는데 뭐가 다른가

| | GameSimulation\* | GameRealtime\* |
|---|---|---|
| tick 의 의미 | 도메인 단위(예: 1 hour). 앱이 `advance(ticks:)`/`step()` 으로 **직접 몇 틱 진행할지 지정** | 벽시계 시간을 `TickPolicy.fixedStep` 으로 나눠 **소비**. `consumeElapsed`/`FixedTickAccumulator` 가 catch-up·clamp·backlog 처리 |
| 수치 | 도메인 자유(Int/Double). 결정성은 `GameSimulationRandomState` 시드로 확보 | `FixedPoint`(Int32, scale 1024) 정수 고정소수 — 부동소수 비결정성 자체를 제거 |
| 상태 모델 | `GameSimulationState` 채택 struct(도메인 상태 + `GameEntityRepository`) | `CanonicalWorldState` / `EntityStore` (엔진이 소유) |
| 입력 | 타입 지정 `Reducer.Action` | `CombatInputFrame`(버튼 비트 + 좌표) |
| 실행 단위 | 앱 reducer 를 감싼 `GameSimulationMachine<R>` | `SystemSchedule` 의 `SystemStage` 파이프라인 + 충돌·지연명령 |
| 저장 | `GameSimulationSnapshotStore` + 스키마 마이그레이션 | `CanonicalSnapshot` + `CheckpointRing`(롤백/리플레이) |
| 한 줄 | **"앱 규칙을 내가 쓰고, 결정적 실행·저장·명령 프로토콜만 빌린다"** | **"엔진이 루프·시간·결정성을 소유하고, 나는 시스템과 입력만 꽂는다"** |

경영 시뮬 안에 실시간 전투가 들어가는 경우 둘을 **같이** 쓴다(바깥은 Simulation, 전투 씬만 Realtime).

## 3. 최소 채택 형태 (fantasy-territory 실사례)

도메인 상태를 새로 쓰지 않는다. **기존 상태를 감싸서** 프로토콜만 만족시킨다.
(`apps/game-fantasy-territory-management-swift/Sources/GameFantasyTerritorySimulation/CampaignEngineState.swift`)

```swift
import GameSimulationStateKit

struct CampaignEngineState: GameSimulationRuntimeParityState {
    static let schemaVersion = 1

    var entities: GameEntityRepository   // 프로토콜 요구. 안 써도 된다(아래 주석 참조)
    var simulation: SimulationState      // ← 앱의 기존 도메인 상태 그대로

    var simulationRevision: Int64 {
        get { Int64(simulation.revision) }
        set { simulation.revision = Int(newValue) }
    }
    var simulationTick: GameSimulationTick {
        get { GameSimulationTick(simulation.hour) }   // 1 tick = 1 hour
        set { simulation.hour = Int(newValue) }
    }
}
```

reducer 는 도메인 규칙만 담는다.

```swift
import GameSimulationReducerKit

struct CampaignReducer: GameSimulationReducer {
    typealias State = CampaignEngineState
    typealias Action = CampaignAction
    typealias Environment = CampaignReducerEnvironment
    // reduceTick / reduceAction / reduceEntityEvent 구현
}
```

런타임은 machine 을 소유하기만 한다.
(`Sources/GameFantasyTerritoryRuntime/CampaignRuntimeController.swift`)

```swift
import GameSimulationRuntimeKit

private var machine: GameSimulationMachine<CampaignReducer>
// 초기화
machine = GameSimulationMachine(state: ..., environment: ..., reducer: CampaignReducer())
// 진행 / 명령 / 저장
try machine.advance(ticks: 1)
try machine.send(.recruit(officerID))
```

> 알려진 마찰: `GameSimulationState`/`RuntimeParityState` 가 `entities: GameEntityRepository`
> 를 **요구**하지만 fantasy-territory 는 실사용 0회다(빈 저장소를 들고만 있다). ECS 를 안 쓰는
> 도메인에도 채택 비용이 붙는다는 뜻 — 후속으로 `entities` 기본 구현 분리를 검토할 것.

## 4. 채택 현황 (main/apps 실측 · import + Package.swift 기준)

| 앱 | swiftkit 게임 모듈 사용 | 자체 구현(이관 후보) |
|---|---|---|
| `game-fantasy-territory-management-swift` | `GameSimulationStateKit`, `GameSimulationReducerKit`, `GameSimulationRuntimeKit`, `GameDepthEngineKit` | — (척추 정석 채택 사례) |
| `game-depth-engine-studio-swift` | `GameDepthEngineKit`, `GameDepthEngineControlKit`, `GameUIAssetKit` | — |
| `game-agent-of-gaya` | `GameUIAssetKit` (2회) | 세션 프로토콜·전투 시뮬 코어·전리품 코어를 앱 내부 모듈로 자체 구현 → `GameSimulationProtocolKit`/`GameRealtime*` 후보 |
| `game-isekai-connect-idle-strategy-simulation` | **없음** | core 6,488줄 전량 자체 구현: `Commands/*CommandReducer`(11개) ↔ `GameSimulationReducerKit`, `Engine/GameSimulationEngine`+`State/GameSimulationSession` ↔ `GameSimulationRuntimeKit`, `Persistence/GameSaveStore` ↔ `SnapshotStore`, `TimeSettlementCommandReducer` ↔ `GameIdleSettlementKit` |
| `game-animated-character-stages` | 없음 | 캐릭터 리그·페인트·애니메이션 전용 스택(척추와 별개 도메인, 이관 대상 아님) |
| `game-fantasy-territory-management-officer-detail-swift` | 없음 (Swift 소스 없음 — 스펙/에셋 전용) | — |

**우선 이관 후보**: isekai 의 시간정산(`TimeSettlementCommandReducer`) → `GameIdleSettlementKit`,
저장(`GameSaveStore`) → `GameSimulationSnapshotStore`. 명령/reducer 층은 표면적이 넓어 그 다음.

## 5. 새 게임을 시작할 때 체크리스트

1. 턴/시간 스텝인가 실시간 루프인가 → §2 표로 축 선택
2. 상태를 새로 설계하지 말고 **감싸기**(§3)
3. 저장은 직접 만들지 말고 `SnapshotStore`(+ `SnapshotMigration`)
4. UI/CLI/에이전트가 같은 게임을 조작하면 `GameSimulationProtocolKit`
5. 화면은 매니페스트 + `game-ui-manifest-check` 를 CI 에
