//
//  LoadTests.swift
//  
//
//  Created by Alberto Espinilla Garrido on 22/3/23.
//

import CryptoKit
import XCTest
@testable import Tiktoken

final class LoadTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("tiktoken-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        Tiktoken.shared.configureRegistry(.init(cacheDirectory: tempDirectory))
    }

    override func tearDownWithError() throws {
        Tiktoken.shared.configureRegistry(.init())
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testGivenCachedRemoteSourceWhenLoadBpeThenUseCache() async throws {
        let remoteURL = URL(string: "https://example.com/custom.tiktoken")!
        let cacheFile = tempDirectory.appendingPathComponent(Self.sha256(remoteURL.absoluteString))
        try sampleBpeData().write(to: cacheFile)
        let source = BPEFileSource(location: .remote(url: remoteURL))
        let result = try await Load.loadTiktokenBpe(source: source)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[[UInt8]("a".utf8)], 0)
    }

    func testGivenChecksumMismatchWhenLoadThenThrow() async {
        let source = BPEFileSource(location: .data(Data("bad".utf8)), expectedChecksum: "deadbeef")
        do {
            _ = try await Load.loadTiktokenBpe(source: source)
            XCTFail("Expected checksum mismatch")
        } catch let error as LoadError {
            switch error {
            case .checksumMismatch:
                XCTAssertTrue(true)
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private extension LoadTests {
    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func sampleBpeData() -> Data {
        let lines = [
            "\(Data("a".utf8).base64EncodedString()) 0",
            "\(Data("b".utf8).base64EncodedString()) 1"
        ]
        return lines.joined(separator: "\n").data(using: .utf8)!
    }
}
