import SwiftUI

/// 나무위키(theseed/espejo 테마) 색상 팔레트 — 2026-07-19 실측 이식.
/// 위키 뷰어에 나무위키 정체성을 입힌다: 브랜드 초록·파랑 내부링크·초록 외부링크·연초록 제목밑줄.
enum NamuTheme {
    /// 시그니처 청록 (#00a69c) — 상단 네비·강조.
    static let brand = Color(red: 0x00 / 255, green: 0xa6 / 255, blue: 0x9c / 255)
    /// 보조 초록 (#28b472) — 그라디언트 끝.
    static let brand2 = Color(red: 0x28 / 255, green: 0xb4 / 255, blue: 0x72 / 255)
    /// 내부 링크 파랑 (#0275d8).
    static let internalLink = Color(red: 0x02 / 255, green: 0x75 / 255, blue: 0xd8 / 255)
    /// 외부 링크 초록 (#377e21).
    static let externalLink = Color(red: 0x37 / 255, green: 0x7e / 255, blue: 0x21 / 255)
    /// 없는 문서(빨간 링크) — 나무위키식 빨강.
    static let redLink = Color(red: 0xd6 / 255, green: 0x4a / 255, blue: 0x58 / 255)
    /// 제목 네임스페이스 밑줄 연초록 (#d4f0e3).
    static let titleUnderline = Color(red: 0xd4 / 255, green: 0xf0 / 255, blue: 0xe3 / 255)
    /// 헤딩 하단 경계 (#ccc).
    static let headingBorder = Color(red: 0xcc / 255, green: 0xcc / 255, blue: 0xcc / 255)
    /// 상단 네비 그라디언트.
    static let navGradient = LinearGradient(
        colors: [brand, brand, brand2], startPoint: .leading, endPoint: .trailing)
}
