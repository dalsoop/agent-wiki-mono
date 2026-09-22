# agent-wiki-grapher

## 목표
gujo-wiki 객체 그래프의 영향도·경로를 계산하는 앱.

## 지금 범위
- 저장 경로: AppPaths
- GUI: Window
- CLI: agent-wiki-grapher
- **없음**:

## CLI
이 앱의 도메인 조작은 CLI가 문이다(App CLI First). 상태 파일 직접 수정·GUI 클릭 우회 금지.
```bash
agent-wiki-grapher capabilities
agent-wiki-grapher --help
```

## 상태
- 상태 루트: `AppPaths.stateDirectory()` → StateRootKit(`~/.agent-wiki-grapher/`).
- StateMirror: `~/.swift-app-state/agent-wiki-grapher.json`
- 헬스 펄스: `HealthPulse.publish(app:)` → `~/.swift-app-state/pulse/agent-wiki-grapher.pulse`
