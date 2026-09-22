# Agent Wiki Studio

**내부용** Agent Wiki 클라이언트. 발행·운영.

- CLI: `agent-wiki-studio` → 현재 full `agent-wiki` 프록시
- **full dual-entry 정본**은 이관 완료 전까지 monlith `knowledge-base-wiki-swift` 의 `agent-wiki`  
  (Helpers PATH install · 별칭 `knowledge-base-wiki` / `memo-citation-ledger`). Studio 가 이후 승계.
- GUI: 자체 창(내 기록·수집 안내·최근·world·간단 발행) + monlith studio 표면 폴백

```bash
agent-wiki-studio --world person-personal list
# publish 등 agent-wiki 와 동일 인자
```

### 설치

```bash
app-build-manager ship apps/agent-wiki-studio-swift release --no-launch
```

### dual-entry 승계 (full CLI 표면)

- **CLI 소스 정본**: `Sources/AgentWikiFullCLI` (38 files)
- **Studio 빌드**: `swift build --product agent-wiki`
- **Core**: monlith `KnowledgeBaseWikiCore` 라이브러리 의존 (다음 이전 대상)
- **monlith**: `KnowledgeBaseWikiCLI` 는 Studio 로 역 symlink — 호환 product 유지
- **설치 표면**: `dual-entry adopt` / monlith `install` 자동 adopt

```bash
swift build --package-path apps/agent-wiki-studio-swift --product agent-wiki
agent-wiki-studio dual-entry adopt
agent-wiki dual-entry --json
```
