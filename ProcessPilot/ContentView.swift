import SwiftUI

struct ContentView: View {
    @StateObject private var monitor = ProcessMonitor()
    @State private var selectedPID: Int32?
    
    private var selectedProcess: AppProcessInfo? {
        guard let selectedPID else { return nil }
        return monitor.processes.first { $0.pid == selectedPID }
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
                selectedPID: $selectedPID
            )
            .frame(minWidth: 400)
        } detail: {
            // 詳細パネル
            if let process = selectedProcess {
                ProcessDetailView(
                    process: process,
                    onTerminate: { handleTerminate(process: process, force: false) },
                    onForceTerminate: { handleTerminate(process: process, force: true) }
                )
            } else {
                Text("プロセスを選択してください")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .onChange(of: monitor.processes) { _ in
            guard let selectedPID else { return }
            if !monitor.processes.contains(where: { $0.pid == selectedPID }) {
                self.selectedPID = nil
            }
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
        
        // 成功したら選択を解除
        if case .success = result {
            selectedPID = nil
        }
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
        case .name: return "textformat"
        }
    }
}

#Preview {
    ContentView()
}
