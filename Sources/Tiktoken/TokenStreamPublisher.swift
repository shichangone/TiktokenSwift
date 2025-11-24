#if canImport(Combine)
import Combine
import Foundation

/// Combine publisher that bridges `Encoding.tokenStream` into the reactive world.
@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
public struct TokenStreamPublisher: Publisher {
    public typealias Output = TokenStreamChunk
    public typealias Failure = Error

    private let builder: () -> AsyncThrowingStream<TokenStreamChunk, Error>

    init(builder: @escaping () -> AsyncThrowingStream<TokenStreamChunk, Error>) {
        self.builder = builder
    }

    public func receive<S>(subscriber: S) where S: Subscriber, Error == S.Failure, TokenStreamChunk == S.Input {
        let subscription = TokenStreamSubscription(subscriber: subscriber, stream: builder())
        subscriber.receive(subscription: subscription)
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
private final class TokenStreamSubscription<S: Subscriber>: Subscription where S.Input == TokenStreamChunk, S.Failure == Error {
    private var subscriber: S?
    private var task: Task<Void, Never>?
    private let stream: AsyncThrowingStream<TokenStreamChunk, Error>
    private let lock = NSLock()
    private var started = false

    init(subscriber: S, stream: AsyncThrowingStream<TokenStreamChunk, Error>) {
        self.subscriber = subscriber
        self.stream = stream
    }

    func request(_ demand: Subscribers.Demand) {
        guard demand > .none else { return }
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return }
        started = true
        task = Task { [weak self] in
            await self?.produce()
        }
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        task?.cancel()
        task = nil
        subscriber = nil
    }

    private func produce() async {
        var iterator = stream.makeAsyncIterator()
        do {
            while let chunk = try await iterator.next() {
                try Task.checkCancellation()
                guard let subscriber else { break }
                _ = subscriber.receive(chunk)
            }
            subscriber?.receive(completion: .finished)
        } catch {
            subscriber?.receive(completion: .failure(error))
        }
        cancel()
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
public extension Encoding {
    /// Exposes streaming tokens as a Combine publisher for reactive pipelines.
    func tokenPublisher(value: String,
                        allowedSpecial: SpecialTokenSet = .none,
                        disallowedSpecial: SpecialTokenSet = .automatic,
                        request: TokenStreamRequest = .init()) -> TokenStreamPublisher {
        TokenStreamPublisher {
            self.tokenStream(value: value,
                              allowedSpecial: allowedSpecial,
                              disallowedSpecial: disallowedSpecial,
                              request: request)
        }
    }
}

#endif
