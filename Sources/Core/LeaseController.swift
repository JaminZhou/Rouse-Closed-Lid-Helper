import Foundation

public struct LeaseControllerStatus: Equatable, Sendable {
    public let isActive: Bool
    public let leaseCount: Int
    public let nextExpiry: Date?
    public let recoveryJournalPresent: Bool

    public init(isActive: Bool, leaseCount: Int, nextExpiry: Date?, recoveryJournalPresent: Bool) {
        self.isActive = isActive
        self.leaseCount = leaseCount
        self.nextExpiry = nextExpiry
        self.recoveryJournalPresent = recoveryJournalPresent
    }
}

public enum LeaseControllerError: LocalizedError, Equatable {
    case invalidDuration

    public var errorDescription: String? {
        "Lease duration is outside the allowed range."
    }
}

public final class LeaseController: @unchecked Sendable {
    private let lock = NSLock()
    private let powerSettings: any PowerSettingsControlling
    private let journalStore: any RecoveryJournalStoring
    private let maximumLeaseDuration: TimeInterval
    private let wallClockNow: @Sendable () -> Date
    private let monotonicNow: @Sendable () -> ContinuousClock.Instant
    private var leases: [UUID: ContinuousClock.Instant] = [:]

    public init(
        powerSettings: any PowerSettingsControlling,
        journalStore: any RecoveryJournalStoring,
        maximumLeaseDuration: TimeInterval = 120
    ) {
        self.powerSettings = powerSettings
        self.journalStore = journalStore
        self.maximumLeaseDuration = maximumLeaseDuration
        wallClockNow = { Date() }
        monotonicNow = { ContinuousClock().now }
    }

    init(
        powerSettings: any PowerSettingsControlling,
        journalStore: any RecoveryJournalStoring,
        maximumLeaseDuration: TimeInterval = 120,
        wallClockNow: @escaping @Sendable () -> Date,
        monotonicNow: @escaping @Sendable () -> ContinuousClock.Instant
    ) {
        self.powerSettings = powerSettings
        self.journalStore = journalStore
        self.maximumLeaseDuration = maximumLeaseDuration
        self.wallClockNow = wallClockNow
        self.monotonicNow = monotonicNow
    }

    public func recoverInterruptedOverride() throws {
        lock.lock()
        defer { lock.unlock() }
        try restoreFromJournalIfNeeded()
        leases.removeAll()
    }

    @discardableResult
    public func renewLease(
        clientID: UUID,
        duration: TimeInterval
    ) throws -> LeaseControllerStatus {
        guard duration > 0, duration <= maximumLeaseDuration else {
            throw LeaseControllerError.invalidDuration
        }

        lock.lock()
        defer { lock.unlock() }

        let wallNow = wallClockNow()
        let monotonicNow = monotonicNow()
        try expireLeasesLocked(now: monotonicNow)
        if leases.isEmpty {
            try activateOverride(now: wallNow)
        }
        leases[clientID] = monotonicNow.advanced(by: .seconds(duration))
        return statusLocked(wallNow: wallNow, monotonicNow: monotonicNow)
    }

    @discardableResult
    public func endLease(clientID: UUID) throws -> LeaseControllerStatus {
        lock.lock()
        defer { lock.unlock() }
        leases.removeValue(forKey: clientID)
        if leases.isEmpty {
            try restoreFromJournalIfNeeded()
        }
        return statusLocked(wallNow: wallClockNow(), monotonicNow: monotonicNow())
    }

    @discardableResult
    public func expireLeases() throws -> LeaseControllerStatus {
        lock.lock()
        defer { lock.unlock() }
        let wallNow = wallClockNow()
        let monotonicNow = monotonicNow()
        try expireLeasesLocked(now: monotonicNow)
        return statusLocked(wallNow: wallNow, monotonicNow: monotonicNow)
    }

    @discardableResult
    public func restoreAll() throws -> LeaseControllerStatus {
        lock.lock()
        defer { lock.unlock() }
        leases.removeAll()
        try restoreFromJournalIfNeeded()
        return statusLocked(wallNow: wallClockNow(), monotonicNow: monotonicNow())
    }

    public func status() -> LeaseControllerStatus {
        lock.lock()
        defer { lock.unlock() }
        return statusLocked(wallNow: wallClockNow(), monotonicNow: monotonicNow())
    }

    private func activateOverride(now: Date) throws {
        if journalStore.exists {
            try restoreFromJournalIfNeeded()
        }

        let originalSettings = try powerSettings.capture()
        try journalStore.save(RecoveryJournal(originalSettings: originalSettings, recordedAt: now))

        do {
            try powerSettings.enableClosedLidOverride()
        } catch {
            do {
                try powerSettings.restore(originalSettings)
                try journalStore.clear()
            } catch {
                // Keep the journal so the expiry timer or next daemon launch can retry recovery.
            }
            throw error
        }
    }

    private func expireLeasesLocked(now: ContinuousClock.Instant) throws {
        leases = leases.filter { $0.value > now }
        if leases.isEmpty {
            try restoreFromJournalIfNeeded()
        }
    }

    private func restoreFromJournalIfNeeded() throws {
        guard let journal = try journalStore.load() else { return }
        try powerSettings.restore(journal.originalSettings)
        try journalStore.clear()
    }

    private func statusLocked(
        wallNow: Date,
        monotonicNow: ContinuousClock.Instant
    ) -> LeaseControllerStatus {
        LeaseControllerStatus(
            isActive: !leases.isEmpty && journalStore.exists,
            leaseCount: leases.count,
            nextExpiry: leases.values.min().map {
                wallNow.addingTimeInterval(monotonicNow.duration(to: $0).timeInterval)
            },
            recoveryJournalPresent: journalStore.exists
        )
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
