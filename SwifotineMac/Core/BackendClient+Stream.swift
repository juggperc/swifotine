import Foundation

extension BackendClient {
    func eventStream() async -> AsyncStream<RPCEvent> {
        return AsyncStream { continuation in
            let cancellable = self.eventSubject.sink { event in
                continuation.yield(event)
            }
            continuation.onTermination = { @Sendable _ in
                cancellable.cancel()
            }
        }
    }
}
