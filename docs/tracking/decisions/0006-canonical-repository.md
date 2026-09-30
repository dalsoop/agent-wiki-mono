# 0006. agent-wiki 의 정본 저장소는 agent-wiki-mono 다

## 맥락

2026-09-30 까지 설치된 `agent-wiki`(AgentWikiGlobal.app)는 이 저장소가 아니라 1세대 모노레포 swift-app-mono 의 사본
(`apps/agent-wiki-synchronizer`, `agent-wiki-kit` 등)에서 빌드됐다(설치본 Info.plist 의 SASourceDirectory 로 확인). 두 사본은
파일 수백 개가 갈라져 있었고, 한쪽의 수정(병합 개정, 결정 0005)이 다른 쪽에 따로 들어가야 했다.

## 결정

팀 리드 결정(2026-09-30): agent-wiki 의 정본은 이 저장소다. 근거는 두 가지다 — swift-app-mono 는 아카이브 예정이고(위키
2e34c5c1), 앱 하나에 소스 한 곳이 상용 표준이다.

- swift-app-mono 사본의 최신 상태(설치본 1.0.28, 커밋 7083ad6)를 이 저장소로 가져와 두 사본을 같게 만든다
  (`agent-wiki-kit`, `citationledgerkit`, `agent-wiki-ui`, `apps/agent-wiki-*`, `swiftkit*`). 이 저장소에만 있던 문서
  (`AGENTS.md`·`docs/`)는 남긴다.
- 설치는 이 저장소에서 `app-build-manager ship apps/agent-wiki-synchronizer` 로 한다. 버전 정본은 `Versions/<앱>` 이다.
- swift-app-mono 사본은 퇴역한다. README 에 이 저장소 포인터를 두고, 빌드 대상에서 빼고, lint 로 새 변경을 막는다. 소스
  삭제는 다음 정리 때 한다.

## 결과

- 설치본의 SASourceDirectory·SASourceCommit 이 이 저장소를 가리킨다.
- editor 의 분기 CLI(`AgentWikiFullCLI`)는 가져온 사본에서 이미 지워져 있어 함께 사라졌다. `agent-wiki-ui` 도 이제 커밋된다.
- synchronizer 타깃 이름이 `AgentWikiSynchronizer*` 로 바뀌었다(가져온 사본의 이름).
