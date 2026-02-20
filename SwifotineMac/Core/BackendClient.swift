import Combine
import Foundation

actor BackendClient {
    static let shared = BackendClient()

    private var helperProcess: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?

    private var continuationMap: [String: CheckedContinuation<Data, Error>] = [:]

    private init() {}

    func launchHelper() async {
        guard helperProcess == nil else { return }

        // Locate the python helper script in the app bundle
        guard let helperPath = Bundle.main.path(forResource: "swifotine_helper", ofType: "py")
        else {
            print("Failed to find helper script in bundle.")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [helperPath]

        let inPipe = Pipe()
        let outPipe = Pipe()

        process.standardInput = inPipe
        process.standardOutput = outPipe

        self.inputPipe = inPipe
        self.outputPipe = outPipe
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

    private func handleOutput(_ data: Data) async {
        // Here we parse line-delimited JSON and trigger actions or fulfill continuations
        // For standard IPC, lines are separated by \n
        if let stringResponse = String(data: data, encoding: .utf8) {
            let lines = stringResponse.split(separator: "\n")
            for line in lines {
                print("Helper Output: \(line)")
            }
        }
    }

    func shutdown() {
        helperProcess?.terminate()
        helperProcess = nil
    }
}
