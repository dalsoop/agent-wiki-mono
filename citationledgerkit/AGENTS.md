# citationledgerkit

## 범위

- 내용 주소 해시 `CitationLedger.sha256Hex`, `CitationLedgerObject.contentID`.
- ms 정밀 ISO8601 시각 포맷·파싱, UUIDv7 생성.
- 작성자 신원 해석 `CitationActor.resolve()`: 환경 변수 `CITATION_ACTOR` → `~/.config/citation-ledger/actor` 첫 줄 → `<user>@<host 첫 라벨>`.
- `LedgerLookup`: 객체 존재·철회·개정 상태 조회.

원장 파일 저장, 프런트매터 직렬화, world 설정, CLI는 이 패키지 범위가 아니다(`agent-wiki-kit` 담당). 이 패키지는 다른 로컬 패키지를 import하지 않는다. 외부 의존은 `swift-crypto` 하나다.

## 불변식

- `sha256Hex`는 같은 문자열에 대해 항상 같은 64자리 소문자 16진수를 낸다. 해시 알고리즘·인코딩(UTF-8)·대소문자를 바꾸면 모든 원장 객체 id가 어긋난다.
- ms 시각은 포맷 → 파싱 → 포맷 왕복에서 같은 문자열이 나와야 한다. 원장 코어의 `published` 줄이 이 포맷을 쓴다.
- UUIDv7은 생성 시각 순서대로 정렬된다.
- 신원 해석 순서를 바꾸지 않는다. forge와 Agent Wiki가 같은 actor 문자열을 공유한다.

## 테스트

- 패키지 테스트는 2026-09-30 기준 10개가 모두 통과한다.
- 해시 재현성, 내용 변화에 따른 id 변화, 두 가지 시각 정밀도 파싱, ms 왕복, UUIDv7 시간순, 환경 변수가 파일보다 우선함, 미설정 폴백을 검사한다. 해석 순서나 포맷을 바꿔야 한다면 테스트보다 호출측(원장 id, forge actor) 영향을 먼저 확인한다.
