import SwiftUI
import AppKit

struct MainContentBottomBarView: View {
    let sortBy: ProcessMonitor.SortOption
    let metrics: BottomBarMetrics
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.3)
            
            switch sortBy {
            case .cpu:
                CPUBottomPanel(metrics: metrics.cpu)
            case .memory:
                MemoryBottomPanel(metrics: metrics.memory)
            }
        }
        .background(Color.clear)
        .padding(.horizontal, 2)
        .liquidGlassPanel(
            cornerRadius: 16,
            tint: Color.white.opacity(0.05)
        )
    }
}

private struct CPUBottomPanel: View {
    let metrics: BottomBarMetrics.CPUSection
    
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                metricRow(title: "システム:", value: metrics.systemPercent, color: .red)
                metricRow(title: "ユーザ:", value: metrics.userPercent, color: .cyan)
                
                Divider()
                    .opacity(0.35)
                
                metricRow(title: "アイドル状態:", value: metrics.idlePercent, color: .primary)
            }
            .padding(16)
            .frame(width: MetricLayoutPolicy.cpuSummaryColumnWidth, alignment: .leading)
            
            Divider()
                .opacity(0.35)
            
            VStack(alignment: .leading, spacing: 10) {
                Text("CPU負荷")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                
                CPUHistoryChart(
                    userHistory: metrics.userHistory,
                    systemHistory: metrics.systemHistory
                )
                .frame(height: 92)
                
                HStack(spacing: 14) {
                    legendItem(title: "ユーザ", color: .cyan)
                    legendItem(title: "システム", color: .red)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 170)
    }
    
    private func metricRow(title: String, value: Double, color: Color) -> some View {
        HStack {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
            Spacer(minLength: 8)
            Text(
                ProcessDisplayMetrics.cpuText(
                    for: value,
                    decimalPlaces: 2
                )
            )
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundColor(color)
        }
    }
    
    private func legendItem(title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
        }
    }
}

private struct MemoryBottomPanel: View {
    let metrics: BottomBarMetrics.MemorySection
    
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("メモリプレッシャー")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                
                MemoryPressureChart(history: metrics.pressureHistory)
                    .frame(height: 92)
                
                Text("現在 \(ProcessDisplayMetrics.cpuText(for: metrics.pressurePercent))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            .padding(16)
            .frame(width: MetricLayoutPolicy.memoryPressureColumnWidth, alignment: .leading)
            
            Divider()
                .opacity(0.35)
            
            MemoryMetricColumn(
                rows: [
                    ("物理メモリ:", ProcessDisplayMetrics.memoryText(for: metrics.physicalMemoryMB, gbPrecision: 2, mbPrecision: 1)),
                    ("使用済みメモリ:", ProcessDisplayMetrics.memoryText(for: metrics.usedMemoryMB, gbPrecision: 2, mbPrecision: 1)),
                    ("現在利用中（回収可能）:", ProcessDisplayMetrics.memoryText(for: metrics.cachedFilesMB, gbPrecision: 2, mbPrecision: 1)),
                    ("メモリからの退避分:", ProcessDisplayMetrics.memoryText(for: metrics.swapUsedMB, gbPrecision: 2, mbPrecision: 1))
                ]
            )
            .frame(maxWidth: .infinity)
            .padding(16)
            
            Divider()
                .opacity(0.35)
            
            MemoryMetricColumn(
                rows: [
                    ("アプリメモリ:", ProcessDisplayMetrics.memoryText(for: metrics.appMemoryMB, gbPrecision: 2, mbPrecision: 1)),
                    ("システム固定メモリ:", ProcessDisplayMetrics.memoryText(for: metrics.wiredMemoryMB, gbPrecision: 2, mbPrecision: 1)),
                    ("メモリ圧縮量:", ProcessDisplayMetrics.memoryText(for: metrics.compressedMemoryMB, gbPrecision: 2, mbPrecision: 1))
                ]
            )
            .frame(maxWidth: .infinity)
            .padding(16)
        }
        .frame(height: 170)
    }
}

private struct MemoryMetricColumn: View {
    let rows: [(String, String)]
    private let metricFontSize: CGFloat = 12
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 10) {
                    Text(row.0)
                        .font(.system(size: metricFontSize, weight: .semibold))
                    Spacer(minLength: 8)
                    Text(row.1)
                        .font(.system(size: metricFontSize))
                        .monospacedDigit()
                }
                
                if index < rows.count - 1 {
                    Divider()
                        .opacity(0.35)
                }
            }
        }
    }
}

private struct CPUHistoryChart: View {
    let userHistory: [Double]
    let systemHistory: [Double]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.thinMaterial)
                
                let userPoints = chartPoints(
                    values: userHistory,
                    maxValue: 100,
                    size: geometry.size
                )
                let systemPoints = chartPoints(
                    values: systemHistory,
                    maxValue: 100,
                    size: geometry.size
                )
                
                drawHorizontalGuides(in: geometry.size)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)
                
                linePath(from: userPoints)
                    .stroke(Color.cyan, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                
                linePath(from: systemPoints)
                    .stroke(Color.red, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

private struct MemoryPressureChart: View {
    let history: [Double]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.thinMaterial)
                
                let points = chartPoints(values: history, maxValue: 1, size: geometry.size)
                
                areaPath(from: points, size: geometry.size)
                    .fill(
                        LinearGradient(
                            colors: [Color.green.opacity(0.45), Color.green.opacity(0.15)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                linePath(from: points)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

private func drawHorizontalGuides(in size: CGSize) -> Path {
    var path = Path()
    let steps = 4
    
    for index in 1..<steps {
        let y = (size.height / CGFloat(steps)) * CGFloat(index)
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: size.width, y: y))
    }
    
    return path
}

private func chartPoints(values: [Double], maxValue: Double, size: CGSize) -> [CGPoint] {
    let clampedValues = values.map { min(max($0, 0), maxValue) }
    guard !clampedValues.isEmpty else { return [] }
    
    let stepX = clampedValues.count > 1
        ? size.width / CGFloat(clampedValues.count - 1)
        : 0
    
    return clampedValues.enumerated().map { index, value in
        let x = CGFloat(index) * stepX
        let normalizedY = maxValue > 0 ? CGFloat(value / maxValue) : 0
        let y = size.height - (normalizedY * size.height)
        return CGPoint(x: x, y: y)
    }
}

private func linePath(from points: [CGPoint]) -> Path {
    var path = Path()
    guard let first = points.first else { return path }
    
    path.move(to: first)
    for point in points.dropFirst() {
        path.addLine(to: point)
    }
    
    if points.count == 1 {
        path.addLine(to: CGPoint(x: first.x + 1, y: first.y))
    }
    
    return path
}

private func areaPath(from points: [CGPoint], size: CGSize) -> Path {
    var path = Path()
    guard let first = points.first, let last = points.last else { return path }
    
    path.move(to: CGPoint(x: first.x, y: size.height))
    path.addLine(to: first)
    for point in points.dropFirst() {
        path.addLine(to: point)
    }
    path.addLine(to: CGPoint(x: last.x, y: size.height))
    path.closeSubpath()
    
    return path
}
