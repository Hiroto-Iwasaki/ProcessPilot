import SwiftUI

struct ProcessDetailView: View {
    let process: AppProcessInfo
    let isTerminating: Bool
    let onTerminate: () -> Void
    let onForceTerminate: () -> Void
    @State private var isExecutablePathExpanded = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SidebarSectionCard {
                    headerSection
                }

                SidebarSectionCard(title: "リソース使用量") {
                    resourceSection
                }

                SidebarSectionCard(title: "プロセス情報") {
                    detailSection
                }

                if process.isSystemProcess {
                    SidebarSectionCard {
                        warningSection
                    }
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
        .onChange(of: process.pid) { _ in
            isExecutablePathExpanded = false
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack(spacing: 16) {
            // アイコン
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(sourceTintColor.opacity(0.14))
                    .frame(width: 58, height: 58)

                if let appIcon = ProcessAppIconProvider.icon(forExecutablePath: process.executablePath) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                } else {
                    Image(systemName: sourceIcon)
                        .font(.title)
                        .foregroundColor(sourceTintColor)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(process.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    if shouldShowSourceBadge {
                        Text(process.source.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(sourceTintColor.opacity(0.2))
                            .foregroundColor(sourceTintColor)
                            .cornerRadius(4)
                    }
                }
                
                Text(process.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
    }
    
    // MARK: - Resource Section
    
    private var resourceSection: some View {
        HStack(spacing: 20) {
            SidebarMetricRing(
                title: "CPU",
                icon: "cpu",
                value: ProcessDisplayMetrics.cpuValueText(for: process.cpuUsage),
                unit: "%",
                progress: process.cpuUsage / 100,
                color: cpuRingColor(for: process.cpuUsage)
            )

            SidebarMetricRing(
                title: "メモリ",
                icon: "memorychip",
                value: ProcessDisplayMetrics.memoryValue(for: process.memoryUsage),
                unit: ProcessDisplayMetrics.memoryUnit(for: process.memoryUsage),
                progress: process.memoryUsage / 8192,
                color: memoryRingColor(for: process.memoryUsage)
            )
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Detail Section
    
    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailRow(label: "PID", value: "\(process.pid)")
            DetailRow(label: "出処", value: process.source.rawValue)
            DetailRow(label: "ユーザー", value: process.user)
            
            if let parentApp = process.parentApp {
                DetailRow(label: "親アプリ", value: parentApp)
            }
            
            DetailRow(
                label: "種類",
                value: process.isSystemProcess ? "システムプロセス" : "アプリケーション"
            )
            
            if let executablePath = process.executablePath {
                VStack(alignment: .leading, spacing: 6) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExecutablePathExpanded.toggle()
                        }
                    }) {
                        HStack(spacing: 8) {
                            Text("実行ファイル")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Image(systemName: isExecutablePathExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    if isExecutablePathExpanded {
                        Text(executablePath)
                            .font(.caption)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                DetailRow(label: "実行ファイル", value: "取得不可")
            }
        }
    }
    
    // MARK: - Warning Section
    
    private var warningSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("警告", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundColor(.orange)
            
            if ProcessDescriptions.isCriticalProcess(process.name) {
                Text("このプロセスはmacOSの動作に不可欠です。終了することはできません。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("このプロセスを終了すると、システムが不安定になる可能性があります。慎重に操作してください。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Action Section
    
    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if ProcessDescriptions.isCriticalProcess(process.name) {
                // 終了不可プロセス
                Text("このプロセスは終了できません")
                    .foregroundColor(.secondary)
            } else {
                if isTerminating {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("終了中...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(spacing: 12) {
                    // 終了ボタン
                    Button(action: onTerminate) {
                        Label("終了", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .disabled(isTerminating)
                    
                    // 強制終了ボタン
                    Button(action: onForceTerminate) {
                        Label("強制終了", systemImage: "xmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(isTerminating)
                }
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
    
    private var sourceIcon: String {
        switch process.source {
        case .currentApp:
            return "sparkles"
        case .system:
            return "gearshape.fill"
        case .application:
            return "app.fill"
        case .commandLine:
            return "terminal.fill"
        case .unknown:
            return "questionmark.app"
        }
    }
    
    private var sourceTintColor: Color {
        switch process.source {
        case .currentApp:
            return .blue
        case .system:
            return .orange
        case .application:
            return .blue
        case .commandLine:
            return .teal
        case .unknown:
            return .gray
        }
    }
    
    private var shouldShowSourceBadge: Bool {
        process.source == .currentApp || process.source == .system
    }
    
}

// MARK: - Detail Row

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

#Preview {
    ProcessDetailView(
        process: AppProcessInfo(
            pid: 1234,
            name: "Safari",
            user: "user",
            cpuUsage: 25.5,
            memoryUsage: 512,
            description: "Safari ウェブブラウザ",
            isSystemProcess: false,
            parentApp: nil
        ),
        isTerminating: false,
        onTerminate: {},
        onForceTerminate: {}
    )
    .frame(width: 300, height: 600)
}
