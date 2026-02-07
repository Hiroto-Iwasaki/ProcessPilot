import Foundation

struct AppProcessInfo: Identifiable, Hashable, Sendable {
    enum Source: String, Sendable {
        case currentApp = "このアプリ"
        case system = "システム"
        case application = "他アプリ"
        case commandLine = "コマンド"
        case unknown = "不明"
    }
    
    var id: Int32 { pid }
    let pid: Int32
    let name: String
    let user: String
    var cpuUsage: Double
    var memoryUsage: Double // in MB
    var description: String
    var isSystemProcess: Bool
    var parentApp: String?
    var executablePath: String? = nil
    
    var displayName: String {
        if let parent = parentApp, !parent.isEmpty {
            return "\(name) (\(parent))"
        }
        return name
    }
    
    var source: Source {
        if isSystemProcess {
            return .system
        }
        
        if let parentApp, Self.currentAppAliases.contains(parentApp.lowercased()) {
            return .currentApp
        }
        
        guard let executablePath else {
            return .unknown
        }
        
        if Self.systemPathPrefixes.contains(where: { executablePath.hasPrefix($0) }) {
            return .system
        }
        
        if executablePath.contains(".app/") {
            if Self.currentAppAliases.contains(where: { alias in
                executablePath.localizedCaseInsensitiveContains("/\(alias).app/")
            }) {
                return .currentApp
            }
            return .application
        }
        
        if Self.commandLinePathPrefixes.contains(where: { executablePath.hasPrefix($0) }) {
            return .commandLine
        }
        
        return .unknown
    }
    
    static func == (lhs: AppProcessInfo, rhs: AppProcessInfo) -> Bool {
        lhs.pid == rhs.pid
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
    }
    
    private static let systemPathPrefixes = [
        "/System/",
        "/usr/libexec/",
        "/usr/sbin/",
        "/sbin/"
    ]
    
    private static let commandLinePathPrefixes = [
        "/bin/",
        "/usr/bin/",
        "/usr/local/bin/",
        "/opt/homebrew/bin/"
    ]
    
    private static let currentAppAliases: Set<String> = {
        var aliases: Set<String> = ["processpilot"]
        if let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String {
            aliases.insert(bundleName.lowercased())
        }
        aliases.insert(Foundation.ProcessInfo.processInfo.processName.lowercased())
        return aliases
    }()
}
