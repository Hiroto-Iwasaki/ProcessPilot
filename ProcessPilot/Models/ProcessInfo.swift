import Foundation

struct AppProcessInfo: Identifiable, Hashable, Sendable {
    var id: Int32 { pid }
    let pid: Int32
    let name: String
    let user: String
    var cpuUsage: Double
    var memoryUsage: Double // in MB
    var description: String
    var isSystemProcess: Bool
    var parentApp: String?
    
    var displayName: String {
        if let parent = parentApp, !parent.isEmpty {
            return "\(name) (\(parent))"
        }
        return name
    }
    
    static func == (lhs: AppProcessInfo, rhs: AppProcessInfo) -> Bool {
        lhs.pid == rhs.pid
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
    }
}
