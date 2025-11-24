import XCTest
@testable import Tiktoken

/// Validates plugin lifecycle management (load/unload/restore).
final class EncodingPluginTests: XCTestCase {
    /// Resets the registry after each test to avoid cross-test pollution.
    override func tearDown() {
        super.tearDown()
        EncodingRegistry.shared.resetCustomRegistrations()
        Tiktoken.shared.configureRegistry(.init())
    }

    /// Loading a plugin should register its vocab and unloading should clean it up.
    func testPluginLoadAndUnloadLifecycle() throws {
        let pluginDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        Tiktoken.shared.configureRegistry(.init(pluginDirectory: pluginDirectory))
        EncodingRegistry.shared.resetCustomRegistrations()

        let plugin = TestEncodingPlugin(identifier: "dev.tiktoken.tests.plugin", vocabName: "plugin-mini")
        try EncodingRegistry.shared.load(plugin: plugin)
        XCTAssertNotNil(EncodingRegistry.shared.registration(for: plugin.vocabName))

        try EncodingRegistry.shared.unloadPlugin(withIdentifier: plugin.metadata.identifier)
        XCTAssertNil(EncodingRegistry.shared.registration(for: plugin.vocabName))
    }

    /// Persisted metadata should allow plugins to be restored after process restart.
    func testRestorePersistedPluginsLoadsFromDisk() throws {
        let pluginDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        Tiktoken.shared.configureRegistry(.init(pluginDirectory: pluginDirectory))
        EncodingRegistry.shared.resetCustomRegistrations()

        let plugin = TestEncodingPlugin(identifier: "dev.tiktoken.tests.plugin.restore", vocabName: "plugin-restore")
        try EncodingRegistry.shared.load(plugin: plugin)

        let metadataURL = pluginDirectory.appendingPathComponent("plugins.json")
        let persistedData = try Data(contentsOf: metadataURL)
        try EncodingRegistry.shared.unloadPlugin(withIdentifier: plugin.metadata.identifier)
        try persistedData.write(to: metadataURL, options: .atomic)

        let failures = EncodingRegistry.shared.restorePersistedPlugins { metadata in
            guard metadata.identifier == plugin.metadata.identifier else { return nil }
            return TestEncodingPlugin(metadata: metadata)
        }
        XCTAssertTrue(failures.isEmpty)
        XCTAssertNotNil(EncodingRegistry.shared.registration(for: plugin.vocabName))
    }
}

/// Minimal plugin used by tests to exercise registry hooks.
private final class TestEncodingPlugin: EncodingPlugin {
    let metadata: EncodingPluginMetadata
    private let ranks: [[UInt8]: Int]
    private let pattern = "[\\s\\S]"
    private let alias: String
    let vocabName: String

    /// Builds a plugin with explicit identifier and vocab name.
    init(identifier: String, vocabName: String) {
        self.metadata = EncodingPluginMetadata(identifier: identifier,
                               version: "1.0.0",
                               summary: vocabName)
        self.vocabName = vocabName
        self.alias = "alias-\(vocabName)"
        self.ranks = TestEncodingPlugin.buildRanks()
    }

    /// Convenience initializer used during restore flows.
    init(metadata: EncodingPluginMetadata) {
        self.metadata = metadata
        self.vocabName = metadata.summary
        self.alias = "alias-\(vocabName)"
        self.ranks = TestEncodingPlugin.buildRanks()
    }

    /// Registers the tiny vocab and alias pair.
    func register(into registry: EncodingRegistry, context: EncodingPluginContext) throws {
        let vocab = Vocab(name: vocabName,
                          url: "file://plugin",
                          explicitNVocab: ranks.count,
                          pattern: pattern)
        registry.register(.init(vocab: vocab, loader: .mergeableRanks(ranks)))
        registry.registerAlias(alias, encodingName: vocabName)
    }

    /// Cleans up custom aliases and vocab entries.
    func deregister(from registry: EncodingRegistry) {
        registry.unregisterAlias(alias)
        registry.unregisterEncoding(named: vocabName)
    }

    /// Creates a predictable mergeable rank map for the plugin vocab.
    private static func buildRanks() -> [[UInt8]: Int] {
        var ranks: [[UInt8]: Int] = [:]
        let tokens = [" ", "a", "b", "ab", "ba"]
        for (index, value) in tokens.enumerated() {
            ranks[Array(value.utf8)] = index
        }
        return ranks
    }
}
