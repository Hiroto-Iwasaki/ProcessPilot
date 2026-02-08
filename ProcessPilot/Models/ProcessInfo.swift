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
    let isSystemProcess: Bool
    let parentApp: String?
    let executablePath: String?
    let source: Source
    
    var displayName: String {
        if let parent = parentApp, !parent.isEmpty {
            return "\(name) (\(parent))"
        }
        return name
    }
    
    init(
        pid: Int32,
        name: String,
        user: String,
        cpuUsage: Double,
        memoryUsage: Double,
        description: String,
        isSystemProcess: Bool,
        parentApp: String?,
        executablePath: String? = nil,
        source: Source? = nil
    ) {
        self.pid = pid
        self.name = name
        self.user = user
        self.cpuUsage = cpuUsage
        self.memoryUsage = memoryUsage
        self.description = description
        self.isSystemProcess = isSystemProcess
        self.parentApp = parentApp
        let normalizedExecutablePath = executablePath?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.executablePath = (normalizedExecutablePath?.isEmpty == false)
            ? normalizedExecutablePath
            : nil
        self.source = source ?? Self.resolveSource(
            isSystemProcess: isSystemProcess,
            parentApp: parentApp,
            executablePath: self.executablePath
        )
    }
    
    static func == (lhs: AppProcessInfo, rhs: AppProcessInfo) -> Bool {
        lhs.pid == rhs.pid
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
    }

    private static func resolveSource(
        isSystemProcess: Bool,
        parentApp: String?,
        executablePath: String?
    ) -> Source {
        if isSystemProcess {
            return .system
        }

        if let parentApp, currentAppAliases.contains(parentApp.lowercased()) {
            return .currentApp
        }

        guard let executablePath else {
            return .unknown
        }

        if systemPathPrefixes.contains(where: { executablePath.hasPrefix($0) }) {
            return .system
        }

        if executablePath.contains(".app/") {
            if currentAppAliases.contains(where: { alias in
                executablePath.localizedCaseInsensitiveContains("/\(alias).app/")
            }) {
                return .currentApp
            }
            return .application
        }

        if commandLinePathPrefixes.contains(where: { executablePath.hasPrefix($0) }) {
            return .commandLine
        }

        return .unknown
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
