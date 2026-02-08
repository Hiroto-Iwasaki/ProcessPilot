import Foundation

struct ProcessGroup: Identifiable, Equatable, Sendable {
    var id: String { appName }
    let appName: String
    let processes: [AppProcessInfo]
    let representativeExecutablePath: String?
    let rawTotalCPU: Double
    let totalMemory: Double
    var smoothedTotalCPU: Double? = nil
    
    init(appName: String, processes: [AppProcessInfo], smoothedTotalCPU: Double? = nil) {
        self.appName = appName
        self.processes = processes
        self.representativeExecutablePath = ProcessGroup.resolveRepresentativeExecutablePath(from: processes)
        self.rawTotalCPU = processes.reduce(0) { $0 + $1.cpuUsage }
        self.totalMemory = processes.reduce(0) { $0 + $1.memoryUsage }
        self.smoothedTotalCPU = smoothedTotalCPU
    }
    
    var totalCPU: Double {
        smoothedTotalCPU ?? rawTotalCPU
    }
    
    var isSystemGroup: Bool {
        processes.first?.isSystemProcess ?? false
    }
    
    var processCount: Int {
        processes.count
    }
    
    private static func resolveRepresentativeExecutablePath(from processes: [AppProcessInfo]) -> String? {
        let executablePaths = processes.compactMap(\.executablePath)
        
        return executablePaths.first(where: { path in
            let lowercasedPath = path.lowercased()
            return lowercasedPath.contains(".app/") ||
                lowercasedPath.contains(".xpc/") ||
                lowercasedPath.contains(".appex/") ||
                lowercasedPath.hasSuffix(".app") ||
                lowercasedPath.hasSuffix(".xpc") ||
                lowercasedPath.hasSuffix(".appex")
        }) ?? executablePaths.first
    }
}
