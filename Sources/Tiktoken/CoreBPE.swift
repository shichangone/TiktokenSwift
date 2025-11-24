//
//  CoreBPE.swift
//  
//
//  Created by Alberto Espinilla Garrido on 23/3/23.
//

import Foundation

final class CoreBPE {
    private let encoder: [[UInt8]: Int]
    private let specialTokensEncoder: [String: Int]
    private let decoder: [Int: [UInt8]]
    private let specialTokensDecoder: [Int: [UInt8]]
    private let regexTls: [NSRegularExpression]
    private let sortedTokenBytes: [[UInt8]]

    init(encoder: [[UInt8]: Int] = .init(),
         specialTokensEncoder: [String: Int] = .init(),
         decoder: [Int: [UInt8]] = .init(),
         specialTokensDecoder: [Int: [UInt8]] = .init(),
         regexTls: [NSRegularExpression] = .init()) {
        self.encoder = encoder
        self.specialTokensEncoder = specialTokensEncoder
        self.decoder = decoder
        self.specialTokensDecoder = specialTokensDecoder
        self.regexTls = regexTls
        self.sortedTokenBytes = encoder.keys.sorted { lhs, rhs in
            lhs.lexicographicallyPrecedes(rhs)
        }
    }

    /// Splits text with the base regex and performs BPE merges.
    /// - Parameter text: Source text to encode.
    /// - Returns: Token sequence representing the text.
    func encodeOrdinaryNative(text: String) -> [Int] {
        guard let regex = regexTls.first else { return [] }
        var ret = [Int]()
        for mat in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(mat.range, in: text) else { continue }
            let piece = Array(text[range].utf8)
            let encoded = encodeSinglePiece(piece)
            ret.append(contentsOf: encoded)
        }
        return ret
    }
    
    /// Runs byte pair encoding for a single UTF-8 slice.
    /// - Parameter piece: Target byte slice.
    /// - Returns: Tokens produced by the slice.
    func encodeSinglePiece(_ piece: [UInt8]) -> [Int] {
        if let token = encoder[piece] {
            return [token]
        }
        return bytePairEncode(piece, encoder)
    }

    /// Finds the byte representation for a token.
    /// - Parameter token: Token identifier.
    /// - Returns: Token bytes if available.
    func decodeSingleTokenBytes(token: Int) -> [UInt8]? {
        if let specialBytes = specialTokensDecoder[token] {
            return specialBytes
        }
        return decoder[token]
    }

    /// Converts a list of tokens back into bytes.
    /// - Parameter tokens: Sequence to decode.
    /// - Returns: Data buffer representing the tokens.
    func decodeBytes(tokens: [Int]) -> Data {
        tokens.reduce(into: Data()) { partialResult, token in
            if let bytes = decodeSingleTokenBytes(token: token) {
                partialResult.append(contentsOf: bytes)
            }
        }
    }

    /// Returns byte payloads for all tokens, useful for visualization.
    func tokenByteValues() -> [Data] {
        let decoderKeys = Set(decoder.keys)
        let specialKeys = Set(specialTokensDecoder.keys)
        let allKeys = decoderKeys.union(specialKeys)
        guard let maxToken = allKeys.max() else { return [] }
        return (0...maxToken).compactMap { token -> Data? in
            guard let bytes = decodeSingleTokenBytes(token: token) else { return nil }
            return Data(bytes)
        }
    }
    
    /// Finds the token that matches the provided bytes exactly.
    func encodeSingleToken(bytes: [UInt8]) -> Int? {
        if let token = encoder[bytes] {
            return token
        }
        if let text = String(bytes: bytes, encoding: .utf8),
           let special = specialTokensEncoder[text] {
            return special
        }
        return nil
    }
    
    /// Converts tokens into byte arrays for offset calculations.
    func decodeTokensBytes(tokens: [Int]) -> [[UInt8]] {
        tokens.compactMap { decodeSingleTokenBytes(token: $0) }
    }

    /// Runs BPE without regex splitting, mirroring `byte_pair_encode`.
    func bytePairEncodeRaw(piece: [UInt8]) -> [Int] {
        bytePairEncode(piece, encoder)
    }

    /// Finds tokens whose byte payload starts with a prefix.
    func tokensStarting(with prefix: [UInt8]) -> [([UInt8], Int)] {
        guard !prefix.isEmpty, !sortedTokenBytes.isEmpty else { return [] }
        var matches: [([UInt8], Int)] = []
        var low = 0
        var high = sortedTokenBytes.count
        while low < high {
            let mid = (low + high) / 2
            if sortedTokenBytes[mid].lexicographicallyPrecedes(prefix) {
                low = mid + 1
            } else {
                high = mid
            }
        }
        var index = low
        while index < sortedTokenBytes.count {
            let bytes = sortedTokenBytes[index]
            if bytes.starts(with: prefix) {
                if let token = encoder[bytes] {
                    matches.append((bytes, token))
                }
                index += 1
                continue
            }
            break
        }
        return matches
    }

    /// Returns `true` when a token decodes exclusively to whitespace bytes.
    func tokenIsAllWhitespace(token: Int) -> Bool {
        guard let bytes = decodeSingleTokenBytes(token: token) else { return false }
        return bytes.allSatisfy { byte in
            byte == 0x20 || byte == 0x0A || byte == 0x09
        }
    }

    /// Computes decoded byte length for a token (0 if unknown).
    func byteCount(for token: Int) -> Int {
        decodeSingleTokenBytes(token: token)?.count ?? 0
    }

    /// Extends the last piece length if whitespace merges can destabilize splits.
    func extendedLastPieceLength(tokens: [Int], lastPieceTokenLength: Int) -> Int {
        guard lastPieceTokenLength > 0, tokens.count >= lastPieceTokenLength else {
            return lastPieceTokenLength
        }
        var length = lastPieceTokenLength
        var index = tokens.count - length
        guard index < tokens.count, tokenIsAllWhitespace(token: tokens[index]) else {
            return length
        }
        while index > 0 {
            let previous = index - 1
            guard tokenIsAllWhitespace(token: tokens[previous]) else { break }
            length += 1
            index = previous
        }
        return length
    }
}

