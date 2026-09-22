# agent-wiki-editor

## 목표
내부용 Agent Wiki 클라이언트.

## 지금 범위
- 저장 경로: AppPaths
- GUI: Window + Menubar
- CLI: agent-wiki-editor
- **없음**:

## CLI
이 앱의 도메인 조작은 CLI가 문이다(App CLI First). 상태 파일 직접 수정·GUI 클릭 우회 금지.
```bash
agent-wiki-editor capabilities
agent-wiki-editor --help
```

## 상태
- 상태 루트: `AppPaths.stateDirectory()` → StateRootKit(`~/.agent-wiki-editor/`).
- StateMirror: `~/.swift-app-state/agent-wiki-editor.json`
- 헬스 펄스: `HealthPulse.publish(app:)` → `~/.swift-app-state/pulse/agent-wiki-editor.pulse`
