import Foundation

/// Registry that tracks vocab-to-model mappings while supporting custom sources, cache settings, and plugins.
public final class EncodingRegistry {
    /// Describes a single vocab registration entry.
    public struct Registration {
        public let vocab: Vocab
        public let loader: Loader
        public init(vocab: Vocab, loader: Loader) {
            self.vocab = vocab
            self.loader = loader
        }
    }

    /// Enumerates supported loader strategies for vocab sources.
    public enum Loader {
        case tiktokenFile(source: BPEFileSource)
        case dataGym(vocabFile: BPEFileSource, encoderFile: BPEFileSource? = nil)
        case mergeableRanks([[UInt8]: Int])
    }

    /// Configuration applied to the registry and propagated to loaders/plugins.
    public struct Configuration: Sendable {
        public let cacheDirectory: URL?
        public let environmentKey: String
        public let verifyChecksums: Bool
        public let pluginDirectory: URL?
        public init(cacheDirectory: URL? = nil,
                    environmentKey: String = "TIKTOKEN_CACHE_DIR",
                    verifyChecksums: Bool = true,
                    pluginDirectory: URL? = nil) {
            self.cacheDirectory = cacheDirectory
            self.environmentKey = environmentKey
            self.verifyChecksums = verifyChecksums
            self.pluginDirectory = pluginDirectory
        }
    }

    /// Errors thrown during plugin lifecycle management.
    public enum PluginError: Error, LocalizedError {
        case duplicate(String)
        case unknown(String)

        public var errorDescription: String? {
            switch self {
            case let .duplicate(id):
                return "Plugin already loaded: \(id)"
            case let .unknown(id):
                return "Plugin not found: \(id)"
            }
        }
    }

    /// Shared singleton used by `Tiktoken` entry points.
    public static let shared = EncodingRegistry()

    private var encodings: [String: Registration] = [:]
    private var aliasMap: [String: String] = [:]
    private var prefixAliasMap: [String: String] = [:]
    private var activePlugins: [String: EncodingPlugin] = [:]
    private var pluginMetadata: [String: EncodingPluginMetadata] = [:]
    private var pluginDirectory: URL?
    private var configurationSnapshot: Configuration
    private let builtInNames: Set<String>
    private let builtInAliases: [String: String]
    private let builtInPrefixAliases: [String: String]
    private let lock = NSLock()

    private init() {
        configurationSnapshot = .init()
        var builtIns: [String: Registration] = [:]
        Vocab.all.forEach { vocab in
            if let registration = Self.registration(for: vocab) {
                builtIns[vocab.name] = registration
            }
        }
        encodings = builtIns
        builtInNames = Set(builtIns.keys)
        builtInAliases = Model.modelToEncoding
        builtInPrefixAliases = Model.modelPrefixToEncoding
        aliasMap = builtInAliases
        prefixAliasMap = builtInPrefixAliases
        pluginDirectory = configurationSnapshot.pluginDirectory
        Model.registerDefaults(into: self)
        configure(configurationSnapshot)
    }

    /// Configures cache directory, environment variable, checksum policy, and plugin directory.
    public func configure(_ configuration: Configuration) {
        lock.lock(); defer { lock.unlock() }
        configurationSnapshot = configuration
        pluginDirectory = configuration.pluginDirectory
        Load.configure(.init(cacheDirectory: configuration.cacheDirectory,
                             environmentKey: configuration.environmentKey,
                             verifyChecksums: configuration.verifyChecksums))
        persistPluginMetadata()
    }

    /// Registers a new vocabulary record.
    public func register(_ registration: Registration) {
        lock.lock(); defer { lock.unlock() }
        encodings[registration.vocab.name] = registration
    }

    /// Removes a previously registered vocabulary when it is not part of the built-in set.
    public func unregisterEncoding(named name: String) {
        lock.lock(); defer { lock.unlock() }
        guard !builtInNames.contains(name) else { return }
        encodings.removeValue(forKey: name)
        aliasMap = aliasMap.filter { $0.value != name }
        prefixAliasMap = prefixAliasMap.filter { $0.value != name }
    }

    /// Registers a model alias pointing to a vocabulary name.
    public func registerAlias(_ alias: String, encodingName: String) {
        lock.lock(); defer { lock.unlock() }
        aliasMap[alias] = encodingName
    }

    /// Removes a model alias or resets it to the built-in mapping if one exists.
    public func unregisterAlias(_ alias: String) {
        lock.lock(); defer { lock.unlock() }
        if let builtIn = builtInAliases[alias] {
            aliasMap[alias] = builtIn
        } else {
            aliasMap.removeValue(forKey: alias)
        }
    }

    /// Registers a prefix alias for model families.
    public func registerPrefixAlias(_ prefix: String, encodingName: String) {
        lock.lock(); defer { lock.unlock() }
        prefixAliasMap[prefix] = encodingName
    }

