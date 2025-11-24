import XCTest
@testable import Tiktoken

final class EncodingRegistryTests: XCTestCase {
    private var tempFileURL: URL!

    override func setUpWithError() throws {
        let directory = FileManager.default.temporaryDirectory
        tempFileURL = directory.appendingPathComponent("custom.tiktoken")
        try sampleBpeData().write(to: tempFileURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempFileURL)
        Tiktoken.shared.resetCustomRegistry()
    }

    func testRegisterCustomLocalEncoding() async throws {
        let vocab = Vocab(name: "custom-test",
                          url: tempFileURL.path,
                          explicitNVocab: 2,
                          pattern: "[\\s\\S]",
                          specialTokens: [:])
        Tiktoken.shared.registerEncoding(vocab, loader: .tiktokenFile(source: .local(path: tempFileURL.path)))
        let encoderOptional = try await Tiktoken.shared.getEncoding(vocab.name)
        let encoder = try XCTUnwrap(encoderOptional)
        let tokens = try encoder.encode(value: "ab", disallowedSpecial: .none)
        XCTAssertEqual(tokens, [0, 1])
        XCTAssertEqual(encoder.decode(value: tokens), "ab")
    }

    func testRegisterCustomAliasResolvesEncoding() async throws {
        let vocab = Vocab(name: "custom-alias",
                          url: tempFileURL.path,
                          explicitNVocab: 2,
                          pattern: "[\\s\\S]",
                          specialTokens: [:])
        Tiktoken.shared.registerEncoding(vocab, loader: .tiktokenFile(source: .local(path: tempFileURL.path)))
        Tiktoken.shared.registerModelAlias("my-model", encodingName: vocab.name)
        let encoderOptional = try await Tiktoken.shared.getEncoding("my-model")
        let encoder = try XCTUnwrap(encoderOptional)
        let tokens = try encoder.encode(value: "aa", disallowedSpecial: .none)
        XCTAssertEqual(tokens, [0, 0])
    }
}

private extension EncodingRegistryTests {
    func sampleBpeData() -> Data {
        let lines = [
            "\(Data("a".utf8).base64EncodedString()) 0",
            "\(Data("b".utf8).base64EncodedString()) 1"
        ]
        return lines.joined(separator: "\n").data(using: .utf8)!
    }
}
