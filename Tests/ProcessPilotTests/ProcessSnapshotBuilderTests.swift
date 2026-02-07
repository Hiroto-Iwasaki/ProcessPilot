import XCTest
@testable import ProcessPilot

final class ProcessSnapshotBuilderTests: XCTestCase {
    func testParseProcessesExtractsExpectedFields() throws {
        let output = """
        testuser 999001 12.5 1.0 /Applications/Safari.app/Contents/MacOS/Safari
        root 999002 0.0 0.1 /System/Library/Kernels/kernel_task
        """
        
        let processes = ProcessSnapshotBuilder.parseProcesses(output)
        
        XCTAssertEqual(processes.count, 2)
        
        let safari = try XCTUnwrap(processes.first { $0.pid == 999001 })
        XCTAssertEqual(safari.name, "Safari")
        XCTAssertEqual(safari.parentApp, "Safari")
        XCTAssertEqual(safari.executablePath, "/Applications/Safari.app/Contents/MacOS/Safari")
        XCTAssertEqual(safari.source, .application)
        XCTAssertFalse(safari.isSystemProcess)
        XCTAssertGreaterThan(safari.memoryUsage, 0)
        
        let kernelTask = try XCTUnwrap(processes.first { $0.pid == 999002 })
        XCTAssertEqual(kernelTask.name, "kernel_task")
        XCTAssertEqual(kernelTask.executablePath, "/System/Library/Kernels/kernel_task")
        XCTAssertEqual(kernelTask.source, .system)
        XCTAssertTrue(kernelTask.isSystemProcess)
    }
    
    func testParseProcessesHandlesExecutablePathsWithSpaces() throws {
        let output = """
        testuser 999003 1.0 0.5 /Applications/OpenIn Helper.app/Contents/MacOS/OpenIn Helper --type=renderer
        """
        
        let processes = ProcessSnapshotBuilder.parseProcesses(output)
        XCTAssertEqual(processes.count, 1)
        
        let process = try XCTUnwrap(processes.first)
        XCTAssertEqual(process.executablePath, "/Applications/OpenIn Helper.app/Contents/MacOS/OpenIn Helper")
        XCTAssertEqual(process.name, "OpenIn Helper")
        XCTAssertEqual(process.parentApp, "OpenIn Helper")
    }
    
    func testParseProcessesDoesNotTruncateLongProcessName() throws {
        let output = """
        testuser 999004 2.0 0.3 /Applications/LongNameApp.app/Contents/MacOS/ThisIsAVeryLongProcessBinaryNameForTesting
        """
        
        let processes = ProcessSnapshotBuilder.parseProcesses(output)
        XCTAssertEqual(processes.count, 1)
        
        let process = try XCTUnwrap(processes.first)
        XCTAssertEqual(process.name, "ThisIsAVeryLongProcessBinaryNameForTesting")
        XCTAssertGreaterThan(process.name.count, 20)
    }
    
    func testSortAndGroupProcesses() {
        let input = [
            AppProcessInfo(
                pid: 10,
                name: "Safari",
                user: "user",
                cpuUsage: 12.0,
                memoryUsage: 256,
                description: "Safari ウェブブラウザ",
                isSystemProcess: false,
                parentApp: "Safari"
            ),
            AppProcessInfo(
                pid: 1,
                name: "kernel_task",
                user: "root",
                cpuUsage: 2.0,
                memoryUsage: 128,
                description: "macOSカーネル",
                isSystemProcess: true,
                parentApp: nil
            )
        ]
        
        let cpuHighFirst = ProcessSnapshotBuilder.sortProcesses(
            input,
            sortBy: .cpu,
            filterText: "",
            showHighUsageFirst: true
        )
        XCTAssertEqual(cpuHighFirst.first?.pid, 10)
        
        let cpuLowFirst = ProcessSnapshotBuilder.sortProcesses(
            input,
            sortBy: .cpu,
            filterText: "",
            showHighUsageFirst: false
        )
        XCTAssertEqual(cpuLowFirst.first?.pid, 1)
        
        let memoryHighFirst = ProcessSnapshotBuilder.sortProcesses(
            input,
            sortBy: .memory,
            filterText: "",
            showHighUsageFirst: true
        )
        XCTAssertEqual(memoryHighFirst.first?.pid, 10)
        
        let memoryLowFirst = ProcessSnapshotBuilder.sortProcesses(
            input,
            sortBy: .memory,
            filterText: "",
            showHighUsageFirst: false
        )
        XCTAssertEqual(memoryLowFirst.first?.pid, 1)
        
        let groups = ProcessSnapshotBuilder.groupProcesses(input, sortBy: .cpu)
        XCTAssertTrue(groups.contains { $0.appName == "Safari" })
        XCTAssertTrue(groups.contains { $0.appName == "システム" })
    }
}
