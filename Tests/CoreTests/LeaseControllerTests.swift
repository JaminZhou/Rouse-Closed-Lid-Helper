import XCTest
@testable import RouseClosedLidCore

final class LeaseControllerTests: XCTestCase {
    private let original = PowerSettingsSnapshot(disablesleepBySource: [.battery: 0, .charger: 0])

    func testFirstLeaseCapturesBeforeEnablingAndLastClientRestores() throws {
        let power = FakePowerSettings(snapshot: original)
        let journal = MemoryJournalStore()
        let controller = LeaseController(powerSettings: power, journalStore: journal)
        let firstClient = UUID()
        let secondClient = UUID()

        try controller.renewLease(clientID: firstClient, duration: 60)
        try controller.renewLease(clientID: secondClient, duration: 90)

        XCTAssertEqual(power.events, [.capture, .enable])
        XCTAssertTrue(journal.exists)
        XCTAssertEqual(controller.status().leaseCount, 2)

        try controller.endLease(clientID: firstClient)
        XCTAssertEqual(power.events, [.capture, .enable])

        try controller.endLease(clientID: secondClient)
        XCTAssertEqual(power.events, [.capture, .enable, .restore(original)])
        XCTAssertFalse(journal.exists)
    }

    func testExpiredLeaseRestoresSettings() throws {
        let power = FakePowerSettings(snapshot: original)
        let journal = MemoryJournalStore()
        let clock = TestLeaseClock(wallNow: Date(timeIntervalSince1970: 2_000))
        let controller = LeaseController(
            powerSettings: power,
            journalStore: journal,
            wallClockNow: { clock.wallNow },
            monotonicNow: { clock.monotonicNow }
        )

        try controller.renewLease(clientID: UUID(), duration: 30)
        clock.advance(wallTime: 31, monotonicTime: .seconds(31))
        let status = try controller.expireLeases()

        XCTAssertFalse(status.isActive)
        XCTAssertEqual(power.events, [.capture, .enable, .restore(original)])
        XCTAssertFalse(journal.exists)
    }

    func testBackwardWallClockChangeDoesNotExtendLease() throws {
        let power = FakePowerSettings(snapshot: original)
        let journal = MemoryJournalStore()
        let initialWallTime = Date(timeIntervalSince1970: 2_500)
        let clock = TestLeaseClock(wallNow: initialWallTime)
        let controller = LeaseController(
            powerSettings: power,
            journalStore: journal,
            wallClockNow: { clock.wallNow },
            monotonicNow: { clock.monotonicNow }
        )

        let renewed = try controller.renewLease(clientID: UUID(), duration: 30)
        XCTAssertEqual(renewed.nextExpiry, initialWallTime.addingTimeInterval(30))

        clock.advance(wallTime: -3_600, monotonicTime: .seconds(31))
        let expired = try controller.expireLeases()

        XCTAssertFalse(expired.isActive)
        XCTAssertEqual(power.events, [.capture, .enable, .restore(original)])
        XCTAssertFalse(journal.exists)
    }

    func testStartupRecoveryRestoresPersistedSettings() throws {
        let power = FakePowerSettings(snapshot: original)
        let journal = MemoryJournalStore(
            journal: RecoveryJournal(originalSettings: original, recordedAt: Date(timeIntervalSince1970: 3_000))
        )
        let controller = LeaseController(powerSettings: power, journalStore: journal)

        try controller.recoverInterruptedOverride()

        XCTAssertEqual(power.events, [.restore(original)])
        XCTAssertFalse(journal.exists)
    }

    func testInvalidLeaseDoesNotTouchPowerSettings() {
        let power = FakePowerSettings(snapshot: original)
        let journal = MemoryJournalStore()
        let controller = LeaseController(powerSettings: power, journalStore: journal, maximumLeaseDuration: 120)

        XCTAssertThrowsError(try controller.renewLease(clientID: UUID(), duration: 121))
        XCTAssertTrue(power.events.isEmpty)
        XCTAssertFalse(journal.exists)
    }

    func testEnableFailureAttemptsRollbackAndClearsJournal() {
        let power = FakePowerSettings(snapshot: original, enableError: TestError.expected)
        let journal = MemoryJournalStore()
        let controller = LeaseController(powerSettings: power, journalStore: journal)

        XCTAssertThrowsError(try controller.renewLease(clientID: UUID(), duration: 60))
        XCTAssertEqual(power.events, [.capture, .enable, .restore(original)])
        XCTAssertFalse(journal.exists)
    }

    func testEnableFailureKeepsJournalWhenRollbackFails() {
        let power = FakePowerSettings(
            snapshot: original,
            enableError: TestError.expected,
            restoreError: TestError.expected
        )
        let journal = MemoryJournalStore()
        let controller = LeaseController(powerSettings: power, journalStore: journal)

        XCTAssertThrowsError(try controller.renewLease(clientID: UUID(), duration: 60))
        XCTAssertEqual(power.events, [.capture, .enable, .restore(original)])
        XCTAssertTrue(journal.exists)
    }
}

private enum TestError: Error {
    case expected
}

private final class TestLeaseClock: @unchecked Sendable {
    var wallNow: Date
    var monotonicNow = ContinuousClock().now

    init(wallNow: Date) {
        self.wallNow = wallNow
    }

    func advance(wallTime: TimeInterval, monotonicTime: Duration) {
        wallNow = wallNow.addingTimeInterval(wallTime)
        monotonicNow = monotonicNow.advanced(by: monotonicTime)
    }
}

private final class FakePowerSettings: PowerSettingsControlling, @unchecked Sendable {
    enum Event: Equatable {
        case capture
        case enable
        case restore(PowerSettingsSnapshot)
    }

    private let snapshot: PowerSettingsSnapshot
    private let enableError: Error?
    private let restoreError: Error?
    private(set) var events: [Event] = []

    init(
        snapshot: PowerSettingsSnapshot,
        enableError: Error? = nil,
        restoreError: Error? = nil
    ) {
        self.snapshot = snapshot
        self.enableError = enableError
        self.restoreError = restoreError
    }

    func capture() throws -> PowerSettingsSnapshot {
        events.append(.capture)
        return snapshot
    }

    func enableClosedLidOverride() throws {
        events.append(.enable)
        if let enableError { throw enableError }
    }

    func restore(_ snapshot: PowerSettingsSnapshot) throws {
        events.append(.restore(snapshot))
        if let restoreError { throw restoreError }
    }
}

private final class MemoryJournalStore: RecoveryJournalStoring, @unchecked Sendable {
    private var journal: RecoveryJournal?

    init(journal: RecoveryJournal? = nil) {
        self.journal = journal
    }

    var exists: Bool { journal != nil }

    func load() throws -> RecoveryJournal? {
        journal
    }

    func save(_ journal: RecoveryJournal) throws {
        self.journal = journal
    }

    func clear() throws {
        journal = nil
    }
}
