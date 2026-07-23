import Foundation
import RouseClosedLidProtocol

struct DaemonStatus: Equatable {
    let protocolVersion: Int
    let daemonVersion: String
    let isActive: Bool
    let leaseCount: Int
    let nextExpiry: Date?
    let recoveryJournalPresent: Bool
}

enum DaemonClientError: LocalizedError {
    case invalidResponse
    case timedOut
    case remote(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return NSLocalizedString("error_invalid_daemon_response", comment: "")
        case .timedOut:
            return NSLocalizedString("error_daemon_timeout", comment: "")
        case let .remote(message):
            return message
        }
    }
}

final class DaemonClient {
    func fetchStatus() async throws -> DaemonStatus {
        try await withConnection { proxy, finish in
            proxy.fetchStatus { payload in
                guard let protocolVersion = payload[RouseClosedLidIPC.StatusKey.protocolVersion] as? Int,
                      let daemonVersion = payload[RouseClosedLidIPC.StatusKey.daemonVersion] as? String,
                      let active = payload[RouseClosedLidIPC.StatusKey.active] as? Bool,
                      let leaseCount = payload[RouseClosedLidIPC.StatusKey.leaseCount] as? Int,
                      let journalPresent = payload[RouseClosedLidIPC.StatusKey.recoveryJournalPresent] as? Bool else {
                    finish(.failure(DaemonClientError.invalidResponse))
                    return
                }
                let expiryTimestamp = payload[RouseClosedLidIPC.StatusKey.nextExpiry] as? TimeInterval
                finish(.success(DaemonStatus(
                    protocolVersion: protocolVersion,
                    daemonVersion: daemonVersion,
                    isActive: active,
                    leaseCount: leaseCount,
                    nextExpiry: expiryTimestamp.map(Date.init(timeIntervalSince1970:)),
                    recoveryJournalPresent: journalPresent
                )))
            }
        }
    }

    func restoreOriginalSettings() async throws {
        let _: Void = try await withConnection { proxy, finish in
            proxy.restoreOriginalSettings { success, message in
                if success {
                    finish(.success(()))
                } else {
                    finish(.failure(DaemonClientError.remote(
                        message ?? NSLocalizedString("error_unknown_daemon", comment: "")
                    )))
                }
            }
        }
    }

    private func withConnection<T>(
        operation: @escaping (
            RouseClosedLidDaemonProtocol,
            @escaping (Result<T, Error>) -> Void
        ) -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let connection = NSXPCConnection(
                machServiceName: RouseClosedLidIPC.machServiceName,
                options: .privileged
            )
            connection.remoteObjectInterface = NSXPCInterface(with: RouseClosedLidDaemonProtocol.self)
            connection.setCodeSigningRequirement(RouseClosedLidIPC.daemonCodeSigningRequirement)
            let gate = DaemonContinuationGate(
                continuation: continuation,
                connection: connection
            )
            let finish: (Result<T, Error>) -> Void = { result in
                gate.resume(result)
            }

            connection.invalidationHandler = {
                finish(.failure(DaemonClientError.remote(
                    NSLocalizedString("status_unavailable", comment: "")
                )))
            }
            connection.activate()
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + 5,
                execute: DispatchWorkItem {
                    finish(.failure(DaemonClientError.timedOut))
                }
            )

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                finish(.failure(error))
            }) as? RouseClosedLidDaemonProtocol else {
                finish(.failure(DaemonClientError.invalidResponse))
                return
            }

            operation(proxy, finish)
        }
    }
}

private final class DaemonContinuationGate<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var connection: NSXPCConnection?

    init(
        continuation: CheckedContinuation<Value, Error>,
        connection: NSXPCConnection
    ) {
        self.continuation = continuation
        self.connection = connection
    }

    func resume(_ result: Result<Value, Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        let retainedConnection = connection
        self.connection = nil
        lock.unlock()
        retainedConnection?.invalidationHandler = nil
        retainedConnection?.invalidate()
        continuation.resume(with: result)
    }
}
