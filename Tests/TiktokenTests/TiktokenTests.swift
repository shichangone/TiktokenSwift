import XCTest
@testable import Tiktoken

final class TiktokenTests: XCTestCase {
    private var sut: Tiktoken = .shared

    func testGivenGPT2WhenDecodeThenMatch() async throws {
//        let input = "Esto es un texto 👨🏻‍💻 con emojis diferentes 🍿💃🏼🧜‍♂️ y más texto que no tiene sentido 🛟"
//        let expected = [22362, 78, 1658, 555, 2420, 78, 50169, 101, 8582, 237, 119, 447, 235, 8582, 240, 119, 369, 795, 13210, 271, 288, 361, 9100, 274, 12520, 235, 123, 8582, 240, 225, 8582, 237, 120, 8582, 100, 250, 447, 235, 17992, 224, 37929, 331, 285, 40138, 2420, 78, 8358, 645, 46668, 1734, 1908, 17305, 12520, 249, 253]
        
        let input = "這個算法真的太棒了"
        let expected = [34460, 247, 161, 222, 233, 163, 106, 245, 37345, 243, 40367, 253, 21410, 13783, 103, 162, 96, 240, 12859, 228]
        
        let encoderOptional = try await sut.getEncoding("gpt2")
        let encoder = try XCTUnwrap(encoderOptional)
        let output = try encoder.encode(value: input, disallowedSpecial: .none)
        XCTAssertEqual(output, expected)
    }
    
    func testGivenGPT4WhenDecodeThenMatch() async throws {
//        let input = "Esto es un texto 👨🏻‍💻 con emojis diferentes 🍿💃🏼🧜‍ y más texto que no tiene sentido 🛟"
//        let expected = [14101, 78, 1560, 653, 33125, 62904, 101, 9468, 237, 119, 378, 235, 93273, 119, 390, 100166, 46418, 11410, 235, 123, 93273, 225, 9468, 237, 120, 9468, 100, 250, 378, 235, 379, 11158, 33125, 1744, 912, 24215, 65484, 11410, 249, 253]
        
        let input = "這個算法真的太棒了"
        let expected = [11589, 247, 20022, 233, 70203, 25333, 89151, 9554, 8192, 103, 77062, 240, 35287]
        
        let encoderOptional = try await sut.getEncoding("gpt-4")
        let encoder = try XCTUnwrap(encoderOptional)
        let output = try encoder.encode(value: input, disallowedSpecial: .none)
        XCTAssertEqual(output, expected)
    }
    
    /// 验证最新词表可被列出且模型映射正确。
    func testAvailableEncodingsExposeLatestModels() {
        let names = sut.availableEncodingNames()
        XCTAssertTrue(names.contains("o200k_base"))
        XCTAssertTrue(names.contains("o200k_harmony"))
        let gpt4o = Model.getEncoding("gpt-4o")
        XCTAssertEqual(gpt4o?.name, "o200k_base")
        let harmony = Model.getEncoding("gpt-oss-demo")
        XCTAssertEqual(harmony?.name, "o200k_harmony")
    }
    
    /// 验证特殊符号策略与单 token API。
    func testSpecialTokenPolicyAndSingleToken() async throws {
        let encoderOptional = try await sut.getEncoding("gpt-4")
        let encoder = try XCTUnwrap(encoderOptional)
        XCTAssertThrowsError(try encoder.encode(value: "<|endoftext|>", allowedSpecial: .none, disallowedSpecial: .automatic))
        let tokens = try encoder.encode(value: "<|endoftext|>",
                        allowedSpecial: .only(["<|endoftext|>"]),
                        disallowedSpecial: .automatic)
        let eot = try XCTUnwrap(encoder.eotToken)
        XCTAssertEqual(tokens.first, eot)
        let single = try encoder.encodeSingleToken(value: "<|endoftext|>")
        XCTAssertEqual(single, eot)
        let bytes = try encoder.decodeSingleTokenBytes(token: single)
        XCTAssertEqual(String(bytes: bytes, encoding: .utf8), "<|endoftext|>")
    }
    
    /// 验证偏移量接口返回字符级偏移。
    func testDecodeWithOffsets() async throws {
        let encoderOptional = try await sut.getEncoding("gpt-4")
        let encoder = try XCTUnwrap(encoderOptional)
        let text = "hello 👋 world"
        let tokens = try encoder.encode(value: text, disallowedSpecial: .none)
        let result = encoder.decodeWithOffsets(tokens: tokens)
        XCTAssertEqual(result.text, text)
        XCTAssertEqual(result.offsets.count, tokens.count)
        XCTAssertEqual(result.offsets.first, 0)
    }

    /// 验证批量编码/解码可保持顺序并支持并发限制。
    func testBatchEncodeAndDecodeRoundtrip() async throws {
        let encoderOptional = try await sut.getEncoding("gpt-4")
        let encoder = try XCTUnwrap(encoderOptional)
        let inputs = ["hello world", "這個算法真的太棒了", "emoji 👩‍💻 mix"]
        let batchTokens = try await encoder.encodeBatch(values: inputs,
                                                        disallowedSpecial: .none,
                                                        maxConcurrency: 2)
        XCTAssertEqual(batchTokens.count, inputs.count)
        let decoded = await encoder.decodeBatch(batch: batchTokens, maxConcurrency: 2)
        XCTAssertEqual(decoded, inputs)
    }

    func testTokenCountMatchesEncodeLength() async throws {
        let encoderOptional = try await sut.getEncoding("gpt-4")
        let encoder = try XCTUnwrap(encoderOptional)
        let text = "prefix <|endoftext|> suffix"
        let allowed: SpecialTokenSet = .only(["<|endoftext|>"])
        let tokens = try encoder.encode(value: text,
                                        allowedSpecial: allowed,
                                        disallowedSpecial: .automatic)
        let count = try encoder.tokenCount(value: text,
                                           allowedSpecial: allowed,
                                           disallowedSpecial: .automatic)
        XCTAssertEqual(count, tokens.count)
    }

    func testEncodeOnlyNativeBpeMatchesOrdinaryEncode() async throws {
        let encoderOptional = try await sut.getEncoding("gpt-4")
        let encoder = try XCTUnwrap(encoderOptional)
        let text = "emoji 👩‍💻 mix"
        let ordinary = encoder.encode(value: text)
        let native = encoder.encodeOnlyNativeBpe(value: text)
        XCTAssertEqual(native, ordinary)
    }

    func testEncodeWithUnstableProducesPrefixCompletions() async throws {
        let encoderOptional = try await sut.getEncoding("gpt-4")
        let encoder = try XCTUnwrap(encoderOptional)
        let text = "hello fanta"
        let (stable, completions) = try encoder.encodeWithUnstable(value: text,
                                                                   disallowedSpecial: .none)
        XCTAssertFalse(completions.isEmpty)
        let textBytes = Array(text.utf8)
        let stableBytes = Array(encoder.decodeBytes(tokens: stable))
        XCTAssertTrue(textBytes.starts(with: stableBytes))
        for sequence in completions {
            let combined = stable + sequence
            let combinedBytes = Array(encoder.decodeBytes(tokens: combined))
            XCTAssertTrue(combinedBytes.starts(with: textBytes))
        }
    }
}