private extension CoreBPE {
    func bytePairMerge<T>(_ piece: [UInt8], _ ranks: [[UInt8]: Int], completion: (Range<Int>) -> T) -> [T] {
        // This is a vector of (start, rank).
        // The rank is of the byte pair starting at position start.
        // The rank of the last item in the vector is not a valid value.
        var parts = (0..<piece.count + 1).map { ($0, Int.max) }
        
        let getRank: ([(Int, Int)], Int, Int) -> Int? = { parts, startIdx, skip in
            let calculatedIndex = startIdx + skip + 2
            if calculatedIndex < parts.count {
                let range = parts[startIdx].0..<parts[calculatedIndex].0
                let subPiece = Array(piece[range])
                return ranks[subPiece]
            } else {
                return nil
            }
        }
        
        // We look up the ranks once in the beginning and iteratively update
        // them during each merge, which reduces the number of rank lookups.
        for i in 0..<(parts.count - 2) {
            if let rank = getRank(parts, i, 0) {
                assert(rank != Int.max)
                parts[i].1 = rank
            }
        }
        
        // If you have n parts and m merges, this does O(mn) work.
        // We could do something with a heap and do O(m log n) work.
        // It is important to consider that n is often small (<100), and as such
        // the cache-locality benefits outweigh the algorithmic complexity downsides
        // of the `parts` vector data structure above.

        // Note that we hash bytes, not token pairs. As long as we train BPE the way we
        // currently do, this is equivalent. An easy way to break this would be to decouple
        // merge priority from token index or to prevent specific token merges.
        while parts.count > 1 {
            // usize::MAX is a sentinel rank value allowing us to
            // take the min more quickly
            var minRank = (Int.max, 0)
            for (i, ( _, rank)) in parts.enumerated() {
                if rank < minRank.0 {
                    minRank = (rank, i)
                }
            }
            
            if minRank.0 != Int.max {
                let i = minRank.1
                
                // NOTE: We are about to remove parts[i + 1]. We do not do it
                // yet because there are cache-locality benefits to updating
                // parts[i] and parts[i-1] before removing, which could thrash
                // the cache. Thus, we update the rank calculation by skipping over
                // parts[i + 1], by invoking `get_rank!` with `skip = 1`.
                parts[i].1 = getRank(parts, i, 1) ?? Int.max
                if i > 0 {
                    parts[i - 1].1 = getRank(parts, i - 1, 1) ?? Int.max
                }
                parts.remove(at: i + 1)
            } else {
                break
            }
        }
        
        // TODO: Use ranks
        return parts.prevCurrent({ completion($0.0..<$1.0) })
    }
    
    func bytePairEncode(_ piece: [UInt8], _ ranks: [[UInt8]: Int]) -> [Int] {
        if piece.count == 1, let token = ranks[piece] {
            return [token]
        }
        let chunks: [[UInt8]] = bytePairMerge(piece, ranks, completion: { Array(piece[$0]) })
        return chunks.flatMap { chunk -> [Int] in
            if let token = ranks[chunk] {
                return [token]
            }
            if chunk.count == 1, let token = ranks[chunk] {
                return [token]
            }
            return chunk.compactMap { byte -> Int? in
                let key = [byte]
                return ranks[key]
            }
        }
    }
    
//    func bytePairSplit(_ piece: [UInt8], _ ranks: [[UInt8]: Int]) -> [[UInt8]] {
//        if piece.count == 1 {
//            return [piece]
//        }
//        return bytePairMerge(piece, ranks, completion: { Array(piece[$0]) })
//    }
}
