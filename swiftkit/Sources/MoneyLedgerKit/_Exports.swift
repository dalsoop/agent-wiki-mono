// MoneyLedger 우산 모듈 — 재무 원장 제품군(business-ledger 사업 · personal-ledger 개인)의
// 단일 진입점. 소비 앱은 `import MoneyLedgerKit` 한 줄로 예전과 같은 표면을 받는다.
//
// 경계는 **아래 5개 타깃 사이**에서 컴파일러가 강제한다. 우산은 소비자 편의일 뿐이며,
// 예컨대 ReportKit 이 StoreKit 을 몰래 참조하는 일은 SPM 이 막는다.
//
//   MoneyLedgerModels    순수 도메인 값 — Money{Account,Card,Subscription,Transaction},
//                        BusinessProfile, AttachmentRecord, LedgerContext, LedgerDate.
//                        Linux-portable(business-api 컨테이너가 이것만 링크한다).
//   MoneyLedgerStoreKit  sqlite 원장 소유 — LedgerStore.
//   MoneyLedgerImportKit CSV 수입 — CSVTable, CSVImportService.
//   MoneyLedgerReportKit 저장 행 위의 순수 리포트 — 통화 버킷을 합치지 않는다.
//   MoneyLedgerVaultKit  첨부·금고 — AttachmentStore, LedgerVault, VaultDocsGateway.
//
// 이름에 `Money` 를 박은 이유: 이 저장소에는 성격이 전혀 다른 원장이 셋 있고
// 예전 이름 `LedgerKit` 은 그중 무엇인지 말하지 않았다 —
// **돈**(이 모듈) · **위키**(WikiLedgerKit) · **에이전트 루프**(LoopLedgerKit).
// 규칙 근거: 위키 결정 20f80dbc "이름만 보고 대상·역할·경계가 안 나오면 잘못된 이름이다".
@_exported import MoneyLedgerModels
@_exported import MoneyLedgerStoreKit
@_exported import MoneyLedgerImportKit
@_exported import MoneyLedgerReportKit
@_exported import MoneyLedgerVaultKit