    /// Removes a prefix alias or restores the built-in mapping when available.
    public func unregisterPrefixAlias(_ prefix: String) {
        lock.lock(); defer { lock.unlock() }
        if let builtIn = builtInPrefixAliases[prefix] {
            prefixAliasMap[prefix] = builtIn
        } else {
            prefixAliasMap.removeValue(forKey: prefix)
        }
    }

    /// Resolves a registration by name or alias.
    public func registration(for identifier: String) -> Registration? {
        lock.lock(); defer { lock.unlock() }
        if let registration = encodings[identifier] {
            return registration
        }
        if let mapped = aliasMap[identifier], let registration = encodings[mapped] {
            return registration
        }
        if let prefix = prefixAliasMap.keys.first(where: { identifier.starts(with: $0) }),
           let mapped = prefixAliasMap[prefix], let registration = encodings[mapped] {
            return registration
        }
        return nil
    }

    /// Returns the vocabulary associated with the identifier.
    public func vocab(for identifier: String) -> Vocab? {
        registration(for: identifier)?.vocab
    }

    /// Returns every registered encoding name.
    public func encodingNames() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return encodings.keys.sorted()
    }

    /// Resets the registry to built-in vocabularies and aliases (primarily for tests).
    public func resetCustomRegistrations() {
        lock.lock()
        encodings = encodings.filter { builtInNames.contains($0.key) }
        aliasMap = builtInAliases
        prefixAliasMap = builtInPrefixAliases
        let plugins = Array(activePlugins.values)
        activePlugins.removeAll()
        pluginMetadata.removeAll()
        lock.unlock()
        plugins.forEach { $0.deregister(from: self) }
        persistPluginMetadata()
    }

    /// Loads and registers a plugin, persisting metadata on success.
    public func load(plugin: EncodingPlugin) throws {
        lock.lock()
        let id = plugin.metadata.identifier
        guard activePlugins[id] == nil else {
            lock.unlock()
            throw PluginError.duplicate(id)
        }
        let context = EncodingPluginContext(configuration: configurationSnapshot,
                                            cacheDirectory: configurationSnapshot.cacheDirectory)
        lock.unlock()
        try plugin.register(into: self, context: context)
        lock.lock()
        activePlugins[id] = plugin
        pluginMetadata[id] = plugin.metadata
        lock.unlock()
        persistPluginMetadata()
    }

    /// Unloads a plugin identified by metadata identifier.
    public func unloadPlugin(withIdentifier identifier: String) throws {
        lock.lock()
        guard let plugin = activePlugins.removeValue(forKey: identifier) else {
            lock.unlock()
            throw PluginError.unknown(identifier)
        }
        pluginMetadata.removeValue(forKey: identifier)
        lock.unlock()
        plugin.deregister(from: self)
        persistPluginMetadata()
    }

    /// Returns metadata for all loaded plugins.
    public func loadedPlugins() -> [EncodingPluginMetadata] {
        lock.lock(); defer { lock.unlock() }
        return Array(pluginMetadata.values)
    }

    /// Attempts to restore persisted plugin metadata using a factory closure. Returns failures.
    @discardableResult
    public func restorePersistedPlugins(using factory: (EncodingPluginMetadata) -> EncodingPlugin?) -> [EncodingPluginMetadata] {
        let stored = readPersistedMetadata()
        var failures: [EncodingPluginMetadata] = []
        for metadata in stored {
            lock.lock()
            let alreadyLoaded = activePlugins[metadata.identifier] != nil
            lock.unlock()
            guard !alreadyLoaded else { continue }
            guard let plugin = factory(metadata) else {
                failures.append(metadata)
                continue
            }
            do {
                try load(plugin: plugin)
            } catch {
                failures.append(metadata)
            }
        }
        return failures
    }

    private static func registration(for vocab: Vocab) -> Registration? {
        guard let source = loader(for: vocab) else { return nil }
        return Registration(vocab: vocab, loader: source)
    }

    private static func loader(for vocab: Vocab) -> Loader? {
        if vocab.name == "gpt2" {
            guard let source = BPEFileSource.remote(vocab.url) else { return nil }
            return .dataGym(vocabFile: source)
        }
        guard let source = BPEFileSource.remote(vocab.url) else { return nil }
        return .tiktokenFile(source: source)
    }

    /// Persists plugin metadata to disk when a plugin directory is configured.
    private func persistPluginMetadata() {
        guard let directory = pluginDirectory else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("plugins.json")
            let items = Array(pluginMetadata.values)
            let data = try JSONEncoder().encode(items)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[EncodingRegistry] Failed to persist plugin metadata: \(error)")
        }
    }

    /// Reads metadata from disk in order to restore plugins across launches.
    private func readPersistedMetadata() -> [EncodingPluginMetadata] {
        guard let directory = pluginDirectory else { return [] }
        let url = directory.appendingPathComponent("plugins.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([EncodingPluginMetadata].self, from: data)
        } catch {
            print("[EncodingRegistry] Failed to read plugin metadata: \(error)")
            return []
        }
    }
}