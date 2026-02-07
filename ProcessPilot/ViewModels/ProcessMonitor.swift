import Foundation
import Combine
import Darwin

@MainActor
class ProcessMonitor: ObservableObject {
    private struct DisplaySnapshot: Sendable {
        let processes: [AppProcessInfo]
        let groups: [ProcessGroup]
    }
    
    @Published var processes: [AppProcessInfo] = []
    @Published var groups: [ProcessGroup] = []
    @Published var isLoading = false
    @Published var sortBy: SortOption = .cpu
    @Published var showGrouped = true
    @Published var showHighUsageFirst = true
    @Published var filterText = "" {
        didSet {
            applySortingAndGrouping()
        }
    }
    
    private var allProcesses: [AppProcessInfo] = []
    private var usageSmoother = UsageSmoother(windowSize: 3)
    private var snapshotTask: Task<Void, Never>?
    private var snapshotVersion: UInt64 = 0
    
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
            
            allProcesses = usageSmoother.smooth(processes: fetchedProcesses)
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
    
    func removeProcessesFromCache(pids: [Int32]) {
        removeProcessesFromCache(pids: Set(pids))
    }
    
    func removeProcessesFromCache(pids: Set<Int32>) {
        guard !pids.isEmpty else { return }
        
        let previousCount = allProcesses.count
        allProcesses.removeAll { pids.contains($0.pid) }
        usageSmoother.removeHistory(forPIDs: pids)
        
        guard allProcesses.count != previousCount else { return }
        applySortingAndGrouping()
    }
    
    private func applySortingAndGrouping() {
        snapshotVersion &+= 1
        let version = snapshotVersion
        let sourceProcesses = allProcesses
        let sourceSortBy = sortBy
        let sourceFilterText = filterText
        let sourceShowHighUsageFirst = showHighUsageFirst
        
        snapshotTask?.cancel()
        snapshotTask = Task.detached(priority: .userInitiated) { [sourceProcesses, sourceSortBy, sourceFilterText, sourceShowHighUsageFirst] in
            let visibleProcesses = ProcessSnapshotBuilder.sortProcesses(
                sourceProcesses,
                sortBy: sourceSortBy,
                filterText: sourceFilterText,
                showHighUsageFirst: sourceShowHighUsageFirst
            )
            let groupedProcesses = ProcessSnapshotBuilder.groupProcesses(
                visibleProcesses,
                sortBy: sourceSortBy,
                showHighUsageFirst: sourceShowHighUsageFirst
            )
            let snapshot = DisplaySnapshot(processes: visibleProcesses, groups: groupedProcesses)
            
            guard !Task.isCancelled else {
                return
            }
            
            await MainActor.run {
                guard version == self.snapshotVersion else {
                    return
                }
                
                self.processes = snapshot.processes
                self.groups = snapshot.groups
            }
        }
    }
}

struct UsageSmoother: Sendable {
    private struct ProcessHistoryKey: Hashable, Sendable {
        let pid: Int32
        let name: String
    }
    
    private struct UsageSamples: Sendable {
        var cpuSamples: [Double] = []
        var memorySamples: [Double] = []
        
        mutating func append(cpu: Double, memory: Double, maxCount: Int) {
            if cpu.isFinite {
                cpuSamples.append(cpu)
                if cpuSamples.count > maxCount {
                    cpuSamples.removeFirst(cpuSamples.count - maxCount)
                }
            }
            
            if memory.isFinite {
                memorySamples.append(memory)
                if memorySamples.count > maxCount {
                    memorySamples.removeFirst(memorySamples.count - maxCount)
                }
            }
        }
        
        var averagedCPU: Double {
            guard !cpuSamples.isEmpty else { return 0 }
            return cpuSamples.reduce(0, +) / Double(cpuSamples.count)
        }
        
        var averagedMemory: Double {
            guard !memorySamples.isEmpty else { return 0 }
            return memorySamples.reduce(0, +) / Double(memorySamples.count)
        }
    }
    
