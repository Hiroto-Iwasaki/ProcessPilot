import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var monitor = ProcessMonitor()
    @State private var selection: ProcessSelection?
    @State private var didLoadInitialProcesses = false
    
    private var selectedProcess: AppProcessInfo? {
        guard case .process(let selectedPID) = selection else { return nil }
        return monitor.processes.first(where: { $0.pid == selectedPID })
    }
    
    private var selectedGroup: ProcessGroup? {
        guard case .group(let selectedGroupID) = selection else { return nil }
        return monitor.groups.first(where: { $0.id == selectedGroupID })
    }
    
    var body: some View {
        NavigationSplitView {
            // サイドバー
            SidebarView(monitor: monitor)
                .frame(minWidth: 200)
        } content: {
            // メインコンテンツ
            ProcessListView(
                monitor: monitor,
                selection: $selection
            )
            .frame(minWidth: 400)
        } detail: {
            // 詳細パネル
            if let group = selectedGroup {
                ProcessGroupDetailView(
                    group: group,
                    onTerminateGroup: { handleTerminate(group: group, force: false) },
                    onForceTerminateGroup: { handleTerminate(group: group, force: true) }
                )
            } else if let process = selectedProcess {
                ProcessDetailView(
                    process: process,
                    onTerminate: { handleTerminate(process: process, force: false) },
                    onForceTerminate: { handleTerminate(process: process, force: true) }
                )
            } else {
                Text("グループまたはプロセスを選択してください")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .task {
            guard !didLoadInitialProcesses else { return }
            didLoadInitialProcesses = true
            await monitor.refreshProcesses()
        }
        .onChange(of: monitor.processes) { _ in
            validateSelection()
        }
        .onChange(of: monitor.groups) { _ in
            validateSelection()
        }
    }
    
    private func handleTerminate(process: AppProcessInfo, force: Bool) {
        // 終了不可プロセスのチェック
        if ProcessDescriptions.isCriticalProcess(process.name) {
            ProcessManager.showCriticalProcessAlert(processName: process.name)
            return
        }
        
        // システムプロセスの警告
        if process.isSystemProcess {
            ProcessManager.showSystemProcessWarning(processName: process.name) { confirmed in
                if confirmed {
                    performTermination(process: process, force: force)
                }
            }
        } else {
            performTermination(process: process, force: force)
        }
    }
    
    private func performTermination(process: AppProcessInfo, force: Bool) {
        let result: ProcessManager.TerminationResult
        
        if force {
            result = ProcessManager.forceTerminateProcess(pid: process.pid)
        } else {
            result = ProcessManager.terminateProcess(pid: process.pid)
        }
        
        ProcessManager.showResultAlert(result: result, processName: process.name)
        
        switch result {
        case .success, .processNotFound:
            monitor.removeProcessesFromCache(pids: [process.pid])
            selection = nil
        case .permissionDenied, .failed:
            break
        }
    }
    
    private func handleTerminate(group: ProcessGroup, force: Bool) {
        let nonCriticalSystemCount = group.processes.filter {
            $0.isSystemProcess && !ProcessDescriptions.isCriticalProcess($0.name)
        }.count
        
        if nonCriticalSystemCount > 0 {
            ProcessManager.showSystemGroupWarning(
                groupName: group.appName,
                systemProcessCount: nonCriticalSystemCount
            ) { confirmed in
                if confirmed {
                    executeGroupTermination(group: group, force: force)
                }
            }
            return
        }
        
        executeGroupTermination(group: group, force: force)
    }
    
    private func executeGroupTermination(group: ProcessGroup, force: Bool) {
        let summary = performGroupTermination(group: group, force: force)
        monitor.removeProcessesFromCache(pids: summary.endedProcessPIDs)
        showGroupTerminationSummary(summary, groupName: group.appName, force: force)
        
        if !summary.endedProcessPIDs.isEmpty {
            selection = nil
        }
    }
    
    private func performGroupTermination(group: ProcessGroup, force: Bool) -> GroupTerminationSummary {
        var successCount = 0
        var permissionDeniedCount = 0
        var processNotFoundCount = 0
        var failedCount = 0
        var skippedCriticalCount = 0
        var endedProcessPIDs: Set<Int32> = []
        
        for process in group.processes {
            if ProcessDescriptions.isCriticalProcess(process.name) {
                skippedCriticalCount += 1
                continue
            }
            
            let result = force
                ? ProcessManager.forceTerminateProcess(pid: process.pid)
                : ProcessManager.terminateProcess(pid: process.pid)
            
            switch result {
            case .success:
                successCount += 1
                endedProcessPIDs.insert(process.pid)
            case .permissionDenied:
                permissionDeniedCount += 1
            case .processNotFound:
                processNotFoundCount += 1
                endedProcessPIDs.insert(process.pid)
            case .failed:
                failedCount += 1
            }
        }
        
        return GroupTerminationSummary(
            totalCount: group.processCount,
            successCount: successCount,
            permissionDeniedCount: permissionDeniedCount,
            processNotFoundCount: processNotFoundCount,
            failedCount: failedCount,
            skippedCriticalCount: skippedCriticalCount,
            endedProcessPIDs: endedProcessPIDs
        )
    }
    
    private func showGroupTerminationSummary(
        _ summary: GroupTerminationSummary,
        groupName: String,
        force: Bool
    ) {
        let alert = NSAlert()
        alert.addButton(withTitle: "OK")
        
        if summary.successCount > 0 {
            alert.messageText = force ? "グループを強制終了しました" : "グループを終了しました"
            alert.alertStyle = .informational
        } else {
            alert.messageText = "グループ終了の結果"
            alert.alertStyle = .warning
        }
        
        var lines = [
            "対象グループ: \(groupName)",
            "対象プロセス: \(summary.totalCount) 件",
            "成功: \(summary.successCount) 件"
        ]
        
        if summary.permissionDeniedCount > 0 {
            lines.append("権限不足: \(summary.permissionDeniedCount) 件")
        }
        if summary.processNotFoundCount > 0 {
            lines.append("既に終了: \(summary.processNotFoundCount) 件")
        }
        if summary.failedCount > 0 {
            lines.append("失敗: \(summary.failedCount) 件")
        }
        if summary.skippedCriticalCount > 0 {
            lines.append("重要プロセスのため未実行: \(summary.skippedCriticalCount) 件")
        }
        
        alert.informativeText = lines.joined(separator: "\n")
        alert.runModal()
    }
    
    private func validateSelection() {
        guard let selection else { return }
        
        switch selection {
        case .process(let selectedPID):
            if !monitor.processes.contains(where: { $0.pid == selectedPID }) {
                self.selection = nil
            }
        case .group(let selectedGroupID):
            if !monitor.groups.contains(where: { $0.id == selectedGroupID }) {
                self.selection = nil
            }
        }
    }
    
    private struct GroupTerminationSummary {
        let totalCount: Int
        let successCount: Int
        let permissionDeniedCount: Int
        let processNotFoundCount: Int
        let failedCount: Int
        let skippedCriticalCount: Int
        let endedProcessPIDs: Set<Int32>
    }
}

// MARK: - Sidebar View

struct SidebarView: View {
    @ObservedObject var monitor: ProcessMonitor
    @StateObject private var updateService = UpdateService()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // ヘッダー
            VStack(alignment: .leading, spacing: 4) {
                Text("ProcessPilot")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("プロセスマネージャー")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            if let update = updateService.availableUpdate {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.app.fill")
                        .foregroundColor(.accentColor)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("新しいバージョン")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(update.version)
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    
                    Spacer()
                    
                    Button("Update") {
                        updateService.openUpdate()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(10)
                .background(Color.accentColor.opacity(0.08))
                .cornerRadius(8)
                .padding(.horizontal)
            }
            
            Divider()
            
            // 検索フィールド
            TextField("検索...", text: $monitor.filterText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            
            // ソートオプション
            VStack(alignment: .leading, spacing: 8) {
                Text("並び替え")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ForEach(ProcessMonitor.SortOption.allCases, id: \.self) { option in
                    Button(action: {
                        monitor.changeSortOption(option)
                    }) {
                        HStack {
                            Image(systemName: sortIcon(for: option))
                                .frame(width: 20)
                            Text(option.rawValue)
                            Spacer()
                            if monitor.sortBy == option {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
            }
            .padding(.horizontal)
            
            Divider()
            
            // 表示オプション
            Toggle("グループ化表示", isOn: $monitor.showGrouped)
                .padding(.horizontal)
            
            Toggle(
                "使用量の多い順で表示",
                isOn: Binding(
                    get: { monitor.showHighUsageFirst },
                    set: { monitor.changeHighUsageOrder($0) }
                )
            )
            .padding(.horizontal)
            
            Divider()
            
            // 統計情報
            VStack(alignment: .leading, spacing: 8) {
                Text("統計")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Image(systemName: "number")
                        .frame(width: 20)
                    Text("プロセス数")
                    Spacer()
                    Text("\(monitor.processes.count)")
                        .foregroundColor(.secondary)
                }
                .font(.caption)
                
                HStack {
                    Image(systemName: "folder")
                        .frame(width: 20)
                    Text("グループ数")
                    Spacer()
                    Text("\(monitor.groups.count)")
                        .foregroundColor(.secondary)
                }
                .font(.caption)
            }
            .padding(.horizontal)
            
            Spacer()
            
            // 更新ボタン
            Button(action: {
                Task {
                    await monitor.refreshProcesses()
                }
            }) {
                HStack {
                    if monitor.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("更新")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func sortIcon(for option: ProcessMonitor.SortOption) -> String {
        switch option {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        }
    }
}

#Preview {
    ContentView()
}
