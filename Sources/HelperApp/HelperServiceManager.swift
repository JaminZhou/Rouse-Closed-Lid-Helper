import AppKit
import Foundation
import RouseClosedLidProtocol
import ServiceManagement

enum HelperServiceStatus: Equatable {
    case notInApplications
    case notRegistered
    case requiresApproval
    case updateRequired(installedVersion: String, bundledVersion: String)
    case recoveryRequired(daemonVersion: String)
    case enabled(daemonVersion: String, active: Bool)
    case unavailable

    var localizedTitle: String {
        switch self {
        case .notInApplications:
            return NSLocalizedString("status_move_to_applications", comment: "")
        case .notRegistered:
            return NSLocalizedString("status_not_installed", comment: "")
        case .requiresApproval:
            return NSLocalizedString("status_requires_approval", comment: "")
        case let .updateRequired(installedVersion, bundledVersion):
            return String(
                format: NSLocalizedString("status_update_required", comment: ""),
                installedVersion,
                bundledVersion
            )
        case let .recoveryRequired(daemonVersion):
            return String(
                format: NSLocalizedString("status_recovery_required", comment: ""),
                daemonVersion
            )
        case let .enabled(daemonVersion, active):
            return String(
                format: NSLocalizedString(active ? "status_active" : "status_ready", comment: ""),
                daemonVersion
            )
        case .unavailable:
            return NSLocalizedString("status_unavailable", comment: "")
        }
    }
}

@MainActor
final class HelperServiceManager: ObservableObject {
    @Published private(set) var status: HelperServiceStatus = .notRegistered
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    private let service = SMAppService.daemon(plistName: RouseClosedLidIPC.daemonPlistName)
    private let client = DaemonClient()

    private var bundledVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var isInstalledInApplications: Bool {
        let path = Bundle.main.bundleURL.standardizedFileURL.path
        return path.hasPrefix("/Applications/")
    }

    func refresh(clearExistingError: Bool = true) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        if clearExistingError {
            errorMessage = nil
        }

        guard isInstalledInApplications else {
            status = .notInApplications
            return
        }

        switch service.status {
        case .notRegistered, .notFound:
            // A bundled daemon that has never been registered can report
            // `.notFound` on current macOS releases. Registration is still the
            // correct first action; any malformed or missing bundled plist is
            // surfaced by `register()`.
            status = .notRegistered
        case .requiresApproval:
            status = .requiresApproval
        case .enabled:
            do {
                let daemonStatus = try await client.fetchStatus()
                guard daemonStatus.protocolVersion == RouseClosedLidIPC.protocolVersion else {
                    status = .unavailable
                    errorMessage = NSLocalizedString("error_incompatible_protocol", comment: "")
                    return
                }
                guard daemonStatus.daemonVersion == bundledVersion else {
                    status = .updateRequired(
                        installedVersion: daemonStatus.daemonVersion,
                        bundledVersion: bundledVersion
                    )
                    return
                }
                guard !daemonStatus.recoveryJournalPresent || daemonStatus.isActive else {
                    status = .recoveryRequired(daemonVersion: daemonStatus.daemonVersion)
                    return
                }
                status = .enabled(daemonVersion: daemonStatus.daemonVersion, active: daemonStatus.isActive)
            } catch {
                status = .unavailable
                errorMessage = error.localizedDescription
            }
        @unknown default:
            status = .unavailable
        }
    }

    func install() async {
        guard isInstalledInApplications else {
            status = .notInApplications
            return
        }
        isWorking = true
        errorMessage = nil
        do {
            switch service.status {
            case .notRegistered, .notFound:
                try registerService()
            case .requiresApproval, .enabled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
        await refresh(clearExistingError: false)
    }

    func repairOrUpdate() async {
        guard isInstalledInApplications else {
            status = .notInApplications
            return
        }
        isWorking = true
        errorMessage = nil
        do {
            if service.status == .enabled {
                do {
                    try await client.restoreOriginalSettings()
                } catch {
                    // Continue with re-registration when the installed daemon cannot answer.
                    // Its termination handler or the replacement daemon's startup recovery
                    // will restore any settings recorded in the recovery journal.
                }
            }

            switch service.status {
            case .enabled, .requiresApproval:
                try await service.unregister()
                // Service Management may reject an immediate unregister/register
                // pair even after the async unregister call returns. Yield a short
                // interval before re-enrolling the same bundled daemon.
                try await Task.sleep(nanoseconds: 500_000_000)
            case .notRegistered, .notFound:
                break
            @unknown default:
                break
            }
            try registerService()
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
        await refresh(clearExistingError: false)
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func revealApplicationsFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
    }

    func restoreAndRemove() async {
        isWorking = true
        errorMessage = nil
        var restoreErrorMessage: String?
        do {
            if service.status == .enabled {
                do {
                    try await client.restoreOriginalSettings()
                } catch {
                    restoreErrorMessage = error.localizedDescription
                }
            }

            switch service.status {
            case .enabled, .requiresApproval:
                try await service.unregister()
            case .notRegistered, .notFound:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        if errorMessage == nil {
            errorMessage = restoreErrorMessage
        }
        isWorking = false
        await refresh(clearExistingError: false)
    }

    private func registerService() throws {
        do {
            try service.register()
        } catch {
            // Current macOS releases can return EPERM after successfully adding
            // a daemon that still needs approval. The status is authoritative:
            // keep the real error only when registration did not reach that
            // expected intermediate state.
            guard service.status == .requiresApproval else {
                throw error
            }
        }
    }
}
