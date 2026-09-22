#if os(macOS)
@preconcurrency import AppKit
import Carbon.HIToolbox
import SwiftUI

extension HotKeyKit {
	/// SwiftUI NSViewRepresentable 로 RecorderCocoa 를 심는 내부 래퍼.
	private struct _Recorder: NSViewRepresentable {
		typealias NSViewType = RecorderCocoa

		let name: Name
		let onChange: ((_ shortcut: Shortcut?) -> Void)?

		func makeNSView(context: Context) -> NSViewType {
			.init(for: name, onChange: onChange)
		}

		func updateNSView(_ nsView: NSViewType, context: Context) {
			nsView.shortcutName = name
		}
	}

	/// 사용자가 단축키를 녹화하는 SwiftUI 뷰. 보통 설정 창에 둔다.
	///
	/// 시스템/앱 메인 메뉴가 이미 점유한 조합은 친절한 경고로 막고, 조합은 UserDefaults 에
	/// 자동 저장한다.
	/// ```swift
	/// HotKeyKit.Recorder("토글:", name: .toggleUnicornMode)
	/// ```
	public struct Recorder<Label: View>: View {
		private let name: Name
		private let onChange: ((Shortcut?) -> Void)?
		private let hasLabel: Bool
		private let label: Label

		init(
			for name: Name,
			onChange: ((Shortcut?) -> Void)? = nil,
			hasLabel: Bool,
			@ViewBuilder label: () -> Label
		) {
			self.name = name
			self.onChange = onChange
			self.hasLabel = hasLabel
			self.label = label()
		}

		public var body: some View {
			if hasLabel {
				if #available(macOS 13, *) {
					LabeledContent {
						_Recorder(name: name, onChange: onChange)
					} label: {
						label
					}
				} else {
					_Recorder(name: name, onChange: onChange)
						.formLabel { label }
				}
			} else {
				_Recorder(name: name, onChange: onChange)
			}
		}
	}
}

extension HotKeyKit.Recorder<EmptyView> {
	/// 라벨 없는 Recorder.
	public init(
		for name: HotKeyKit.Name,
		onChange: ((HotKeyKit.Shortcut?) -> Void)? = nil
	) {
		self.init(for: name, onChange: onChange, hasLabel: false) {}
	}
}

extension HotKeyKit.Recorder<Text> {
	/// 제목(LocalizedStringKey) + 이름.
	public init(
		_ title: LocalizedStringKey,
		name: HotKeyKit.Name,
		onChange: ((HotKeyKit.Shortcut?) -> Void)? = nil
	) {
		self.init(for: name, onChange: onChange, hasLabel: true) { Text(title) }
	}

	/// 제목(String) + 이름.
	@_disfavoredOverload
	public init(
		_ title: String,
		name: HotKeyKit.Name,
		onChange: ((HotKeyKit.Shortcut?) -> Void)? = nil
	) {
		self.init(for: name, onChange: onChange, hasLabel: true) { Text(title) }
	}
}

extension HotKeyKit.Recorder {
	/// 이름 + 커스텀 label 클로저.
	public init(
		for name: HotKeyKit.Name,
		onChange: ((HotKeyKit.Shortcut?) -> Void)? = nil,
		@ViewBuilder label: () -> Label
	) {
		self.init(for: name, onChange: onChange, hasLabel: true, label: label)
	}
}

extension View {
	/// 라벨과 컨트롤을 한 줄로 정렬(구 macOS fallback).
	func formLabel(@ViewBuilder _ label: () -> some View) -> some View {
		HStack(alignment: .firstTextBaseline) {
			label()
			labelsHidden()
		}
	}
}
#endif
