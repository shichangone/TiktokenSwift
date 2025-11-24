import Foundation

/// Describes the origin of a `.tiktoken` or `.bpe` vocabulary payload.
public struct BPEFileSource {
    public enum Location {
        case remote(url: URL)
        case local(url: URL)
        case data(Data)
    }

    public let location: Location
    public let expectedChecksum: String?

    /// - Parameters:
    ///   - location: Source for the data.
    ///   - expectedChecksum: Optional SHA256 checksum used for cache validation.
    public init(location: Location, expectedChecksum: String? = nil) {
        self.location = location
        self.expectedChecksum = expectedChecksum
    }

    /// Convenience helper for remote sources.
    public static func remote(_ urlString: String, checksum: String? = nil) -> BPEFileSource? {
        guard let url = URL(string: urlString) else { return nil }
        return .init(location: .remote(url: url), expectedChecksum: checksum)
    }

    /// Convenience helper for local files.
    public static func local(path: String, checksum: String? = nil) -> BPEFileSource {
        .init(location: .local(url: URL(fileURLWithPath: path)), expectedChecksum: checksum)
    }

    /// Convenience helper for in-memory data.
    public static func inMemory(data: Data, checksum: String? = nil) -> BPEFileSource {
        .init(location: .data(data), expectedChecksum: checksum)
    }
}
