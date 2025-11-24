//
//  Encoding.swift
//  

//  Created by Alberto Espinilla Garrido on 20/3/23.
//

import Foundation

/// Describes how callers provide special-token policies.
public enum SpecialTokenSet {
    /// Do not allow any special tokens.
    case none
    /// Allow every special token defined by the encoding.
    case all
    /// Allow exactly the provided tokens.
    case only(Set<String>)
    /// Default policy for `disallowedSpecial`: block everything except the allowed set.
    case automatic
}

/// Errors that may be thrown during encoding workflows.
public enum EncodingError: Error, LocalizedError {
    case disallowedSpecialToken(String)
    case singleTokenNotFound(String)
    case tokenBytesNotFound(Int)
    
    public var errorDescription: String? {
        switch self {
        case let .disallowedSpecialToken(token):
            return "Disallowed special token: \(token)"
        case let .singleTokenNotFound(value):
            return "Token not found for value: \(value)"
        case let .tokenBytesNotFound(value):
            return "Bytes not found for token: \(value)"
        }
    }
}

public final class Encoding: @unchecked Sendable {
    private let name: String
    private let regex: NSRegularExpression
    private let mergeableRanks: [[UInt8]: Int]
    private let specialTokens: [String: Int]
    private let maxValueToken: Int
    private let coreBpe: CoreBPE
    private let specialTokenKeys: [String]
    private let explicitNVocab: Int?
    
    init(name: String,
         regex: NSRegularExpression,
         mergeableRanks: [[UInt8]: Int],
         specialTokens: [String: Int],
         explicitNVocab: Int? = nil) {
        self.name = name
        self.regex = regex
        self.mergeableRanks = mergeableRanks
        self.specialTokens = specialTokens
        self.explicitNVocab = explicitNVocab
        self.maxValueToken = max(mergeableRanks.values.max() ?? 0, specialTokens.values.max() ?? 0)
        self.specialTokenKeys = specialTokens.keys.sorted(by: { $0.count > $1.count })
        let decoder = mergeableRanks.inverted
        let specialDecoder = specialTokens.reduce(into: [Int: [UInt8]]()) { partialResult, entry in
            partialResult[entry.value] = Array(entry.key.utf8)
        }
        self.coreBpe = .init(encoder: mergeableRanks,
                             specialTokensEncoder: specialTokens,
                             decoder: decoder,
                             specialTokensDecoder: specialDecoder,
                             regexTls: [regex])
        validateExplicitNVocab()
    }
    
    /// Encodes a string while enforcing special-token policies.
    /// - Parameters:
    ///   - value: Input string to encode.
    ///   - allowedSpecial: Set of special tokens that may be emitted directly.
    ///   - disallowedSpecial: Special tokens that must be rejected. `.automatic` blocks every token outside of `allowedSpecial`.
    /// - Returns: Token sequence for the provided text.
    public func encode(value: String,
                       allowedSpecial: SpecialTokenSet = .none,
                       disallowedSpecial: SpecialTokenSet = .automatic) throws -> [Int] {
        let allowed = resolve(set: allowedSpecial)
        let disallowed = resolveDisallowed(set: disallowedSpecial, allowed: allowed)
        return try encodeInternal(text: value, allowed: allowed, disallowed: disallowed)
    }

    /// Counts tokens without storing the intermediate sequence.
    /// - Parameters:
    ///   - value: Input string.
    ///   - allowedSpecial: Special tokens that can be emitted.
    ///   - disallowedSpecial: Special tokens that must be rejected.
    /// - Returns: Token count matching `encode(value:allowedSpecial:disallowedSpecial).count`.
    public func tokenCount(value: String,
                           allowedSpecial: SpecialTokenSet = .none,
                           disallowedSpecial: SpecialTokenSet = .automatic) throws -> Int {
        let allowed = resolve(set: allowedSpecial)
        let disallowed = resolveDisallowed(set: disallowedSpecial, allowed: allowed)
        return try tokenCountInternal(text: value, allowed: allowed, disallowed: disallowed)
    }
    
