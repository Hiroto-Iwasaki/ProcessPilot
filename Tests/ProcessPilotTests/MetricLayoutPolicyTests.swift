import XCTest
@testable import ProcessPilot

final class MetricLayoutPolicyTests: XCTestCase {
    func testTierSelectionBoundaries() {
        XCTAssertEqual(MetricLayoutPolicy.tier(forContentWidth: 760), .wide)
        XCTAssertEqual(MetricLayoutPolicy.tier(forContentWidth: 759), .regular)
        XCTAssertEqual(MetricLayoutPolicy.tier(forContentWidth: 620), .regular)
        XCTAssertEqual(MetricLayoutPolicy.tier(forContentWidth: 619), .compact)
    }

    func testMetricWidthsForEachTier() {
        XCTAssertEqual(MetricLayoutPolicy.resourceBadgeValueWidth(for: .wide), 66)
        XCTAssertEqual(MetricLayoutPolicy.resourceBadgeValueWidth(for: .regular), 60)
        XCTAssertEqual(MetricLayoutPolicy.resourceBadgeValueWidth(for: .compact), 54)

        XCTAssertEqual(MetricLayoutPolicy.processRowMetricValueWidth(for: .wide), 64)
        XCTAssertEqual(MetricLayoutPolicy.processRowMetricValueWidth(for: .regular), 58)
        XCTAssertEqual(MetricLayoutPolicy.processRowMetricValueWidth(for: .compact), 52)

        XCTAssertEqual(MetricLayoutPolicy.processRowMetricBarWidth(for: .wide), 50)
        XCTAssertEqual(MetricLayoutPolicy.processRowMetricBarWidth(for: .regular), 46)
        XCTAssertEqual(MetricLayoutPolicy.processRowMetricBarWidth(for: .compact), 40)

        XCTAssertEqual(MetricLayoutPolicy.groupMetricsClusterWidth(for: .wide), 196)
        XCTAssertEqual(MetricLayoutPolicy.groupMetricsClusterWidth(for: .regular), 176)
        XCTAssertEqual(MetricLayoutPolicy.groupMetricsClusterWidth(for: .compact), 156)
    }
}
