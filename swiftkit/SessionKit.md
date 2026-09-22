# SessionKit

로컬 AI 대화 세션을 앱마다 다시 해석하지 않도록 묶은 공통 패키지다.

지원 런타임과 기본 저장소:

- Claude Code: `~/.claude/projects/**/*.jsonl`
- Codex: `~/.codex/sessions/**/rollout-*.jsonl`
- Grok: `~/.grok/sessions/<encoded-cwd>/<session-id>/{summary.json,updates.jsonl}`

새 앱은 `AISessionCatalog.discover()`의 `AISessionRecord`를 사용한다. 런타임 표시명,
실행 파일명, 재개 인자는 `AIRuntime`이 정본이다. JSONL 공통 판독은 `SessionLine`,
메타데이터는 `SessionMeta`, 경로 탐색은 `SessionRoots`에 추가한다. 새 AI 런타임을
지원할 때 이 계층을 먼저 확장하고 앱에는 표시·도메인별 변환만 둔다.

환경변수 `CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `GROK_HOME`을 따른다.
