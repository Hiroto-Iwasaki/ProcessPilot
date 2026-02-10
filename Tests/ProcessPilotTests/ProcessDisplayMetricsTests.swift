import XCTest
@testable import ProcessPilot

final class ProcessDisplayMetricsTests: XCTestCase {
    func testCPUTextVariantsAreOrderedFromDetailedToCompact() {
        let variants = ProcessDisplayMetrics.cpuTextVariants(usage: 12.34)

        XCTAssertEqual(variants, ["12.3%", "12%", "12"])
    }

    func testMemoryTextVariantsForGBFollowExpectedFallbackOrder() {
        let variants = ProcessDisplayMetrics.memoryTextVariants(for: 1228.8)

        XCTAssertEqual(variants, ["1.2 GB", "1.2GB", "1G"])
    }

    func testMemoryTextVariantsForMBFollowExpectedFallbackOrder() {
        let variants = ProcessDisplayMetrics.memoryTextVariants(for: 824)

        XCTAssertEqual(variants, ["824 MB", "824MB", "824M"])
    }

    func testMemoryTextCompatibilityReturnsPrimaryVariant() {
        XCTAssertEqual(
            ProcessDisplayMetrics.memoryText(for: 1536, gbPrecision: 2, mbPrecision: 1),
            "1.50 GB"
        )
    }
}
