import SwiftUI

struct ProcessListView: View {
    @ObservedObject var monitor: ProcessMonitor
    @Binding var selectedPID: Int32?
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if monitor.showGrouped {
                    // グループ化表示
                    ForEach(monitor.groups) { group in
                        ProcessGroupView(
                            group: group,
                            selectedPID: $selectedPID
                        )
                    }
                } else {
                    // フラット表示
                    ForEach(monitor.processes) { process in
                        ProcessRowView(
                            process: process,
                            isSelected: selectedPID == process.pid
                        )
                        .onTapGesture {
                            selectedPID = process.pid
                        }
                        
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Group View

struct ProcessGroupView: View {
    let group: ProcessGroup
    @Binding var selectedPID: Int32?
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // グループヘッダー
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                    
                    // アイコン
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(group.isSystemGroup ? Color.orange.opacity(0.2) : Color.blue.opacity(0.2))
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: group.isSystemGroup ? "gearshape.fill" : "app.fill")
                            .foregroundColor(group.isSystemGroup ? .orange : .blue)
                    }
                    
                    // グループ名
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.appName)
                            .fontWeight(.medium)
                        
                        Text("\(group.processCount) プロセス")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // リソース使用量
                    HStack(spacing: 16) {
                        ResourceBadge(
                            icon: "cpu",
                            value: String(format: "%.1f%%", group.totalCPU),
                            color: ProcessDisplayMetrics.cpuColor(for: group.totalCPU)
                        )
                        
                        ResourceBadge(
                            icon: "memorychip",
                            value: ProcessDisplayMetrics.memoryText(for: group.totalMemory),
                            color: ProcessDisplayMetrics.memoryColor(for: group.totalMemory)
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color(NSColor.controlBackgroundColor))
            
            // 展開時のプロセス一覧
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(group.processes) { process in
                        HStack {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: 32)
                            
                            ProcessRowView(
                                process: process,
                                isSelected: selectedPID == process.pid,
                                isNested: true
                            )
                        }
                        .onTapGesture {
                            selectedPID = process.pid
                        }
                        
                        Divider()
                            .padding(.leading, 64)
                    }
                }
                .background(Color(NSColor.textBackgroundColor).opacity(0.5))
            }
            
            Divider()
        }
    }
}

// MARK: - Resource Badge

struct ResourceBadge: View {
    let icon: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(value)
                .font(.caption)
                .monospacedDigit()
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(4)
    }
}

#Preview {
    ProcessListView(
        monitor: ProcessMonitor(),
        selectedPID: .constant(nil)
    )
}
