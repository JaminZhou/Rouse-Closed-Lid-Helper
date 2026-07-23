import AppKit
import Foundation
import RouseClosedLidProtocol
import ServiceManagement

enum HelperServiceStatus: Equatable {
    case notInApplications
    case notRegistered
    case requiresApproval
    case updateRequired(installedVersion: String, bundledVersion: String)
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

    func refresh() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        guard isInstalledInApplications else {
            status = .notInApplications
            return
        }

        switch service.status {
        case .notRegistered:
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
                status = .enabled(daemonVersion: daemonStatus.daemonVersion, active: daemonStatus.isActive)
            } catch {
                status = .unavailable
                errorMessage = error.localizedDescription
            }
        case .notFound:
            status = .unavailable
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
            if service.status == .notRegistered {
                try service.register()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
        await refresh()
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
            if service.status != .notRegistered {
                try await service.unregister()
            }
            try service.register()
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
        await refresh()
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
        do {
            if service.status == .enabled {
                try await client.restoreOriginalSettings()
            }
            if service.status != .notRegistered {
                try await service.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
        await refresh()
    }
}