    /// Legacy overload that always treats special tokens as plain text.
    public func encode(value: String) -> [Int] {
        coreBpe.encodeOrdinaryNative(text: value)
    }

    /// Mirrors Python's `_encode_only_native_bpe` helper by splitting locally and running BPE merges.
    public func encodeOnlyNativeBpe(value: String) -> [Int] {
        coreBpe.encodeOrdinaryNative(text: value)
    }

    /// Python-compatible entry point that forwards to `encodeOnlyNativeBpe`.
    public func _encodeOnlyNativeBpe(value: String) -> [Int] {
        encodeOnlyNativeBpe(value: value)
    }
    
    /// Decodes tokens into a UTF-8 string, falling back to replacement semantics when necessary.
    public func decode(value: [Int]) -> String {
        let data = decodeBytes(tokens: value)
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }
    
    /// Decodes tokens into their raw bytes.
    public func decodeBytes(tokens: [Int]) -> Data {
        coreBpe.decodeBytes(tokens: tokens)
    }
    
    /// Decodes tokens into text alongside character offsets.
    public func decodeWithOffsets(tokens: [Int]) -> (text: String, offsets: [Int]) {
        let tokenBytes = coreBpe.decodeTokensBytes(tokens: tokens)
        var textLength = 0
        var offsets = [Int]()
        offsets.reserveCapacity(tokenBytes.count)
        tokenBytes.forEach { bytes in
            let startsWithContinuation = bytes.first.map { ($0 & 0b1100_0000) == 0b1000_0000 } ?? false
            let offset = startsWithContinuation ? max(0, textLength - 1) : textLength
            offsets.append(offset)
            // UTF-8 continuation bytes (10xxxxxx) do not count as characters, mirroring the Python reference implementation.
            let charCount = bytes.reduce(into: 0) { partial, byte in
                let isContinuation = (byte & 0b1100_0000) == 0b1000_0000
                if !isContinuation {
                    partial += 1
                }
            }
            textLength += charCount
        }
        let textData = tokenBytes.reduce(into: Data()) { partial, bytes in
            partial.append(contentsOf: bytes)
        }
        let text = String(data: textData, encoding: .utf8) ?? String(decoding: textData, as: UTF8.self)
        return (text, offsets)
    }

    /// Encodes a batch of texts using Swift Concurrency with bounded parallelism.
    /// - Parameters:
    ///   - values: Input sentences to encode.
    ///   - allowedSpecial: Special tokens that may be emitted per request.
    ///   - disallowedSpecial: Special tokens that must be rejected.
    ///   - maxConcurrency: Maximum concurrent tasks; defaults to active CPU count.
    /// - Returns: Tokens per input, matching the original order.
    public func encodeBatch(values: [String],
                           allowedSpecial: SpecialTokenSet = .none,
                           disallowedSpecial: SpecialTokenSet = .automatic,
                           maxConcurrency: Int = ProcessInfo.processInfo.activeProcessorCount) async throws -> [[Int]] {
        guard !values.isEmpty else { return [] }
        let allowed = resolve(set: allowedSpecial)
        let disallowed = resolveDisallowed(set: disallowedSpecial, allowed: allowed)
        let workerCount = max(1, min(maxConcurrency, values.count))
        var results = Array(repeating: [Int](), count: values.count)
        try await withThrowingTaskGroup(of: (Int, [Int]).self) { group in
            var nextIndex = 0
            func scheduleNext(_ group: inout ThrowingTaskGroup<(Int, [Int]), Error>) {
                guard nextIndex < values.count else { return }
                let currentIndex = nextIndex
                let text = values[currentIndex]
                nextIndex += 1
                group.addTask {
                    let tokens = try self.encodeInternal(text: text, allowed: allowed, disallowed: disallowed)
                    return (currentIndex, tokens)
                }
            }
            for _ in 0..<workerCount {
                scheduleNext(&group)
            }
            while let (index, tokens) = try await group.next() {
                results[index] = tokens
                scheduleNext(&group)
            }
        }
        return results
    }

