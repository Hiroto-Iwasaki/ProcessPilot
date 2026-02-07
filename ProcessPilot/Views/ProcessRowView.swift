import SwiftUI

struct ProcessRowView: View {
    let process: AppProcessInfo
    let isSelected: Bool
    var isNested: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            // プロセスアイコン
            ZStack {
                Circle()
                    .fill(process.isSystemProcess ? Color.orange.opacity(0.2) : Color.blue.opacity(0.2))
                    .frame(width: 28, height: 28)
                
                Image(systemName: processIcon)
                    .font(.caption)
                    .foregroundColor(process.isSystemProcess ? .orange : .blue)
            }
            
            // プロセス情報
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(process.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    if process.isSystemProcess {
                        Text("システム")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
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
        if process.isSystemProcess {
            return "gearshape.fill"
        }
        return "app.fill"
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
