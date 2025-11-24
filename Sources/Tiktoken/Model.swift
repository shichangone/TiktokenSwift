//
//  Model.swift
//  
//
//  Created by Alberto Espinilla Garrido on 20/3/23.
//

import Foundation

enum Model {
    static let modelPrefixToEncoding: [String: String] = [
        "o1-": "o200k_base",
        "o3-": "o200k_base",
        "o3-mini-": "o200k_base",
        "o1-mini-": "o200k_base",
        "o4-mini-": "o200k_base",
        // chat
        "gpt-5.1-": "o200k_base",
        "gpt-5-": "o200k_base",
        "gpt-4.5-": "o200k_base",
        "gpt-4.1-": "cl100k_base",
        "chatgpt-4o-": "o200k_base",
        "gpt-4o-": "o200k_base",  // e.g., gpt-4o-2024-05-13
        "gpt-4-": "cl100k_base",  // e.g., gpt-4-0314, etc., plus gpt-4-32k
        "gpt-3.5-turbo-": "cl100k_base",  // e.g, gpt-3.5-turbo-0301, -0401, etc.
        "gpt-35-turbo-": "cl100k_base",  // Azure deployment name
        "gpt-oss-": "o200k_harmony",
        // fine-tuned
        "ft:gpt-4o": "o200k_base",
        "ft:gpt-4": "cl100k_base",
        "ft:gpt-3.5-turbo": "cl100k_base",
        "ft:davinci-002": "cl100k_base",
        "ft:babbage-002": "cl100k_base"
    ]
    
    static let modelToEncoding: [String: String] = [
        // chat
        "o1": "o200k_base",
        "o3": "o200k_base",
        "o3-mini": "o200k_base",
        "o1-mini": "o200k_base",
        "o1-preview": "o200k_base",
        "o4-mini": "o200k_base",
        "gpt-5.1": "o200k_base",
        "gpt-5": "o200k_base",
        "gpt-5-mini": "o200k_base",
        "gpt-5-nano": "o200k_base",
        "gpt-4.1": "cl100k_base",
        "gpt-4o": "o200k_base",
        "gpt-4": "cl100k_base",
        "gpt-3.5-turbo": "cl100k_base",
        "gpt-3.5": "cl100k_base",  // Common shorthand
        "gpt-35-turbo": "cl100k_base",  // Azure deployment name
        // base
        "davinci-002": "cl100k_base",
        "babbage-002": "cl100k_base",
        // embeddings
        "text-embedding-ada-002": "cl100k_base",
        "text-embedding-3-small": "cl100k_base",
        "text-embedding-3-large": "cl100k_base",
        // DEPRECATED MODELS
        // text (DEPRECATED)
        "text-davinci-003": "p50k_base",
        "text-davinci-002": "p50k_base",
        "text-davinci-001": "r50k_base",
        "text-curie-001": "r50k_base",
        "text-babbage-001": "r50k_base",
        "text-ada-001": "r50k_base",
        "davinci": "r50k_base",
        "curie": "r50k_base",
        "babbage": "r50k_base",
        "ada": "r50k_base",
        // code (DEPRECATED)
        "code-davinci-002": "p50k_base",
        "code-davinci-001": "p50k_base",
        "code-cushman-002": "p50k_base",
        "code-cushman-001": "p50k_base",
        "davinci-codex": "p50k_base",
        "cushman-codex": "p50k_base",
        // edit (DEPRECATED)
        "text-davinci-edit-001": "p50k_edit",
        "code-davinci-edit-001": "p50k_edit",
        // old embeddings (DEPRECATED)
        "text-similarity-davinci-001": "r50k_base",
        "text-similarity-curie-001": "r50k_base",
        "text-similarity-babbage-001": "r50k_base",
        "text-similarity-ada-001": "r50k_base",
        "text-search-davinci-doc-001": "r50k_base",
        "text-search-curie-doc-001": "r50k_base",
        "text-search-babbage-doc-001": "r50k_base",
        "text-search-ada-doc-001": "r50k_base",
        "code-search-babbage-code-001": "r50k_base",
        "code-search-ada-code-001": "r50k_base",
        // open source
        "gpt2": "gpt2",
        "gpt-2": "gpt2",  // Maintains consistency with gpt-4
    ]
    
    static func getEncoding(_ name: String) -> Vocab? {
        EncodingRegistry.shared.vocab(for: name)
    }

    static func registerDefaults(into registry: EncodingRegistry) {
        modelToEncoding.forEach { registry.registerAlias($0.key, encodingName: $0.value) }
        modelPrefixToEncoding.forEach { registry.registerPrefixAlias($0.key, encodingName: $0.value) }
    }
}