    /// Encodes text while exposing unstable completions, matching Python's `encode_with_unstable`.
    /// - Parameters:
    ///   - value: Input text.
    ///   - allowedSpecial: Special tokens allowed in the output.
    ///   - disallowedSpecial: Special tokens that should fail fast when encountered.
    /// - Returns: Stable tokens plus candidate continuations that preserve the input prefix when appended.
    public func encodeWithUnstable(value: String,
                                   allowedSpecial: SpecialTokenSet = .none,
                                   disallowedSpecial: SpecialTokenSet = .automatic) throws -> (stable: [Int], completions: [[Int]]) {
        let allowed = resolve(set: allowedSpecial)
        let disallowed = resolveDisallowed(set: disallowedSpecial, allowed: allowed)
        var (tokens, lastPieceTokenLength) = try encodeInternal(text: value,
                                                                allowed: allowed,
                                                                disallowed: disallowed,
                                                                captureLastPiece: true)
        guard lastPieceTokenLength > 0 else { return (tokens, []) }
        lastPieceTokenLength = coreBpe.extendedLastPieceLength(tokens: tokens,
                                                              lastPieceTokenLength: lastPieceTokenLength)
        guard lastPieceTokenLength > 0 else { return (tokens, []) }
        let unstableTokens = Array(tokens.suffix(lastPieceTokenLength))
        tokens.removeLast(lastPieceTokenLength)
        let unstableBytes = flattenBytes(byteChunks: coreBpe.decodeTokensBytes(tokens: unstableTokens))
        guard !unstableBytes.isEmpty else { return (tokens, []) }
        let completions = buildUnstableCompletions(unstableBytes: unstableBytes)
        return (tokens, completions)
    }

