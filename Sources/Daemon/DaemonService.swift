import Foundation
import OSLog
import RouseClosedLidCore
import RouseClosedLidProtocol

final class DaemonService: NSObject, RouseClosedLidDaemonProtocol {
    private let clientID: UUID
    private let controller: LeaseController
    private let daemonVersion: String

    init(clientID: UUID, controller: LeaseController, daemonVersion: String) {
        self.clientID = clientID
        self.controller = controller
        self.daemonVersion = daemonVersion
    }

    func fetchStatus(withReply reply: @escaping (NSDictionary) -> Void) {
        let status = controller.status()
        var payload: [String: Any] = [
            RouseClosedLidIPC.StatusKey.protocolVersion: RouseClosedLidIPC.protocolVersion,
            RouseClosedLidIPC.StatusKey.daemonVersion: daemonVersion,
            RouseClosedLidIPC.StatusKey.active: status.isActive,
            RouseClosedLidIPC.StatusKey.leaseCount: status.leaseCount,
            RouseClosedLidIPC.StatusKey.recoveryJournalPresent: status.recoveryJournalPresent,
        ]
        if let nextExpiry = status.nextExpiry {
            payload[RouseClosedLidIPC.StatusKey.nextExpiry] = nextExpiry.timeIntervalSince1970
        }
        reply(payload as NSDictionary)
    }

    func renewLease(duration: TimeInterval, withReply reply: @escaping (Bool, String?) -> Void) {
        do {
            try controller.renewLease(clientID: clientID, duration: duration)
            Logger.daemon.info("Renewed closed-lid lease for client \(self.clientID.uuidString, privacy: .public)")
            reply(true, nil)
        } catch {
            Logger.daemon.error("Could not renew closed-lid lease: \(error.localizedDescription, privacy: .public)")
            reply(false, error.localizedDescription)
        }
    }

    func endLease(withReply reply: @escaping (Bool, String?) -> Void) {
        do {
            try controller.endLease(clientID: clientID)
            Logger.daemon.info("Ended closed-lid lease for client \(self.clientID.uuidString, privacy: .public)")
            reply(true, nil)
        } catch {
            Logger.daemon.error("Could not end closed-lid lease: \(error.localizedDescription, privacy: .public)")
            reply(false, error.localizedDescription)
        }
    }

    func restoreOriginalSettings(withReply reply: @escaping (Bool, String?) -> Void) {
        do {
            try controller.restoreAll()
            Logger.daemon.info("Restored original power settings")
            reply(true, nil)
        } catch {
            Logger.daemon.error("Could not restore original power settings: \(error.localizedDescription, privacy: .public)")
            reply(false, error.localizedDescription)
        }
    }
}

extension Logger {
    static let daemon = Logger(
        subsystem: "com.jaminzhou.rouse.closed-lid-helper",
        category: "daemon"
    )
}

