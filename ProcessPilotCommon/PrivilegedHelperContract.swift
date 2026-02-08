import Foundation

public enum PrivilegedHelperContract {
    public static let defaultMachServiceName = "com.local.processpilot.privilegedhelper"
    public static let defaultDaemonPlistName = "com.local.processpilot.privilegedhelper.plist"
    public static let appInfoKeyMachServiceName = "PPPrivilegedHelperLabel"
    public static let appInfoKeyDaemonPlistName = "PPPrivilegedHelperDaemonPlist"
}

@objc public protocol ProcessPilotPrivilegedHelperXPC {
    func sendSignal(pid: Int32, signal: Int32, withReply reply: @escaping (Int32) -> Void)
}
