import Foundation
import OSLog
import RouseClosedLidCore
import RouseClosedLidProtocol

final class DaemonListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let controller: LeaseController
    private let daemonVersion: String
    private let lock = NSLock()
    private var connections: [UUID: NSXPCConnection] = [:]
    private var services: [UUID: DaemonService] = [:]

    init(controller: LeaseController, daemonVersion: String) {
        self.controller = controller
        self.daemonVersion = daemonVersion
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let clientID = UUID()
        let service = DaemonService(clientID: clientID, controller: controller, daemonVersion: daemonVersion)

        connection.exportedInterface = NSXPCInterface(with: RouseClosedLidDaemonProtocol.self)
        connection.exportedObject = service
        connection.invalidationHandler = { [weak self] in
            self?.removeConnection(clientID: clientID)
        }
        connection.interruptionHandler = { [weak self] in
            self?.endLease(clientID: clientID)
        }

        lock.lock()
        connections[clientID] = connection
        services[clientID] = service
        lock.unlock()

        connection.activate()
        Logger.daemon.info("Accepted XPC client \(clientID.uuidString, privacy: .public)")
        return true
    }

    private func removeConnection(clientID: UUID) {
        endLease(clientID: clientID)
        lock.lock()
        connections.removeValue(forKey: clientID)
        services.removeValue(forKey: clientID)
        lock.unlock()
    }

    private func endLease(clientID: UUID) {
        do {
            try controller.endLease(clientID: clientID)
        } catch {
            Logger.daemon.error("Client cleanup could not restore settings: \(error.localizedDescription, privacy: .public)")
        }
    }
}

