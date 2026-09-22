/// 진단 계약(`DoctorFinding`·`DoctorProvider`·`DoctorOrchestrator`)은 **Foundation only**
/// 인 `DoctorContract` 로 내려갔다.
///
/// 왜 나눴나: 앱 CLI 타깃은 AppKit 을 링크하면 dual-entry 가 멈춰서(2026-07-25) 가벼운
/// `AgentCLIKit` 만 링크한다. 그래서 CLI 는 DoctorKit 을 못 쓰고, 검사를 옆에
/// 하드코딩하게 됐다 — 오늘 그렇게 만든 검사가 여섯 갈래로 흩어졌다.
/// 계약만 내려오면 **가벼운 쪽도 같은 스키마로 findings 를 낸다.**
///
/// 여기서 다시 내보내므로 `import DoctorKit` 하던 42개 파일은 그대로 컴파일된다.
@_exported import DoctorContract
@_exported import DoctorProbeKit
