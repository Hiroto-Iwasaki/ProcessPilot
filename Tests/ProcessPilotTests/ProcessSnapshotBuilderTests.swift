import XCTest
import Foundation
@testable import ProcessPilot

final class ProcessSnapshotBuilderTests: XCTestCase {
    func testParseProcessesExtractsExpectedFields() throws {
        let safariExecutablePath = try makeTemporaryExecutablePath(
            bundleName: "Safari.app",
            executableName: "Safari"
        )
        
        let output = """
        testuser 999001 12.5 1.0 \(safariExecutablePath)
        root 999002 0.0 0.1 /usr/libexec/xpcproxy
        """
        
        let processes = ProcessSnapshotBuilder.parseProcesses(output)
        
        XCTAssertEqual(processes.count, 2)
        
        let safari = try XCTUnwrap(processes.first { $0.pid == 999001 })
        XCTAssertEqual(safari.name, "Safari")
        XCTAssertEqual(safari.parentApp, "Safari")
        XCTAssertEqual(safari.executablePath, safariExecutablePath)
        XCTAssertEqual(safari.source, .application)
        XCTAssertFalse(safari.isSystemProcess)
        XCTAssertGreaterThan(safari.memoryUsage, 0)
        
        let systemProcess = try XCTUnwrap(processes.first { $0.pid == 999002 })
        XCTAssertEqual(systemProcess.name, "xpcproxy")
        XCTAssertEqual(systemProcess.executablePath, "/usr/libexec/xpcproxy")
        XCTAssertEqual(systemProcess.source, .system)
        XCTAssertTrue(systemProcess.isSystemProcess)
    }
    
    func testParseProcessesHandlesExecutablePathsWithSpaces() throws {
        let executablePath = try makeTemporaryExecutablePath(
            bundleName: "OpenIn Helper.app",
            executableName: "OpenIn Helper"
        )
        
        let output = """
        testuser 999003 1.0 0.5 \(executablePath) --type=renderer
        """
        
        let processes = ProcessSnapshotBuilder.parseProcesses(output)
        XCTAssertEqual(processes.count, 1)
        
        let process = try XCTUnwrap(processes.first)
        XCTAssertEqual(process.executablePath, executablePath)
        XCTAssertEqual(process.name, "OpenIn Helper")
        XCTAssertEqual(process.parentApp, "OpenIn Helper")
    }
    
    func testParseProcessesDoesNotTruncateLongProcessName() throws {
        let executablePath = try makeTemporaryExecutablePath(
            bundleName: "LongNameApp.app",
            executableName: "ThisIsAVeryLongProcessBinaryNameForTesting"
        )
        
        let output = """
        testuser 999004 2.0 0.3 \(executablePath)
        """
        
        let processes = ProcessSnapshotBuilder.parseProcesses(output)
        XCTAssertEqual(processes.count, 1)
        
        let process = try XCTUnwrap(processes.first)
        XCTAssertEqual(process.name, "ThisIsAVeryLongProcessBinaryNameForTesting")
        XCTAssertGreaterThan(process.name.count, 20)
    }
    
    func testParseProcessesStripsFilePathArgumentFromAppCommand() throws {
        let executablePath = try makeTemporaryExecutablePath(
            bundleName: "TextEdit.app",
            executableName: "TextEdit"
        )
        
        let output = """
        testuser 999005 0.9 0.2 \(executablePath) /Users/test/Documents/note.txt
        """
        
        let processes = ProcessSnapshotBuilder.parseProcesses(output)
        XCTAssertEqual(processes.count, 1)
        
        let process = try XCTUnwrap(processes.first)
        XCTAssertEqual(process.executablePath, executablePath)
        XCTAssertEqual(process.name, "TextEdit")
        XCTAssertEqual(process.parentApp, "TextEdit")
    }
    
