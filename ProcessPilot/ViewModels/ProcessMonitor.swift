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
    
    private var timer: Timer?
    
    enum SortOption: String, CaseIterable {
        case cpu = "CPU"
        case memory = "メモリ"
        case name = "名前"
    }
    
    init() {
        startMonitoring()
    }
    
    func startMonitoring() {
        // 初回読み込み
        Task {
            await refreshProcesses()
        }
        
        // 2秒ごとに更新
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshProcesses()
            }
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    func refreshProcesses() async {
        isLoading = true
        
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.launchPath = "/bin/ps"
        task.arguments = ["aux"]
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                parseProcesses(output)
            }
        } catch {
            print("Error running ps: \(error)")
        }
        
        isLoading = false
    }
    
    private func parseProcesses(_ output: String) {
        var newProcesses: [AppProcessInfo] = []
        let lines = output.components(separatedBy: "\n")
        
        // ヘッダー行をスキップ
        for line in lines.dropFirst() {
            guard !line.isEmpty else { continue }
            
            let components = line.split(separator: " ", omittingEmptySubsequences: true)
            guard components.count >= 11 else { continue }
            
            let user = String(components[0])
            guard let pid = Int32(components[1]) else { continue }
            guard let cpu = Double(components[2]) else { continue }
            guard let mem = Double(components[3]) else { continue }
            
            // プロセス名は最後の部分（パスの場合があるので抽出）
            let commandPath = components[10...].joined(separator: " ")
            let processName = extractProcessName(from: commandPath)
            
            // メモリ使用量をKBからMBに変換（RSSは4番目の列）
            let memoryMB = mem * getPhysicalMemoryGB() * 10.24 // 概算
            
            let isSystem = ProcessDescriptions.isSystemProcess(processName)
            let description = ProcessDescriptions.getDescription(for: processName)
            let parentApp = extractParentApp(from: commandPath)
            
            let process = AppProcessInfo(
                pid: pid,
                name: processName,
                user: user,
                cpuUsage: cpu,
                memoryUsage: memoryMB,
                description: description,
                isSystemProcess: isSystem,
                parentApp: parentApp
            )
            
            newProcesses.append(process)
        }
        
        // ソート
        processes = sortProcesses(newProcesses)
        
        // グループ化
        groups = groupProcesses(processes)
    }
    
    private func extractProcessName(from commandPath: String) -> String {
        // パスからプロセス名を抽出
        let path = commandPath.components(separatedBy: " ").first ?? commandPath
        let name = path.components(separatedBy: "/").last ?? path
        
        // .app の場合は拡張子を除去
        if name.hasSuffix(".app") {
            return String(name.dropLast(4))
        }
        
        return String(name.prefix(20)) // 長すぎる名前は切り詰め
    }
    
    private func extractParentApp(from commandPath: String) -> String? {
        // .app が含まれていればアプリ名を抽出
        if let range = commandPath.range(of: ".app") {
            let beforeApp = commandPath[..<range.lowerBound]
            let components = beforeApp.components(separatedBy: "/")
            if let appName = components.last {
                return appName
            }
        }
        return nil
    }
    
    private func getPhysicalMemoryGB() -> Double {
        return Double(Foundation.ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
    }
    
    private func sortProcesses(_ processes: [AppProcessInfo]) -> [AppProcessInfo] {
        var sorted = processes
        
        switch sortBy {
        case .cpu:
            sorted.sort { $0.cpuUsage > $1.cpuUsage }
        case .memory:
            sorted.sort { $0.memoryUsage > $1.memoryUsage }
        case .name:
            sorted.sort { $0.name.lowercased() < $1.name.lowercased() }
        }
        
        // フィルタリング
        if !filterText.isEmpty {
            sorted = sorted.filter {
                $0.name.localizedCaseInsensitiveContains(filterText) ||
                $0.description.localizedCaseInsensitiveContains(filterText)
            }
        }
        
        return sorted
    }
    
    private func groupProcesses(_ processes: [AppProcessInfo]) -> [ProcessGroup] {
        var groupDict: [String: [AppProcessInfo]] = [:]
        
        for process in processes {
            let groupName = process.parentApp ?? (process.isSystemProcess ? "システム" : process.name)
            if groupDict[groupName] == nil {
                groupDict[groupName] = []
            }
            groupDict[groupName]?.append(process)
        }
        
        var groups = groupDict.map { ProcessGroup(appName: $0.key, processes: $0.value) }
        
        // 合計リソース使用量でソート
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
    
    func changeSortOption(_ option: SortOption) {
        sortBy = option
        processes = sortProcesses(processes)
        groups = groupProcesses(processes)
    }
}
