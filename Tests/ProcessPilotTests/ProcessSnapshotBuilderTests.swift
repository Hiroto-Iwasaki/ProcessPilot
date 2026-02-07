import XCTest
@testable import ProcessPilot

final class ProcessSnapshotBuilderTests: XCTestCase {
    func testParseProcessesExtractsExpectedFields() throws {
        let output = """
        USER       PID  %CPU %MEM      VSZ    RSS   TT  STAT STARTED      TIME COMMAND
        testuser   123 12.5  1.0   123456   7890   ??  S    10:00AM   0:01.23 /Applications/Safari.app/Contents/MacOS/Safari
        root         1  0.0  0.1   123456   7890   ??  Ss   10:00AM   0:00.10 /System/Library/Kernels/kernel_task
        """
        
        let processes = ProcessSnapshotBuilder.parseProcesses(output)
        
        XCTAssertEqual(processes.count, 2)
        
        let safari = try XCTUnwrap(processes.first { $0.pid == 123 })
        XCTAssertEqual(safari.name, "Safari")
        XCTAssertEqual(safari.parentApp, "Safari")
        XCTAssertFalse(safari.isSystemProcess)
        XCTAssertGreaterThan(safari.memoryUsage, 0)
        
        let kernelTask = try XCTUnwrap(processes.first { $0.pid == 1 })
        XCTAssertEqual(kernelTask.name, "kernel_task")
        XCTAssertTrue(kernelTask.isSystemProcess)
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
