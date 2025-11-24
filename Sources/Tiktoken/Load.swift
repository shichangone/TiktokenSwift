//
//  Load.swift
//  
//
//  Created by Alberto Espinilla Garrido on 22/3/23.
//

import Foundation
import CryptoKit

enum LoadError: Error, LocalizedError {
    case invalidURL(String)
    case checksumMismatch(expected: String, actual: String)
    case cacheDirectoryUnavailable
    case fileNotFound(URL)
    case invalidFileEncoding

    var errorDescription: String? {
        switch self {
        case let .invalidURL(value):
            return "Invalid URL: \(value)"
        case let .checksumMismatch(expected, actual):
            return "Checksum mismatch. expected=\(expected) actual=\(actual)"
        case .cacheDirectoryUnavailable:
            return "Cache directory could not be resolved"
        case let .fileNotFound(url):
            return "File not found at \(url.path)"
        case .invalidFileEncoding:
            return "Unable to decode vocab file as UTF-8"
        }
    }
}

enum Load {
    struct CacheConfiguration {
        let cacheDirectory: URL?
        let environmentKey: String
        let verifyChecksums: Bool
        init(cacheDirectory: URL? = nil,
             environmentKey: String = "TIKTOKEN_CACHE_DIR",
             verifyChecksums: Bool = true) {
            self.cacheDirectory = cacheDirectory
            self.environmentKey = environmentKey
            self.verifyChecksums = verifyChecksums
        }
    }

    private static var cacheConfiguration = CacheConfiguration()
    private static let urlSession = URLSession(configuration: .ephemeral)

    static func configure(_ configuration: CacheConfiguration) {
        cacheConfiguration = configuration
    }

    static func loadTiktokenBpe(source: BPEFileSource, decoder: FileDecoder = FileDecoder()) async throws -> [[UInt8]: Int] {
        let data = try await loadData(from: source)
        return decoder.decode(data)
    }
    
    static func dataGymToMergeableBpeRanks(vocabSource: BPEFileSource, encoderSource: BPEFileSource? = nil) async throws -> [[UInt8]: Int] {
        var rankToIntByte = (0..<exponentialPow).filter({ Character($0).isPrintable && !Character($0).isWhitespace })
        var dataGymByteToByte: [Character: Int] = toDictionary(array: rankToIntByte)
        
        var n = 0
        (0..<exponentialPow)
            .forEach({
                if !rankToIntByte.contains($0) {
                    rankToIntByte.append($0)
                    dataGymByteToByte[Character(exponentialPow + n)] = $0
                    n += 1
                }
            })
        
        let mergesData = try await loadData(from: vocabSource)
        guard let mergesBody = String(data: mergesData, encoding: .utf8) else {
            throw LoadError.invalidFileEncoding
        }
        let bpeMerges = parseMerges(mergesBody)
        var bpeRanks: [[UInt8]: Int] = .init()
        rankToIntByte.enumerated().forEach({
            let key = Array(Character($0.element).utf16).map({ UInt8($0) })
            bpeRanks[key] = $0.offset
        })
        
        n = bpeRanks.count
        bpeMerges.forEach({
            let first = stringToArray(value: $0.0, dict: dataGymByteToByte)
            let second = stringToArray(value: $0.1, dict: dataGymByteToByte)
            let arrayInt = (first + second).map({ UInt8($0) })
            bpeRanks[arrayInt] = n
            n += 1
        })
        
        if let encoderSource {
            _ = try await loadData(from: encoderSource) // Placeholder for future validation hook
        }
        
        return bpeRanks
    }
}

private extension String {
    var sha256: String {
        let data = Data(self.utf8)
        let hashed = SHA256.hash(data: data)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}

private extension Load {
    static var exponentialPow: Int {
        Int(pow(2.0, 8))
    }
    
    static func stringToArray(value: String, dict: [Character: Int]) -> [Int] {
        value.compactMap({ dict[$0] })
    }
    
    static func toDictionary(array: [Int]) -> [Character: Int] {
        array.reduce(into: [:], { $0[Character($1)] = $1 })
    }
    
    static func parseMerges(_ body: String) -> [(String, String)] {
        body.split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap({ line in
                guard !line.starts(with: "#version") else { return nil }
                let segments = String(line).splitWhiteSpaces
                guard let first = segments.first,
                      let last = segments.last else { return nil }
                return (first, last)
            })
    }

    static func loadData(from source: BPEFileSource) async throws -> Data {
        switch source.location {
        case let .data(data):
            try verifyChecksumIfNeeded(data: data, expected: source.expectedChecksum)
            return data
        case let .local(url):
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw LoadError.fileNotFound(url)
            }
            let data = try Data(contentsOf: url)
            try verifyChecksumIfNeeded(data: data, expected: source.expectedChecksum)
            return data
        case let .remote(url):
            return try await loadRemote(url: url, expectedChecksum: source.expectedChecksum)
        }
    }

    static func loadRemote(url: URL, expectedChecksum: String?) async throws -> Data {
        let cacheURL = cacheFileURL(for: url)
        if let cacheURL, FileManager.default.fileExists(atPath: cacheURL.path) {
            let cached = try Data(contentsOf: cacheURL)
            do {
                try verifyChecksumIfNeeded(data: cached, expected: expectedChecksum)
                return cached
            } catch {
                try? FileManager.default.removeItem(at: cacheURL)
            }
        }
        let (data, _) = try await urlSession.data(from: url)
        try verifyChecksumIfNeeded(data: data, expected: expectedChecksum)
        if let cacheURL {
            try ensureCacheDirectoryExists(at: cacheURL.deletingLastPathComponent())
            try data.write(to: cacheURL)
        }
        return data
    }

    static func verifyChecksumIfNeeded(data: Data, expected: String?) throws {
        guard cacheConfiguration.verifyChecksums, let expected else { return }
        let actual = sha256(data: data)
        guard actual == expected else {
            throw LoadError.checksumMismatch(expected: expected, actual: actual)
        }
    }

    static func cacheFileURL(for url: URL) -> URL? {
        guard let directory = resolvedCacheDirectory() else { return nil }
        return directory.appendingPathComponent(url.absoluteString.sha256)
    }

    static func resolvedCacheDirectory() -> URL? {
        if let override = ProcessInfo.processInfo.environment[cacheConfiguration.environmentKey],
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        if let explicit = cacheConfiguration.cacheDirectory {
            return explicit
        }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    }

    static func ensureCacheDirectoryExists(at url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
    }

    static func sha256(data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

}
