import XCTest
@testable import Tiktoken

/// Exercises AsyncSequence-based token streaming behaviors.
final class TokenStreamTests: XCTestCase {
    /// Ensures the stream emits both text and special chunk metadata.
    func testTokenStreamYieldsTextAndSpecialChunks() async throws {
        let encoderOptional = try await Tiktoken.shared.getEncoding("gpt-4")
        let encoder = try XCTUnwrap(encoderOptional)
        let allowed: SpecialTokenSet = .only(["<|endoftext|>"])
        let text = "Hello <|endoftext|> world"
        let stream = encoder.tokenStream(value: text,
                                         allowedSpecial: allowed,
                                         disallowedSpecial: .automatic,
                                         request: .init(chunkSize: 2))
        var totalTokens = 0
        var textChunks = 0
        var specialChunks = 0
        for try await chunk in stream {
            totalTokens += chunk.tokens.count
            switch chunk.kind {
            case let .text(range):
                XCTAssertGreaterThan(range.count, 0)
                textChunks += 1
            case let .special(token, position):
                XCTAssertEqual(token, "<|endoftext|>")
                XCTAssertEqual(position, 6)
                specialChunks += 1
            }
        }
        XCTAssertGreaterThan(totalTokens, 0)
        XCTAssertGreaterThan(textChunks, 0)
        XCTAssertEqual(specialChunks, 1)
    }

    /// Verifies disallowed specials surface as stream errors.
    func testTokenStreamThrowsForDisallowedSpecialTokens() async throws {
        do {
            let encoderOptional = try await Tiktoken.shared.getEncoding("gpt-4")
            let encoder = try XCTUnwrap(encoderOptional)
            let stream = encoder.tokenStream(value: "Hello <|endoftext|>",
                                             allowedSpecial: .none,
                                             disallowedSpecial: .automatic)
            var iterator = stream.makeAsyncIterator()
            while let _ = try await iterator.next() {
                // exhaust stream
            }
            XCTFail("Expected disallowed special token error")
        } catch let error as EncodingError {
            switch error {
            case let .disallowedSpecialToken(token):
                XCTAssertEqual(token, "<|endoftext|>")
            default:
                XCTFail("Unexpected encoding error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
