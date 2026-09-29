# 0004. 전역 CLI는 cwd를 보지 않고 `gujo-wiki`를 기본 world로 연다

## 맥락

원장은 개인(`person-*`), 테넌트, 원격 공유(`gujo-wiki`), 저장소별 `.wiki` 층으로 나뉜다. 2026-08-19 원장 층 정리 때 world 해석 규칙을 다시 정했다. world를 고르는 입력 후보는 명령 앞 `--world`, cwd 위쪽의 `.wiki`, 활성 테넌트의 world, 설정 파일의 `currentWorld` 네 가지다.

## 결정

- 전역 CLI(`agent-wiki`)는 cwd의 `.wiki`를 찾지 않고, `--world`가 없으면 항상 `gujo-wiki`를 연다(설치 메타데이터의 목적 문구: "cwd를 쓰지 않고 gujo-wiki 세계를 기본으로 다루는 전역 Agent Wiki CLI").
- 저장소 `.wiki` 원장은 별도 CLI(`agent-wiki-local`)가 cwd에서 위로 찾아 연다.
- `LedgerConfig.resolveWorld`는 명시 world, cwd `.wiki`, 활성 테넌트 world 중 어느 것도 없으면 `nil`을 돌려준다. `currentWorld`로 떨어지는 폴백은 코드 주석에 "금지"로 명시되어 있다.

## 대안

- 전역 CLI에서도 cwd `.wiki` 자동 탐지: 이 동작은 repo CLI로 분리되었다. 전역 CLI에서 뺀 이유는 코드와 커밋에 적혀 있지 않다.
- `currentWorld` 폴백: 옛 구현의 동작이었고 2026-08-19 규칙에서 금지되었다. 금지 이유의 원문은 이 저장소 밖(원장 층 정리 기록)에 있다.

## 결과

- 개인·테넌트 world에 쓰려면 매번 명령 앞에 `--world`를 적어야 한다. 명령 뒤에 적은 `--world`는 조회 명령에서 무시되고 `gujo-wiki`가 열린다.
- `world use`로 바꾼 `currentWorld`는 전역 CLI의 world 선택에 영향을 주지 않는다. GUI와 `init` 등 다른 경로는 여전히 이 값을 쓴다.
- 같은 명령 문장은 cwd와 상관없이 같은 원장을 가리킨다.
