import Foundation

struct ProcessGroup: Identifiable {
    let id = UUID()
    let appName: String
    var processes: [AppProcessInfo]
    
    var totalCPU: Double {
        processes.reduce(0) { $0 + $1.cpuUsage }
    }
    
    var totalMemory: Double {
        processes.reduce(0) { $0 + $1.memoryUsage }
    }
    
    var isSystemGroup: Bool {
        processes.first?.isSystemProcess ?? false
    }
    
    var processCount: Int {
        processes.count
    }
}
