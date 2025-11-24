import Foundation
import Tiktoken

/// Simple CLI that records average latency for core encoding workflows.
@main
struct TiktokenBenchmarks {
    static func main() async throws {
        let iterations = Self.iterationCount()
        guard let encoder = try await Tiktoken.shared.getEncoding("o200k_base") else {
            throw BenchmarkError.encodingUnavailable
        }
        let paragraph = String(repeating: "Large language models are great at summarization. ", count: 64)
        let batch = Array(repeating: paragraph, count: 16)
        let cases = [
            BenchmarkCase(name: "tokenCount/paragraph") { encoder in
                _ = try encoder.tokenCount(value: paragraph,
                                            allowedSpecial: .none,
                                            disallowedSpecial: .automatic)
            },
            BenchmarkCase(name: "encode/paragraph") { encoder in
                _ = try encoder.encode(value: paragraph,
                                       allowedSpecial: .none,
                                       disallowedSpecial: .automatic)
            },
            BenchmarkCase(name: "encodeBatch/16x") { encoder in
                _ = try await encoder.encodeBatch(values: batch,
                                                   allowedSpecial: .none,
                                                   disallowedSpecial: .automatic,
                                                   maxConcurrency: 4)
            }
        ]
        for benchmark in cases {
            let average = try await benchmark.run(iterations: iterations, encoder: encoder)
            let milliseconds = average * 1_000
            print(String(format: "%@ avg: %.2f ms", benchmark.name, milliseconds))
        }
    }

    /// Parses the optional iteration count from the first CLI argument.
    private static func iterationCount() -> Int {
        guard let raw = CommandLine.arguments.dropFirst().first,
              let value = Int(raw), value > 0 else {
            return 25
        }
        return value
    }
}

/// Represents a single benchmark scenario.
struct BenchmarkCase {
    let name: String
    let body: (Encoding) async throws -> Void

    /// Executes the benchmark and returns the average duration in seconds.
    func run(iterations: Int, encoder: Encoding) async throws -> Double {
        var total: Double = 0
        for _ in 0..<iterations {
            let start = CFAbsoluteTimeGetCurrent()
            try await body(encoder)
            total += CFAbsoluteTimeGetCurrent() - start
        }
        return total / Double(iterations)
    }
}

/// Errors that can surface when running benchmarks.
enum BenchmarkError: Error {
    case encodingUnavailable
}