    func testParseProcessesDoesNotTruncateAppPathContainingHyphen() throws {
        let executablePath = try makeTemporaryExecutablePath(
            bundleName: "Visual Studio Code - Insiders.app",
            executableName: "Electron"
        )
        
        let output = """
        testuser 999006 1.3 0.4 \(executablePath) --type=renderer
        """
        
        let processes = ProcessSnapshotBuilder.parseProcesses(output)
        XCTAssertEqual(processes.count, 1)
        
        let process = try XCTUnwrap(processes.first)
        XCTAssertEqual(process.executablePath, executablePath)
        XCTAssertEqual(process.parentApp, "Visual Studio Code - Insiders")
    }
    
    func testParseProcessesStripsSingleHyphenArgumentFromAppCommand() throws {
        let executablePath = try makeTemporaryExecutablePath(
            bundleName: "TextEdit.app",
            executableName: "TextEdit"
        )
        
        let output = """
        testuser 999007 0.5 0.1 \(executablePath) -psn_0_12345
        """
        
        let processes = ProcessSnapshotBuilder.parseProcesses(output)
        XCTAssertEqual(processes.count, 1)
        
        let process = try XCTUnwrap(processes.first)
        XCTAssertEqual(process.executablePath, executablePath)
        XCTAssertEqual(process.name, "TextEdit")
        XCTAssertEqual(process.parentApp, "TextEdit")
    }
    