    let windowSize: Int
    private var samplesByProcess: [ProcessHistoryKey: UsageSamples] = [:]
    
    init(windowSize: Int) {
        self.windowSize = max(1, windowSize)
    }
    
    mutating func smooth(processes: [AppProcessInfo]) -> [AppProcessInfo] {
        var activeKeys: Set<ProcessHistoryKey> = []
        var smoothedProcesses: [AppProcessInfo] = []
        smoothedProcesses.reserveCapacity(processes.count)
        
        for var process in processes {
            let key = ProcessHistoryKey(pid: process.pid, name: process.name)
            activeKeys.insert(key)
            
            var samples = samplesByProcess[key] ?? UsageSamples()
            samples.append(cpu: process.cpuUsage, memory: process.memoryUsage, maxCount: windowSize)
            samplesByProcess[key] = samples
            
            process.cpuUsage = samples.averagedCPU
            process.memoryUsage = samples.averagedMemory
            smoothedProcesses.append(process)
        }
        
        samplesByProcess = samplesByProcess.filter { activeKeys.contains($0.key) }
        return smoothedProcesses
    }
    
    mutating func removeHistory(forPIDs pids: [Int32]) {
        removeHistory(forPIDs: Set(pids))
    }
    
    mutating func removeHistory(forPIDs pids: Set<Int32>) {
        guard !pids.isEmpty else { return }
        samplesByProcess = samplesByProcess.filter { !pids.contains($0.key.pid) }
    }
}

