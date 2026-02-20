import Foundation

public enum ConnectionState: String, Codable {
    case offline
    case connecting
    case online
    case error
}

@MainActor
class SessionStore: ObservableObject {
    @Published var connectionState: ConnectionState = .offline
    @Published var username: String = ""
}

// Data models mapping to our JSON-RPC spec
public struct RPCRequest: Codable {
    let id: String
    let method: String
    let params: [String: String]?
}

public struct RPCResponse: Codable {
    let id: String
    let ok: Bool
    // result and error are typed natively but for JSON parsing we'll handle loosely.
}

public struct RPCEvent: Codable {
    let event: String
    let payload: [String: String]?
}
