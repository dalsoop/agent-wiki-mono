# Agent Wiki Studio

**내부용** Agent Wiki 클라이언트. 발행·운영.

- CLI: `agent-wiki-editor`(별칭 `agent-wiki-studio`) → PATH 의 `agent-wiki` 프록시
- PATH CLI `agent-wiki` 는 `agent-wiki-synchronizer` 가 소유한다(`cli_aliases`). 이 앱 번들에는 `agent-wiki` 를 싣지 않는다.
- GUI: 자체 창(내 기록·수집 안내·최근·world·간단 발행) + monlith studio 표면 폴백

```bash
agent-wiki-studio --world person-personal list
# publish 등 agent-wiki 와 동일 인자
```

### PATH 연결

이 앱은 PATH 에 아무것도 쓰지 않는다. PATH 명령(`agent-wiki-editor`, 별칭 `agent-wiki-studio`) 연결은 배포 도구만 한다.

```bash
app-build-manager ship apps/agent-wiki-editor release --no-launch
```

### dual-entry

- `agent-wiki-studio dual-entry status [--json]` 는 읽기 전용 진단이다.
- `dual-entry adopt` 는 옛 호출자 호환용 안내다(아무것도 쓰지 않고 0 으로 끝난다. `--json` 이면 `{"ok":true,"message":"..."}`).
