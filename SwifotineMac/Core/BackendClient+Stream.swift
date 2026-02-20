import Foundation

extension BackendClient {
    func eventStream() async -> AsyncStream<RPCEvent> {
        return AsyncStream { continuation in
            let cancellable = self.eventSubject.sink { event in
                continuation.yield(event)
            }
            // Keep strong ref to it (simplified, assumes app lifecycle)
            Task {
                var c = cancellable  // retaining
            }
        }
    }
}
