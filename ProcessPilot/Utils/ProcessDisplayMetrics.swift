import SwiftUI

enum ProcessDisplayMetrics {
    private static let highCPUThreshold: Double = 50
    private static let mediumCPUThreshold: Double = 20
    private static let highMemoryThresholdMB: Double = 1000
    private static let mediumMemoryThresholdMB: Double = 500
    private static let memoryDisplaySwitchMB: Double = 1000
    
    static func cpuColor(for usage: Double) -> Color {
        if usage > highCPUThreshold { return .red }
        if usage > mediumCPUThreshold { return .orange }
        return .green
    }
    
    static func memoryColor(for usageMB: Double) -> Color {
        if usageMB > highMemoryThresholdMB { return .red }
        if usageMB > mediumMemoryThresholdMB { return .orange }
        return .green
    }
    
    static func memoryText(
        for usageMB: Double,
        gbPrecision: Int = 1,
        mbPrecision: Int = 0
    ) -> String {
        "\(memoryValue(for: usageMB, gbPrecision: gbPrecision, mbPrecision: mbPrecision)) \(memoryUnit(for: usageMB))"
    }
    
    static func memoryValue(
        for usageMB: Double,
        gbPrecision: Int = 1,
        mbPrecision: Int = 0
    ) -> String {
        let resolvedGBPrecision = max(0, gbPrecision)
        let resolvedMBPrecision = max(0, mbPrecision)
        
        if usageMB >= memoryDisplaySwitchMB {
            return String(format: "%.\(resolvedGBPrecision)f", usageMB / 1024)
        }
        
        return String(format: "%.\(resolvedMBPrecision)f", usageMB)
    }
    
    static func memoryUnit(for usageMB: Double) -> String {
        usageMB >= memoryDisplaySwitchMB ? "GB" : "MB"
    }
}
