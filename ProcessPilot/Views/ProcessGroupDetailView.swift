import SwiftUI

struct ProcessGroupDetailView: View {
    let group: ProcessGroup
    let onTerminateGroup: () -> Void
    let onForceTerminateGroup: () -> Void
    @State private var isProcessListExpanded = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                
                Divider()
                
                resourceSection
                
                Divider()
                
                detailSection
                
                Divider()
                
                actionSection
                
                Spacer()
            }
            .padding(24)
        }
        .frame(minWidth: 280)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var headerSection: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(group.isSystemGroup ? Color.orange.opacity(0.2) : Color.blue.opacity(0.2))
                    .frame(width: 56, height: 56)
                
                Image(systemName: group.isSystemGroup ? "gearshape.fill" : "square.stack.3d.up.fill")
                    .font(.title)
                    .foregroundColor(group.isSystemGroup ? .orange : .blue)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(group.appName)
                        .font(.title2)
                        .fontWeight(.bold)
                        .lineLimit(1)
                    
                    if group.isSystemGroup {
                        Text("システム")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }
                }
                
                Text("\(group.processCount) プロセス")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var resourceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("グループ使用量")
                .font(.headline)
            
            HStack(spacing: 24) {
                resourceRing(
                    title: "CPU",
                    icon: "cpu",
                    value: String(format: "%.1f", group.totalCPU),
                    unit: "%",
                    progress: min(group.totalCPU / 100, 1.0),
                    color: ProcessDisplayMetrics.cpuColor(for: group.totalCPU)
                )
                
                resourceRing(
                    title: "メモリ",
                    icon: "memorychip",
                    value: ProcessDisplayMetrics.memoryValue(for: group.totalMemory),
                    unit: ProcessDisplayMetrics.memoryUnit(for: group.totalMemory),
                    progress: min(group.totalMemory / 8192, 1.0),
                    color: ProcessDisplayMetrics.memoryColor(for: group.totalMemory)
                )
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    private func resourceRing(
        title: String,
        icon: String,
        value: String,
        unit: String,
        progress: Double,
        color: Color
    ) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                    .frame(width: 80, height: 80)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 0) {
                    Text(value)
                        .font(.title3)
                        .fontWeight(.bold)
                    Text(unit)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("グループ情報")
                .font(.headline)
            
            DetailRow(label: "グループ名", value: group.appName)
            DetailRow(label: "プロセス数", value: "\(group.processCount)")
            DetailRow(
                label: "種類",
                value: group.isSystemGroup ? "システムグループ" : "アプリケーショングループ"
            )
            
            if !group.processes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isProcessListExpanded.toggle()
                        }
                    }) {
                        HStack(spacing: 8) {
                            Text("含まれるプロセス")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(group.processCount) 件")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Image(systemName: isProcessListExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    if isProcessListExpanded {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(group.processes) { process in
                                Text("• \(process.name) (PID: \(process.pid))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
    }
    
    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("操作")
                .font(.headline)
            
            HStack(spacing: 12) {
                Button(action: onTerminateGroup) {
                    Label("グループ終了", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                
                Button(action: onForceTerminateGroup) {
                    Label("グループ強制終了", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
    }
}

#Preview {
    ProcessGroupDetailView(
        group: ProcessGroup(
            appName: "Sample Group",
            processes: [
                AppProcessInfo(
                    pid: 100,
                    name: "Sample Process A",
                    user: "user",
                    cpuUsage: 12.3,
                    memoryUsage: 450,
                    description: "sample",
                    isSystemProcess: false,
                    parentApp: "Sample Group"
                ),
                AppProcessInfo(
                    pid: 101,
                    name: "Sample Process B",
                    user: "user",
                    cpuUsage: 8.1,
                    memoryUsage: 300,
                    description: "sample",
                    isSystemProcess: false,
                    parentApp: "Sample Group"
                )
            ]
        ),
        onTerminateGroup: {},
        onForceTerminateGroup: {}
    )
    .frame(width: 320, height: 620)
}
