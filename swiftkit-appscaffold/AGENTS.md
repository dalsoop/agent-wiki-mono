# swiftkit-appscaffold

## 범위

- `AppScaffoldKit`: macOS 앱 수명주기와 메뉴바·창 앱 뼈대, `GujoManaged` 진입 가드, 낡은 설치본 경고(`StaleInstallIndex`).
- 패키지 trait `GujoManaged`, `SelfUpdating`, `Telemetry`. 앱마다 `Package.swift`에서 켜는 trait가 다르다(indexer·synchronizer는 `GujoManaged`·`SelfUpdating`, editor·reader·grapher는 여기에 `Telemetry`까지).

원장 로직, CLI 명령 구현은 범위 밖이다.

## 불변식

- `GujoManaged.exitIfNotEntitledSync()`는 모든 CLI의 첫 호출이다. `help`·`version`보다 먼저 불려 낡은 설치본을 stderr 한 줄로 알린다. 표준 출력(JSON)을 건드리지 않는다.
- 가드 동작(종료 조건)을 바꾸는 변경은 이 저장소의 모든 CLI 동작을 바꾸므로 제품 소유자 결정 없이 하지 않는다. 보안 이슈 있음, 비공개 추적.
- `Derived/`는 Tuist 생성물이다. 손으로 고치지 않는다.

## 테스트

- 2026-09-30 확인에서 별도로 실행하지 않았고, indexer 빌드 과정에서 컴파일되는 것만 확인했다.
- 가드를 바꾸면 "`--help`만 쳐도 낡은 설치본 경고가 나옴", "`capabilities` 표준 출력이 순수 JSON으로 유지됨"을 검사한다.
