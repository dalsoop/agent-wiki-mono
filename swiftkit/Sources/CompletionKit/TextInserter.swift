import Foundation
import CoreGraphics
import ApplicationServices

// MARK: - 수락된 제안 텍스트 삽입기

/// 1순위: AX kAXSelectedTextAttribute 치환 (선택이 비어 있으면 캐럿 위치 삽입).
/// 2순위: CGEvent 합성 타이핑 폴백. 둘 다 실패하면 false.
@MainActor
public final class TextInserter: TextInserting {
    public init() {}

    public func insert(_ text: String) -> InsertResult {
        // 빈 텍스트는 넣을 게 없으므로 성공으로 본다.
        guard !text.isEmpty else { return .success }
        // AX 삽입 전후로 필드 문자 수를 비교해 "AX 는 성공인데 값이 안 바뀐"(E05) 경우를 잡는다.
        let element = focusedElement()
        let before = element.flatMap { charCount(of: $0) }
        if insertViaAccessibility(text) {
            if let before, let after = element.flatMap({ charCount(of: $0) }),
               after <= before {
                // AX .success 인데 길이가 안 늘었다 → 앱이 무시. 합성 타이핑으로 재시도.
                if insertViaSyntheticTyping(text) { return .success }
                return .appIgnored
            }
            return .success   // 검증 못 하거나 길이 증가 확인 → 성공
        }
        return insertViaSyntheticTyping(text) ? .success : .failed
    }

