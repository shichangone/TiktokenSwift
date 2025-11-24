import Foundation

/// Describes metadata associated with a plugin.
public struct EncodingPluginMetadata: Codable, Sendable, Hashable {
    public let identifier: String
    public let version: String
    public let summary: String

    public init(identifier: String, version: String, summary: String) {
        self.identifier = identifier
        self.version = version
        self.summary = summary
    }
}

/// Provides context information when plugins register with the registry.
public struct EncodingPluginContext: Sendable {
    public let configuration: EncodingRegistry.Configuration
    public let cacheDirectory: URL?

    public init(configuration: EncodingRegistry.Configuration, cacheDirectory: URL?) {
        self.configuration = configuration
        self.cacheDirectory = cacheDirectory
    }
}

/// Protocol implemented by registry plugins.
public protocol EncodingPlugin: AnyObject {
    /// Static metadata describing the plugin (identifier/version/summary).
    var metadata: EncodingPluginMetadata { get }
    /// Called when the plugin is being loaded so it can register vocabs or aliases.
    func register(into registry: EncodingRegistry, context: EncodingPluginContext) throws
    /// Called when the plugin is being unloaded to undo prior registrations.
    func deregister(from registry: EncodingRegistry)
}
