import XCTest
import Foundation
@testable import ProcessPilot

final class ProcessMonitorWarmupTests: XCTestCase {
    @MainActor
    func testInitialWarmupContinuesAfterManualRefreshCancellation() async throws {
        let fetcher = MockProcessFetcher()
        let sleepGate = WarmupSleepGate()
        let clock = MonotonicClock(start: 1_000_000_000, step: 1_000_000_000)

        let monitor = ProcessMonitor(
            fetchProcessesOperation: {
                try await fetcher.fetch()
            },
            calculateCPUUsageOperation: { processes, _, timestampNanoseconds in
                CPUUsageDeltaComputation(
                    processes: processes,
                    state: CPUUsageDeltaState(
                        cpuTimeTicksByPID: Dictionary(
                            uniqueKeysWithValues: processes.map { ($0.pid, UInt64(timestampNanoseconds)) }
                        ),
                        sampleTimestampNanoseconds: timestampNanoseconds
                    ),
                    hasValidElapsedInterval: true
                )
            },
            timestampProvider: {
                clock.next()
            },
            sleepOperation: { _ in
                try await sleepGate.sleepUntilOpen()
            }
        )

        await monitor.refreshProcesses()
        let firstFetchCount = await fetcher.callCount()
        XCTAssertEqual(firstFetchCount, 1)

        await monitor.refreshProcesses()
        let secondFetchCount = await fetcher.callCount()
        XCTAssertEqual(secondFetchCount, 2)

        // Cancelled warmup task should terminate while the gate is still closed.
        try await Task.sleep(nanoseconds: 20_000_000)
        await sleepGate.open()

        try await waitUntil(timeoutNanoseconds: 600_000_000) {
            await fetcher.callCount() >= 3
        }

        let finalFetchCount = await fetcher.callCount()
        XCTAssertEqual(finalFetchCount, 3)
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64,
        pollIntervalNanoseconds: UInt64 = 5_000_000,
        condition: @escaping () async -> Bool
    ) async throws {
        let start = DispatchTime.now().uptimeNanoseconds

        while !(await condition()) {
            if DispatchTime.now().uptimeNanoseconds - start > timeoutNanoseconds {
                XCTFail("Timed out while waiting for condition.")
                return
            }
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
    }
}

private actor MockProcessFetcher {
    private var calls = 0

    func callCount() -> Int {
        calls
    }

    func fetch() throws -> [AppProcessInfo] {
        calls += 1
        return [
            AppProcessInfo(
                pid: 4242,
                name: "MockProcess\(calls)",
                user: "tester",
                cpuUsage: 0,
                memoryUsage: 10,
                description: "test",
                isSystemProcess: false,
                parentApp: nil,
                executablePath: "/Applications/Mock.app/Contents/MacOS/Mock"
            )
        ]
    }
}

private actor WarmupSleepGate {
    private var isOpen = false

    func open() {
        isOpen = true
    }

    func sleepUntilOpen() async throws {
        while !isOpen {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

private final class MonotonicClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: UInt64
    private let step: UInt64

    init(start: UInt64, step: UInt64) {
        self.current = start
        self.step = step
    }

    func next() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        let value = current
        current = current &+ step
        return value
    }
}
