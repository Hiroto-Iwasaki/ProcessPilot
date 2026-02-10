import SwiftUI

struct ProcessGroupDetailView: View {
    let group: ProcessGroup
    let isTerminating: Bool
    let onTerminateGroup: () -> Void
    let onForceTerminateGroup: () -> Void
    @State private var isProcessListExpanded = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SidebarSectionCard {
                    headerSection
                }

                SidebarSectionCard(title: "グループ使用量") {
                    resourceSection
                }

                SidebarSectionCard(title: "グループ情報") {
                    detailSection
                }

                SidebarSectionCard(title: "操作") {
                    actionSection
                }

                Spacer(minLength: 8)
            }
            .padding(20)
        }
        .background(Color.clear)
        .padding(10)
    }
    
    private var headerSection: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(group.isSystemGroup ? Color.orange.opacity(0.14) : Color.blue.opacity(0.14))
                    .frame(width: 58, height: 58)

                if let appIcon = ProcessAppIconProvider.icon(forExecutablePath: group.representativeExecutablePath) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                } else {
                    Image(systemName: group.isSystemGroup ? "gearshape.fill" : "square.stack.3d.up.fill")
                        .font(.title)
                        .foregroundColor(group.isSystemGroup ? .orange : .blue)
                }
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
                            .background(
                                Capsule()
                                    .fill(Color.orange.opacity(0.2))
                            )
                            .foregroundColor(.orange)
                    }
                }
                
                Text("\(group.processCount) プロセス")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
    }
    
    private var resourceSection: some View {
        HStack(spacing: 20) {
            SidebarMetricRing(
                title: "CPU",
                icon: "cpu",
                value: ProcessDisplayMetrics.cpuValueText(for: group.totalCPU),
                unit: "%",
                progress: group.totalCPU / 100,
                color: cpuRingColor(for: group.totalCPU)
            )

            SidebarMetricRing(
                title: "メモリ",
                icon: "memorychip",
                value: ProcessDisplayMetrics.memoryValue(for: group.totalMemory),
                unit: ProcessDisplayMetrics.memoryUnit(for: group.totalMemory),
                progress: group.totalMemory / 8192,
                color: memoryRingColor(for: group.totalMemory)
            )
        }
        .frame(maxWidth: .infinity)
    }
    
    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                    }
                }
            }
        }
    }
    
    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isTerminating {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("グループ終了中...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack(spacing: 12) {
                Button(action: onTerminateGroup) {
                    Label("終了", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .disabled(isTerminating)
                
                Button(action: onForceTerminateGroup) {
                    Label("強制終了", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(isTerminating)
            }
        }
    }

    private func cpuRingColor(for usage: Double) -> Color {
        switch usage {
        case ..<40:
            return .green
        case ..<80:
            return .orange
        default:
            return .red
        }
    }

    private func memoryRingColor(for usageMB: Double) -> Color {
        switch usageMB {
        case ..<1024:
            return .green
        case ..<4096:
            return .blue
        default:
            return .orange
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
        isTerminating: false,
        onTerminateGroup: {},
        onForceTerminateGroup: {}
    )
    .frame(width: 320, height: 620)
}
