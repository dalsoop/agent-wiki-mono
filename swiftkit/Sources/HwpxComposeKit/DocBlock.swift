import Foundation

/// HWPX 문서를 구성하는 블록 모델.
public enum DocBlock: Sendable, Equatable {
    case heading(level: Int, text: String)
    case paragraph([Run])
    case bullet([String])
    case table(rows: [[Cell]], widthsPercent: [Int])
    case pageBreak
    case image(data: Data, widthMM: Int)

    public struct Run: Sendable, Equatable {
        public let text: String
        public let bold: Bool
        public init(text: String, bold: Bool = false) {
            self.text = text
            self.bold = bold
        }
    }

    public struct Cell: Sendable, Equatable {
        public let text: String
        public let colspan: Int
        public init(text: String, colspan: Int = 1) {
            self.text = text
            self.colspan = colspan
        }
    }
}
