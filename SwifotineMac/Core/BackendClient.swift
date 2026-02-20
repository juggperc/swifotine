import Combine
import Foundation
import os

actor BackendClient {
    static let shared = BackendClient()

    private var helperProcess: Process?
    private var inputPipe: Pipe?
    private var outputBuffer = Data()

    private var pendingRequests: [String: CheckedContinuation<RPCResponse, Error>] = [:]

    // We send events to the MainActor via subjects
    let eventSubject = PassthroughSubject<RPCEvent, Never>()

    private init() {}

    func launchHelper() async {
        if let helperProcess, helperProcess.isRunning, inputPipe != nil {
            return
        }

        var helperPath = Bundle.main.path(
            forResource: "swifotine_helper", ofType: "py", inDirectory: "backend/slsk-helper")

        if helperPath == nil {
            // Resolve relative to this source file, since 'swift run' executes from arbitrary CWDs
            let sourceFilePath = #filePath
            let selfCoreURL = URL(fileURLWithPath: sourceFilePath).deletingLastPathComponent()
            let helperURL = selfCoreURL.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("backend/slsk-helper/swifotine_helper.py")

            if FileManager.default.fileExists(atPath: helperURL.path) {
                helperPath = helperURL.path
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
        process.standardError = outPipe
        process.terminationHandler = { [weak self] process in
            Task {
                await self?.handleHelperTermination(process)
            }
        }

        self.inputPipe = inPipe
        self.helperProcess = process
        self.outputBuffer.removeAll(keepingCapacity: true)

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
        if inputPipe == nil || helperProcess?.isRunning != true {
            await launchHelper()
        }

        let id = UUID().uuidString
        let request = RPCRequest(id: id, method: method, params: params)
        let data = try JSONEncoder().encode(request)

        guard let inPipe = inputPipe else {
            throw NSError(
                domain: "BackendClient", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Input pipe not configured"])
        }

        var payload = data
        payload.append(0x0A)
        inPipe.fileHandleForWriting.write(payload)

        return try await withCheckedThrowingContinuation { continuation in
            self.pendingRequests[id] = continuation
        }
    }

    private func handleOutput(_ data: Data) {
        outputBuffer.append(data)

        while let newlineIndex = outputBuffer.firstIndex(of: 0x0A) {
            let lineData = Data(outputBuffer[..<newlineIndex])
            outputBuffer.removeSubrange(...newlineIndex)

            guard !lineData.isEmpty else { continue }
            handleLine(lineData)
        }
    }

    private func handleLine(_ lineData: Data) {
        let decoder = JSONDecoder()

        if let response = try? decoder.decode(RPCResponse.self, from: lineData),
            let id = response.id
        {
            if let continuation = pendingRequests.removeValue(forKey: id) {
                continuation.resume(returning: response)
            }
            return
        }

        if let event = try? decoder.decode(RPCEvent.self, from: lineData) {
            eventSubject.send(event)
            return
        }

        if let line = String(data: lineData, encoding: .utf8) {
            print("Helper Output (raw): \(line)")
        }
    }

    private func handleHelperTermination(_ process: Process) {
        guard helperProcess === process else { return }

        helperProcess = nil
        inputPipe = nil
        outputBuffer.removeAll(keepingCapacity: true)

        let reason: String
        switch process.terminationReason {
        case .exit:
            reason = "exit"
        case .uncaughtSignal:
            reason = "uncaught signal"
        @unknown default:
            reason = "unknown"
        }

        failPendingRequests(
            message:
                "Helper process terminated (\(reason), status \(process.terminationStatus))."
        )
    }

    private func failPendingRequests(message: String) {
        guard !pendingRequests.isEmpty else { return }
        let pending = pendingRequests
        pendingRequests.removeAll()

        let error = NSError(
            domain: "BackendClient",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: message]
        )

        for continuation in pending.values {
            continuation.resume(throwing: error)
        }
    }

    func shutdown() {
        helperProcess?.terminate()
        failPendingRequests(message: "Helper process stopped.")
        helperProcess = nil
        outputBuffer.removeAll(keepingCapacity: true)
        inputPipe = nil
    }
}
