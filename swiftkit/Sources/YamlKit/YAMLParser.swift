import Foundation

/// YAML 텍스트 → `YAMLNode`. 블록 매핑/시퀀스 + 플로우 컬렉션 + 따옴표/plain 스칼라.
/// 들여쓰기 기반 블록 파서와 괄호 기반 플로우 파서를 섞어 쓴다.
enum YAMLParser {
    static func parse(_ text: String) throws -> Any? {
        try parseNode(text).any()
    }

    static func parseNode(_ text: String) throws -> YAMLNode {
        var parser = Parser(text: text)
        return try parser.parseDocument()
    }
}
