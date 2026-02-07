import Foundation
import Combine

@MainActor
class ProcessMonitor: ObservableObject {
    @Published var processes: [AppProcessInfo] = []
    @Published var groups: [ProcessGroup] = []
    @Published var isLoading = false
    @Published var sortBy: SortOption = .cpu
    @Published var showGrouped = true
    @Published var showHighUsageFirst = false
    @Published var filterText = "" {
        didSet {
            applySortingAndGrouping()
        }
    }
    
    private var allProcesses: [AppProcessInfo] = []
    
    enum SortOption: String, CaseIterable, Sendable {
        case cpu = "CPU"
        case memory = "メモリ"
    }
    
    func refreshProcesses() async {
        guard !isLoading else { return }
        isLoading = true
        
        do {
            let fetchedProcesses = try await Task.detached(priority: .utility) {
                try ProcessSnapshotBuilder.fetchProcesses()
            }.value
            
            allProcesses = fetchedProcesses
            applySortingAndGrouping()
        } catch {
            print("Error refreshing process list: \(error)")
        }
        
        isLoading = false
    }
    
    func changeSortOption(_ option: SortOption) {
        sortBy = option
        applySortingAndGrouping()
    }
    
    func changeHighUsageOrder(_ isEnabled: Bool) {
        showHighUsageFirst = isEnabled
        applySortingAndGrouping()
    }
    
    private func applySortingAndGrouping() {
        let visibleProcesses = ProcessSnapshotBuilder.sortProcesses(
            allProcesses,
            sortBy: sortBy,
            filterText: filterText,
            showHighUsageFirst: showHighUsageFirst
        )
        processes = visibleProcesses
        groups = ProcessSnapshotBuilder.groupProcesses(
            visibleProcesses,
            sortBy: sortBy,
            showHighUsageFirst: showHighUsageFirst
        )
    }
}

enum ProcessSnapshotBuilder {
    static func fetchProcesses() throws -> [AppProcessInfo] {
        let output = try runPS()
        return parseProcesses(output)
    }
    
    static func sortProcesses(
        _ processes: [AppProcessInfo],
        sortBy: ProcessMonitor.SortOption,
        filterText: String,
        showHighUsageFirst: Bool = false
    ) -> [AppProcessInfo] {
        var sorted = processes
        let descending = showHighUsageFirst
        
        switch sortBy {
        case .cpu:
            orderCollection(
                &sorted,
                value: { $0.cpuUsage },
                descending: descending,
                tieBreaker: { lhs, rhs in
                    lhs.name.lowercased() < rhs.name.lowercased()
                }
            )
        case .memory:
            orderCollection(
                &sorted,
                value: { $0.memoryUsage },
                descending: descending,
                tieBreaker: { lhs, rhs in
                    lhs.name.lowercased() < rhs.name.lowercased()
                }
            )
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
        sortBy: ProcessMonitor.SortOption,
        showHighUsageFirst: Bool = false
    ) -> [ProcessGroup] {
        var groupDict: [String: [AppProcessInfo]] = [:]
        let descending = showHighUsageFirst
        
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
            orderCollection(
                &groups,
                value: { $0.totalCPU },
                descending: descending,
                tieBreaker: { lhs, rhs in
                    lhs.appName.lowercased() < rhs.appName.lowercased()
                }
            )
        case .memory:
            orderCollection(
                &groups,
                value: { $0.totalMemory },
                descending: descending,
                tieBreaker: { lhs, rhs in
                    lhs.appName.lowercased() < rhs.appName.lowercased()
                }
            )
        }
        
        return groups
    }
    
    private static func orderCollection<T, Value: Comparable>(
        _ values: inout [T],
        value: (T) -> Value,
        descending: Bool,
        tieBreaker: (T, T) -> Bool
    ) {
        values.sort { lhs, rhs in
            let lhsValue = value(lhs)
            let rhsValue = value(rhs)
            
            if lhsValue == rhsValue {
                return tieBreaker(lhs, rhs)
            }
            
            return descending ? lhsValue > rhsValue : lhsValue < rhsValue
        }
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
