import XCTest
@testable import ProcessPilot

final class ProcessDescriptionsTests: XCTestCase {
    override func tearDownWithError() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ProcessDescriptionsTests", isDirectory: true)
        try? FileManager.default.removeItem(at: tempDirectory)
        try super.tearDownWithError()
    }
    
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
    
    func testDescriptionLookupReadsBundleInfoWhenDictionaryMisses() throws {
        let executablePath = try createFakeBundle(
            bundleFolderName: "SampleService.xpc",
            executableName: "SampleService",
            bundleName: "Sample Service",
            bundleIdentifier: "com.example.SampleService"
        )
        
        XCTAssertEqual(
            ProcessDescriptions.getDescription(
                for: "unknown-process",
                executablePath: executablePath
            ),
            "Sample Service (com.example.SampleService)"
        )
    }
    
    func testDescriptionLookupReadsAppBundleInfoWhenDictionaryMisses() throws {
        let executablePath = try createFakeBundle(
            bundleFolderName: "Tool.app",
            executableName: "Tool",
            bundleName: "Tool App",
            bundleIdentifier: "com.example.Tool"
        )
        
        XCTAssertEqual(
            ProcessDescriptions.getDescription(
                for: "unknown-process",
                executablePath: executablePath
            ),
            "Tool App (com.example.Tool)"
        )
    }
    
    private func createFakeBundle(
        bundleFolderName: String,
        executableName: String,
        bundleName: String,
        bundleIdentifier: String
    ) throws -> String {
        let fileManager = FileManager.default
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ProcessDescriptionsTests", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        let bundleURL = tempDirectory.appendingPathComponent(bundleFolderName, isDirectory: true)
        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let macosURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        
        try fileManager.createDirectory(at: macosURL, withIntermediateDirectories: true)
        
        let executableURL = macosURL.appendingPathComponent(executableName)
        fileManager.createFile(atPath: executableURL.path, contents: Data("echo test".utf8))
        
        let plist: [String: Any] = [
            "CFBundleName": bundleName,
            "CFBundleIdentifier": bundleIdentifier
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"))
        
        return executableURL.path
    }
}
