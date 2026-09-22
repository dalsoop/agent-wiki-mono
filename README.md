# agent-wiki-mono

AI Agent Wiki 시스템 및 지식 원장 오케스트레이션 모노레포.

## 구성

### Apps (`apps/`)
- **`agent-wiki-synchronizer`**: 글로벌 위키 동기화 및 단일 진실 원천(`agent-wiki`) 관리 (GUI / CLI).
- **`agent-wiki-reader`**: 위키 원장 탐색 및 읽기 뷰어.
- **`agent-wiki-editor`**: 위키 문서 편집 및 마크다운 동기화.
- **`agent-wiki-indexer`**: 지식 베이스 색인 및 벡터/키워드 검색기.
- **`agent-wiki-grapher`**: 지식 그래프 및 관계망 시각화.

### Swift Kits (Root)
- **`swiftkit/`**: StateRootKit, CommandKit, InteropKit 등 핵심 런타임 프레임워크.
- **`agent-wiki-kit/`**: KnowledgeBaseWikiCore, WikiCLIShared 지식 엔진.
- **`citationledgerkit/`**: 인용 및 증거 원장 킷.
- **`swiftkit-appscaffold/`**: 공통 앱 스캐폴딩.
- **`swiftkit-sparkle/`**: 인앱 업데이트 지원 킷.

## 빌드 방법

```bash
cd apps/agent-wiki-synchronizer
swift build
```

## 라이선스

MIT License
