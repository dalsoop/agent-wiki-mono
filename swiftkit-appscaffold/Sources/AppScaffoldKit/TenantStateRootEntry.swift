/// 기동 진입에서 테넌트 상태 루트를 한 번 적용한다.
///
/// `GujoManaged`·`RanodeApp` 은 기존 부채가 있어 훅을 두면 파일 전체가 스캔된다.
/// 깨끗한 진입 체인에서만 이 함수를 부른다.
public enum TenantStateRootEntry {
    public static func applyIfNeeded() {
        TenantStateRootBootstrap.apply()
    }
}
