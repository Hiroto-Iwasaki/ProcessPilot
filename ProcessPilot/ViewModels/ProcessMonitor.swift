import Foundation
import Combine

@MainActor
class ProcessMonitor: ObservableObject {
    @Published var processes: [AppProcessInfo] = []
    @Published var groups: [ProcessGroup] = []
    @Published var isLoading = false
    @Published var sortBy: SortOption = .cpu
    @Published var showGrouped = true
    @Published var filterText = ""
    
    enum SortOption: String, CaseIterable, Sendable {
        case cpu = "CPU"
        case memory = "メモリ"
        case name = "名前"
    }
    
    init() {
        Task {
            await refreshProcesses()
        }
    }
    
    func refreshProcesses() async {
        guard !isLoading else { return }
        isLoading = true
        
        let currentSortBy = sortBy
        let currentFilterText = filterText
        
        do {
            let snapshot = try await Task.detached(priority: .utility) {
                try ProcessSnapshotBuilder.build(
                    sortBy: currentSortBy,
                    filterText: currentFilterText
                )
            }.value
            
            processes = snapshot.processes
            groups = snapshot.groups
        } catch {
            print("Error refreshing process list: \(error)")
        }
        
        isLoading = false
    }
    
    func changeSortOption(_ option: SortOption) {
        sortBy = option
        processes = ProcessSnapshotBuilder.sortProcesses(
            processes,
            sortBy: sortBy,
            filterText: filterText
        )
        groups = ProcessSnapshotBuilder.groupProcesses(processes, sortBy: sortBy)
    }
}

enum ProcessSnapshotBuilder {
    struct Snapshot: Sendable {
        let processes: [AppProcessInfo]
        let groups: [ProcessGroup]
    }
    
    static func build(
        sortBy: ProcessMonitor.SortOption,
        filterText: String
    ) throws -> Snapshot {
        let output = try runPS()
        let parsed = parseProcesses(output)
        let sorted = sortProcesses(parsed, sortBy: sortBy, filterText: filterText)
        let groups = groupProcesses(sorted, sortBy: sortBy)
        
        return Snapshot(processes: sorted, groups: groups)
    }
    
    static func sortProcesses(
        _ processes: [AppProcessInfo],
        sortBy: ProcessMonitor.SortOption,
        filterText: String
    ) -> [AppProcessInfo] {
        var sorted = processes
        
        switch sortBy {
        case .cpu:
            sorted.sort { $0.cpuUsage > $1.cpuUsage }
        case .memory:
            sorted.sort { $0.memoryUsage > $1.memoryUsage }
        case .name:
            sorted.sort { $0.name.lowercased() < $1.name.lowercased() }
        }
        
        if !filterText.isEmpty {
            sorted = sorted.filter {
                $0.name.localizedCaseInsensitiveContains(filterText) ||
                $0.description.localizedCaseInsensitiveContains(filterText)
            }
        }
        
        return sorted
    }
    
    static func groupProcesses(
        _ processes: [AppProcessInfo],
        sortBy: ProcessMonitor.SortOption
    ) -> [ProcessGroup] {
        var groupDict: [String: [AppProcessInfo]] = [:]
        
        for process in processes {
            let groupName = process.parentApp ?? (process.isSystemProcess ? "システム" : process.name)
            if groupDict[groupName] == nil {
                groupDict[groupName] = []
            }
            groupDict[groupName]?.append(process)
        }
        
        var groups = groupDict.map { ProcessGroup(appName: $0.key, processes: $0.value) }
        
        switch sortBy {
        case .cpu:
            groups.sort { $0.totalCPU > $1.totalCPU }
        case .memory:
            groups.sort { $0.totalMemory > $1.totalMemory }
        case .name:
            groups.sort { $0.appName.lowercased() < $1.appName.lowercased() }
        }
        
        return groups
    }
    
    private static func runPS() throws -> String {
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["aux"]
        
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        
        guard task.terminationStatus == 0 else {
            throw NSError(
                domain: "ProcessSnapshotBuilder",
                code: Int(task.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "ps command exited with status \(task.terminationStatus)."]
            )
        }
        
        guard let output = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "ProcessSnapshotBuilder",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to decode ps output."]
            )
        }
        
        return output
    }
    
    static func parseProcesses(_ output: String) -> [AppProcessInfo] {
        var newProcesses: [AppProcessInfo] = []
        let lines = output.components(separatedBy: "\n")
        
        for line in lines.dropFirst() {
            guard !line.isEmpty else { continue }
            
            let components = line.split(separator: " ", omittingEmptySubsequences: true)
            guard components.count >= 11 else { continue }
            
            let user = String(components[0])
            guard let pid = Int32(components[1]) else { continue }
            guard let cpu = Double(components[2]) else { continue }
            guard let mem = Double(components[3]) else { continue }
            
            let commandPath = components[10...].joined(separator: " ")
            let processName = extractProcessName(from: commandPath)
            let memoryMB = mem * getPhysicalMemoryGB() * 10.24
            
            let process = AppProcessInfo(
                pid: pid,
                name: processName,
                user: user,
                cpuUsage: cpu,
                memoryUsage: memoryMB,
                description: ProcessDescriptions.getDescription(for: processName),
                isSystemProcess: ProcessDescriptions.isSystemProcess(processName),
                parentApp: extractParentApp(from: commandPath)
            )
            
            newProcesses.append(process)
        }
        
        return newProcesses
    }
    
    private static func extractProcessName(from commandPath: String) -> String {
        let path = commandPath.components(separatedBy: " ").first ?? commandPath
        let name = path.components(separatedBy: "/").last ?? path
        
        if name.hasSuffix(".app") {
            return String(name.dropLast(4))
        }
        
        return String(name.prefix(20))
    }
    
    private static func extractParentApp(from commandPath: String) -> String? {
        if let range = commandPath.range(of: ".app") {
            let beforeApp = commandPath[..<range.lowerBound]
            let components = beforeApp.components(separatedBy: "/")
            if let appName = components.last {
                return appName
            }
        }
        return nil
    }
    
    private static func getPhysicalMemoryGB() -> Double {
        Double(Foundation.ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
    }
}
