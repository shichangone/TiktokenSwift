# TiktokenSwift

[![Swift](https://img.shields.io/badge/Swift-5.7+-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2013%20%7C%20macOS%2010.15%20%7C%20watchOS%206%20%7C%20tvOS%2013-blue.svg)](https://developer.apple.com/swift/)
[![License](https://img.shields.io/badge/License-MIT-lightgrey.svg)](LICENSE)

A high-performance, pure Swift implementation of OpenAI's `tiktoken` tokenizer.

Designed for parity with the official Python library, **TiktokenSwift** is built with modern Swift concurrency (Async/Await), providing a thread-safe, memory-efficient, and extensible solution for tokenizing text for LLMs.

## 🌟 Key Features

*   **Full Parity:** Supports all official OpenAI encodings, including `o200k_base` (**GPT-4o**, **o1**).
*   **Async-First:** Heavy lifting is done off the main thread using Swift Concurrency (`TaskGroup`, actors).
*   **Streaming Support:** Tokenize in real-time using `AsyncThrowingStream` or **Combine** publishers.
*   **Zero-Dependency:** No external C++ bindings or heavy dependencies.
*   **Memory Efficient:** dedicated `tokenCount` method for O(1) memory usage when you don't need the tokens.
*   **Robust:** Verified with **SwiftCheck** property-based testing to ensure Unicode, Emoji, and CJK round-trip stability.
*   **Extensible:** Plugin system to load custom vocabularies or cache from remote sources.

## 📦 Installation

Add `Tiktoken` to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/shichangone/TiktokenSwift.git", from: "1.0.0")
]
```

Then import it in your target:

```swift
import Tiktoken
```

## 🤖 Supported Models

| Encoding | Associated Models |
| :--- | :--- |
| **`o200k_base`** | **GPT-5.1** (Instant / Thinking)<br>**GPT-5** (including mini/nano)<br>**o1**, **o1-mini**, **o1-preview**<br>**o3**, **o3-mini**<br>**gpt-4o**, **gpt-4o-mini** |
| **`cl100k_base`** | **GPT-4.1** (Smartest non-reasoning)<br>**gpt-4**, gpt-4-turbo<br>gpt-3.5-turbo<br>text-embedding-3-small/large |
| `p50k_base` | text-davinci-003, code-davinci-002 |
| `r50k_base` | GPT-3 series (davinci, curie, babbage) |
| `gpt2` | GPT-2 |

## 🚀 Usage

### 1. Basic Encoding & Decoding

Get an encoder by model name. The library handles caching and loading automatically.

```swift
// Initialize the encoder (async load)
guard let encoder = try await Tiktoken.shared.getEncoding("gpt-4o") else {
    print("Failed to load model")
    return
}

// Encode text to integers
let text = "Hello, world! 🌍"
let tokens = try encoder.encode(value: text)
print("Tokens:", tokens) // [9906, 11, 1917, 0, 235]

// Decode back to string
let decoded = encoder.decode(value: tokens)
print("Decoded:", decoded)
```

### 2. Batch Encoding (Concurrency)

Process multiple strings in parallel, automatically utilizing available CPU cores.

```swift
let documents = ["Document 1...", "Document 2...", "Document 3..."]

// Encodes concurrently with a limit of 4 active tasks
let batchTokens = try await encoder.encodeBatch(
    values: documents,
    maxConcurrency: 4
)

// Decode efficiently
let decodedBatch = await encoder.decodeBatch(batch: batchTokens)
```

### 3. Token Counting (Memory Optimized)

If you only need the *count* (e.g., for checking context window limits), use `tokenCount`. It avoids allocating the integer array in memory.

```swift
let prompt = "Describe the theory of relativity..."
let count = try encoder.tokenCount(value: prompt)
print("Token usage: \(count)")
```

### 4. Special Tokens

Handle special tokens like `<|endoftext|>` with granular control.

```swift
let prompt = "<|endoftext|>System: You are a helper."

// ❌ Throws error (Security default)
// try encoder.encode(value: prompt, disallowedSpecial: .automatic)

// ✅ Explicitly allow specific tokens
let tokens = try encoder.encode(
    value: prompt,
    allowedSpecial: .only(["<|endoftext|>"]),
    disallowedSpecial: .automatic
)
```

### 5. Streaming Tokens

Ideal for UI applications (like typing effects). Supports both `AsyncSequence` and `Combine`.

**Async/Await:**
```swift
let stream = encoder.tokenStream(
    value: longText,
    request: .init(chunkSize: 64)
)

for try await chunk in stream {
    switch chunk.kind {
    case .text(let range):
        print("Processed range: \(range)")
    case .special(let token, let pos):
        print("Special token found: \(token)")
    }
}
```

**Combine:**
```swift
let cancellable = encoder.tokenPublisher(value: longText)
    .sink(receiveCompletion: { _ in }, receiveValue: { chunk in
        print("Received chunk of \(chunk.tokens.count) tokens")
    })
```

### 6. Unstable Completions (Advanced)

Mirrors Python's `encode_with_unstable`. Useful when streaming incomplete text chunks where the last token might merge with future input.

```swift
let partial = "Hello fan" 
let (stable, completions) = try encoder.encodeWithUnstable(value: partial)

// 'stable' are tokens that won't change.
// 'completions' are potential tokens for the suffix (e.g., completing "fan" -> "fantastic")
```

## ⚙️ Configuration & Plugins

### Caching

Configure where vocabulary files are downloaded and stored.

```swift
Tiktoken.shared.configureRegistry(.init(
    cacheDirectory: URL(fileURLWithPath: "/path/to/cache"),
    verifyChecksums: true // Validates SHA256 of downloaded files
))
```

### Custom Vocabularies

Register your own BPE dictionaries from local files.

```swift
let customVocab = Vocab(
    name: "my-custom-model",
    url: "file:///local/vocab.bpe",
    pattern: #"[^\s]+|\s+"#, // Regex pattern
    specialTokens: ["<|padding|>": 100]
)

Tiktoken.shared.registerEncoding(customVocab, loader: .tiktokenFile(source: .local(path: "...")))
let myEncoder = try await Tiktoken.shared.getEncoding("my-custom-model")
```

### Plugin System

Implement the `EncodingPlugin` protocol to distribute custom tokenizers or proprietary encoding logic.

```swift
class MyCorpPlugin: EncodingPlugin {
    var metadata = EncodingPluginMetadata(identifier: "com.corp.tokenizer", version: "1.0", summary: "Corp Internal")

    func register(into registry: EncodingRegistry, context: EncodingPluginContext) throws {
        // Register custom vocabs/aliases here
    }
    
    func deregister(from registry: EncodingRegistry) { ... }
}

try EncodingRegistry.shared.load(plugin: MyCorpPlugin())
```

## 📊 Benchmarks

TiktokenSwift includes a benchmark suite to measure throughput.

To run benchmarks:
```bash
swift run TiktokenBenchmarks --iterations 25
```

*Typical performance covers encoding, decoding, and token counting latency across large paragraphs and batches.*

## 📄 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.