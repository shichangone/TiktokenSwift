import Foundation

public struct Tiktoken {
    
    public static let shared: Tiktoken = .init()
    
    private init() {}
    
    public func getEncoding(_ name: String) async throws -> Encoding? {
        guard let registration = EncodingRegistry.shared.registration(for: name) else { return nil }
        let encoder = try await loadRanks(registration.loader)
        let regex = try NSRegularExpression(pattern: registration.vocab.pattern)
        let encoding = Encoding(name: registration.vocab.name,
                                regex: regex,
                                mergeableRanks: encoder,
                                specialTokens: registration.vocab.specialTokens,
                                explicitNVocab: registration.vocab.explicitNVocab)
        return encoding
    }
    
    /// Returns the list of built-in vocabulary names to help discover encodings.
    public func availableEncodingNames() -> [String] {
        EncodingRegistry.shared.encodingNames()
    }

    /// Registers a custom vocabulary and loader pair.
    public func registerEncoding(_ vocab: Vocab, loader: EncodingRegistry.Loader) {
        EncodingRegistry.shared.register(.init(vocab: vocab, loader: loader))
    }

    /// Registers an alias mapping a model name to an encoding.
    public func registerModelAlias(_ alias: String, encodingName: String) {
        EncodingRegistry.shared.registerAlias(alias, encodingName: encodingName)
    }

    /// Registers a prefix mapping for model families.
    public func registerModelPrefix(_ prefix: String, encodingName: String) {
        EncodingRegistry.shared.registerPrefixAlias(prefix, encodingName: encodingName)
    }

    /// Configures cache directory and checksum policy.
    public func configureRegistry(_ configuration: EncodingRegistry.Configuration) {
        EncodingRegistry.shared.configure(configuration)
    }

    /// Clears custom vocabulary registrations.
    public func resetCustomRegistry() {
        EncodingRegistry.shared.resetCustomRegistrations()
    }
    
//    public func getEncoding(for vocab: Vocab) -> Encoding? {
//        return nil
//    }
//    
//    public func register() {
//        // TODO: Register model and Encoding
//    }
//    
//    public func clear() {
//        // TODO: Clear all cached encoding
//    }
}

private extension Tiktoken {
    func loadRanks(_ loader: EncodingRegistry.Loader) async throws -> [[UInt8]: Int] {
        switch loader {
        case let .tiktokenFile(source):
            return try await Load.loadTiktokenBpe(source: source)
        case let .dataGym(vocabFile, encoderFile):
            return try await Load.dataGymToMergeableBpeRanks(vocabSource: vocabFile, encoderSource: encoderFile)
        case let .mergeableRanks(ranks):
            return ranks
        }
    }
}
