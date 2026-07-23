import Darwin
import Foundation
import OSLog
import RouseClosedLidCore
import RouseClosedLidProtocol

if CommandLine.arguments.dropFirst() == ["--self-test"] {
    print("RouseClosedLidDaemon self-test passed")
    exit(EXIT_SUCCESS)
}

let controller = LeaseController(
    powerSettings: PMSetController(),
    journalStore: FileRecoveryJournalStore(),
    maximumLeaseDuration: RouseClosedLidIPC.maximumLeaseDuration
)

do {
    try controller.recoverInterruptedOverride()
} catch {
    Logger.daemon.critical("Startup recovery failed: \(error.localizedDescription, privacy: .public)")
    exit(EXIT_FAILURE)
}

let daemonVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
let delegate = DaemonListenerDelegate(controller: controller, daemonVersion: daemonVersion)
let listener = NSXPCListener(machServiceName: RouseClosedLidIPC.machServiceName)

listener.setConnectionCodeSigningRequirement(RouseClosedLidIPC.acceptedClientCodeSigningRequirement)
listener.delegate = delegate
listener.activate()

let expiryTimer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
expiryTimer.schedule(deadline: .now() + 5, repeating: 5)
expiryTimer.setEventHandler {
    do {
        try controller.expireLeases()
    } catch {
        Logger.daemon.error("Lease expiry recovery failed: \(error.localizedDescription, privacy: .public)")
    }
}
expiryTimer.activate()

signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let terminationSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
let interruptSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
let terminate: @Sendable () -> Void = {
    do {
        try controller.restoreAll()
    } catch {
        Logger.daemon.error("Shutdown recovery failed: \(error.localizedDescription, privacy: .public)")
    }
    exit(EXIT_SUCCESS)
}
terminationSource.setEventHandler(handler: terminate)
interruptSource.setEventHandler(handler: terminate)
terminationSource.activate()
interruptSource.activate()

Logger.daemon.info("Rouse closed-lid daemon started")
RunLoop.main.run()