enum ProcessSnapshotBuilder {
    private static let psLineRegex = try? NSRegularExpression(
        pattern: #"^\s*(\S+)\s+(\d+)\s+([0-9.]+)\s+([0-9.]+)\s+(.*)$"#
    )
    
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
                    let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                    if nameOrder != .orderedSame {
                        return nameOrder == .orderedAscending
                    }
                    return lhs.pid < rhs.pid
                }
            )
        case .memory:
            orderCollection(
                &sorted,
                value: { $0.memoryUsage },
                descending: descending,
                tieBreaker: { lhs, rhs in
                    let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                    if nameOrder != .orderedSame {
                        return nameOrder == .orderedAscending
                    }
                    return lhs.pid < rhs.pid
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
                    lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) == .orderedAscending
                }
            )
        case .memory:
            orderCollection(
                &groups,
                value: { $0.totalMemory },
                descending: descending,
                tieBreaker: { lhs, rhs in
                    lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) == .orderedAscending
                }
            )
        }
        
        return groups
    }
    
    private static func orderCollection<T>(
        _ values: inout [T],
        value: (T) -> Double,
        descending: Bool,
        tieBreaker: (T, T) -> Bool
    ) {
        values.sort { lhs, rhs in
            let lhsValue = normalizedSortValue(value(lhs), descending: descending)
            let rhsValue = normalizedSortValue(value(rhs), descending: descending)
            
            if lhsValue == rhsValue {
                return tieBreaker(lhs, rhs)
            }
            
            return descending ? lhsValue > rhsValue : lhsValue < rhsValue
        }
    }
    
    private static func normalizedSortValue(_ value: Double, descending: Bool) -> Double {
        guard value.isFinite else {
            return descending ? -.greatestFiniteMagnitude : .greatestFiniteMagnitude
        }
        return value
    }
    
    private static func runPS() throws -> String {
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "user=,pid=,%cpu=,%mem=,command="]
        
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
        
        for line in lines {
            guard let parsed = parsePSLine(line) else { continue }
            
            let user = parsed.user
            let pid = parsed.pid
            let cpu = parsed.cpu
            let mem = parsed.mem
            let commandPath = parsed.command
            let executablePath = resolveExecutablePath(pid: pid, commandPath: commandPath)
            let processName = executablePath.map(extractProcessName(fromExecutablePath:)) ?? extractProcessName(fromCommandPath: commandPath)
            let memoryMB = mem * getPhysicalMemoryGB() * 10.24
            let isSystemProcess = ProcessDescriptions.isSystemProcess(processName) || isSystemPath(executablePath)
            
            let process = AppProcessInfo(
                pid: pid,
                name: processName,
                user: user,
                cpuUsage: cpu,
                memoryUsage: memoryMB,
                description: ProcessDescriptions.getDescription(
                    for: processName,
                    executablePath: executablePath
                ),
                isSystemProcess: isSystemProcess,
                parentApp: extractParentApp(from: executablePath ?? commandPath),
                executablePath: executablePath
            )
            
            newProcesses.append(process)
        }
        
        return newProcesses
    }
    
    private static func parsePSLine(_ line: String) -> (user: String, pid: Int32, cpu: Double, mem: Double, command: String)? {
        guard let regex = psLineRegex else { return nil }
        let range = NSRange(location: 0, length: line.utf16.count)
        guard let match = regex.firstMatch(in: line, range: range), match.numberOfRanges == 6 else {
            return nil
        }
        
        func capture(_ index: Int) -> String {
            guard let captureRange = Range(match.range(at: index), in: line) else { return "" }
            return String(line[captureRange])
        }
        
        let user = capture(1)
        guard let pid = Int32(capture(2)) else { return nil }
        guard let cpu = Double(capture(3)) else { return nil }
        guard let mem = Double(capture(4)) else { return nil }
        let command = capture(5)
        
        guard !user.isEmpty, !command.isEmpty else { return nil }
        return (user: user, pid: pid, cpu: cpu, mem: mem, command: command)
    }
    
    private static func extractProcessName(fromExecutablePath executablePath: String) -> String {
        let normalizedPath = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = URL(fileURLWithPath: normalizedPath).lastPathComponent
        
        if name.hasSuffix(".app") {
            return String(name.dropLast(4))
        }
        
        return name
    }
    
    private static func extractProcessName(fromCommandPath commandPath: String) -> String {
        let path = commandPath.components(separatedBy: " ").first ?? commandPath
        let name = path.components(separatedBy: "/").last ?? path
        
        if name.hasSuffix(".app") {
            return String(name.dropLast(4))
        }
        
        return name
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
    
    private static func extractExecutablePath(from commandPath: String) -> String? {
        let trimmed = commandPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        if let argumentStart = trimmed.range(of: " --") {
            let candidate = String(trimmed[..<argumentStart.lowerBound])
            if candidate.hasPrefix("/") {
                return candidate
            }
        }
        
        if !trimmed.contains(" ") {
            return trimmed
        }
        
        if trimmed.hasPrefix("/") && (
            trimmed.localizedCaseInsensitiveContains(".app/") ||
            trimmed.localizedCaseInsensitiveContains(".xpc/") ||
            trimmed.localizedCaseInsensitiveContains(".appex/")
        ) {
            return trimmed
        }
        
        let firstToken = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first
        guard let firstToken else { return nil }
        let executable = String(firstToken)
        return executable.isEmpty ? nil : executable
    }
    
    private static func resolveExecutablePath(pid: Int32, commandPath: String) -> String? {
        if let pidPath = executablePathFromPID(pid: pid) {
            return pidPath
        }
        
        return extractExecutablePath(from: commandPath)
    }
    
    private static func executablePathFromPID(pid: Int32) -> String? {
        let bufferSize = Int(MAXPATHLEN) * 4
        var buffer = [CChar](repeating: 0, count: bufferSize)
        let result = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard result > 0 else { return nil }
        return String(cString: buffer)
    }
    
    private static func isSystemPath(_ executablePath: String?) -> Bool {
        guard let executablePath else { return false }
        
        return executablePath.hasPrefix("/System/") ||
            executablePath.hasPrefix("/usr/libexec/") ||
            executablePath.hasPrefix("/usr/sbin/") ||
            executablePath.hasPrefix("/sbin/")
    }
    
    private static func getPhysicalMemoryGB() -> Double {
        Double(Foundation.ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
    }
}
