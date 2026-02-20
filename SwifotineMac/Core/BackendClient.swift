import Combine
import Foundation
import os

actor BackendClient {
    static let shared = BackendClient()

    private var helperProcess: Process?
    private var inputPipe: Pipe?

    private var pendingRequests: [String: CheckedContinuation<RPCResponse, Error>] = [:]

    // We send events to the MainActor via subjects
    let eventSubject = PassthroughSubject<RPCEvent, Never>()

    private init() {}

    func launchHelper() async {
        guard helperProcess == nil else { return }

        // Due to SwiftPM, the python script might not be in Resources, so we fall back or find it.
        var helperPath = Bundle.main.path(forResource: "swifotine_helper", ofType: "py")
        if helperPath == nil {
            // For dev environments
            let pwd = FileManager.default.currentDirectoryPath
            let altPath = "\(pwd)/backend/slsk-helper/swifotine_helper.py"
            if FileManager.default.fileExists(atPath: altPath) {
                helperPath = altPath
            }
        }

        guard let validHelperPath = helperPath else {
            print("Failed to find helper script.")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [validHelperPath]

        // SwiftPM running locally will have the `vendor` relative to the CWD, which is fine since we set the path correctly.
        let pwd = FileManager.default.currentDirectoryPath
        process.currentDirectoryURL = URL(fileURLWithPath: pwd)

        let inPipe = Pipe()
        let outPipe = Pipe()

        process.standardInput = inPipe
        process.standardOutput = outPipe

        self.inputPipe = inPipe
        self.helperProcess = process

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            Task {
                await self?.handleOutput(data)
            }
        }

        do {
            try process.run()
            print("Swifotine Helper launched successfully.")
        } catch {
            print("Failed to run helper process: \(error.localizedDescription)")
        }
    }

    func sendRequest(method: String, params: [String: String]? = nil) async throws -> RPCResponse {
        let id = UUID().uuidString
        let request = RPCRequest(id: id, method: method, params: params)
        let data = try JSONEncoder().encode(request)

        guard let inPipe = inputPipe else {
            throw NSError(
                domain: "BackendClient", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Input pipe not configured"])
        }

        var stringReq = String(data: data, encoding: .utf8)!
        stringReq += "\n"

        if let dataToWrite = stringReq.data(using: .utf8) {
            inPipe.fileHandleForWriting.write(dataToWrite)
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.pendingRequests[id] = continuation
        }
    }

    private func handleOutput(_ data: Data) {
        guard let stringResponse = String(data: data, encoding: .utf8) else { return }

        let lines = stringResponse.split(separator: "\n")
        let decoder = JSONDecoder()

        for line in lines {
            let lineData = Data(line.utf8)

            // Try as Response
            if let response = try? decoder.decode(RPCResponse.self, from: lineData),
                let id = response.id
            {
                if let continuation = pendingRequests.removeValue(forKey: id) {
                    continuation.resume(returning: response)
                }
            }
            // Try as Event
            else if let event = try? decoder.decode(RPCEvent.self, from: lineData) {
                eventSubject.send(event)
            } else {
                print("Helper Output (raw): \(line)")
            }
        }
    }

    func shutdown() {
        helperProcess?.terminate()
        helperProcess = nil
    }
}
