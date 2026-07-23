import Foundation

public struct CommandResult: Equatable, Sendable {
    public let standardOutput: String
    public let standardError: String
    public let terminationStatus: Int32

    public init(standardOutput: String, standardError: String, terminationStatus: Int32) {
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.terminationStatus = terminationStatus
    }
}

public enum CommandRunnerError: LocalizedError, Equatable {
    case failedToLaunch(String)
    case nonZeroExit(executable: String, arguments: [String], status: Int32, standardError: String)

    public var errorDescription: String? {
        switch self {
        case let .failedToLaunch(message):
            return "Failed to launch power settings command: \(message)"
        case let .nonZeroExit(executable, arguments, status, standardError):
            let command = ([executable] + arguments).joined(separator: " ")
            return "Command failed (\(status)): \(command). \(standardError)"
        }
    }
}

public protocol CommandRunning: Sendable {
    func run(executable: String, arguments: [String]) throws -> CommandResult
}

public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(executable: String, arguments: [String]) throws -> CommandResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "LANG": "C",
            "LC_ALL": "C",
        ]

        do {
            try process.run()
        } catch {
            throw CommandRunnerError.failedToLaunch(error.localizedDescription)
        }

        process.waitUntilExit()
        let output = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let error = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let result = CommandResult(
            standardOutput: output,
            standardError: error.trimmingCharacters(in: .whitespacesAndNewlines),
            terminationStatus: process.terminationStatus
        )

        guard result.terminationStatus == 0 else {
            throw CommandRunnerError.nonZeroExit(
                executable: executable,
                arguments: arguments,
                status: result.terminationStatus,
                standardError: result.standardError
            )
        }
        return result
    }
}