    func testParseProcessesDropsUnresolvableExecutablePathFallback() throws {
        let output = """
        testuser 999998 0.8 0.2 /Applications/DefinitelyMissingApp.app/Contents/MacOS/Missing --type=renderer
        """
        
        let processes = ProcessSnapshotBuilder.parseProcesses(output)
        XCTAssertEqual(processes.count, 1)
        
        let process = try XCTUnwrap(processes.first)
        XCTAssertNil(process.executablePath)
        XCTAssertEqual(process.source, .unknown)
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
    
    func testSortProcessesUsesPIDAsStableTieBreaker() {
        let input = [
            AppProcessInfo(
                pid: 200,
                name: "SameName",
                user: "user",
                cpuUsage: 10.0,
                memoryUsage: 100,
                description: "desc",
                isSystemProcess: false,
                parentApp: nil
            ),
            AppProcessInfo(
                pid: 100,
                name: "SameName",
                user: "user",
                cpuUsage: 10.0,
                memoryUsage: 100,
                description: "desc",
                isSystemProcess: false,
                parentApp: nil
            )
        ]
        
        let sorted = ProcessSnapshotBuilder.sortProcesses(
            input,
            sortBy: .cpu,
            filterText: "",
            showHighUsageFirst: true
        )
        
        XCTAssertEqual(sorted.map(\.pid), [100, 200])
    }
    
    func testSortProcessesPlacesNonFiniteUsageAtEndForDescending() {
        let input = [
            AppProcessInfo(
                pid: 1,
                name: "NaNProcess",
                user: "user",
                cpuUsage: .nan,
                memoryUsage: 100,
                description: "desc",
                isSystemProcess: false,
                parentApp: nil
            ),
            AppProcessInfo(
                pid: 2,
                name: "HighCPU",
                user: "user",
                cpuUsage: 20.0,
                memoryUsage: 100,
                description: "desc",
                isSystemProcess: false,
                parentApp: nil
            ),
            AppProcessInfo(
                pid: 3,
                name: "LowCPU",
                user: "user",
                cpuUsage: 5.0,
                memoryUsage: 100,
                description: "desc",
                isSystemProcess: false,
                parentApp: nil
            )
        ]
        
        let sorted = ProcessSnapshotBuilder.sortProcesses(
            input,
            sortBy: .cpu,
            filterText: "",
            showHighUsageFirst: true
        )
        
        XCTAssertEqual(sorted.map(\.pid), [2, 3, 1])
    }
    
    func testSortProcessesCancellableMatchesLegacyOrdering() throws {
        let input = [
            makeProcess(pid: 3, name: "Gamma", cpu: 30.0, memory: 300),
            makeProcess(pid: 2, name: "Beta", cpu: 30.0, memory: 200),
            makeProcess(pid: 1, name: "Alpha", cpu: 10.0, memory: 100)
        ]
        
        let expected = ProcessSnapshotBuilder.sortProcesses(
            input,
            sortBy: .cpu,
            filterText: "",
            showHighUsageFirst: true
        )
        let actual = try ProcessSnapshotBuilder.sortProcessesCancellable(
            input,
            sortBy: .cpu,
            filterText: "",
            showHighUsageFirst: true
        )
        
        XCTAssertEqual(actual.map(\.pid), expected.map(\.pid))
    }
    
    func testSortProcessesCancellableThrowsOnCancellation() async {
        let input = makeLargeProcessInput(count: 5000)
        
        let task = Task.detached { () -> Result<[AppProcessInfo], Error> in
            do {
                let sorted = try ProcessSnapshotBuilder.sortProcessesCancellable(
                    input,
                    sortBy: .cpu,
                    filterText: "",
                    showHighUsageFirst: true
                )
                return .success(sorted)
            } catch {
                return .failure(error)
            }
        }
        task.cancel()
        
        switch await task.value {
        case .success:
            XCTFail("Expected CancellationError")
        case .failure(let error):
            XCTAssertTrue(error is CancellationError, "Unexpected error: \(error)")
        }
    }
    
    func testUsageSmootherUsesMovingAverageWindowOfThree() {
        var smoother = UsageSmoother(windowSize: 3)
        
        let first = smoother.smooth(processes: [makeProcess(pid: 1, name: "A", cpu: 10, memory: 100)])[0]
        XCTAssertEqual(first.cpuUsage, 10, accuracy: 0.001)
        XCTAssertEqual(first.memoryUsage, 100, accuracy: 0.001)
        
        let second = smoother.smooth(processes: [makeProcess(pid: 1, name: "A", cpu: 40, memory: 400)])[0]
        XCTAssertEqual(second.cpuUsage, 25, accuracy: 0.001)
        XCTAssertEqual(second.memoryUsage, 250, accuracy: 0.001)
        
        let third = smoother.smooth(processes: [makeProcess(pid: 1, name: "A", cpu: 70, memory: 700)])[0]
        XCTAssertEqual(third.cpuUsage, 40, accuracy: 0.001)
        XCTAssertEqual(third.memoryUsage, 400, accuracy: 0.001)
        
        let fourth = smoother.smooth(processes: [makeProcess(pid: 1, name: "A", cpu: 100, memory: 1000)])[0]
        XCTAssertEqual(fourth.cpuUsage, 70, accuracy: 0.001)
        XCTAssertEqual(fourth.memoryUsage, 700, accuracy: 0.001)
    }
    
    func testUsageSmootherDropsHistoryForMissingProcesses() {
        var smoother = UsageSmoother(windowSize: 3)
        
        _ = smoother.smooth(processes: [makeProcess(pid: 1, name: "A", cpu: 10, memory: 100)])
        _ = smoother.smooth(processes: [makeProcess(pid: 2, name: "B", cpu: 20, memory: 200)])
        
        let reappeared = smoother.smooth(processes: [makeProcess(pid: 1, name: "A", cpu: 100, memory: 1000)])[0]
        XCTAssertEqual(reappeared.cpuUsage, 100, accuracy: 0.001)
        XCTAssertEqual(reappeared.memoryUsage, 1000, accuracy: 0.001)
    }
    
    func testUsageSmootherCanDropHistoryForSpecificPID() {
        var smoother = UsageSmoother(windowSize: 3)
        
        _ = smoother.smooth(processes: [makeProcess(pid: 1, name: "A", cpu: 10, memory: 100)])
        _ = smoother.smooth(processes: [makeProcess(pid: 1, name: "A", cpu: 40, memory: 400)])
        
        smoother.removeHistory(forPIDs: [1])
        
        let reset = smoother.smooth(processes: [makeProcess(pid: 1, name: "A", cpu: 100, memory: 1000)])[0]
        XCTAssertEqual(reset.cpuUsage, 100, accuracy: 0.001)
        XCTAssertEqual(reset.memoryUsage, 1000, accuracy: 0.001)
    }
    
    func testCPUUsageDeltaCalculatorUsesPIDCPUTimeDelta() {
        let processes = [makeProcess(pid: 10, name: "A", cpu: 999, memory: 100)]
        let previousState = CPUUsageDeltaState(
            cpuTimeTicksByPID: [10: 100_000_000],
            sampleTimestampNanoseconds: 1_000_000_000
        )
        
        let result = CPUUsageDeltaCalculator.calculate(
            processes: processes,
            currentCPUTimeTicksByPID: [10: 112_000_000],
            previousState: previousState,
            timestampNanoseconds: 2_000_000_000,
            timebaseNumer: 125,
            timebaseDenom: 3
        )
        
        XCTAssertEqual(result.processes.count, 1)
        XCTAssertEqual(result.processes[0].cpuUsage, 50, accuracy: 0.001)
        XCTAssertEqual(result.state.cpuTimeTicksByPID[10], 112_000_000)
        XCTAssertEqual(result.state.sampleTimestampNanoseconds, 2_000_000_000)
        XCTAssertTrue(result.hasValidElapsedInterval)
    }
    
    func testCPUUsageDeltaCalculatorReturnsZeroWhenNoPreviousSample() {
        let processes = [makeProcess(pid: 10, name: "A", cpu: 12.5, memory: 100)]
        
        let result = CPUUsageDeltaCalculator.calculate(
            processes: processes,
            currentCPUTimeTicksByPID: [10: 1_500_000],
            previousState: CPUUsageDeltaState(),
            timestampNanoseconds: 2_000_000_000,
            timebaseNumer: 125,
            timebaseDenom: 3
        )
        
        XCTAssertEqual(result.processes[0].cpuUsage, 0, accuracy: 0.001)
        XCTAssertFalse(result.hasValidElapsedInterval)
    }
    
    func testCPUUsageDeltaCalculatorReturnsZeroForNewPIDInElapsedWindow() {
        let processes = [makeProcess(pid: 20, name: "B", cpu: 77.7, memory: 100)]
        let previousState = CPUUsageDeltaState(
            cpuTimeTicksByPID: [10: 1_000_000],
            sampleTimestampNanoseconds: 1_000_000_000
        )
        
        let result = CPUUsageDeltaCalculator.calculate(
            processes: processes,
            currentCPUTimeTicksByPID: [20: 2_000_000],
            previousState: previousState,
            timestampNanoseconds: 2_000_000_000,
            timebaseNumer: 125,
            timebaseDenom: 3
        )
        
        XCTAssertEqual(result.processes[0].cpuUsage, 0, accuracy: 0.001)
    }
    
    func testCPUUsageDeltaCalculatorReturnsZeroWhenElapsedIntervalIsTooShort() {
        let processes = [makeProcess(pid: 10, name: "A", cpu: 99.9, memory: 100)]
        let previousState = CPUUsageDeltaState(
            cpuTimeTicksByPID: [10: 100_000_000],
            sampleTimestampNanoseconds: 1_000_000_000
        )
        
        let result = CPUUsageDeltaCalculator.calculate(
            processes: processes,
            currentCPUTimeTicksByPID: [10: 112_000_000],
            previousState: previousState,
            timestampNanoseconds: 1_400_000_000,
            timebaseNumer: 125,
            timebaseDenom: 3
        )
        
        XCTAssertEqual(result.processes[0].cpuUsage, 0, accuracy: 0.001)
        XCTAssertEqual(result.state.cpuTimeTicksByPID[10], 112_000_000)
        XCTAssertEqual(result.state.sampleTimestampNanoseconds, 1_400_000_000)
        XCTAssertFalse(result.hasValidElapsedInterval)
    }
    
    func testCPUUsageDeltaCalculatorPrunesRemovedPIDsFromState() {
        let processes = [makeProcess(pid: 20, name: "B", cpu: 10, memory: 100)]
        let previousState = CPUUsageDeltaState(
            cpuTimeTicksByPID: [10: 1_000_000, 20: 2_000_000],
            sampleTimestampNanoseconds: 1_000_000_000
        )
        
        let result = CPUUsageDeltaCalculator.calculate(
            processes: processes,
            currentCPUTimeTicksByPID: [20: 2_500_000],
            previousState: previousState,
            timestampNanoseconds: 2_000_000_000,
            timebaseNumer: 125,
            timebaseDenom: 3
        )
        
        XCTAssertNil(result.state.cpuTimeTicksByPID[10])
        XCTAssertEqual(result.state.cpuTimeTicksByPID[20], 2_500_000)
    }
    
    func testCPUUsageDeltaCalculatorConvertsTicksToNanosecondsWithTimebase() {
        let nanoseconds = CPUUsageDeltaCalculator.ticksToNanoseconds(
            24,
            numer: 125,
            denom: 3
        )
        
        XCTAssertEqual(nanoseconds, 1_000, accuracy: 0.001)
    }
    
    func testSystemGroupCPUSmootherSmoothsOnlySystemGroup() throws {
        var smoother = SystemGroupCPUSmoother(windowSize: 3)
        
        let first = smoother.smooth(groups: [
            makeGroup(name: "システム", cpu: 90, isSystem: true),
            makeGroup(name: "AppA", cpu: 30, isSystem: false)
        ])
        let firstSystemCPU = try XCTUnwrap(first.first(where: { $0.appName == "システム" })?.totalCPU)
        let firstAppCPU = try XCTUnwrap(first.first(where: { $0.appName == "AppA" })?.totalCPU)
        XCTAssertEqual(firstSystemCPU, 90, accuracy: 0.001)
        XCTAssertEqual(firstAppCPU, 30, accuracy: 0.001)
        
        let second = smoother.smooth(groups: [
            makeGroup(name: "システム", cpu: 30, isSystem: true),
            makeGroup(name: "AppA", cpu: 30, isSystem: false)
        ])
        let secondSystemCPU = try XCTUnwrap(second.first(where: { $0.appName == "システム" })?.totalCPU)
        let secondAppCPU = try XCTUnwrap(second.first(where: { $0.appName == "AppA" })?.totalCPU)
        XCTAssertEqual(secondSystemCPU, 60, accuracy: 0.001)
        XCTAssertEqual(secondAppCPU, 30, accuracy: 0.001)
    }
    
    func testSystemGroupCPUSmootherResetsWhenSystemGroupDisappears() throws {
        var smoother = SystemGroupCPUSmoother(windowSize: 3)
        
        _ = smoother.smooth(groups: [makeGroup(name: "システム", cpu: 90, isSystem: true)])
        _ = smoother.smooth(groups: [makeGroup(name: "Other", cpu: 10, isSystem: false)])
        let resumed = smoother.smooth(groups: [makeGroup(name: "システム", cpu: 30, isSystem: true)])
        
        let resumedCPU = try XCTUnwrap(resumed.first?.totalCPU)
        XCTAssertEqual(resumedCPU, 30, accuracy: 0.001)
    }
    
    func testBottomBarHistoryCalculatesCPUDeltas() {
        var history = BottomBarHistory(historyLimit: 8)
        
        let first = history.nextMetrics(
            from: makeBottomBarSnapshot(
                cpuUser: 100,
                cpuSystem: 50,
                cpuIdle: 850,
                pressureRatio: 0.40
            )
        )
        
        XCTAssertEqual(first.cpu.userPercent, 10, accuracy: 0.001)
        XCTAssertEqual(first.cpu.systemPercent, 5, accuracy: 0.001)
        XCTAssertEqual(first.cpu.idlePercent, 85, accuracy: 0.001)
        
        let second = history.nextMetrics(
            from: makeBottomBarSnapshot(
                cpuUser: 130,
                cpuSystem: 70,
                cpuIdle: 900,
                pressureRatio: 0.55
            )
        )
        
        XCTAssertEqual(second.cpu.userPercent, 30, accuracy: 0.001)
        XCTAssertEqual(second.cpu.systemPercent, 20, accuracy: 0.001)
        XCTAssertEqual(second.cpu.idlePercent, 50, accuracy: 0.001)
        XCTAssertEqual(second.cpu.userHistory.count, 2)
        XCTAssertEqual(second.cpu.systemHistory.count, 2)
    }
    
    func testBottomBarHistoryCapsHistoryLength() {
        var history = BottomBarHistory(historyLimit: 3)
        
        for index in 0..<5 {
            _ = history.nextMetrics(
                from: makeBottomBarSnapshot(
                    cpuUser: UInt64(100 + index * 10),
                    cpuSystem: UInt64(100 + index * 5),
                    cpuIdle: UInt64(1_000 + index * 20),
                    pressureRatio: Double(index) * 0.2
                )
            )
        }
        
        let latest = history.nextMetrics(
            from: makeBottomBarSnapshot(
                cpuUser: 200,
                cpuSystem: 140,
                cpuIdle: 1_200,
                pressureRatio: 0.6
            )
        )
        
        XCTAssertEqual(latest.cpu.userHistory.count, 3)
        XCTAssertEqual(latest.cpu.systemHistory.count, 3)
        XCTAssertEqual(latest.memory.pressureHistory.count, 3)
    }
    
    private func makeProcess(
        pid: Int32,
        name: String,
        cpu: Double,
        memory: Double
    ) -> AppProcessInfo {
        AppProcessInfo(
            pid: pid,
            name: name,
            user: "user",
            cpuUsage: cpu,
            memoryUsage: memory,
            description: "desc",
            isSystemProcess: false,
            parentApp: nil
        )
    }
    
    private func makeTemporaryExecutablePath(
        bundleName: String,
        executableName: String
    ) throws -> String {
        let fileManager = FileManager.default
        let rootDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ProcessSnapshotBuilderTests-\(UUID().uuidString)", isDirectory: true)
        let executableURL = rootDirectory
            .appendingPathComponent(bundleName, isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent(executableName)
        
        try fileManager.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        fileManager.createFile(atPath: executableURL.path, contents: Data(), attributes: nil)
        return executableURL.path
    }
    
    private func makeLargeProcessInput(count: Int) -> [AppProcessInfo] {
        var result: [AppProcessInfo] = []
        result.reserveCapacity(count)
        
        for index in 0..<count {
            result.append(
                AppProcessInfo(
                    pid: Int32(index + 1),
                    name: "Process\(index)",
                    user: "user",
                    cpuUsage: Double(count - index),
                    memoryUsage: Double(index),
                    description: "desc",
                    isSystemProcess: false,
                    parentApp: nil
                )
            )
        }
        
        return result
    }
    
    private func makeGroup(name: String, cpu: Double, isSystem: Bool) -> ProcessGroup {
        ProcessGroup(
            appName: name,
            processes: [
                AppProcessInfo(
                    pid: Int32(abs(name.hashValue % 100000) + 1),
                    name: name,
                    user: "user",
                    cpuUsage: cpu,
                    memoryUsage: 100,
                    description: "desc",
                    isSystemProcess: isSystem,
                    parentApp: nil
                )
            ]
        )
    }
    
    private func makeBottomBarSnapshot(
        cpuUser: UInt64,
        cpuSystem: UInt64,
        cpuIdle: UInt64,
        pressureRatio: Double
    ) -> BottomBarRawSnapshot {
        BottomBarRawSnapshot(
            cpuTicks: SystemMetricsCollector.CPUTicks(
                user: cpuUser,
                system: cpuSystem,
                idle: cpuIdle,
                nice: 0
            ),
            memory: SystemMetricsCollector.MemorySnapshot(
                pressureRatio: pressureRatio,
                physicalMemoryMB: 16 * 1024,
                usedMemoryMB: 8 * 1024,
                cachedFilesMB: 2 * 1024,
                swapUsedMB: 512,
                appMemoryMB: 4 * 1024,
                wiredMemoryMB: 2 * 1024,
                compressedMemoryMB: 1024
            )
        )
    }
}
