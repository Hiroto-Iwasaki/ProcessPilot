import SwiftUI

struct ProcessDetailView: View {
    let process: AppProcessInfo
    let onTerminate: () -> Void
    let onForceTerminate: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // ヘッダー
                headerSection
                
                Divider()
                
                // リソース使用量
                resourceSection
                
                Divider()
                
                // プロセス詳細
                detailSection
                
                Divider()
                
                // 警告メッセージ
                if process.isSystemProcess {
                    warningSection
                    Divider()
                }
                
                // アクションボタン
                actionSection
                
                Spacer()
            }
            .padding(24)
        }
        .frame(minWidth: 280)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack(spacing: 16) {
            // アイコン
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(sourceTintColor.opacity(0.2))
                    .frame(width: 56, height: 56)
                
                Image(systemName: sourceIcon)
                    .font(.title)
                    .foregroundColor(sourceTintColor)
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
            }
        }
    }
    
    // MARK: - Resource Section
    
    private var resourceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("リソース使用量")
                .font(.headline)
            
            HStack(spacing: 24) {
                // CPU
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                            .frame(width: 80, height: 80)
                        
                        Circle()
                            .trim(from: 0, to: min(process.cpuUsage / 100, 1.0))
                            .stroke(
                                ProcessDisplayMetrics.cpuColor(for: process.cpuUsage),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .frame(width: 80, height: 80)
                            .rotationEffect(.degrees(-90))
                        
                        VStack(spacing: 0) {
                            Text(String(format: "%.1f", process.cpuUsage))
                                .font(.title3)
                                .fontWeight(.bold)
                            Text("%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Label("CPU", systemImage: "cpu")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // メモリ
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                            .frame(width: 80, height: 80)
                        
                        Circle()
                            .trim(from: 0, to: min(process.memoryUsage / 8192, 1.0))
                            .stroke(
                                ProcessDisplayMetrics.memoryColor(for: process.memoryUsage),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .frame(width: 80, height: 80)
                            .rotationEffect(.degrees(-90))
                        
                        VStack(spacing: 0) {
                            Text(ProcessDisplayMetrics.memoryValue(for: process.memoryUsage))
                                .font(.title3)
                                .fontWeight(.bold)
                            Text(ProcessDisplayMetrics.memoryUnit(for: process.memoryUsage))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Label("メモリ", systemImage: "memorychip")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    // MARK: - Detail Section
    
    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("プロセス情報")
                .font(.headline)
            
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
                VStack(alignment: .leading, spacing: 4) {
                    Text("実行ファイル")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(executablePath)
                        .font(.caption)
                        .textSelection(.enabled)
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
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Action Section
    
    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("操作")
                .font(.headline)
            
            if ProcessDescriptions.isCriticalProcess(process.name) {
                // 終了不可プロセス
                Text("このプロセスは終了できません")
                    .foregroundColor(.secondary)
            } else {
                HStack(spacing: 12) {
                    // 終了ボタン
                    Button(action: onTerminate) {
                        Label("終了", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    
                    // 強制終了ボタン
                    Button(action: onForceTerminate) {
                        Label("強制終了", systemImage: "xmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
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
        onTerminate: {},
        onForceTerminate: {}
    )
    .frame(width: 300, height: 600)
}
