# swiftkit-sparkle

`SparkleUpdateKit` 은 Sparkle 2 자동 업데이트를 swiftkit 앱에 붙이는 얇은 래퍼다. 앱은 진입점에서 `.sparkleUpdates()` 모디파이어나 `SparkleUpdaterHost.shared.start()` 한 줄로 업데이트를 켠다.

## 업데이트 채널

설치본마다 업데이트 채널을 고를 수 있다. 채널 설정은 앱 자신의 기본 defaults 도메인에 있는 `GujoUpdateChannel` 키에 둔다. 값은 `stable`, `beta`, `alpha`, `dev` 가운데 하나이다. 키가 없거나 모르는 값이 들어 있으면 `stable` 로 본다.

appcast 는 채널 쿼리가 없는 피드 하나에 모든 채널의 항목을 싣는다. stable 이 아닌 항목에는 `<sparkle:channel>` 태그가 붙는다. Sparkle 은 태그가 없는 항목을 항상 보고, 태그가 붙은 항목은 허용된 채널의 것만 본다. 각 채널이 허용하는 채널은 다음과 같다. 덜 불안정한 채널을 함께 허용한다.

| 설정값 | 허용하는 채널 |
|---|---|
| `stable` | 없음 (태그 없는 항목만 받는다) |
| `beta` | `beta` |
| `alpha` | `beta`, `alpha` |
| `dev` | `beta`, `alpha`, `dev` |

다른 앱이나 터미널에서 채널을 바꾸려면 앱의 번들 ID 를 도메인으로 써서 키를 적는다.

```sh
defaults write <번들ID> GujoUpdateChannel dev
```

설정은 업데이트를 확인할 때마다 다시 읽는다. 그래서 앱을 다시 켜지 않아도 다음 확인부터 새 채널이 적용된다. 코드에서는 `UpdateChannel.current` 로 읽고 `UpdateChannel.set(_:)` 로 쓴다. 허용 집합은 `UpdateChannel.allowedSparkleChannels(for:)` 가 계산한다.

`Info.plist` 의 `SUFeedURL` 에는 채널을 넣지 않는다. 채널 선택은 이 설정과 Sparkle 의 `allowedChannels(for:)` 델리게이트가 맡는다.
