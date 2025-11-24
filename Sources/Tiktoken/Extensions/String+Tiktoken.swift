import Foundation

extension String {
    func base64Encoded() -> String? {
        data(using: .utf8)?.base64EncodedString()
    }

    /// Decodes base64 into raw data while preserving emoji and binary payloads.
    func base64DecodedData() -> Data? {
        Data(base64Encoded: self)
    }

    func index(from: Int) -> Index {
        index(startIndex, offsetBy: from)
    }

    func substring(from: Int) -> String {
        let fromIndex = index(from: from)
        return String(self[fromIndex...])
    }

    func substring(to: Int) -> String {
        let toIndex = index(from: to)
        return String(self[..<toIndex])
    }

    func substring(with range: Range<Int>) -> String {
        let startIndex = index(from: range.lowerBound)
        let endIndex = index(from: range.upperBound)
        return String(self[startIndex..<endIndex])
    }

    var splitWhiteSpaces: [String] {
        split(separator: " ").map(String.init)
    }

    var uInt8: [UInt8] {
        utf16.map { UInt8($0) }
    }
}
