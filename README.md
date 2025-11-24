# Tiktoken (Swift)

A Swift implementation of OpenAI's `tiktoken`, focused on parity with the official Python library while remaining lightweight and fully async-ready.

## Supported vocabularies

- `gpt2` (also covers GPT-3)
- `r50k_base`
- `p50k_base`
- `p50k_edit`
- `cl100k_base` (GPT-4 / GPT-3.5 turbo)
- `o200k_base` (GPT-4o, o1, o1-mini, gpt-4o-mini)

Unicode, CJK, and emoji round-trips are verified in the test suite.

## Usage

### Basic encode / decode

```swift
guard let encoder = try await Tiktoken.shared.getEncoding("gpt-4") else {
	return
}

let tokens = try encoder.encode(value: "這個算法真的太棒了", disallowedSpecial: .none)
print(tokens)
print(encoder.decode(value: tokens))

let offsets = encoder.decodeWithOffsets(tokens: tokens)
print(offsets.text, offsets.offsets)
```

### Special tokens & offsets

```swift
let special = try encoder.encode(
	value: "<|endoftext|>",
	allowedSpecial: .only(["<|endoftext|>"]),
	disallowedSpecial: .automatic
)
let single = try encoder.encodeSingleToken(value: "<|endoftext|>")
let bytes = try encoder.decodeSingleTokenBytes(token: single)
print("Special token: \(special), bytes: \(bytes)")
```

### Batch operations (Swift concurrency)

```swift
let inputs = ["hello", "emoji 👩‍💻 mix", "你好，世界"]
let batchTokens = try await encoder.encodeBatch(values: inputs,
												disallowedSpecial: .none,
												maxConcurrency: 4)
let decoded = await encoder.decodeBatch(batch: batchTokens)
print(decoded)
```

### Token counting (O(1) memory)

```swift
let text = "function call(🧪: Int) -> Int"
let count = try encoder.tokenCount(value: text,
								   allowedSpecial: .none,
								   disallowedSpecial: .automatic)
print("Token count only: \(count)")
```

`tokenCount` shares the same tokenizer pipeline as `encode` but never materializes the array. It is ideal for quota checks or fast estimations.

### Native BPE & unstable completions

```swift
let ordinary = encoder.encodeOnlyNativeBpe(value: prompt)
let (stable, completions) = try encoder.encodeWithUnstable(value: prompt,
														   allowedSpecial: .all,
														   disallowedSpecial: .none)
print("Stable prefix tokens: \(stable.count)")
print("First completion candidate: \(completions.first ?? [])")
```

`encodeWithUnstable` mirrors Python's `encode_with_unstable`, so each completion sequence appended to `stable` still decodes to the original prefix.

### Streaming tokens (AsyncSequence & Combine)

```swift
let stream = encoder.tokenStream(value: prompt,
								 allowedSpecial: .all,
								 disallowedSpecial: .none,
								 request: .init(chunkSize: 64))

for try await chunk in stream {
	switch chunk.kind {
	case let .text(range):
		print("text chunk covering characters", range)
	case let .special(token, position):
		print("special token", token, "at", position)
	}
}
```

On Apple platforms that ship with Combine you can bridge the async stream:

```swift
import Combine

let cancellable = encoder.tokenPublisher(value: prompt)
	.sink(receiveCompletion: { completion in
		print("Completed:", completion)
	}, receiveValue: { chunk in
		print("chunk tokens", chunk.tokens)
	})
```

### Custom vocab registration

```swift
let tempURL = URL(fileURLWithPath: "/path/to/custom.tiktoken")
let customVocab = Vocab(name: "custom-local",
						url: tempURL.path,
						explicitNVocab: 128,
						pattern: "[\\s\\S]",
						specialTokens: [:])

Tiktoken.shared.registerEncoding(customVocab,
								 loader: .tiktokenFile(source: .local(path: tempURL.path)))
Tiktoken.shared.registerModelAlias("my-model", encodingName: customVocab.name)

let customEncoder = try await Tiktoken.shared.getEncoding("my-model")
```

### Cache configuration & discovery

```swift
Tiktoken.shared.configureRegistry(.init(cacheDirectory: URL(fileURLWithPath: "/tmp/tiktoken-cache"),
										environmentKey: "MY_TIKTOKEN_CACHE",
										verifyChecksums: true))

let encodings = Tiktoken.shared.availableEncodingNames()
print("Built-in encodings:", encodings)
```

### Plugin-based registry & persistence

Plugins conform to `EncodingPlugin`, register custom vocabs/aliases, and are persisted as metadata:

```swift
public final class MyPlugin: EncodingPlugin {
	public let metadata = EncodingPluginMetadata(identifier: "com.example.myplugin",
												 version: "1.0.0",
												 summary: "Adds corp-1 encoding")

	public func register(into registry: EncodingRegistry, context: EncodingPluginContext) throws {
		registry.register(.init(vocab: myVocab, loader: .mergeableRanks(myRanks)))
		registry.registerAlias("corp-1", encodingName: myVocab.name)
	}

	public func deregister(from registry: EncodingRegistry) {
		registry.unregisterAlias("corp-1")
		registry.unregisterEncoding(named: myVocab.name)
	}
}

let pluginDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("tiktoken-plugins")
Tiktoken.shared.configureRegistry(.init(pluginDirectory: pluginDirectory))
try EncodingRegistry.shared.load(plugin: MyPlugin())
EncodingRegistry.shared.restorePersistedPlugins { metadata in
	metadata.identifier == "com.example.myplugin" ? MyPlugin() : nil
}
```

`plugins.json` is stored under the configured `pluginDirectory`, enabling your app to restore plugins after restart.

### Benchmarks & QA

- **Benchmarks**: `swift run TiktokenBenchmarks --iterations 25` executes encode/tokenCount/encodeBatch throughput tests and prints average latency per iteration.
- **SwiftCheck property tests**: `swift test` now includes random Unicode/emoji round-trip checks to ensure `decode(encode(x)) == x` under permissive special-token policies.


Stars are always appreciated.