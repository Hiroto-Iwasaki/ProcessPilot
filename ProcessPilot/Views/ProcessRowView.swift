import SwiftUI

struct ProcessRowView: View {
    let process: AppProcessInfo
    let isSelected: Bool
    var isNested: Bool = false
    var isCompact: Bool = false
    var widthTier: MetricWidthTier = .wide
    
    var body: some View {
        HStack(spacing: 12) {
            // プロセスアイコン
            ZStack {
                Circle()
                    .fill(sourceTintColor.opacity(0.2))
                    .frame(width: 28, height: 28)
                
                if isCompact {
                    Image(systemName: processIcon)
                        .font(.caption)
                        .foregroundColor(sourceTintColor)
                } else {
                    AsyncProcessIconView(
                        executablePath: process.executablePath,
                        imageSize: CGSize(width: 18, height: 18),
                        cornerRadius: 4
                    ) {
                        Image(systemName: processIcon)
                            .font(.caption)
                            .foregroundColor(sourceTintColor)
                    }
                }
            }
            
            // プロセス情報
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(process.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    if !isCompact && shouldShowSourceBadge {
                        Text(process.source.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                Capsule()
                                    .fill(sourceBadgeColor.opacity(0.16))
                            )
                            .foregroundColor(sourceBadgeColor)
                    }
                }
                
                if !isCompact {
                    Text(process.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // PID
            if isCompact {
                Text("#\(process.pid)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            } else {
                Text("PID: \(process.pid)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            
            // リソース使用量
            HStack(spacing: 12) {
                if !isCompact {
                    // CPU
                    VStack(alignment: .trailing, spacing: 2) {
                        MetricValueLabel(
                            variants: ProcessDisplayMetrics.cpuTextVariants(usage: process.cpuUsage),
                            color: ProcessDisplayMetrics.cpuColor(for: process.cpuUsage),
                            width: MetricLayoutPolicy.processRowMetricValueWidth(for: widthTier)
                        )
                        
                        ProgressView(value: min(process.cpuUsage / 100, 1.0))
                            .progressViewStyle(.linear)
                            .frame(width: MetricLayoutPolicy.processRowMetricBarWidth(for: widthTier))
                            .tint(ProcessDisplayMetrics.cpuColor(for: process.cpuUsage))
                    }
                    
                    // メモリ
                    VStack(alignment: .trailing, spacing: 2) {
                        MetricValueLabel(
                            variants: ProcessDisplayMetrics.memoryTextVariants(for: process.memoryUsage),
                            color: ProcessDisplayMetrics.memoryColor(for: process.memoryUsage),
                            width: MetricLayoutPolicy.processRowMetricValueWidth(for: widthTier)
                        )
                        
                        ProgressView(value: min(process.memoryUsage / 8192, 1.0)) // 8GB を 100% とする
                            .progressViewStyle(.linear)
                            .frame(width: MetricLayoutPolicy.processRowMetricBarWidth(for: widthTier))
                            .tint(ProcessDisplayMetrics.memoryColor(for: process.memoryUsage))
                    }
                }
            }
        }
        .padding(.horizontal, isNested ? 8 : 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: isNested ? 8 : 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: isNested ? 8 : 10, style: .continuous)
                        .strokeBorder(
                            Color.white.opacity(isSelected ? 0.25 : 0.06),
                            lineWidth: 1
                        )
                )
        )
        .padding(.horizontal, isNested ? 2 : 6)
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
}

private struct MetricValueLabel: View {
    let variants: [String]
    let color: Color
    let width: CGFloat

    var body: some View {
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
        .frame(width: width, alignment: .trailing)
    }

    private var displayVariants: [String] {
        variants.isEmpty ? ["--"] : variants
    }

    private func valueText(_ value: String) -> some View {
        Text(value)
            .font(.caption)
            .monospacedDigit()
            .lineLimit(1)
            .foregroundColor(color)
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
