import Foundation

/// Describes a single chunk emitted by the streaming encoder.
public struct TokenStreamChunk: Sendable {
    public enum Kind: Sendable {
        /// Tokens that originated from regular text. Range is measured in character offsets.
        case text(range: Range<Int>)
        /// Tokens that map to a special token string at a specific character position.
        case special(token: String, position: Int)
    }

    public let tokens: [Int]
    public let kind: Kind

    public init(tokens: [Int], kind: Kind) {
        self.tokens = tokens
        self.kind = kind
    }
}

/// Configuration for streaming token requests.
public struct TokenStreamRequest: Sendable {
    public let chunkSize: Int

    public init(chunkSize: Int = 256) {
        self.chunkSize = max(1, chunkSize)
    }
}
