//
//  Vocab.swift
//  
//
//  Created by Alberto Espinilla Garrido on 17/5/23.
//

import Foundation

public struct Vocab {
    public let name: String
    public let url: String
    public let explicitNVocab: Int?
    public let pattern: String
    public let specialTokens: [String: Int]
    private static let o200kPattern = "[^\\r\\n\\p{L}\\p{N}]?[\\p{Lu}\\p{Lt}\\p{Lm}\\p{Lo}\\p{M}]*[\\p{Ll}\\p{Lm}\\p{Lo}\\p{M}]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?|[^\\r\\n\\p{L}\\p{N}]?[\\p{Lu}\\p{Lt}\\p{Lm}\\p{Lo}\\p{M}]+[\\p{Ll}\\p{Lm}\\p{Lo}\\p{M}]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?|\\p{N}{1,3}| ?[^\\s\\p{L}\\p{N}]+[\\r\\n/]*|\\s*[\\r\\n]+|\\s+(?!\\S)|\\s+"
    
    public init(name: String,
                url: String,
                explicitNVocab: Int? = nil,
                pattern: String,
                specialTokens: [String : Int] = [:]) {
        self.name = name
        self.url = url
        self.explicitNVocab = explicitNVocab
        self.pattern = pattern
        self.specialTokens = specialTokens
    }
}

public extension Vocab {
    static var gpt2: Vocab {
        .init(name: "gpt2",
              url: "https://openaipublic.blob.core.windows.net/gpt-2/encodings/main/vocab.bpe",
              explicitNVocab: 50257,
              pattern: "'s|'t|'re|'ve|'m|'ll|'d| ?\\p{L}+| ?\\p{N}+| ?[^\\s\\p{L}\\p{N}]+|\\s+(?!\\S)|\\s+",
              specialTokens: ["<|endoftext|>": 50256])
    }
    
    static var r50kBase: Vocab {
        .init(name: "r50k_base",
              url: "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
              explicitNVocab: 50257,
              pattern: "'s|'t|'re|'ve|'m|'ll|'d| ?\\p{L}+| ?\\p{N}+| ?[^\\s\\p{L}\\p{N}]+|\\s+(?!\\S)|\\s+",
              specialTokens: ["<|endoftext|>": 50256])
    }
    
    static var p50kBase: Vocab {
        .init(name: "p50k_base",
              url: "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
              explicitNVocab: 50281,
              pattern: "'s|'t|'re|'ve|'m|'ll|'d| ?\\p{L}+| ?\\p{N}+| ?[^\\s\\p{L}\\p{N}]+|\\s+(?!\\S)|\\s+",
              specialTokens: ["<|endoftext|>": 50256])
    }
    
    static var p50kEdit: Vocab {
        .init(name: "p50k_edit",
              url: "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
              pattern: "'s|'t|'re|'ve|'m|'ll|'d| ?\\p{L}+| ?\\p{N}+| ?[^\\s\\p{L}\\p{N}]+|\\s+(?!\\S)|\\s+",
              specialTokens: [
                "<|endoftext|>": 50256,
                "<|fim_prefix|>": 50281,
                "<|fim_middle|>": 50282,
                "<|fim_suffix|>": 50283
              ])
    }
    
    static var cl100kBase: Vocab {
        .init(name: "cl100k_base",
              url: "https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken",
              pattern: "(?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\\r\\n\\p{L}\\p{N}]?\\p{L}+|\\p{N}{1,3}| ?[^\\s\\p{L}\\p{N}]+[\\r\\n]*|\\s*[\\r\\n]+|\\s+(?!\\S)|\\s+",
              specialTokens: [
                "<|endoftext|>": 100257,
                "<|fim_prefix|>": 100258,
                "<|fim_middle|>": 100259,
                "<|fim_suffix|>": 100260,
                "<|endofprompt|>": 100276
              ])
    }

    static var o200kBase: Vocab {
        .init(name: "o200k_base",
              url: "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
              pattern: o200kPattern,
              specialTokens: [
                "<|endoftext|>": 199999,
                "<|endofprompt|>": 200018
              ])
    }

    static var o200kHarmony: Vocab {
        var tokens = o200kBase.specialTokens
        tokens["<|startoftext|>"] = 199998
        tokens["<|reserved_200000|>"] = 200000
        tokens["<|reserved_200001|>"] = 200001
        tokens["<|return|>"] = 200002
        tokens["<|constrain|>"] = 200003
        tokens["<|reserved_200004|>"] = 200004
        tokens["<|channel|>"] = 200005
        tokens["<|start|>"] = 200006
        tokens["<|end|>"] = 200007
        tokens["<|message|>"] = 200008
        tokens["<|reserved_200009|>"] = 200009
        tokens["<|reserved_200010|>"] = 200010
        tokens["<|reserved_200011|>"] = 200011
        tokens["<|call|>"] = 200012
        (200013...201087).forEach({ index in
            let reservedKey = "<|reserved_\(String(index))|>"
            tokens[reservedKey] = index
        })
        return .init(name: "o200k_harmony",
                     url: "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
                     pattern: o200kPattern,
                     specialTokens: tokens)
    }
    
    static var all: [Vocab] = [.gpt2, .r50kBase, .p50kBase, .p50kEdit, .cl100kBase, .o200kBase, .o200kHarmony]
}
