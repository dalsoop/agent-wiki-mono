# 퇴역 — AgentWikiReader (2026-10-04)

## 상태: 배포 컷오프(재설치 금지)

## 왜
읽기 전용 프록시 화면과 CLI 다. AgentWikiStudio 와 같은 화면 모듈을 쓰는 중복이고, 다른 앱·스킬·훅에서 `agent-wiki-reader` 를 부르는 곳이 없다. 결정 0008.

## 대체
- 원장 열람 → AgentWikiStudio
- 읽기 명령 → `agent-wiki show|list|search|context|contents`

## 로컬 정리(한 번)
설치본은 지우지 않고 `~/Library/Application Support/agent-wiki-cutoff/` 로 옮긴다. PATH 의 `agent-wiki-reader` 링크는 배포 도구가 거둔다.
