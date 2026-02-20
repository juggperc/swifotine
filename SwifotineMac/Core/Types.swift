import Combine
import Foundation
import SwiftUI

public struct RPCRequest: Codable {
    public let id: String
    public let method: String
    public let params: [String: String]?
}

public struct RPCResponse: Codable {
    public let id: String?
    public let ok: Bool?
    public let error: RPCError?
}

public struct RPCError: Codable {
    let code: String
    let message: String
}

public struct RPCEvent: Codable {
    public let event: String
    public let payload: [String: String]?
}

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
    @Published var lastError: String? = nil

    private var subscribers = Set<AnyCancellable>()

    init() {
        // Subscribe to events from BackendClient
        Task {
            await bindEvents()
        }
    }

    private func bindEvents() async {
        let stream = await BackendClient.shared.eventStream()
        Task {
            for await event in stream {
                if event.event == "connection.state_changed", let payload = event.payload {
                    if let stateStr = payload["state"],
                        let newState = ConnectionState(rawValue: stateStr)
                    {
                        self.connectionState = newState
                        if newState == .error {
                            self.lastError = payload["server_reason"]
                        }
                    }
                }
            }
        }
    }

    func connect(username: String, passcode: String) async {
        self.username = username
        self.connectionState = .connecting

        do {
            let client = BackendClient.shared

            // Set paths
            let downloadsFolder = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Music/Swifotine/Downloads").path
            let incompleteFolder = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Music/Swifotine/Incomplete").path

            try FileManager.default.createDirectory(
                atPath: downloadsFolder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                atPath: incompleteFolder, withIntermediateDirectories: true)

            _ = try await client.sendRequest(
                method: "session.configure",
                params: [
                    "username": username,
                    "password": passcode,
                    "downloadRoot": downloadsFolder,
                    "incompleteRoot": incompleteFolder,
                ])

            _ = try await client.sendRequest(method: "session.connect", params: nil)
        } catch {
            self.connectionState = .error
            self.lastError = error.localizedDescription
        }
    }
}
