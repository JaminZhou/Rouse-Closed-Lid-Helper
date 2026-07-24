import ProjectDescription

let appVersion = "1.0.0"
let buildNumber = "1"
let teamID = "NA4X3TYR2P"
let appGroup = "NA4X3TYR2P.com.jaminzhou.rouse"

let commonSettings: SettingsDictionary = [
    "MACOSX_DEPLOYMENT_TARGET": "13.0",
    "DEVELOPMENT_TEAM": .string(teamID),
    "CODE_SIGN_STYLE": "Automatic",
    "ENABLE_HARDENED_RUNTIME": "YES",
    "SWIFT_VERSION": "5.10",
    "ONLY_ACTIVE_ARCH": "NO",
]

let protocolTarget: Target = .target(
    name: "RouseClosedLidProtocol",
    destinations: .macOS,
    product: .staticFramework,
    bundleId: "com.jaminzhou.rouse.closed-lid-helper.protocol",
    sources: ["Sources/Protocol/**"],
    settings: .settings(base: commonSettings)
)

let coreTarget: Target = .target(
    name: "RouseClosedLidCore",
    destinations: .macOS,
    product: .staticFramework,
    bundleId: "com.jaminzhou.rouse.closed-lid-helper.core",
    sources: ["Sources/Core/**"],
    settings: .settings(base: commonSettings)
)

let daemonTarget: Target = .target(
    name: "RouseClosedLidDaemon",
    destinations: .macOS,
    product: .commandLineTool,
    productName: "RouseClosedLidDaemon",
    bundleId: "com.jaminzhou.rouse.closed-lid-helper.daemon",
    infoPlist: .extendingDefault(with: [
        "CFBundleShortVersionString": .string("$(MARKETING_VERSION)"),
        "CFBundleVersion": .string("$(CURRENT_PROJECT_VERSION)"),
    ]),
    sources: ["Sources/Daemon/**"],
    dependencies: [
        .target(name: "RouseClosedLidProtocol"),
        .target(name: "RouseClosedLidCore"),
    ],
    settings: .settings(base: commonSettings.merging([
        "PRODUCT_BUNDLE_IDENTIFIER": "com.jaminzhou.rouse.closed-lid-helper.daemon",
        "CODE_SIGN_ENTITLEMENTS": "Entitlements/Daemon.entitlements",
        "CREATE_INFOPLIST_SECTION_IN_BINARY": "YES",
        "MARKETING_VERSION": .string(appVersion),
        "CURRENT_PROJECT_VERSION": .string(buildNumber),
        "SKIP_INSTALL": "YES",
    ]) { _, new in new })
)

let helperTarget: Target = .target(
    name: "RouseClosedLidHelper",
    destinations: .macOS,
    product: .app,
    productName: "RouseClosedLidHelper",
    bundleId: "com.jaminzhou.rouse.closed-lid-helper",
    infoPlist: .extendingDefault(with: [
        "CFBundleDisplayName": "Rouse Closed-Lid Helper",
        "CFBundleShortVersionString": .string("$(MARKETING_VERSION)"),
        "CFBundleVersion": .string("$(CURRENT_PROJECT_VERSION)"),
        "LSApplicationCategoryType": "public.app-category.utilities",
        "NSHumanReadableCopyright": "Copyright © 2026 JaminZhou. All rights reserved.",
    ]),
    sources: ["Sources/HelperApp/**"],
    resources: ["Sources/HelperApp/Resources/**"],
    scripts: [
        .post(
            script: """
            set -euo pipefail
            DAEMON_SOURCE="${BUILT_PRODUCTS_DIR}/RouseClosedLidDaemon"
            DAEMON_DEST="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Library/HelperTools/RouseClosedLidDaemon"
            PLIST_SOURCE="${SRCROOT}/Support/LaunchDaemons/NA4X3TYR2P.com.jaminzhou.rouse.closed-lid-daemon.plist"
            PLIST_DEST="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Library/LaunchDaemons/NA4X3TYR2P.com.jaminzhou.rouse.closed-lid-daemon.plist"

            test -f "${DAEMON_SOURCE}"
            install -d "$(dirname "${DAEMON_DEST}")" "$(dirname "${PLIST_DEST}")"
            ditto "${DAEMON_SOURCE}" "${DAEMON_DEST}"
            chmod 755 "${DAEMON_DEST}"
            ditto "${PLIST_SOURCE}" "${PLIST_DEST}"
            """,
            name: "Embed privileged daemon",
            inputPaths: [
                "$(BUILT_PRODUCTS_DIR)/RouseClosedLidDaemon",
                "$(SRCROOT)/Support/LaunchDaemons/NA4X3TYR2P.com.jaminzhou.rouse.closed-lid-daemon.plist",
            ],
            outputPaths: [
                "$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Library/HelperTools/RouseClosedLidDaemon",
                "$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Library/LaunchDaemons/NA4X3TYR2P.com.jaminzhou.rouse.closed-lid-daemon.plist",
            ],
            basedOnDependencyAnalysis: false
        ),
    ],
    dependencies: [
        .target(name: "RouseClosedLidDaemon"),
        .target(name: "RouseClosedLidProtocol"),
    ],
    settings: .settings(base: commonSettings.merging([
        "PRODUCT_BUNDLE_IDENTIFIER": "com.jaminzhou.rouse.closed-lid-helper",
        "PRODUCT_NAME": "Rouse Closed-Lid Helper",
        "CODE_SIGN_ENTITLEMENTS": "Entitlements/Helper.entitlements",
        "ASSETCATALOG_COMPILER_APPICON_NAME": .string("AppIcon"),
        "MARKETING_VERSION": .string(appVersion),
        "CURRENT_PROJECT_VERSION": .string(buildNumber),
    ]) { _, new in new })
)

let coreTests: Target = .target(
    name: "RouseClosedLidCoreTests",
    destinations: .macOS,
    product: .unitTests,
    bundleId: "com.jaminzhou.rouse.closed-lid-helper.core-tests",
    sources: ["Tests/CoreTests/**"],
    dependencies: [
        .target(name: "RouseClosedLidCore"),
        .target(name: "RouseClosedLidProtocol"),
    ],
    settings: .settings(base: commonSettings.merging([
        "MACOSX_DEPLOYMENT_TARGET": "14.0",
    ]) { _, new in new })
)

let appScheme: Scheme = .scheme(
    name: "Rouse-Closed-Lid-Helper",
    buildAction: .buildAction(targets: [.target("RouseClosedLidHelper")]),
    testAction: .targets([.testableTarget(target: .target("RouseClosedLidCoreTests"))]),
    runAction: .runAction(configuration: "Debug", executable: .target("RouseClosedLidHelper")),
    archiveAction: .archiveAction(configuration: "Release")
)

let project = Project(
    name: "RouseClosedLidHelper",
    settings: .settings(base: commonSettings),
    targets: [protocolTarget, coreTarget, daemonTarget, helperTarget, coreTests],
    schemes: [appScheme]
)
