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

    static func cpuText(
        for usage: Double,
        decimalPlaces: Int = 1,
        includePercentSymbol: Bool = true
    ) -> String {
        let precision = max(0, decimalPlaces)
        let value = String(format: "%.\(precision)f", normalized(usage))
        return includePercentSymbol ? "\(value)%" : value
    }

    static func cpuPrimaryText(usage: Double) -> String {
        cpuText(for: usage)
    }

    static func cpuValueText(for usage: Double, decimalPlaces: Int = 1) -> String {
        cpuText(for: usage, decimalPlaces: decimalPlaces, includePercentSymbol: false)
    }

    static func cpuTextVariants(usage: Double) -> [String] {
        let safeUsage = normalized(usage)
        return deduplicated(
            [
                cpuText(for: safeUsage, decimalPlaces: 1, includePercentSymbol: true),
                cpuText(for: safeUsage, decimalPlaces: 0, includePercentSymbol: true),
                cpuText(for: safeUsage, decimalPlaces: 0, includePercentSymbol: false)
            ]
        )
    }

    static func memoryText(
        for usageMB: Double,
        gbPrecision: Int = 1,
        mbPrecision: Int = 0
    ) -> String {
        memoryTextVariants(
            for: usageMB,
            gbPrecision: gbPrecision,
            mbPrecision: mbPrecision
        ).first ?? "0 MB"
    }

    static func memoryTextVariants(
        for usageMB: Double,
        gbPrecision: Int = 1,
        mbPrecision: Int = 0
    ) -> [String] {
        let unitInfo = memoryValueUnit(
            for: usageMB,
            gbPrecision: gbPrecision,
            mbPrecision: mbPrecision
        )
        let shortUnit = unitInfo.unit == "GB" ? "G" : "M"
        let shortValue = format(
            unitInfo.numericValue,
            precision: 0
        )

        return deduplicated(
            [
                "\(unitInfo.value) \(unitInfo.unit)",
                "\(unitInfo.value)\(unitInfo.unit)",
                "\(shortValue)\(shortUnit)"
            ]
        )
    }

    static func memoryValue(
        for usageMB: Double,
        gbPrecision: Int = 1,
        mbPrecision: Int = 0
    ) -> String {
        memoryValueUnit(
            for: usageMB,
            gbPrecision: gbPrecision,
            mbPrecision: mbPrecision
        ).value
    }

    static func memoryUnit(for usageMB: Double) -> String {
        memoryValueUnit(for: usageMB).unit
    }

    static func memoryValueUnit(
        for usageMB: Double,
        gbPrecision: Int = 1,
        mbPrecision: Int = 0
    ) -> (value: String, unit: String, numericValue: Double) {
        let resolvedGBPrecision = max(0, gbPrecision)
        let resolvedMBPrecision = max(0, mbPrecision)
        let safeUsage = normalized(usageMB)

        if safeUsage >= memoryDisplaySwitchMB {
            let gbValue = safeUsage / 1024
            return (
                value: format(gbValue, precision: resolvedGBPrecision),
                unit: "GB",
                numericValue: gbValue
            )
        }

        return (
            value: format(safeUsage, precision: resolvedMBPrecision),
            unit: "MB",
            numericValue: safeUsage
        )
    }

    private static func format(_ value: Double, precision: Int) -> String {
        String(format: "%.\(max(0, precision))f", value)
    }

    private static func normalized(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return max(0, value)
    }

    private static func deduplicated(_ values: [String]) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        for value in values where !value.isEmpty {
            if seen.insert(value).inserted {
                result.append(value)
            }
        }
        return result
    }
}
