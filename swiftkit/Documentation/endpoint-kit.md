# EndpointRouterKit

키 → URL 라우터. 앱은 호스트를 하드코딩하지 않고 키만 묻는다. 값은 **app-build-manager** 가 원장에 쓴다.

정본 폴백: `swiftkit/Sources/EndpointRouterKit/Resources/endpoints-defaults.json`.
앱 소스가 폴백 URL 을 복제하면 `[kit-bypass-amnesia]` · `[endpoint-kit-ssot]` 에 걸린다.

클러스터·내부 호스트는 번들에 넣지 않는다. 키는 두고 값은 빈 문자열이다. 채우는 곳은 빌드 앱이다 (`endpoints list|set`, 클러스터 화면).

## 해석 우선순위 (키별)

1. env 개별 오버라이드 `GUJO_ENDPOINT_<KEY>` (키를 대문자화)
2. env `GUJO_ENDPOINTS_FILE` 이 가리키는 원장 파일
3. 빌드 앱 원장 `StateRootKit.url(".app-build-manager/endpoints.json")`
4. 번들 폴백 표 `Resources/endpoints-defaults.json`

원장 스키마:

```json
{ "schema_version": 1,
  "endpoints": { "core": "https://gujo.test", "learn": "https://learn.example" },
  "note": "…" }
```

스키마 버전이 다르거나 JSON 이 깨지면 그 파일을 무시하고 폴백으로 내려간다.

## 오버레이 키 철자

해석은 키를 **소문자로만** 맞춘다. hyphen(`-`) 과 underscore(`_`) 는 서로 바꾸지 않는다.
이 동작은 바꾸지 않는다(실측 2026-09-10).

| 입력 | 해석 키 | `catalog-parquet` 폴백 |
|---|---|---|
| env `GUJO_ENDPOINT_CATALOG_PARQUET` | `catalog_parquet` (별개 키) | 그대로(빈 문자열) |
| 원장 `"catalog-parquet"` | `catalog-parquet` | 덮음 |
| 원장 `"CATALOG-PARQUET"` | `catalog-parquet` (소문자만) | 덮음 |

하이픈 키를 env 로 덮으려면 이름에 하이픈이 들어가야 한다(`GUJO_ENDPOINT_CATALOG-PARQUET`).
셸 변수 이름으로는 불편하므로 원장 파일을 쓴다.

## 공개 접근자

| 접근자 | 키 | 용도 |
|---|---|---|
| `app` | `app` | 브랜드 앵커 |
| `gujoCore` | `gujo-core` | GujoAuthKit / GujoStaffAPIKit 호스트 |
| `apps` / `appsProd` | `apps` / `apps-prod` | 앱 포털 |
| `assets` / `assetsProd` | `assets` / `assets-prod` | Asset 영역 |
| `support` / `supportProd` | `support` / `support-prod` | 고객지원 |
| `pay` / `payProd` | `pay` / `pay-prod` | 결제. `gujo.ai/pricing` 이 아니다 |
| `learn` / `learnProd` | `learn` / `learn-prod` | 강좌·수강. `lecture` 와 별개 |
| `gpuPanel` | `gpu-panel` | GPU 패널. 번들 값은 빈 문자열 |

없는 키는 `string(_:)` 가 빈 문자열, `url(_:)` 가 nil. 경로 조립은 `joining(_:path:)`. 값이 빈 키도 `url(_:)` 가 nil.

## 키별 호스트 · 선언 상태

host-infra 선언은 인프라 원장에 그 호스트가 있는지다. EndpointRouterKit 폴백과 같지 않다.

| 키 | 폴백 | host-infra 선언 |
|---|---|---|
| `app` | `https://gujo.ai` | 선언 |
| `apps` / `apps-prod` | `https://apps.gujo.ai` | 선언 |
| `assets` / `assets-prod` | `https://assets.gujo.ai` | 선언 |
| `support` / `support-prod` | `https://support.gujo.ai` | 선언 |
| `learn` / `learn-prod` | `https://learn.gujo.ai` | 선언 — `lecture.gujo.ai` 와 별개 호스트 |
| `pay` / `pay-prod` | `https://pay.gujo.ai` | 미선언 — 결정 대기 (백로그 A01E22AF, 실측 2026-09-10). **값은 바꾸지 않는다** |
| `lecture` | `http://lecture.gujo.test:8014` | 로컬 폴백 |
| `lecture-prod` | `https://lecture.gujo.ai` | 선언 — 강좌 사이트. `learn` 과 별개 |
| `core` | `http://gujo.test:8001` | 로컬 폴백 |
| `core-prod` / `gujo-core` | `https://gujo.ai` | 선언 |
| `software` | `http://apps.gujo.test:8012` | 로컬 폴백 |
| `tokens` | `http://tokens.gujo.test:8011` | 로컬 폴백 |
| `api-prod` | `https://api.gujo.ai` | 선언 |
| `infisical` | `https://infisical.local.ranode.net` | InfisicalCerts 권장 호스트 |
| `s3` | `https://s3.ranode.net` | Sparkle S3 |
| `ranode-internal` | `https://internal.ranode.net` | 내부 게이트 |
| `catalog-kr` | (빈 문자열) | 클러스터 — 기계 원장이 채움 |
| `catalog-parquet` | (빈 문자열) | 클러스터 — 기계 원장이 채움 |
| `emulator-control` | (빈 문자열) | 클러스터 — 기계 원장이 채움 |
| `whisper` | (빈 문자열) | 클러스터 — 기계 원장이 채움 |
| `mesh` | (빈 문자열) | 클러스터 — 기계 원장이 채움 |
| `clipboard-sync` | (빈 문자열) | 클러스터 — 기계 원장이 채움 |
| `prom` | (빈 문자열) | 클러스터 — 기계 원장이 채움 |
| `otel` | (빈 문자열) | 클러스터 — 기계 원장이 채움 |
| `grafana` | (빈 문자열) | 클러스터 — 기계 원장이 채움 |
| `comfyui` | (빈 문자열) | 클러스터 — 기계 원장이 채움 |
| `alertmanager` | (빈 문자열) | 클러스터 — 기계 원장이 채움 |
| `llmwiki-archive` | (빈 문자열) | 클러스터 — 기계 원장이 채움 |
| `gpu-panel` | (빈 문자열) | 클러스터 — 기계 원장이 채움 |

## 금지

- 앱 소스에 `https://*.gujo.ai` 리터럴. 키만 쓴다.
- 번들 폴백에 클러스터 호스트를 지어 넣기(`*.local.ranode.net` 등). 빈 문자열이 정직하다.
- `pay` 값을 host-infra 에 맞춰 임의로 바꾸기. 사용자 결정(A01E22AF)까지 유지.
- env/원장 키의 hyphen ↔ underscore 정규화. 현재 동작을 고정한다.
