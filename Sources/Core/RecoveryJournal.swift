import Foundation

public struct RecoveryJournal: Codable, Equatable, Sendable {
    public let originalSettings: PowerSettingsSnapshot
    public let recordedAt: Date

    public init(originalSettings: PowerSettingsSnapshot, recordedAt: Date) {
        self.originalSettings = originalSettings
        self.recordedAt = recordedAt
    }
}

public protocol RecoveryJournalStoring: Sendable {
    func load() throws -> RecoveryJournal?
    func save(_ journal: RecoveryJournal) throws
    func clear() throws
    var exists: Bool { get }
}

public final class FileRecoveryJournalStore: RecoveryJournalStoring, @unchecked Sendable {
    public static let defaultURL = URL(
        fileURLWithPath: "/Library/Application Support/com.jaminzhou.rouse.closed-lid-helper/recovery.json"
    )

    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL = FileRecoveryJournalStore.defaultURL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public var exists: Bool {
        fileManager.fileExists(atPath: fileURL.path)
    }

    public func load() throws -> RecoveryJournal? {
        guard exists else { return nil }
        return try decoder.decode(RecoveryJournal.self, from: Data(contentsOf: fileURL))
    }

    public func save(_ journal: RecoveryJournal) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try encoder.encode(journal).write(to: fileURL, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    public func clear() throws {
        guard exists else { return }
        try fileManager.removeItem(at: fileURL)
    }
}

