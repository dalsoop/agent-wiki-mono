# 퇴역 — AgentWikiLocal (2026-10-04)

## 상태: 배포 컷오프(재설치 금지)

## 왜
저장소 `.wiki/`(ledger 2) 전용 CLI 다. 남은 저장소 위키는 swift-app-mono 하나뿐이고, 다른 앱·스킬·훅에서 `agent-wiki-local` 을 부르는 곳이 없다. 결정 0008.

## 대체
- 저장소 위키 읽기·쓰기 → `agent-wiki --world <저장소 world> …`(전역 CLI 가 ledger 2 원장도 다룬다)
- 새 지식 → agent-law 원장

## 로컬 정리(한 번)
설치본은 지우지 않고 `~/Library/Application Support/agent-wiki-cutoff/` 로 옮긴다. PATH 의 `agent-wiki-local` 링크는 배포 도구가 거둔다.
