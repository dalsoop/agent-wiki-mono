# swiftkit-sparkle

## 범위

- `SparkleUpdateKit`: Sparkle 프레임워크를 감싼 인앱 자동 업데이트. 이 저장소에서는 indexer(`AgentWikiLocal`)와 synchronizer(`AgentWikiGlobal`)의 GUI 타깃만 쓴다.

CLI 타깃, 원장 로직, 설치(`app-build-manager`)는 범위 밖이다.

## 불변식

- CLI 타깃이 이 패키지를 의존하지 않는다. Sparkle은 AppKit을 끌고 오므로 PATH CLI에 링크되면 dual-entry 실행이 멈춘다.
- `Derived/`는 Tuist 생성물이다. 손으로 고치지 않는다.

## 테스트

- 2026-09-30 확인에서 별도로 실행하지 않았고, indexer 빌드 과정에서 컴파일되는 것만 확인했다.
