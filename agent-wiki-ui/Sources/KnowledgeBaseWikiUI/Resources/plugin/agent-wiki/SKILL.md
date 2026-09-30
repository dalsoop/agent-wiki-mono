---
name: agent-wiki
description: |
  Agent Wiki CLI·원장 사용법. gujo wiki / repo `.wiki` 조회·발행·world·dual-entry.
  트리거: "agent-wiki", "Agent Wiki", "위키에서 찾아", "원장 조회", "gujo wiki 검색",
  "memo-citation-ledger", "knowledge-base-wiki", "원장 발행", "wiki show/search/context".

  정본 원장 이름 = **gujo wiki** (`~/gujo-wiki`). 공개 CLI = **agent-wiki**.
  기록(발행)만이면 wiki-record 스킬과 겹침 — 조회·world·설치·dual-entry 는 이 스킬.
---

# Agent Wiki

Display **Agent Wiki** · CLI **`agent-wiki`** · 권위 원장 **gujo wiki**.

## 이름

| 층 | 이름 |
|---|---|
| GUI | Agent Wiki |
| PATH CLI | `agent-wiki` |
| 별칭 | `knowledge-base-wiki`, `memo-citation-ledger` |
| 정본 원장 | gujo wiki · world `gujo-wiki` · `~/gujo-wiki` |
| repo 지식 | `<repo>/.wiki` (별 world) |

## 조회 (원장 우선)

파일 grep·웹 검색 전에:

```bash
agent-wiki --world gujo-wiki context "<질문>"
agent-wiki --world gujo-wiki search "<키워드>"
agent-wiki --world gujo-wiki show <id접두어>
agent-wiki --world gujo-wiki path <id1> <id2>
```

활성 world가 이미 gujo-wiki 면 `--world` 생략 가능.  
`agent-wiki world list` 로 world 확인.

## 발행

```bash
printf '%s' "<본문 md>" | agent-wiki --world gujo-wiki --as <author> publish \
  --title "근거: <제목>" [--type decision|note|…] [--origin <url>] \
  [--cite <id> references] [--supersedes <id>]
```

완료 = **발행 id 출력** + `agent-wiki --world gujo-wiki verify` (이상 없음).  
발행 규약 상세는 **wiki-record** 스킬.

## dual-entry

PATH CLI 는 Helpers 바이너리만. GUI MacOS 를 심링크 금지.

```bash
agent-wiki dual-entry
"/Applications/Agent Wiki.app/Contents/Helpers/agent-wiki" install
```

## 스킬 부착 (앱 생명주기)

```bash
agent-wiki skill-install    # ~/.codex|claude|grok|agents/skills 에 부착
agent-wiki skill-status
agent-wiki skill-uninstall  # 이 앱이 붙인 것만 제거
```

install(PATH) 시 skill-install 도 자동 호출.

## 금지

- `~/gujo-wiki` / world id 를 agent-wiki 로 경로 리네임
- Agent Wiki 를 정본 원장 이름처럼 단독 사용 (gujo wiki 병기)
- GUI 바이너리를 PATH 에 심링크
