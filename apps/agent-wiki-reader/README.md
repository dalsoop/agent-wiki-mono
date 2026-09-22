# Agent Wiki Reader

**보고용** Agent Wiki 클라이언트. 읽기·검색·world 조회만.

- CLI: `agent-wiki-reader` (publish 등 쓰기 거절 → studio/agent-wiki)
- GUI: 메뉴바 스캐폴드 (영역 이관 진행 중)
- 서버: `wiki-server-mono` (gujo-wiki-hub)
- 데이터: `gujo-wiki`, `person-yun-jeonghan` 등 local world 읽기

```bash
agent-wiki-reader --world person-yun-jeonghan show 온보딩
agent-wiki-reader status
```

### 설치

```bash
app-build-manager ship apps/agent-wiki-reader-swift release --no-launch
```
