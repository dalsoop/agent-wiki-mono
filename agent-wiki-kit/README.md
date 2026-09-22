# AgentWikiKit

Shared **KnowledgeBaseWikiCore** for Agent Wiki products.

| Consumer | Role |
|---|---|
| `agent-wiki-kit` | Core library SSOT |
| `agent-wiki-studio-swift` | full CLI (`agent-wiki`) + Studio GUI |
| `knowledge-base-wiki-swift` | monlith GUI only |
| `agent-wiki-reader-swift` | report client (PATH proxy; optional Core later) |

```bash
swift test --package-path agent-wiki-kit
swift build --package-path apps/agent-wiki-studio-swift --product agent-wiki
swift build --package-path apps/knowledge-base-wiki-swift --product KnowledgeBaseWiki
```
