import XCTest
@testable import RouseClosedLidCore

final class PowerSettingsTests: XCTestCase {
    func testParserTreatsMissingDisablesleepAsDefaultZero() throws {
        let output = """
        Battery Power:
         sleep 1
         displaysleep 2
        AC Power:
         sleep 1
         displaysleep 10
        """

        let snapshot = try PowerSettingsSnapshot.parse(pmsetCustomOutput: output)

        XCTAssertEqual(snapshot.disablesleepBySource[.battery], 0)
        XCTAssertEqual(snapshot.disablesleepBySource[.charger], 0)
        XCTAssertNil(snapshot.disablesleepBySource[.ups])
    }

    func testParserPreservesEachPowerSourceValue() throws {
        let output = """
        Battery Power:
         disablesleep 0
        AC Power:
         disablesleep 1
        UPS Power:
         disablesleep 0
        """

        let snapshot = try PowerSettingsSnapshot.parse(pmsetCustomOutput: output)

        XCTAssertEqual(snapshot.disablesleepBySource, [.battery: 0, .charger: 1, .ups: 0])
    }

    func testPMSetControllerUsesOnlyFixedArguments() throws {
        let runner = RecordingCommandRunner(results: [
            CommandResult(standardOutput: "Battery Power:\n sleep 1\nAC Power:\n sleep 1\n", standardError: "", terminationStatus: 0),
            CommandResult(standardOutput: "", standardError: "", terminationStatus: 0),
            CommandResult(standardOutput: "", standardError: "", terminationStatus: 0),
            CommandResult(standardOutput: "", standardError: "", terminationStatus: 0),
        ])
        let controller = PMSetController(runner: runner)

        let snapshot = try controller.capture()
        try controller.enableClosedLidOverride()
        try controller.restore(snapshot)

        XCTAssertEqual(runner.invocations, [
            .init(executable: "/usr/bin/pmset", arguments: ["-g", "custom"]),
            .init(executable: "/usr/bin/pmset", arguments: ["-a", "disablesleep", "1"]),
            .init(executable: "/usr/bin/pmset", arguments: ["-b", "disablesleep", "0"]),
            .init(executable: "/usr/bin/pmset", arguments: ["-c", "disablesleep", "0"]),
        ])
    }
}

private final class RecordingCommandRunner: CommandRunning, @unchecked Sendable {
    struct Invocation: Equatable {
        let executable: String
        let arguments: [String]
    }

    private(set) var invocations: [Invocation] = []
    private var results: [CommandResult]

    init(results: [CommandResult]) {
        self.results = results
    }

    func run(executable: String, arguments: [String]) throws -> CommandResult {
        invocations.append(.init(executable: executable, arguments: arguments))
        return results.removeFirst()
    }
}

