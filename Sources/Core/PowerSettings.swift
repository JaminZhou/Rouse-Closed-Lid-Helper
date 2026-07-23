import Foundation

public enum PowerSource: String, Codable, CaseIterable, Sendable {
    case battery
    case charger
    case ups

    var pmsetFlag: String {
        switch self {
        case .battery: "-b"
        case .charger: "-c"
        case .ups: "-u"
        }
    }
}

public struct PowerSettingsSnapshot: Codable, Equatable, Sendable {
    public let disablesleepBySource: [PowerSource: Int]

    public init(disablesleepBySource: [PowerSource: Int]) {
        self.disablesleepBySource = disablesleepBySource
    }

    public static func parse(pmsetCustomOutput output: String) throws -> PowerSettingsSnapshot {
        var values: [PowerSource: Int] = [:]
        var currentSource: PowerSource?

        for rawLine in output.split(whereSeparator: \Character.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            switch line {
            case "Battery Power:":
                currentSource = .battery
                values[.battery] = 0
            case "AC Power:":
                currentSource = .charger
                values[.charger] = 0
            case "UPS Power:":
                currentSource = .ups
                values[.ups] = 0
            default:
                guard let currentSource else { continue }
                let fields = line.split(whereSeparator: \Character.isWhitespace)
                guard fields.count == 2, fields[0] == "disablesleep", let value = Int(fields[1]) else {
                    continue
                }
                values[currentSource] = value
            }
        }

        guard !values.isEmpty else {
            throw PowerSettingsError.unrecognizedOutput
        }
        return PowerSettingsSnapshot(disablesleepBySource: values)
    }
}

public enum PowerSettingsError: LocalizedError, Equatable {
    case unrecognizedOutput
    case noPowerSources

    public var errorDescription: String? {
        switch self {
        case .unrecognizedOutput:
            return "Could not read the current macOS power settings."
        case .noPowerSources:
            return "No restorable macOS power source was found."
        }
    }
}

public protocol PowerSettingsControlling: Sendable {
    func capture() throws -> PowerSettingsSnapshot
    func enableClosedLidOverride() throws
    func restore(_ snapshot: PowerSettingsSnapshot) throws
}

public struct PMSetController: PowerSettingsControlling {
    private let runner: any CommandRunning
    private let executable = "/usr/bin/pmset"

    public init(runner: any CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    public func capture() throws -> PowerSettingsSnapshot {
        let result = try runner.run(executable: executable, arguments: ["-g", "custom"])
        return try PowerSettingsSnapshot.parse(pmsetCustomOutput: result.standardOutput)
    }

    public func enableClosedLidOverride() throws {
        _ = try runner.run(executable: executable, arguments: ["-a", "disablesleep", "1"])
    }

    public func restore(_ snapshot: PowerSettingsSnapshot) throws {
        guard !snapshot.disablesleepBySource.isEmpty else {
            throw PowerSettingsError.noPowerSources
        }

        for source in PowerSource.allCases {
            guard let value = snapshot.disablesleepBySource[source] else { continue }
            _ = try runner.run(
                executable: executable,
                arguments: [source.pmsetFlag, "disablesleep", String(value)]
            )
        }
    }
}

