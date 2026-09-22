#if os(macOS)
extension HotKeyKit {
	/// 단축키의 strongly-typed 이름. 문자열 키로 UserDefaults 에 조합을 영속화한다.
	///
	/// 등록 후 `HotKeyKit.onKeyDown(_:for:)`, `HotKeyKit.Recorder` 등에서 사용한다.
	/// ```swift
	/// extension HotKeyKit.Name {
	///     static let toggleUnicornMode = Self("toggleUnicornMode")
	/// }
	/// ```
	public struct Name: Hashable, Sendable {
		/// Name 없이 `Shortcut` 를 쓸 수 있게 하는 네임스페이스 축약.
		public typealias Shortcut = HotKeyKit.Shortcut

		/// 저장 키로 쓰이는 원시 문자열. 한 번 정하면 바꾸면 안 된다(사용자 설정 유실).
		public let rawValue: String

		/// 초기 단축키(기본값). `reset(_:)` 이 이 값으로 되돌린다.
		public let defaultShortcut: Shortcut?

		/// 이름에 할당된 현재 단축키.
		public var shortcut: Shortcut? {
			get { HotKeyKit.getShortcut(for: self) }
			nonmutating set { HotKeyKit.setShortcut(newValue, for: self) }
		}

		/// - Parameters:
		///   - name: 단축키 이름(저장 키).
		///   - initialShortcut: 선택 기본 조합. 사용자가 기존 단축키를 훔치게 되므로 꼭 필요할 때만.
		///     보통은 첫 실행 웰컴 화면에서 사용자가 직접 설정하게 두는 것이 낫다.
		public init(_ name: String, default initialShortcut: Shortcut? = nil) {
			self.rawValue = name
			self.defaultShortcut = initialShortcut

			// 기본값이 있고 아직 저장값이 없으면 기본값을 채운다(첫 실행부터 동작).
			if let initialShortcut, !HotKeyKit.userDefaultsContains(name: self) {
				HotKeyKit.setShortcut(initialShortcut, for: self)
			}

			HotKeyKit.initialize()
		}
	}
}

extension HotKeyKit.Name: RawRepresentable {
	/// :nodoc:
	public init(rawValue: String) {
		self.init(rawValue)
	}
}
#endif
