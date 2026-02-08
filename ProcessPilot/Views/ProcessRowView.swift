import SwiftUI
import AppKit

struct ProcessRowView: View {
    let process: AppProcessInfo
    let isSelected: Bool
    var isNested: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            // プロセスアイコン
            ZStack {
                Circle()
                    .fill(sourceTintColor.opacity(0.2))
                    .frame(width: 28, height: 28)
                
                if let appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: processIcon)
                        .font(.caption)
                        .foregroundColor(sourceTintColor)
                }
            }
            
            // プロセス情報
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(process.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    if shouldShowSourceBadge {
                        Text(process.source.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(sourceBadgeColor.opacity(0.2))
                            .foregroundColor(sourceBadgeColor)
                            .cornerRadius(3)
                    }
                }
                
                Text(process.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // PID
            Text("PID: \(process.pid)")
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
            
            // リソース使用量
            HStack(spacing: 12) {
                // CPU
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.1f%%", process.cpuUsage))
                        .font(.caption)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundColor(ProcessDisplayMetrics.cpuColor(for: process.cpuUsage))
                    
                    ProgressView(value: min(process.cpuUsage / 100, 1.0))
                        .progressViewStyle(.linear)
                        .frame(width: 50)
                        .tint(ProcessDisplayMetrics.cpuColor(for: process.cpuUsage))
                }
                
                // メモリ
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ProcessDisplayMetrics.memoryText(for: process.memoryUsage))
                        .font(.caption)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundColor(ProcessDisplayMetrics.memoryColor(for: process.memoryUsage))
                    
                    ProgressView(value: min(process.memoryUsage / 8192, 1.0)) // 8GB を 100% とする
                        .progressViewStyle(.linear)
                        .frame(width: 50)
                        .tint(ProcessDisplayMetrics.memoryColor(for: process.memoryUsage))
                }
            }
        }
        .padding(.horizontal, isNested ? 8 : 16)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
    }
    
    private var processIcon: String {
        switch process.source {
        case .system:
            return "gearshape.fill"
        case .currentApp:
            return "sparkles"
        case .application:
            return "app.fill"
        case .commandLine:
            return "terminal.fill"
        case .unknown:
            return "questionmark.app"
        }
    }
    
    private var shouldShowSourceBadge: Bool {
        process.source == .system || process.source == .currentApp
    }
    
    private var sourceBadgeColor: Color {
        switch process.source {
        case .system:
            return .orange
        case .currentApp:
            return .blue
        case .application:
            return .blue
        case .commandLine:
            return .teal
        case .unknown:
            return .gray
        }
    }
    
    private var sourceTintColor: Color {
        switch process.source {
        case .system:
            return .orange
        case .currentApp:
            return .blue
        case .application:
            return .blue
        case .commandLine:
            return .teal
        case .unknown:
            return .gray
        }
    }
    
    private var appIcon: NSImage? {
        ProcessAppIconProvider.icon(forExecutablePath: process.executablePath)
    }
}

#Preview {
    VStack(spacing: 0) {
        ProcessRowView(
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
            isSelected: false
        )
        
        Divider()
        
        ProcessRowView(
            process: AppProcessInfo(
                pid: 1,
                name: "kernel_task",
                user: "root",
                cpuUsage: 5.0,
                memoryUsage: 1024,
                description: "macOSカーネル（終了不可）",
                isSystemProcess: true,
                parentApp: nil
            ),
            isSelected: true
        )
    }
    .frame(width: 600)
}
