import CoreGraphics

enum MetricWidthTier: Equatable {
    case compact
    case regular
    case wide
}

enum MetricLayoutPolicy {
    static func tier(forContentWidth width: CGFloat) -> MetricWidthTier {
        if width >= 760 { return .wide }
        if width >= 620 { return .regular }
        return .compact
    }

    static func resourceBadgeValueWidth(for tier: MetricWidthTier) -> CGFloat {
        switch tier {
        case .wide:
            return 66
        case .regular:
            return 60
        case .compact:
            return 54
        }
    }

    static func processRowMetricValueWidth(for tier: MetricWidthTier) -> CGFloat {
        switch tier {
        case .wide:
            return 64
        case .regular:
            return 58
        case .compact:
            return 52
        }
    }

    static func processRowMetricBarWidth(for tier: MetricWidthTier) -> CGFloat {
        switch tier {
        case .wide:
            return 50
        case .regular:
            return 46
        case .compact:
            return 40
        }
    }

    static func groupMetricsClusterWidth(for tier: MetricWidthTier) -> CGFloat {
        switch tier {
        case .wide:
            return 196
        case .regular:
            return 176
        case .compact:
            return 156
        }
    }

    static let cpuSummaryColumnWidth: CGFloat = 200
    static let memoryPressureColumnWidth: CGFloat = 150
}
