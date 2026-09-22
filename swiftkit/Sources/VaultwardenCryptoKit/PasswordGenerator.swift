import Foundation
import Security

public struct PasswordGeneratorOptions: Sendable, Equatable {
    public var length: Int
    public var useLowercase: Bool
    public var useUppercase: Bool
    public var useDigits: Bool
    public var useSymbols: Bool

    public init(length: Int = 20, useLowercase: Bool = true, useUppercase: Bool = true,
                useDigits: Bool = true, useSymbols: Bool = true) {
        self.length = length
        self.useLowercase = useLowercase
        self.useUppercase = useUppercase
        self.useDigits = useDigits
        self.useSymbols = useSymbols
    }
}

public enum PasswordGenerator {
    static let lower = Array("abcdefghijklmnopqrstuvwxyz")
    static let upper = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    static let digits = Array("0123456789")
    static let symbols = Array("!@#$%^&*-_=+?")

    /// CSPRNG(SecRandom) 기반. 켜진 각 문자군에서 최소 1자 보장.
    public static func generate(_ opts: PasswordGeneratorOptions) -> String {
        var pools: [[Character]] = []
        if opts.useLowercase { pools.append(lower) }
        if opts.useUppercase { pools.append(upper) }
        if opts.useDigits { pools.append(digits) }
        if opts.useSymbols { pools.append(symbols) }
        guard !pools.isEmpty else { return "" }

        let length = max(opts.length, pools.count)
        let all = pools.flatMap { $0 }
        var chars: [Character] = pools.map { $0[random(below: $0.count)] }
        while chars.count < length {
            chars.append(all[random(below: all.count)])
        }
        // Fisher–Yates 셔플 (CSPRNG)
        for i in stride(from: chars.count - 1, through: 1, by: -1) {
            chars.swapAt(i, random(below: i + 1))
        }
        return String(chars)
    }

    /// 모듈로 편향 없는 균등 난수.
    static func random(below bound: Int) -> Int {
        precondition(bound > 0)
        let limit = UInt32.max - UInt32.max % UInt32(bound)
        var value: UInt32 = 0
        repeat {
            _ = withUnsafeMutableBytes(of: &value) {
                SecRandomCopyBytes(kSecRandomDefault, 4, $0.baseAddress!)
            }
        } while value >= limit
        return Int(value % UInt32(bound))
    }
}
