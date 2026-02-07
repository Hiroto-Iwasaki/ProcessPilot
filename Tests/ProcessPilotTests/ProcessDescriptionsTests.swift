import XCTest
@testable import ProcessPilot

final class ProcessDescriptionsTests: XCTestCase {
    func testCriticalProcessDetection() {
        XCTAssertTrue(ProcessDescriptions.isCriticalProcess("kernel_task"))
        XCTAssertTrue(ProcessDescriptions.isCriticalProcess("WindowServer"))
        XCTAssertFalse(ProcessDescriptions.isCriticalProcess("Safari"))
    }
    
    func testSystemProcessPrefixDetection() {
        XCTAssertTrue(ProcessDescriptions.isSystemProcess("mds_stores.501"))
        XCTAssertTrue(ProcessDescriptions.isSystemProcess("launchd"))
        XCTAssertFalse(ProcessDescriptions.isSystemProcess("Google Chrome"))
    }
    
    func testDescriptionLookupFallback() {
        XCTAssertEqual(
            ProcessDescriptions.getDescription(for: "Safari"),
            "Safari ウェブブラウザ"
        )
        XCTAssertEqual(
            ProcessDescriptions.getDescription(for: "unknown-process"),
            "不明なプロセス"
        )
    }
}
