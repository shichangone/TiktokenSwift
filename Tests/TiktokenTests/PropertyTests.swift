import SwiftCheck
import XCTest
@testable import Tiktoken

/// Runs property-based regression tests backed by SwiftCheck.
final class PropertyTests: XCTestCase {
    /// Random Unicode inputs should round-trip through encode/decode.
    func testUnicodeRoundtripProperty() async throws {
        let encoderOptional = try await Tiktoken.shared.getEncoding("cl100k_base")
        let encoder = try XCTUnwrap(encoderOptional)
        let generator = PropertyTests.makeUnicodeGenerator()
        property("decode(encode(x)) round-trips sample Unicode strings") <-
        forAllNoShrink(generator) { value in
            guard let tokens = try? encoder.encode(value: value,
                                                   allowedSpecial: .all,
                                                   disallowedSpecial: .none) else {
                return false
            }
            let decoded = encoder.decode(value: tokens)
            return decoded == value
        }
    }
}

private extension PropertyTests {
    /// Builds the generator that mixes curated corpus entries with random scalars.
    static func makeUnicodeGenerator() -> Gen<String> {
        let corpus = [
            "hello world",
            "emoji 👩‍💻",
            "混合中文",
            "emoji 👾🎧",
            "trim\u{2028}line",
            "नगरपालिका",
            "مرحبا",
            "plain text",
            "newline\n",
            "special <|endoftext|> token"
        ]
        let scalarRange: (UnicodeScalar, UnicodeScalar) = (UnicodeScalar(0x20)!, UnicodeScalar(0x1FFF)!)
        let scalarChunk = Gen<UnicodeScalar>.choose(scalarRange)
            .proliferateNonEmpty
            .map { scalars -> String in
                String(String.UnicodeScalarView(scalars))
            }
        let buildingBlock = Gen<String>.one(of: [
            Gen<String>.fromElements(of: corpus),
            scalarChunk
        ])
        let combined = buildingBlock.proliferateNonEmpty.map { pieces -> String in
            pieces.joined(separator: " ")
        }
        return combined.suchThat { $0.count <= 64 }
    }
}
