# FileBrowserKit — 출처 고지

이 타깃의 소스는 **mq-dir** 의 `mqdirCore` 및 `DirectoryWatcher` 에서 이식했다.

- upstream: https://github.com/h5nam/mq-dir
- 라이선스: MIT
- 원 저작권: `Copyright (c) 2026 mq-dir contributors`
- 이식 시점 upstream 커밋: `mq-dir@0.2.0` (2026-07-03 push 기준 shallow clone)

MIT 전문은 upstream 저장소 `LICENSE` 를 따른다.

## 이식한 것

| 파일 | 출처 |
|---|---|
| `FileEntry.swift` | `Sources/mqdirCore/FileEntry.swift` |
| `FileSystemService.swift` | `Sources/mqdirCore/FileSystemService.swift` |
| `FileOperationService.swift` | `Sources/mqdirCore/FileOperationService.swift` |
| `HangulNFCFilename.swift` | `Sources/mqdirCore/HangulNFCFilename.swift` |
| `HangulNormalization.swift` | `Sources/mqdirCore/HangulNormalization.swift` |
| `DirectoryWatcher.swift` | `Sources/mq-dir/DirectoryWatcher.swift` (앱 타깃) |

## 이식하지 않은 것 (mq-dir UI 결정에 묶여 있음)

`PersistenceService` · `SelectionModel` · `ShortcutBinding` · `PaneLayout` ·
`PaneViewMode` · `PaneColumnWidths` — 전부 mq-dir 의 쿼드 페인 UX 전용이라
재사용 가치가 없다. `QuickLookManager` 는 SwiftUI/AppKit 의존이라 코어 타깃에
넣지 않았다 (필요해지면 별도 UI 타깃으로).

## 변경한 것

1. 모듈명 `mqdirCore` → `FileBrowserKit`
2. 타깃 밖에서 쓰려고 `FileEntry` · `FileEntrySortKey` · `FileEntrySorter` ·
   `FileSystemService` · `DirectoryWatcher` 의 API 를 `public` 승격.
   `FileOperationService` · `HangulNFCFilename` · `HangulNormalization` 은
   upstream 이 이미 public.
3. 각 파일 상단에 출처 고지 주석 2줄 추가.

로직은 손대지 않았다. upstream 테스트 그대로 `Tests/FileBrowserKitTests` 에 동봉.
