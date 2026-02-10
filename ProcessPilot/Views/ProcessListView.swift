import SwiftUI

struct ProcessListView: View {
    let processes: [AppProcessInfo]
    let groups: [ProcessGroup]
    let showGrouped: Bool
    @Binding var selection: ProcessSelection?
    
    var body: some View {
        GeometryReader { proxy in
            let widthTier = MetricLayoutPolicy.tier(
                forContentWidth: proxy.size.width
            )

            ScrollView {
                LazyVStack(spacing: 6) {
                    if showGrouped {
                        // グループ化表示
                        ForEach(groups) { group in
                            ProcessGroupView(
                                group: group,
                                selection: $selection,
                                widthTier: widthTier
                            )
                        }
                    } else {
                        // フラット表示
                        ForEach(processes) { process in
                            ProcessRowView(
                                process: process,
                                isSelected: selection == .process(process.pid),
                                widthTier: widthTier
                            )
                            .onTapGesture {
                                selection = .process(process.pid)
                            }
                            
                            Divider()
                                .padding(.leading, 16)
                                .opacity(0.35)
                        }
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 6)
            }
        }
        .background(Color.clear)
        .liquidGlassPanel(
            cornerRadius: 18,
            tint: Color.cyan.opacity(0.04)
        )
    }
}

// MARK: - Group View

struct ProcessGroupView: View {
    let group: ProcessGroup
    @Binding var selection: ProcessSelection?
    let widthTier: MetricWidthTier
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // グループヘッダー
            HStack(spacing: 12) {
                Button(action: {
                    withAnimation(.easeOut(duration: 0.16)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    selection = .group(group.id)
                }) {
                    HStack(spacing: 12) {
                        // アイコン
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(group.isSystemGroup ? Color.orange.opacity(0.2) : Color.blue.opacity(0.2))
                                .frame(width: 32, height: 32)

                            AsyncProcessIconView(
                                executablePath: group.representativeExecutablePath,
                                imageSize: CGSize(width: 20, height: 20),
                                cornerRadius: 4
                            ) {
                                Image(systemName: group.isSystemGroup ? "gearshape.fill" : "app.fill")
                                    .foregroundColor(group.isSystemGroup ? .orange : .blue)
                            }
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
                                valueVariants: ProcessDisplayMetrics.cpuTextVariants(usage: group.totalCPU),
                                widthTier: widthTier,
                                color: ProcessDisplayMetrics.cpuColor(for: group.totalCPU)
                            )
                            
                            ResourceBadge(
                                icon: "memorychip",
                                valueVariants: ProcessDisplayMetrics.memoryTextVariants(for: group.totalMemory),
                                widthTier: widthTier,
                                color: ProcessDisplayMetrics.memoryColor(for: group.totalMemory)
                            )
                        }
                        .frame(
                            width: MetricLayoutPolicy.groupMetricsClusterWidth(for: widthTier),
                            alignment: .trailing
                        )
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        selection == .group(group.id)
                            ? Color.accentColor.opacity(0.18)
                            : Color.white.opacity(0.06)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                Color.white.opacity(selection == .group(group.id) ? 0.24 : 0.08),
                                lineWidth: 1
                            )
                    )
            )
            .padding(.horizontal, 6)
            
            // 展開時のプロセス一覧
            if isExpanded {
                LazyVStack(spacing: 0) {
                    ForEach(group.processes) { process in
                        ProcessRowView(
                            process: process,
                            isSelected: selection == .process(process.pid),
                            isNested: true,
                            isCompact: true,
                            widthTier: widthTier
                        )
                        .padding(.leading, 30)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onTapGesture {
                            selection = .process(process.pid)
                        }
                        
                        Divider()
                            .padding(.leading, 64)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 12)
                .transition(.opacity)
            }
            
            Divider()
                .opacity(0.35)
                .padding(.horizontal, 6)
        }
    }
}

// MARK: - Resource Badge

struct ResourceBadge: View {
    let icon: String
    let valueVariants: [String]
    let widthTier: MetricWidthTier
    let color: Color
    
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption2)

            ViewThatFits(in: .horizontal) {
                if let first = displayVariants.first {
                    valueText(first)
                }
                if displayVariants.count > 1 {
                    valueText(displayVariants[1])
                }
                if displayVariants.count > 2 {
                    valueText(displayVariants[2])
                }
            }
            .frame(
                width: MetricLayoutPolicy.resourceBadgeValueWidth(for: widthTier),
                alignment: .trailing
            )
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(color.opacity(0.09))
                .overlay(
                    Capsule()
                        .strokeBorder(color.opacity(0.35), lineWidth: 0.8)
                )
        )
    }

    private var displayVariants: [String] {
        valueVariants.isEmpty ? ["--"] : valueVariants
    }

    private func valueText(_ value: String) -> some View {
        Text(value)
            .font(.caption)
            .monospacedDigit()
            .lineLimit(1)
    }
}

#Preview {
    ProcessListView(
        processes: [],
        groups: [],
        showGrouped: true,
        selection: .constant(nil)
    )
}