    /// 요소의 문자 수 (kAXNumberOfCharactersAttribute). 못 읽으면 nil → 검증 생략.
    private func charCount(of element: AXUIElement) -> Int? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXNumberOfCharactersAttribute as CFString, &ref) == .success,
            let n = ref as? Int else { return nil }
        return n
    }

    /// 캐럿 앞 utf16Count 유닛을 지우고 text 로 교체 (이모지 shortcode 치환용).
    /// 1순위: AX 선택 범위를 뒤로 넓혀 치환. 실패 시에만 delete 합성 키 폴백.
    /// 캐럿 앞 유닛이 부족하면 있는 만큼만 지운다 (캐럿 뒤 텍스트 오선택/과삭제 방지).
    public func replaceBackward(utf16Count: Int, with text: String) -> InsertResult {
        guard utf16Count >= 0 else { return .failed }
        // 지울 게 없으면 일반 삽입과 동일.
        guard utf16Count > 0 else { return insert(text) }
        if replaceBackwardViaAccessibility(utf16Count: utf16Count, with: text) { return .success }
        // 폴백도 동일 클램프 — AX 로 캐럿을 읽을 수 있으면 캐럿 앞 유닛 수 이하로 제한
        // (캐럿을 못 읽는 앱에서는 이전과 동일하게 요청 수만큼 delete).
        var count = utf16Count
        if let element = focusedElement(), let caret = selectedTextRange(of: element) {
            guard let range = Self.backwardDeletionRange(
                caretLocation: caret.location, utf16Count: utf16Count
            ) else { return .failed }
            count = range.length
        }
        return replaceBackwardViaSyntheticDeletes(utf16Count: count, with: text) ? .success : .failed
    }

    /// 캐럿 앞에서 지울 선택 범위 계산 (순수 — 테스트 대상).
    /// 캐럿 앞 유닛이 utf16Count 보다 적으면 length 를 있는 만큼으로 줄여, 캐럿 뒤 텍스트가
    /// 절대 선택되지 않게 한다. 지울 유닛이 없으면(캐럿이 맨 앞 등) nil.
    nonisolated static func backwardDeletionRange(
        caretLocation: Int, utf16Count: Int
    ) -> CFRange? {
        guard caretLocation > 0, utf16Count > 0 else { return nil }
        let length = min(caretLocation, utf16Count)
        return CFRange(location: caretLocation - length, length: length)
    }

    // MARK: - 공통: 포커스 요소 조회

    private func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let copyErr = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef
        )
        guard copyErr == .success,
              let focusedRef,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(focusedRef, to: AXUIElement.self)
    }

    /// 현재 선택 범위(캐럿 위치) 읽기. kAXSelectedTextRangeAttribute 의 CFRange 는
    /// UTF-16 유닛 단위다. 못 읽으면 nil.
    private func selectedTextRange(of element: AXUIElement) -> CFRange? {
        var rangeRef: CFTypeRef?
        let copyErr = AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeRef
        )
        guard copyErr == .success,
              let rangeRef,
              CFGetTypeID(rangeRef) == AXValueGetTypeID()
        else { return nil }
        let rangeVal = unsafeDowncast(rangeRef, to: AXValue.self)
        var caret = CFRange()
        guard AXValueGetValue(rangeVal, .cfRange, &caret) else { return nil }
        return caret
    }

    // MARK: - 1순위: AX 선택 텍스트 치환

    private func insertViaAccessibility(_ text: String) -> Bool {
        guard let element = focusedElement() else { return false }
        let setErr = AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFTypeRef
        )
        return setErr == .success
    }

    /// AX 로 캐럿 앞 utf16Count 유닛을 선택한 뒤 text 로 치환.
    /// kAXSelectedTextRangeAttribute 의 CFRange 는 UTF-16 유닛 단위다.
    private func replaceBackwardViaAccessibility(utf16Count: Int, with text: String) -> Bool {
        guard let element = focusedElement() else { return false }
        guard let caret = selectedTextRange(of: element) else { return false }

        // 캐럿 앞 유닛이 부족하면 length 도 줄여서 선택 — 캐럿 뒤 텍스트가 절대 포함되지 않게.
        guard var target = Self.backwardDeletionRange(
            caretLocation: caret.location, utf16Count: utf16Count
        ) else { return false }
        guard let targetValue = AXValueCreate(.cfRange, &target) else { return false }
        guard AXUIElementSetAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, targetValue
        ) == .success else { return false }

        // 선택 구간을 교체 텍스트로 치환 (빈 문자열이면 순수 삭제).
        return AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFTypeRef
        ) == .success
    }

    // MARK: - 2순위: 합성 키 폴백

    /// delete(keyCode 51) 합성 키를 utf16Count 회 보낸 뒤 text 를 합성 타이핑.
    ///
    /// 주의: macOS 텍스트 필드의 delete 1회는 UTF-16 유닛이 아니라 **grapheme 1개**를
    /// 지운다. 서로게이트 페어(2유닛=1문자)·ZWJ 이모지가 섞이면 utf16Count 회 delete 가
    /// **과삭제**될 수 있다. 계약상 호출자가 utf16Count 를 주므로 여기서는 유닛 수만큼
    /// 보내는 것 외에 대안이 없다 — 그래서 AX 경로 실패 시에만 사용한다.
    private func replaceBackwardViaSyntheticDeletes(utf16Count: Int, with text: String) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        let deleteKey: CGKeyCode = 51
        for _ in 0..<utf16Count {
            guard
                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: deleteKey, keyDown: true),
                let keyUp = CGEvent(keyboardEventSource: source, virtualKey: deleteKey, keyDown: false)
            else { return false }
            for event in [keyDown, keyUp] {
                // KeyEventTap 이 자기 합성 이벤트를 다시 처리하지 않게 magic 마킹.
                event.setIntegerValueField(
                    .eventSourceUserData, value: KeyEventTap.syntheticEventMagic
                )
                event.post(tap: .cghidEventTap)
            }
        }
        guard !text.isEmpty else { return true }
        return insertViaSyntheticTyping(text)
    }

    private func insertViaSyntheticTyping(_ text: String) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        for chunk in TextChunker.split(text) {
            let units = Array(chunk.utf16)
            guard
                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { return false }
            for event in [keyDown, keyUp] {
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                // KeyEventTap 이 자기 합성 이벤트를 다시 처리하지 않게 magic 마킹.
                event.setIntegerValueField(
                    .eventSourceUserData, value: KeyEventTap.syntheticEventMagic
                )
                event.post(tap: .cghidEventTap)
            }
        }
        return true
    }
}
