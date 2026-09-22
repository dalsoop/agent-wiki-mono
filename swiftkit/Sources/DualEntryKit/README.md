# DualEntryKit

macOS GUI/CLI dual-entry hang 예방 공용 규칙.

## 계약

| dual_entry | PATH | 번들 |
|------------|------|------|
| `helpers` | SPM CLI 실파일만 | `MacOS/<GUI>` + `Helpers/<cli>` |
| `argv` | 단일 바이너리 허용(명시) | `MacOS/<Exe>` 만 |
| `cli_only` | CLI product | GUI 없음 |

금지: `ln -s …/Contents/MacOS/<GUI> /opt/homebrew/bin/<cli>`

## 사용

```swift
import DualEntryKit

let profile = DualEntryProfile(
    guiExecutableName: "MyApp",
    cliProductName: "my-app",
    stampHomeRelativeDir: ".my-app"
)

// GUI @main init
DualEntryRules.exitIfMisusedAsCLI(profile: profile)

// 수신 Settings 는 DualEntryKit 이 아니라 SparkleUpdateKit:
//   SparkleReceiveSettingsScene() 또는 SparkleReceiveSettings.wrap(_:)

// PATH 검사
DualEntryRules.isSafeCLIExecutable(path, profile: profile)
DualEntryRules.diagnose(profile: profile)
```

설치 SSOT: `app-build-manager install-cli` (`CLIInstaller.swift`) · lint: `scripts/lint-dual-entry.sh`  
위키: dual-entry hang (PATH→GUI)
