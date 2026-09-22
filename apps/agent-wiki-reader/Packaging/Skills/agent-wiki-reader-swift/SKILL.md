---
name: agent-wiki-reader
description: |
  Agent Wiki Reader (agent-wiki-reader). Agent Wiki를 읽기·검색·world 조회만 하는 보고용 클라이언트
  트리거 — "agent-wiki-reader", "Agent Wiki Reader".
  쓰지 말 것: 다른 앱 도메인 조작, 이 앱 Sources 를 건너뛴 JSON-only 수정.
  전제: PATH CLI `agent-wiki-reader`.
---

# Agent Wiki Reader (`agent-wiki-reader`)

Agent Wiki를 읽기·검색·world 조회만 하는 보고용 클라이언트

## 4면 계약
- GUI: `Agent Wiki Reader.app`
- Core: `Agent Wiki ReaderCore`
- CLI: `agent-wiki-reader`
- StateMirror: `~/` + `.swift-app-` + `state/agent-wiki-reader.json`

## 사용 가능한 커맨드 (Capabilities & Commands)
- `agent-wiki-reader capabilities --json` — 계약
- `agent-wiki-reader help` — 도움말
- `agent-wiki-reader status` — world list
- `agent-wiki-reader version` — 버전
- `agent-wiki-reader open` — GUI
- `agent-wiki-reader blob` — 읽기 전용 blob 프록시
- `agent-wiki-reader event` — 읽기 전용 event 프록시
- `agent-wiki-reader fleet` — 읽기 전용 fleet 프록시
- `agent-wiki-reader graph` — 읽기 전용 graph 프록시
- `agent-wiki-reader gujo` — 읽기 전용 gujo 프록시
- `agent-wiki-reader world` — 읽기 전용 world 프록시

## 운영 및 검증 규칙
1. 도메인 조작은 반드시 소유 CLI(`agent-wiki-reader`)를 통해서만 수행한다 (상태 파일 직접 수정 금지).
2. 조회는 `--json` 플래그를 기본으로 사용한다.
3. 코드 변경 후 품질 검증:
```bash
agent-cli-scaffold quality --app agent-wiki-reader
git ls-files 'apps/agent-wiki-reader-swift' | agent-lint-catalog check --paths-from-stdin
```