    /// Streams encoded tokens chunk-by-chunk using AsyncSequence semantics.
    /// - Parameters:
    ///   - value: Input text.
    ///   - allowedSpecial: Special tokens allowed in the output.
    ///   - disallowedSpecial: Tokens that trigger errors when encountered.
    ///   - request: Chunk configuration (e.g., chunk size).
    /// - Returns: An `AsyncThrowingStream` that yields `TokenStreamChunk` values.
    public func tokenStream(value: String,
                            allowedSpecial: SpecialTokenSet = .none,
                            disallowedSpecial: SpecialTokenSet = .automatic,
                            request: TokenStreamRequest = .init()) -> AsyncThrowingStream<TokenStreamChunk, Error> {
        let allowed = resolve(set: allowedSpecial)
        let disallowed = resolveDisallowed(set: disallowedSpecial, allowed: allowed)
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    try streamEncode(text: value,
                                     allowed: allowed,
                                     disallowed: disallowed,
                                     chunkSize: request.chunkSize) { chunk in
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Decodes token batches concurrently.
    /// - Parameters:
    ///   - batch: Collection of token sequences.
    ///   - maxConcurrency: Maximum concurrent tasks; defaults to CPU count.
    /// - Returns: Decoded strings in the same order as the input batch.
    public func decodeBatch(batch: [[Int]],
                            maxConcurrency: Int = ProcessInfo.processInfo.activeProcessorCount) async -> [String] {
        guard !batch.isEmpty else { return [] }
        let workerCount = max(1, min(maxConcurrency, batch.count))
        var results = Array(repeating: "", count: batch.count)
        await withTaskGroup(of: (Int, String).self) { group in
            var nextIndex = 0
            func scheduleNext(_ group: inout TaskGroup<(Int, String)>) {
                guard nextIndex < batch.count else { return }
                let currentIndex = nextIndex
                let tokens = batch[currentIndex]
                nextIndex += 1
                group.addTask {
                    let decoded = self.decode(value: tokens)
                    return (currentIndex, decoded)
                }
            }
            for _ in 0..<workerCount {
                scheduleNext(&group)
            }
            while let (index, text) = await group.next() {
                results[index] = text
                scheduleNext(&group)
            }
        }
        return results
    }
    
    /// Encodes a single token string, including special tokens.
    public func encodeSingleToken(value: String) throws -> Int {
        if let special = specialTokens[value] {
            return special
        }
        let bytes = Array(value.utf8)
        if let token = coreBpe.encodeSingleToken(bytes: bytes) {
            return token
        }
        throw EncodingError.singleTokenNotFound(value)
    }
    
    /// Encodes raw bytes into a single token if one exists.
    public func encodeSingleToken(bytes: [UInt8]) throws -> Int {
        if let token = coreBpe.encodeSingleToken(bytes: bytes) {
            return token
        }
        let stringValue = String(bytes: bytes, encoding: .utf8) ?? "<non-utf8>"
        throw EncodingError.singleTokenNotFound(stringValue)
    }
    
    /// Decodes a single token into its byte payload.
    public func decodeSingleTokenBytes(token: Int) throws -> [UInt8] {
        if let bytes = coreBpe.decodeSingleTokenBytes(token: token) {
            return bytes
        }
        throw EncodingError.tokenBytesNotFound(token)
    }
    
    /// Returns decoded bytes per token for debugging.
    public func decodeTokensBytes(tokens: [Int]) -> [Data] {
        coreBpe.decodeTokensBytes(tokens: tokens).map { Data($0) }
    }
    
    /// Available special-token keys.
    public var specialTokensSet: Set<String> {
        Set(specialTokens.keys)
    }
    
    /// Vocabulary size (`maxToken + 1`).
    public var nVocab: Int {
        maxValueToken + 1
    }
    
    /// Value for `<|endoftext|>`, when present.
    public var eotToken: Int? {
        specialTokens["<|endoftext|>"]
    }
    
    /// Returns byte blobs for every token.
    public func tokenByteValues() -> [Data] {
        coreBpe.tokenByteValues()
    }
}

private extension Encoding {
    func validateExplicitNVocab() {
        guard let explicit = explicitNVocab else { return }
        assert(mergeableRanks.count + specialTokens.count == explicit,
               "Mismatch between explicit vocab and provided ranks")
        assert(maxValueToken == explicit - 1, "Max token value mismatch")
    }
    
    func resolve(set: SpecialTokenSet) -> Set<String> {
        switch set {
        case .none:
            return []
        case .all:
            return specialTokensSet
        case let .only(values):
            return values
        case .automatic:
            // `.automatic` behaves the same as `.none` for the allowed set.
            return []
        }
    }
    
    func resolveDisallowed(set: SpecialTokenSet, allowed: Set<String>) -> Set<String> {
        switch set {
        case .automatic:
            return specialTokensSet.subtracting(allowed)
        default:
            return resolve(set: set)
        }
    }

    func tokenCountInternal(text: String,
                            allowed: Set<String>,
                            disallowed: Set<String>) throws -> Int {
        var cursor = text.startIndex
        var total = 0
        while cursor < text.endIndex {
            if let match = matchSpecial(in: text, at: cursor) {
                if disallowed.contains(match.token) {
                    throw EncodingError.disallowedSpecialToken(match.token)
                }
                if allowed.contains(match.token), specialTokens[match.token] != nil {
                    total += 1
                    cursor = match.range.upperBound
                    continue
                }
            }
            let nextSpecialStart = nextSpecial(in: text, from: cursor)?.range.lowerBound ?? text.endIndex
            if nextSpecialStart == cursor {
                let nextIndex = text.index(after: cursor)
                let chunk = String(text[cursor..<nextIndex])
                total += coreBpe.encodeOrdinaryNative(text: chunk).count
                cursor = nextIndex
                continue
            }
            let chunk = String(text[cursor..<nextSpecialStart])
            total += coreBpe.encodeOrdinaryNative(text: chunk).count
            cursor = nextSpecialStart
        }
        return total
    }

    func streamEncode(text: String,
                      allowed: Set<String>,
                      disallowed: Set<String>,
                      chunkSize: Int,
                      yield: (TokenStreamChunk) throws -> Void) throws {
        var cursor = text.startIndex
        let chunkSize = max(1, chunkSize)
        while cursor < text.endIndex {
            if let match = matchSpecial(in: text, at: cursor) {
                if disallowed.contains(match.token) {
                    throw EncodingError.disallowedSpecialToken(match.token)
                }
                if allowed.contains(match.token), let tokenValue = specialTokens[match.token] {
                    let position = text.distance(from: text.startIndex, to: match.range.lowerBound)
                    try yield(TokenStreamChunk(tokens: [tokenValue], kind: .special(token: match.token, position: position)))
                    cursor = match.range.upperBound
                    continue
                }
            }
            let nextSpecialStart = nextSpecial(in: text, from: cursor)?.range.lowerBound ?? text.endIndex
            guard nextSpecialStart > cursor else {
                cursor = text.index(after: cursor)
                continue
            }
            let chunkRange = cursor..<nextSpecialStart
            let chunkText = String(text[chunkRange])
            let chunkTokens = coreBpe.encodeOrdinaryNative(text: chunkText)
            guard !chunkTokens.isEmpty else {
                cursor = nextSpecialStart
                continue
            }
            let startOffset = text.distance(from: text.startIndex, to: chunkRange.lowerBound)
            let endOffset = text.distance(from: text.startIndex, to: chunkRange.upperBound)
            var index = 0
            while index < chunkTokens.count {
                let remaining = chunkTokens.count - index
                let take = min(chunkSize, remaining)
                let slice = Array(chunkTokens[index..<(index + take)])
                try yield(TokenStreamChunk(tokens: slice, kind: .text(range: startOffset..<endOffset)))
                index += take
            }
            cursor = nextSpecialStart
        }
    }
    
    func encodeInternal(text: String,
                         allowed: Set<String>,
                         disallowed: Set<String>) throws -> [Int] {
        try encodeInternal(text: text,
                           allowed: allowed,
                           disallowed: disallowed,
                           captureLastPiece: false).tokens
    }

    func encodeInternal(text: String,
                         allowed: Set<String>,
                         disallowed: Set<String>,
                         captureLastPiece: Bool) throws -> (tokens: [Int], lastPieceTokenLength: Int) {
        var cursor = text.startIndex
        var tokens = [Int]()
        var lastPieceTokenLength = 0
        while cursor < text.endIndex {
            if let match = matchSpecial(in: text, at: cursor) {
                if disallowed.contains(match.token) {
                    throw EncodingError.disallowedSpecialToken(match.token)
                }
                if allowed.contains(match.token), let tokenValue = specialTokens[match.token] {
                    tokens.append(tokenValue)
                    cursor = match.range.upperBound
                    lastPieceTokenLength = 0
                    continue
                }
            }
            let nextSpecialStart = nextSpecial(in: text, from: cursor)?.range.lowerBound ?? text.endIndex
            if nextSpecialStart == cursor {
                let nextIndex = text.index(after: cursor)
                let chunk = String(text[cursor..<nextIndex])
                let chunkTokens = coreBpe.encodeOrdinaryNative(text: chunk)
                tokens.append(contentsOf: chunkTokens)
                lastPieceTokenLength = chunkTokens.count
                cursor = nextIndex
                continue
            }
            let chunk = String(text[cursor..<nextSpecialStart])
            let chunkTokens = coreBpe.encodeOrdinaryNative(text: chunk)
            tokens.append(contentsOf: chunkTokens)
            lastPieceTokenLength = chunkTokens.count
            cursor = nextSpecialStart
        }
        return (tokens, captureLastPiece ? lastPieceTokenLength : 0)
    }
    
    func matchSpecial(in text: String, at index: String.Index) -> (token: String, range: Range<String.Index>)? {
        for token in specialTokenKeys {
            guard let end = text.index(index, offsetBy: token.count, limitedBy: text.endIndex) else { continue }
            if String(text[index..<end]) == token {
                return (token, index..<end)
            }
        }
        return nil
    }
    
    func nextSpecial(in text: String, from start: String.Index) -> (token: String, range: Range<String.Index>)? {
        var best: (token: String, range: Range<String.Index>)?
        for token in specialTokenKeys {
            guard let range = text.range(of: token, options: [], range: start..<text.endIndex) else { continue }
            if let current = best {
                if range.lowerBound < current.range.lowerBound {
                    best = (token, range)
                }
            } else {
                best = (token, range)
            }
        }
        return best
    }

    func flattenBytes(byteChunks: [[UInt8]]) -> [UInt8] {
        let total = byteChunks.reduce(0) { $0 + $1.count }
        var flattened = [UInt8]()
        flattened.reserveCapacity(total)
        byteChunks.forEach { flattened.append(contentsOf: $0) }
        return flattened
    }

    func buildUnstableCompletions(unstableBytes: [UInt8]) -> [[Int]] {
        guard !unstableBytes.isEmpty else { return [] }
        var completions = Set<[Int]>()
        for match in coreBpe.tokensStarting(with: unstableBytes) {
            completions.insert([match.1])
        }
        if unstableBytes.count > 1 {
            for index in 1..<unstableBytes.count {
                let prefix = Array(unstableBytes[..<index])
                let suffix = Array(unstableBytes[index...])
                let suffixMatches = coreBpe.tokensStarting(with: suffix)
                guard !suffixMatches.isEmpty else { continue }
                for match in suffixMatches {
                    var possibility = prefix
                    possibility.append(contentsOf: match.0)
                    let encoded: [Int]
                    if let text = String(bytes: possibility, encoding: .utf8) {
                        encoded = coreBpe.encodeOrdinaryNative(text: text)
                    } else {
                        encoded = coreBpe.bytePairEncodeRaw(piece: possibility)
                    }
                    guard !encoded.isEmpty else { continue }
                    var seq = [Int]()
                    seq.reserveCapacity(encoded.count)
                    var consumed = 0
                    for token in encoded {
                        seq.append(token)
                        consumed += coreBpe.byteCount(for: token)
                        if consumed >= unstableBytes.count {
                            break
                        }
                    }
                    if !seq.isEmpty {
                        completions.insert(seq)
                    }
                }
            }
        }
        if unstableBytes.count > 1 {
            let (lastChar, lastCharLength) = decodeLastScalar(bytes: unstableBytes)
            if lastCharLength > 0,
               unstableBytes.count - lastCharLength > 0,
               (lastChar?.isWhitespace ?? false) {
                let suffixStart = unstableBytes.count - lastCharLength
                var prefixTokens = coreBpe.bytePairEncodeRaw(piece: Array(unstableBytes[..<suffixStart]))
                let suffixTokens = coreBpe.bytePairEncodeRaw(piece: Array(unstableBytes[suffixStart...]))
                prefixTokens.append(contentsOf: suffixTokens)
                if !prefixTokens.isEmpty {
                    completions.insert(prefixTokens)
                }
            }
        }
        return completions.sorted { $0.lexicographicallyPrecedes($1) }
    }

    func decodeLastScalar(bytes: [UInt8]) -> (Character?, Int) {
        guard !bytes.isEmpty else { return (nil, 0) }
        var length = 1
        var index = bytes.count - 1
        while index > 0 && (bytes[index] & 0b1100_0000) == 0b1000_0000 {
            length += 1
            index -= 1
        }
        length = min(length, bytes.count)
        let scalarStart = bytes.count - length
        let scalarSlice = Array(bytes[scalarStart..<bytes.count])
        if let character = String(bytes: scalarSlice, encoding: .utf8)?.first {
            return (character, length)
        }
        return (nil, 1)
    }
}
