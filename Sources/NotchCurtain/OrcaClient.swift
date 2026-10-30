import Foundation

struct OrcaClient {
    static var executable: String { let configured = AppSettings.load().orcaPath; return configured.isEmpty ? (OrcaLocator.find() ?? "orca") : configured }
    static var isAvailable: Bool { FileManager.default.isExecutableFile(atPath: executable) }

    static func activateOrca() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Orca"]
        let errors = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Could not activate Orca"
            throw ClientError.command(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    static func run(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory()]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "orca exited with status \(process.terminationStatus)"
            throw ClientError.command(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return data
    }

    enum ClientError: LocalizedError {
        case command(String)
        var errorDescription: String? { if case let .command(text) = self { return text }; return nil }
    }
}
