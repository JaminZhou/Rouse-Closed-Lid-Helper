import Foundation

public enum RouseClosedLidIPC {
    public static let protocolVersion = 1
    public static let appGroupIdentifier = "NA4X3TYR2P.com.jaminzhou.rouse"
    public static let machServiceName = "NA4X3TYR2P.com.jaminzhou.rouse.closed-lid-daemon"
    public static let daemonPlistName = "NA4X3TYR2P.com.jaminzhou.rouse.closed-lid-daemon.plist"
    public static let rouseBundleIdentifier = "com.jaminzhou.rouse"
    public static let helperBundleIdentifier = "com.jaminzhou.rouse.closed-lid-helper"
    public static let maximumLeaseDuration: TimeInterval = 120
    public static let recommendedLeaseDuration: TimeInterval = 90
    public static let recommendedRenewalInterval: TimeInterval = 30

    public enum StatusKey {
        public static let protocolVersion = "protocolVersion"
        public static let daemonVersion = "daemonVersion"
        public static let active = "active"
        public static let leaseCount = "leaseCount"
        public static let nextExpiry = "nextExpiry"
        public static let recoveryJournalPresent = "recoveryJournalPresent"
    }
}

@objc public protocol RouseClosedLidDaemonProtocol {
    func fetchStatus(withReply reply: @escaping (NSDictionary) -> Void)

    func renewLease(
        duration: TimeInterval,
        withReply reply: @escaping (Bool, String?) -> Void
    )

    func endLease(withReply reply: @escaping (Bool, String?) -> Void)

    func restoreOriginalSettings(withReply reply: @escaping (Bool, String?) -> Void)
}

