import SwiftUI

struct ContentView: View {
    @ObservedObject var serviceManager: HelperServiceManager

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "macbook.and.iphone")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 4) {
                    Text("app_title")
                        .font(.title2.weight(.semibold))
                    Text("app_subtitle")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label(serviceManager.status.localizedTitle, systemImage: statusSymbol)
                        .font(.headline)
                    Text("safety_explanation")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            if let errorMessage = serviceManager.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            HStack(spacing: 10) {
                primaryAction
                Button("refresh") {
                    Task { await serviceManager.refresh() }
                }
                .disabled(serviceManager.isWorking)
                Spacer()
                if canRemove {
                    Button("restore_and_remove", role: .destructive) {
                        Task { await serviceManager.restoreAndRemove() }
                    }
                    .disabled(serviceManager.isWorking)
                }
            }

            Divider()

            Text("install_note")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 560)
        .task {
            await serviceManager.refresh()
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch serviceManager.status {
        case .notInApplications:
            Button("open_applications") {
                serviceManager.revealApplicationsFolder()
            }
            .buttonStyle(.borderedProminent)
        case .notRegistered:
            Button("install_service") {
                Task { await serviceManager.install() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(serviceManager.isWorking)
        case .updateRequired:
            Button("update_service") {
                Task { await serviceManager.repairOrUpdate() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(serviceManager.isWorking)
        case .unavailable:
            Button("repair_service") {
                Task { await serviceManager.repairOrUpdate() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(serviceManager.isWorking)
        case .requiresApproval:
            Button("open_system_settings") {
                serviceManager.openApprovalSettings()
            }
            .buttonStyle(.borderedProminent)
        case .enabled:
            Button("open_rouse") {
                guard let appURL = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: "com.jaminzhou.rouse"
                ) else { return }
                NSWorkspace.shared.openApplication(
                    at: appURL,
                    configuration: NSWorkspace.OpenConfiguration()
                )
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var canRemove: Bool {
        switch serviceManager.status {
        case .notRegistered, .notInApplications:
            return false
        case .requiresApproval, .updateRequired, .enabled, .unavailable:
            return true
        }
    }

    private var statusSymbol: String {
        switch serviceManager.status {
        case .enabled(_, true): "bolt.fill"
        case .enabled: "checkmark.circle.fill"
        case .requiresApproval: "person.badge.key.fill"
        case .updateRequired: "arrow.triangle.2.circlepath.circle.fill"
        case .notInApplications: "folder.fill"
        case .notRegistered: "circle.dashed"
        case .unavailable: "exclamationmark.triangle.fill"
        }
    }
}
