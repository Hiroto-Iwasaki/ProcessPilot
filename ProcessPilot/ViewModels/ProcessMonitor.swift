import Foundation
import Combine
import Darwin

@MainActor
class ProcessMonitor: ObservableObject {
    typealias FetchProcessesOperation = @Sendable () async throws -> [AppProcessInfo]
    typealias CalculateCPUUsageOperation = @Sendable ([AppProcessInfo], CPUUsageDeltaState, UInt64) async -> CPUUsageDeltaComputation
    typealias TimestampProvider = @Sendable () -> UInt64
    typealias SleepOperation = @Sendable (UInt64) async throws -> Void

    private struct ProcessComputationResult: Sendable {
        let processes: [AppProcessInfo]
        let cpuUsageState: CPUUsageDeltaState
        let usageSmoother: UsageSmoother
        let hasValidDeltaSample: Bool
    }
    
    @Published var processes: [AppProcessInfo] = []
    @Published var groups: [ProcessGroup] = []
    @Published var isLoading = false
    @Published var sortBy: SortOption = .cpu
    @Published var showGrouped = true
    @Published var showHighUsageFirst = true
    @Published var filterText = "" {
        didSet {
            scheduleApplySortingAndGrouping()
        }
    }
    
    private var allProcesses: [AppProcessInfo] = []
    private var usageSmoother = UsageSmoother(windowSize: 3)
    private var systemGroupCPUSmoother = SystemGroupCPUSmoother(windowSize: 3)
    private var cpuUsageState = CPUUsageDeltaState()
    private var snapshotTask: Task<Void, Never>?
    private var initialWarmupTask: Task<Void, Never>?
    private var currentWarmupTaskID: UInt64?
    private var nextWarmupTaskID: UInt64 = 0
    private var filterDebounceTask: Task<Void, Never>?
    private var snapshotVersion: UInt64 = 0
    private var refreshGeneration: UInt64 = 0
    private var initialWarmupRemainingPasses: Int?

    private let fetchProcessesOperation: FetchProcessesOperation
    private let calculateCPUUsageOperation: CalculateCPUUsageOperation
    private let timestampProvider: TimestampProvider
    private let sleepOperation: SleepOperation
    private let initialWarmupIntervalNanoseconds: UInt64
    private let filterDebounceIntervalNanoseconds: UInt64
    
    enum SortOption: String, CaseIterable, Sendable {
        case cpu = "CPU"
        case memory = "メモリ"
    }

    init(
        fetchProcessesOperation: @escaping FetchProcessesOperation = {
            try await ProcessMonitor.defaultFetchProcessesOperation()
        },
        calculateCPUUsageOperation: @escaping CalculateCPUUsageOperation = { processes, previousState, timestampNanoseconds in
            await ProcessMonitor.defaultCalculateCPUUsageOperation(
                processes: processes,
                previousState: previousState,
                timestampNanoseconds: timestampNanoseconds
            )
        },
        timestampProvider: @escaping TimestampProvider = {
            ProcessMonitor.defaultTimestampProvider()
        },
        sleepOperation: @escaping SleepOperation = { nanoseconds in
            try await ProcessMonitor.defaultSleepOperation(nanoseconds: nanoseconds)
        },
        usageSmoothingWindowSize: Int = 3,
        systemGroupSmoothingWindowSize: Int = 3,
        initialWarmupIntervalNanoseconds: UInt64 = CPUUsageDeltaCalculator.minimumSamplingIntervalNanoseconds,
        filterDebounceIntervalNanoseconds: UInt64 = 200_000_000
    ) {
        self.fetchProcessesOperation = fetchProcessesOperation
        self.calculateCPUUsageOperation = calculateCPUUsageOperation
        self.timestampProvider = timestampProvider
        self.sleepOperation = sleepOperation
        self.usageSmoother = UsageSmoother(windowSize: usageSmoothingWindowSize)
        self.systemGroupCPUSmoother = SystemGroupCPUSmoother(windowSize: systemGroupSmoothingWindowSize)
        self.initialWarmupIntervalNanoseconds = initialWarmupIntervalNanoseconds
        self.filterDebounceIntervalNanoseconds = filterDebounceIntervalNanoseconds
    }
    
    deinit {
        snapshotTask?.cancel()
        initialWarmupTask?.cancel()
        filterDebounceTask?.cancel()
    }
    
    func refreshProcesses() async {
        guard !isLoading else { return }
        refreshGeneration &+= 1
        let generation = refreshGeneration
        initialWarmupTask?.cancel()
        initialWarmupTask = nil
        currentWarmupTaskID = nil
        isLoading = true
        defer { isLoading = false }
        
        do {
            let computation = try await computeProcessedProcesses(
                baseCPUUsageState: cpuUsageState,
                baseUsageSmoother: usageSmoother
            )
            guard !Task.isCancelled else { return }
            guard generation == refreshGeneration else { return }

            applyComputation(computation)
            registerForegroundSampleForInitialWarmup(
                hasValidDeltaSample: computation.hasValidDeltaSample
            )
            applySortingAndGrouping()
            scheduleInitialWarmupIfNeeded(for: generation)
        } catch is CancellationError {
            return
        } catch {
            print("Error refreshing process list: \(error)")
        }
    }
    
    func changeSortOption(_ option: SortOption) {
        filterDebounceTask?.cancel()
        sortBy = option
        applySortingAndGrouping()
    }
    
    func changeHighUsageOrder(_ isEnabled: Bool) {
        filterDebounceTask?.cancel()
        showHighUsageFirst = isEnabled
        applySortingAndGrouping()
    }
    
    func removeProcessesFromCache(pids: [Int32]) {
        removeProcessesFromCache(pids: Set(pids))
    }
    
    func removeProcessesFromCache(pids: Set<Int32>) {
        guard !pids.isEmpty else { return }
        
        let previousCount = allProcesses.count
        allProcesses.removeAll { pids.contains($0.pid) }
        usageSmoother.removeHistory(forPIDs: pids)
        cpuUsageState.removeHistory(forPIDs: pids)
        
        guard allProcesses.count != previousCount else { return }
        applySortingAndGrouping()
    }
    
    private func applySortingAndGrouping() {
        snapshotVersion &+= 1
        let version = snapshotVersion
        let sourceProcesses = allProcesses
        let sourceSortBy = sortBy
        let sourceFilterText = filterText
        let sourceShowHighUsageFirst = showHighUsageFirst
        
        snapshotTask?.cancel()
        snapshotTask = Task.detached(priority: .userInitiated) { [sourceProcesses, sourceSortBy, sourceFilterText, sourceShowHighUsageFirst] in
            do {
                let snapshot = try ProcessSnapshotBuilder.makeDisplaySnapshot(
                    sourceProcesses,
                    sortBy: sourceSortBy,
                    filterText: sourceFilterText,
                    showHighUsageFirst: sourceShowHighUsageFirst
                )
                
                guard !Task.isCancelled else {
                    return
                }
                
                await MainActor.run {
                    guard version == self.snapshotVersion else {
                        return
                    }
                    
                    let smoothedGroups = self.systemGroupCPUSmoother.smooth(
                        groups: snapshot.groups
                    )
                    self.processes = snapshot.processes
                    self.groups = smoothedGroups
                }
            } catch is CancellationError {
                return
            } catch {
                #if DEBUG
                assertionFailure("applySortingAndGrouping failed: \(error)")
                #else
                print("ProcessMonitor.applySortingAndGrouping failed: \(error)")
                #endif
            }
        }
    }
    
    private func scheduleApplySortingAndGrouping() {
        filterDebounceTask?.cancel()
        filterDebounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.filterDebounceIntervalNanoseconds ?? 200_000_000)
            } catch {
                return
            }
            
            guard !Task.isCancelled else { return }
            self?.applySortingAndGrouping()
        }
    }
    
    private func computeProcessedProcesses(
        baseCPUUsageState: CPUUsageDeltaState,
        baseUsageSmoother: UsageSmoother
    ) async throws -> ProcessComputationResult {
        let fetchedProcesses = try await fetchProcessesOperation()
        try Task.checkCancellation()

        let cpuAdjusted = await calculateCPUUsageOperation(
            fetchedProcesses,
            baseCPUUsageState,
            timestampProvider()
        )
        try Task.checkCancellation()
        
        var nextUsageSmoother = baseUsageSmoother
        let smoothedProcesses = nextUsageSmoother.smooth(processes: cpuAdjusted.processes)
        try Task.checkCancellation()
        
        return ProcessComputationResult(
            processes: smoothedProcesses,
            cpuUsageState: cpuAdjusted.state,
            usageSmoother: nextUsageSmoother,
            hasValidDeltaSample: cpuAdjusted.hasValidElapsedInterval
        )
    }

    private func applyComputation(_ computation: ProcessComputationResult) {
        allProcesses = computation.processes
        cpuUsageState = computation.cpuUsageState
        usageSmoother = computation.usageSmoother
    }

    private func registerForegroundSampleForInitialWarmup(hasValidDeltaSample: Bool) {
        if initialWarmupRemainingPasses == nil {
            initialWarmupRemainingPasses = max(usageSmoother.windowSize - 1, 0)
            return
        }

        guard hasValidDeltaSample else { return }
        decrementInitialWarmupRemainingPassesIfNeeded()
    }

    private func scheduleInitialWarmupIfNeeded(for generation: UInt64) {
        guard initialWarmupTask == nil else { return }
        guard (initialWarmupRemainingPasses ?? 0) > 0 else { return }
        nextWarmupTaskID &+= 1
        let taskID = nextWarmupTaskID
        currentWarmupTaskID = taskID
        
        initialWarmupTask = Task { [weak self] in
            await self?.runInitialWarmup(for: generation, taskID: taskID)
        }
    }

    private func runInitialWarmup(for generation: UInt64, taskID: UInt64) async {
        defer {
            if currentWarmupTaskID == taskID {
                initialWarmupTask = nil
                currentWarmupTaskID = nil
            }
        }

        while (initialWarmupRemainingPasses ?? 0) > 0 {
            do {
                try await sleepOperation(initialWarmupIntervalNanoseconds)
            } catch {
                return
            }
            
            guard !Task.isCancelled else { return }
            guard generation == refreshGeneration else { return }
            
            do {
                let computation = try await computeProcessedProcesses(
                    baseCPUUsageState: cpuUsageState,
                    baseUsageSmoother: usageSmoother
                )
                guard !Task.isCancelled else { return }
                guard generation == refreshGeneration else { return }

                applyComputation(computation)
                if computation.hasValidDeltaSample {
                    decrementInitialWarmupRemainingPassesIfNeeded()
                }
                applySortingAndGrouping()
            } catch is CancellationError {
                return
            } catch {
                print("Error warming up initial process samples: \(error)")
                return
            }
        }
    }

    private func decrementInitialWarmupRemainingPassesIfNeeded() {
        guard let remainingPasses = initialWarmupRemainingPasses,
              remainingPasses > 0 else {
            return
        }
        initialWarmupRemainingPasses = remainingPasses - 1
    }

    nonisolated private static func defaultFetchProcessesOperation() async throws -> [AppProcessInfo] {
        try await Task.detached(priority: .utility) {
            try ProcessSnapshotBuilder.fetchProcesses()
        }.value
    }

    nonisolated private static func defaultCalculateCPUUsageOperation(
        processes: [AppProcessInfo],
        previousState: CPUUsageDeltaState,
        timestampNanoseconds: UInt64
    ) async -> CPUUsageDeltaComputation {
        await Task.detached(priority: .utility) {
            CPUUsageDeltaCalculator.calculate(
                processes: processes,
                previousState: previousState,
                timestampNanoseconds: timestampNanoseconds
            )
        }.value
    }

    nonisolated private static func defaultTimestampProvider() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    nonisolated private static func defaultSleepOperation(nanoseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

@MainActor
final class BottomBarMonitor: ObservableObject {
    @Published private(set) var metrics = BottomBarMetrics.empty
    
    private var history = BottomBarHistory(historyLimit: 48)
    private var autoRefreshTask: Task<Void, Never>?
    private let refreshIntervalNanoseconds: UInt64 = 1_000_000_000
    
    func startAutoRefresh() {
        guard autoRefreshTask == nil else { return }
        
        autoRefreshTask = Task { [weak self] in
            await self?.runAutoRefreshLoop()
        }
    }
    
    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }
    
    func refreshOnce() async {
        let snapshot = await Task.detached(priority: .utility) {
            SystemMetricsCollector.capture()
        }.value
        
        metrics = history.nextMetrics(from: snapshot)
    }
    
    private func runAutoRefreshLoop() async {
        defer {
            autoRefreshTask = nil
        }
        
        await refreshOnce()
        
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: refreshIntervalNanoseconds)
            } catch {
                break
            }
            
            guard !Task.isCancelled else { break }
            await refreshOnce()
        }
    }
}

struct BottomBarMetrics: Sendable {
    struct CPUSection: Sendable {
        var systemPercent: Double
        var userPercent: Double
        var idlePercent: Double
        var systemHistory: [Double]
        var userHistory: [Double]
    }
    
    struct MemorySection: Sendable {
        var pressurePercent: Double
        var pressureHistory: [Double]
        var physicalMemoryMB: Double
        var usedMemoryMB: Double
        var cachedFilesMB: Double
        var swapUsedMB: Double
        var appMemoryMB: Double
        var wiredMemoryMB: Double
        var compressedMemoryMB: Double
    }
    
    var cpu: CPUSection
    var memory: MemorySection
    
    static let empty = BottomBarMetrics(
        cpu: CPUSection(
            systemPercent: 0,
            userPercent: 0,
            idlePercent: 100,
            systemHistory: [0],
            userHistory: [0]
        ),
        memory: MemorySection(
            pressurePercent: 0,
            pressureHistory: [0],
            physicalMemoryMB: 0,
            usedMemoryMB: 0,
            cachedFilesMB: 0,
            swapUsedMB: 0,
            appMemoryMB: 0,
            wiredMemoryMB: 0,
            compressedMemoryMB: 0
        )
    )
}

struct BottomBarRawSnapshot: Sendable {
    let cpuTicks: SystemMetricsCollector.CPUTicks
    let memory: SystemMetricsCollector.MemorySnapshot
}

struct BottomBarHistory {
    let historyLimit: Int
    private var previousCPUTicks: SystemMetricsCollector.CPUTicks?
    private var systemHistory: [Double] = []
    private var userHistory: [Double] = []
    private var pressureHistory: [Double] = []
    
    init(historyLimit: Int) {
        self.historyLimit = max(1, historyLimit)
    }
    
    mutating func nextMetrics(from snapshot: BottomBarRawSnapshot) -> BottomBarMetrics {
        let cpu = cpuPercentages(for: snapshot.cpuTicks)
        let memoryPressure = clamp(snapshot.memory.pressureRatio, min: 0, max: 1)
        
        BottomBarHistory.append(cpu.system, to: &systemHistory, limit: historyLimit)
        BottomBarHistory.append(cpu.user, to: &userHistory, limit: historyLimit)
        BottomBarHistory.append(memoryPressure, to: &pressureHistory, limit: historyLimit)
        
        return BottomBarMetrics(
            cpu: .init(
                systemPercent: cpu.system,
                userPercent: cpu.user,
                idlePercent: cpu.idle,
                systemHistory: systemHistory,
                userHistory: userHistory
            ),
            memory: .init(
                pressurePercent: memoryPressure * 100,
                pressureHistory: pressureHistory,
                physicalMemoryMB: snapshot.memory.physicalMemoryMB,
                usedMemoryMB: snapshot.memory.usedMemoryMB,
                cachedFilesMB: snapshot.memory.cachedFilesMB,
                swapUsedMB: snapshot.memory.swapUsedMB,
                appMemoryMB: snapshot.memory.appMemoryMB,
                wiredMemoryMB: snapshot.memory.wiredMemoryMB,
                compressedMemoryMB: snapshot.memory.compressedMemoryMB
            )
        )
    }
    
    private mutating func cpuPercentages(for currentTicks: SystemMetricsCollector.CPUTicks) -> (system: Double, user: Double, idle: Double) {
        defer {
            previousCPUTicks = currentTicks
        }
        
        if let previousCPUTicks,
           let delta = currentTicks.delta(from: previousCPUTicks),
           delta.total > 0 {
            let total = Double(delta.total)
            let userPercent = (Double(delta.user + delta.nice) / total) * 100
            let systemPercent = (Double(delta.system) / total) * 100
            let idlePercent = (Double(delta.idle) / total) * 100
            return (
                clamp(systemPercent, min: 0, max: 100),
                clamp(userPercent, min: 0, max: 100),
                clamp(idlePercent, min: 0, max: 100)
            )
        }
        
        let total = Double(currentTicks.total)
        guard total > 0 else {
            return (0, 0, 100)
        }
        
        let userPercent = (Double(currentTicks.user + currentTicks.nice) / total) * 100
        let systemPercent = (Double(currentTicks.system) / total) * 100
        let idlePercent = (Double(currentTicks.idle) / total) * 100
        return (
            clamp(systemPercent, min: 0, max: 100),
            clamp(userPercent, min: 0, max: 100),
            clamp(idlePercent, min: 0, max: 100)
        )
    }
    
    private static func append(_ value: Double, to history: inout [Double], limit: Int) {
        history.append(value)
        if history.count > limit {
            history.removeFirst(history.count - limit)
        }
    }
    
    private func clamp(_ value: Double, min lowerBound: Double, max upperBound: Double) -> Double {
        guard value.isFinite else { return lowerBound }
        if value < lowerBound { return lowerBound }
        if value > upperBound { return upperBound }
        return value
    }
}

enum SystemMetricsCollector {
    struct CPUTicks: Sendable {
        let user: UInt64
        let system: UInt64
        let idle: UInt64
        let nice: UInt64
        
        var total: UInt64 {
            user &+ system &+ idle &+ nice
        }
        
        func delta(from previous: CPUTicks) -> CPUTicks? {
            guard user >= previous.user,
                  system >= previous.system,
                  idle >= previous.idle,
                  nice >= previous.nice else {
                return nil
            }
            
            return CPUTicks(
                user: user - previous.user,
                system: system - previous.system,
                idle: idle - previous.idle,
                nice: nice - previous.nice
            )
        }
        
        static let zero = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
    }
    
    struct MemorySnapshot: Sendable {
        let pressureRatio: Double
        let physicalMemoryMB: Double
        let usedMemoryMB: Double
        let cachedFilesMB: Double
        let swapUsedMB: Double
        let appMemoryMB: Double
        let wiredMemoryMB: Double
        let compressedMemoryMB: Double
    }
    
    private static let bytesPerMB = 1024.0 * 1024.0
    static func capture() -> BottomBarRawSnapshot {
        BottomBarRawSnapshot(
            cpuTicks: readCPUTicks(),
            memory: readMemorySnapshot()
        )
    }
    
    private static func readCPUTicks() -> CPUTicks {
        var cpuInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        
        let result: kern_return_t = withUnsafeMutablePointer(to: &cpuInfo) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPointer, &count)
            }
        }
        
        guard result == KERN_SUCCESS else {
            return .zero
        }
        
        return CPUTicks(
            user: UInt64(cpuInfo.cpu_ticks.0),
            system: UInt64(cpuInfo.cpu_ticks.1),
            idle: UInt64(cpuInfo.cpu_ticks.2),
            nice: UInt64(cpuInfo.cpu_ticks.3)
        )
    }
    
    private static func readMemorySnapshot() -> MemorySnapshot {
        let physicalMemoryMB = Double(Foundation.ProcessInfo.processInfo.physicalMemory) / bytesPerMB
        
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let pageBytes = Double(max(pageSize, 1))
        let pageToMB = pageBytes / bytesPerMB
        
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        
        let result: kern_return_t = withUnsafeMutablePointer(to: &vmStats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPointer, &count)
            }
        }
        
        guard result == KERN_SUCCESS else {
            return MemorySnapshot(
                pressureRatio: 0,
                physicalMemoryMB: physicalMemoryMB,
                usedMemoryMB: 0,
                cachedFilesMB: 0,
                swapUsedMB: readSwapUsedMB(),
                appMemoryMB: 0,
                wiredMemoryMB: 0,
                compressedMemoryMB: 0
            )
        }
        
        let appMemoryMB = sanitize(Double(vmStats.internal_page_count) * pageToMB)
        let wiredMemoryMB = sanitize(Double(vmStats.wire_count) * pageToMB)
        let compressedMemoryMB = sanitize(Double(vmStats.compressor_page_count) * pageToMB)
        let cachedFilesMB = sanitize(Double(vmStats.external_page_count + vmStats.purgeable_count) * pageToMB)
        let usedMemoryMB = sanitize(appMemoryMB + wiredMemoryMB + compressedMemoryMB)
        let pressureRatio = physicalMemoryMB > 0
            ? min(max(usedMemoryMB / physicalMemoryMB, 0), 1)
            : 0
        
        return MemorySnapshot(
            pressureRatio: pressureRatio,
            physicalMemoryMB: physicalMemoryMB,
            usedMemoryMB: usedMemoryMB,
            cachedFilesMB: cachedFilesMB,
            swapUsedMB: readSwapUsedMB(),
            appMemoryMB: appMemoryMB,
            wiredMemoryMB: wiredMemoryMB,
            compressedMemoryMB: compressedMemoryMB
        )
    }
    
    private static func readSwapUsedMB() -> Double {
        var swapUsage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        
        let result = withUnsafeMutablePointer(to: &swapUsage) { pointer in
            sysctlbyname("vm.swapusage", pointer, &size, nil, 0)
        }
        
        guard result == 0 else {
            return 0
        }
        
        return sanitize(Double(swapUsage.xsu_used) / bytesPerMB)
    }
    
    private static func sanitize(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return max(0, value)
    }
}

struct SystemGroupCPUSmoother: Sendable {
    let windowSize: Int
    private var samples: [Double] = []
    private let systemGroupName = "システム"
    
    init(windowSize: Int) {
        self.windowSize = max(1, windowSize)
    }
    
    mutating func smooth(groups: [ProcessGroup]) -> [ProcessGroup] {
        guard let systemIndex = groups.firstIndex(where: { $0.appName == systemGroupName }) else {
            samples.removeAll()
            return groups
        }
        
        var adjustedGroups = groups
        let rawSystemCPU = adjustedGroups[systemIndex].rawTotalCPU
        
        samples.append(rawSystemCPU)
        if samples.count > windowSize {
            samples.removeFirst(samples.count - windowSize)
        }
        
        let smoothedSystemCPU = samples.reduce(0, +) / Double(samples.count)
        adjustedGroups[systemIndex].smoothedTotalCPU = smoothedSystemCPU
        return adjustedGroups
    }
}

struct CPUUsageDeltaState: Sendable {
    var cpuTimeTicksByPID: [Int32: UInt64] = [:]
    var sampleTimestampNanoseconds: UInt64?
    
    mutating func removeHistory(forPIDs pids: Set<Int32>) {
        guard !pids.isEmpty else { return }
        cpuTimeTicksByPID = cpuTimeTicksByPID.filter { !pids.contains($0.key) }
    }
}

struct CPUUsageDeltaComputation: Sendable {
    let processes: [AppProcessInfo]
    let state: CPUUsageDeltaState
    let hasValidElapsedInterval: Bool
}

enum CPUUsageDeltaCalculator {
    static let minimumSamplingIntervalNanoseconds: UInt64 = 500_000_000
    
    static func calculate(
        processes: [AppProcessInfo],
        previousState: CPUUsageDeltaState,
        timestampNanoseconds: UInt64
    ) -> CPUUsageDeltaComputation {
        let pids = Set(processes.map(\.pid))
        let currentCPUTimeTicksByPID = readCurrentCPUTimeTicks(pids: pids)
        
        return calculate(
            processes: processes,
            currentCPUTimeTicksByPID: currentCPUTimeTicksByPID,
            previousState: previousState,
            timestampNanoseconds: timestampNanoseconds,
            timebaseNumer: systemTimebase.numer,
            timebaseDenom: systemTimebase.denom,
            minimumElapsedNanoseconds: minimumSamplingIntervalNanoseconds
        )
    }
    
    static func calculate(
        processes: [AppProcessInfo],
        currentCPUTimeTicksByPID: [Int32: UInt64],
        previousState: CPUUsageDeltaState,
        timestampNanoseconds: UInt64,
        timebaseNumer: UInt32,
        timebaseDenom: UInt32,
        minimumElapsedNanoseconds: UInt64 = minimumSamplingIntervalNanoseconds
    ) -> CPUUsageDeltaComputation {
        var adjusted = processes
        let elapsedNanoseconds = elapsedNanoseconds(
            previousTimestamp: previousState.sampleTimestampNanoseconds,
            currentTimestamp: timestampNanoseconds,
            minimumRequiredNanoseconds: minimumElapsedNanoseconds
        )
        let hasValidElapsedInterval = elapsedNanoseconds != nil
        
        if let elapsedNanoseconds, elapsedNanoseconds > 0 {
            for index in adjusted.indices {
                let pid = adjusted[index].pid
                guard let currentTicks = currentCPUTimeTicksByPID[pid] else { continue }
                guard let previousTicks = previousState.cpuTimeTicksByPID[pid] else {
                    adjusted[index].cpuUsage = 0
                    continue
                }
                
                guard currentTicks >= previousTicks else {
                    adjusted[index].cpuUsage = 0
                    continue
                }
                
                let cpuDeltaTicks = currentTicks - previousTicks
                let cpuDeltaNanoseconds = ticksToNanoseconds(
                    cpuDeltaTicks,
                    numer: timebaseNumer,
                    denom: timebaseDenom
                )
                let computedCPU = (cpuDeltaNanoseconds / Double(elapsedNanoseconds)) * 100
                
                if computedCPU.isFinite && computedCPU >= 0 {
                    adjusted[index].cpuUsage = computedCPU
                } else {
                    adjusted[index].cpuUsage = 0
                }
            }
        } else {
            for index in adjusted.indices {
                adjusted[index].cpuUsage = 0
            }
        }
        
        return CPUUsageDeltaComputation(
            processes: adjusted,
            state: CPUUsageDeltaState(
                cpuTimeTicksByPID: currentCPUTimeTicksByPID,
                sampleTimestampNanoseconds: timestampNanoseconds
            ),
            hasValidElapsedInterval: hasValidElapsedInterval
        )
    }
    
    private static let taskInfoSize = Int32(MemoryLayout<proc_taskinfo>.stride)
    private static let systemTimebase: mach_timebase_info_data_t = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        if timebase.denom == 0 {
            timebase.denom = 1
        }
        return timebase
    }()
    
    static func ticksToNanoseconds(_ ticks: UInt64, numer: UInt32, denom: UInt32) -> Double {
        guard denom != 0 else { return 0 }
        return (Double(ticks) * Double(numer)) / Double(denom)
    }
    
    private static func readCurrentCPUTimeTicks(pids: Set<Int32>) -> [Int32: UInt64] {
        var cpuTicksByPID: [Int32: UInt64] = [:]
        cpuTicksByPID.reserveCapacity(pids.count)
        
        for pid in pids {
            guard let cpuTicks = readCPUTimeTicks(pid: pid) else { continue }
            cpuTicksByPID[pid] = cpuTicks
        }
        
        return cpuTicksByPID
    }
    
    private static func readCPUTimeTicks(pid: Int32) -> UInt64? {
        var taskInfo = proc_taskinfo()
        let result = proc_pidinfo(
            pid,
            PROC_PIDTASKINFO,
            0,
            &taskInfo,
            taskInfoSize
        )
        
        guard result == taskInfoSize else { return nil }
        return taskInfo.pti_total_user &+ taskInfo.pti_total_system
    }
    
    private static func elapsedNanoseconds(
        previousTimestamp: UInt64?,
        currentTimestamp: UInt64,
        minimumRequiredNanoseconds: UInt64
    ) -> UInt64? {
        guard let previousTimestamp, currentTimestamp > previousTimestamp else {
            return nil
        }
        let elapsed = currentTimestamp - previousTimestamp
        guard elapsed >= minimumRequiredNanoseconds else { return nil }
        return elapsed
    }
}

struct UsageSmoother: Sendable {
    private struct ProcessHistoryKey: Hashable, Sendable {
        let pid: Int32
        let name: String
    }
    
    private struct UsageSamples: Sendable {
        var cpuSamples: [Double] = []
        var memorySamples: [Double] = []
        
        mutating func append(cpu: Double, memory: Double, maxCount: Int) {
            if cpu.isFinite {
                cpuSamples.append(cpu)
                if cpuSamples.count > maxCount {
                    cpuSamples.removeFirst(cpuSamples.count - maxCount)
                }
            }
            
            if memory.isFinite {
                memorySamples.append(memory)
                if memorySamples.count > maxCount {
                    memorySamples.removeFirst(memorySamples.count - maxCount)
                }
            }
        }
        
        var averagedCPU: Double {
            guard !cpuSamples.isEmpty else { return 0 }
            return cpuSamples.reduce(0, +) / Double(cpuSamples.count)
        }
        
        var averagedMemory: Double {
            guard !memorySamples.isEmpty else { return 0 }
            return memorySamples.reduce(0, +) / Double(memorySamples.count)
        }
    }
    
    let windowSize: Int
    private var samplesByProcess: [ProcessHistoryKey: UsageSamples] = [:]
    
    init(windowSize: Int) {
        self.windowSize = max(1, windowSize)
    }
    
    mutating func smooth(processes: [AppProcessInfo]) -> [AppProcessInfo] {
        var activeKeys: Set<ProcessHistoryKey> = []
        var smoothedProcesses: [AppProcessInfo] = []
        smoothedProcesses.reserveCapacity(processes.count)
        
        for var process in processes {
            let key = ProcessHistoryKey(pid: process.pid, name: process.name)
            activeKeys.insert(key)
            
            var samples = samplesByProcess[key] ?? UsageSamples()
            samples.append(cpu: process.cpuUsage, memory: process.memoryUsage, maxCount: windowSize)
            samplesByProcess[key] = samples
            
            process.cpuUsage = samples.averagedCPU
            process.memoryUsage = samples.averagedMemory
            smoothedProcesses.append(process)
        }
        
        samplesByProcess = samplesByProcess.filter { activeKeys.contains($0.key) }
        return smoothedProcesses
    }
    
    mutating func removeHistory(forPIDs pids: [Int32]) {
        removeHistory(forPIDs: Set(pids))
    }
    
    mutating func removeHistory(forPIDs pids: Set<Int32>) {
        guard !pids.isEmpty else { return }
        samplesByProcess = samplesByProcess.filter { !pids.contains($0.key.pid) }
    }
}

enum ProcessSnapshotBuilder {
    private static let psLineRegex = try? NSRegularExpression(
        pattern: #"^\s*(\S+)\s+(\d+)\s+([0-9.]+)\s+([0-9.]+)\s+(.*)$"#
    )
    
    private struct ExecutablePathCacheEntry {
        let commandSignature: String
        let executablePath: String
    }
    
    private struct ExecutablePathMissKey: Hashable {
        let pid: Int32
        let commandSignature: String
    }
    
    private enum ExecutablePathCacheKey: Hashable {
        case hit(Int32)
        case miss(ExecutablePathMissKey)
    }
    
    private static let executablePathCacheLimit = 4096
    private static let executablePathCacheCompactionThreshold = 1024
    private static var executablePathCache: [Int32: ExecutablePathCacheEntry] = [:]
    private static var executablePathMissCache: Set<ExecutablePathMissKey> = []
    private static var executablePathCacheOrder: [ExecutablePathCacheKey] = []
    private static var executablePathCacheHeadIndex = 0
    private static let executablePathCacheLock = NSLock()
    
    static func fetchProcesses() throws -> [AppProcessInfo] {
        let output = try runPS()
        return parseProcesses(output)
    }
    
    static func makeDisplaySnapshot(
        _ processes: [AppProcessInfo],
        sortBy: ProcessMonitor.SortOption,
        filterText: String,
        showHighUsageFirst: Bool = false
    ) throws -> (processes: [AppProcessInfo], groups: [ProcessGroup]) {
        let visibleProcesses = try sortProcessesCancellable(
            processes,
            sortBy: sortBy,
            filterText: filterText,
            showHighUsageFirst: showHighUsageFirst
        )
        let groups = try groupProcessesCancellable(
            visibleProcesses,
            sortBy: sortBy,
            showHighUsageFirst: showHighUsageFirst
        )
        return (visibleProcesses, groups)
    }
    
    static func sortProcesses(
        _ processes: [AppProcessInfo],
        sortBy: ProcessMonitor.SortOption,
        filterText: String,
        showHighUsageFirst: Bool = false
    ) -> [AppProcessInfo] {
        do {
            return try sortProcessesCancellable(
                processes,
                sortBy: sortBy,
                filterText: filterText,
                showHighUsageFirst: showHighUsageFirst
            )
        } catch {
            return []
        }
    }
    
    static func sortProcessesCancellable(
        _ processes: [AppProcessInfo],
        sortBy: ProcessMonitor.SortOption,
        filterText: String,
        showHighUsageFirst: Bool = false
    ) throws -> [AppProcessInfo] {
        var checkCounter = 0
        try checkCancellation(counter: &checkCounter)
        
        let normalizedFilterText = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: [AppProcessInfo]
        
        if normalizedFilterText.isEmpty {
            filtered = processes
        } else {
            var matched: [AppProcessInfo] = []
            matched.reserveCapacity(processes.count)
            
            for process in processes {
                try checkCancellation(counter: &checkCounter)
                if process.name.localizedCaseInsensitiveContains(normalizedFilterText) ||
                    process.description.localizedCaseInsensitiveContains(normalizedFilterText) {
                    matched.append(process)
                }
            }
            filtered = matched
        }
        
        let comparator = processComparator(
            sortBy: sortBy,
            showHighUsageFirst: showHighUsageFirst
        )
        
        return try stableMergeSort(
            filtered,
            by: comparator,
            checkCounter: &checkCounter
        )
    }
    
    static func groupProcesses(
        _ processes: [AppProcessInfo],
        sortBy: ProcessMonitor.SortOption,
        showHighUsageFirst: Bool = false
    ) -> [ProcessGroup] {
        do {
            return try groupProcessesCancellable(
                processes,
                sortBy: sortBy,
                showHighUsageFirst: showHighUsageFirst
            )
        } catch {
            return []
        }
    }
    
    static func groupProcessesCancellable(
        _ processes: [AppProcessInfo],
        sortBy: ProcessMonitor.SortOption,
        showHighUsageFirst: Bool = false
    ) throws -> [ProcessGroup] {
        var checkCounter = 0
        try checkCancellation(counter: &checkCounter)
        
        var groupDict: [String: [AppProcessInfo]] = [:]
        groupDict.reserveCapacity(processes.count)
        
        for process in processes {
            try checkCancellation(counter: &checkCounter)
            
            let groupName = process.parentApp ?? (process.isSystemProcess ? "システム" : process.name)
            groupDict[groupName, default: []].append(process)
        }
        
        var groups: [ProcessGroup] = []
        groups.reserveCapacity(groupDict.count)
        
        for (groupName, groupedProcesses) in groupDict {
            try checkCancellation(counter: &checkCounter)
            groups.append(ProcessGroup(appName: groupName, processes: groupedProcesses))
        }
        
        let comparator = groupComparator(
            sortBy: sortBy,
            showHighUsageFirst: showHighUsageFirst
        )
        
        return try stableMergeSort(
            groups,
            by: comparator,
            checkCounter: &checkCounter
        )
    }
    
    private static func processComparator(
        sortBy: ProcessMonitor.SortOption,
        showHighUsageFirst: Bool
    ) -> (AppProcessInfo, AppProcessInfo) -> Bool {
        let descending = showHighUsageFirst
        
        return { lhs, rhs in
            let lhsMetric: Double
            let rhsMetric: Double
            
            switch sortBy {
            case .cpu:
                lhsMetric = lhs.cpuUsage
                rhsMetric = rhs.cpuUsage
            case .memory:
                lhsMetric = lhs.memoryUsage
                rhsMetric = rhs.memoryUsage
            }
            
            let lhsValue = normalizedSortValue(lhsMetric, descending: descending)
            let rhsValue = normalizedSortValue(rhsMetric, descending: descending)
            
            if lhsValue != rhsValue {
                return descending ? lhsValue > rhsValue : lhsValue < rhsValue
            }
            
            let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return lhs.pid < rhs.pid
        }
    }
    
    private static func groupComparator(
        sortBy: ProcessMonitor.SortOption,
        showHighUsageFirst: Bool
    ) -> (ProcessGroup, ProcessGroup) -> Bool {
        let descending = showHighUsageFirst
        
        return { lhs, rhs in
            let lhsMetric: Double
            let rhsMetric: Double
            
            switch sortBy {
            case .cpu:
                lhsMetric = lhs.totalCPU
                rhsMetric = rhs.totalCPU
            case .memory:
                lhsMetric = lhs.totalMemory
                rhsMetric = rhs.totalMemory
            }
            
            let lhsValue = normalizedSortValue(lhsMetric, descending: descending)
            let rhsValue = normalizedSortValue(rhsMetric, descending: descending)
            
            if lhsValue != rhsValue {
                return descending ? lhsValue > rhsValue : lhsValue < rhsValue
            }
            
            return lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) == .orderedAscending
        }
    }
    
    private static func stableMergeSort<T>(
        _ values: [T],
        by areInOrder: (T, T) -> Bool,
        checkCounter: inout Int
    ) throws -> [T] {
        guard values.count > 1 else {
            return values
        }
        
        var source = values
        var destination = values
        var width = 1
        
        while width < source.count {
            var start = 0
            while start < source.count {
                try checkCancellation(counter: &checkCounter)
                
                let middle = min(start + width, source.count)
                let end = min(start + (2 * width), source.count)
                
                try mergeRuns(
                    source: source,
                    destination: &destination,
                    start: start,
                    middle: middle,
                    end: end,
                    by: areInOrder,
                    checkCounter: &checkCounter
                )
                
                start += (2 * width)
            }
            
            swap(&source, &destination)
            width *= 2
        }
        
        return source
    }
    
    private static func mergeRuns<T>(
        source: [T],
        destination: inout [T],
        start: Int,
        middle: Int,
        end: Int,
        by areInOrder: (T, T) -> Bool,
        checkCounter: inout Int
    ) throws {
        var left = start
        var right = middle
        var index = start
        
        while left < middle && right < end {
            try checkCancellation(counter: &checkCounter)
            
            if areInOrder(source[left], source[right]) {
                destination[index] = source[left]
                left += 1
            } else if areInOrder(source[right], source[left]) {
                destination[index] = source[right]
                right += 1
            } else {
                // 同値の場合は左側を優先してstable sortを維持する。
                destination[index] = source[left]
                left += 1
            }
            index += 1
        }
        
        while left < middle {
            try checkCancellation(counter: &checkCounter)
            destination[index] = source[left]
            left += 1
            index += 1
        }
        
        while right < end {
            try checkCancellation(counter: &checkCounter)
            destination[index] = source[right]
            right += 1
            index += 1
        }
    }
    
    private static func checkCancellation(counter: inout Int) throws {
        counter += 1
        if counter % cancellationCheckStride == 0 {
            try Task.checkCancellation()
        }
    }
    
    private static func normalizedSortValue(_ value: Double, descending: Bool) -> Double {
        guard value.isFinite else {
            return descending ? -.greatestFiniteMagnitude : .greatestFiniteMagnitude
        }
        return value
    }
    
    private static let cancellationCheckStride = 128
    
    private static func runPS() throws -> String {
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "user=,pid=,%cpu=,%mem=,command="]
        
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        
        guard task.terminationStatus == 0 else {
            throw NSError(
                domain: "ProcessSnapshotBuilder",
                code: Int(task.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "ps command exited with status \(task.terminationStatus)."]
            )
        }
        
        guard let output = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "ProcessSnapshotBuilder",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to decode ps output."]
            )
        }
        
        return output
    }
    
    static func parseProcesses(_ output: String) -> [AppProcessInfo] {
        var newProcesses: [AppProcessInfo] = []
        let lines = output.components(separatedBy: "\n")
        let physicalMemoryGB = getPhysicalMemoryGB()
        
        for line in lines {
            guard let parsed = parsePSLine(line) else { continue }
            
            let user = parsed.user
            let pid = parsed.pid
            let cpu = parsed.cpu
            let mem = parsed.mem
            let commandPath = parsed.command
            let executablePath = resolveExecutablePath(pid: pid, commandPath: commandPath)
            let processName = executablePath.map(extractProcessName(fromExecutablePath:)) ?? extractProcessName(fromCommandPath: commandPath)
            let memoryMB = mem * physicalMemoryGB * 10.24
            let isSystemProcess = ProcessDescriptions.isSystemProcess(processName) || isSystemPath(executablePath)
            
            let process = AppProcessInfo(
                pid: pid,
                name: processName,
                user: user,
                cpuUsage: cpu,
                memoryUsage: memoryMB,
                description: ProcessDescriptions.getDescription(
                    for: processName,
                    executablePath: executablePath
                ),
                isSystemProcess: isSystemProcess,
                parentApp: extractParentApp(from: executablePath ?? commandPath),
                executablePath: executablePath
            )
            
            newProcesses.append(process)
        }
        
        return newProcesses
    }
    
    private static func parsePSLine(_ line: String) -> (user: String, pid: Int32, cpu: Double, mem: Double, command: String)? {
        guard let regex = psLineRegex else { return nil }
        let range = NSRange(location: 0, length: line.utf16.count)
        guard let match = regex.firstMatch(in: line, range: range), match.numberOfRanges == 6 else {
            return nil
        }
        
        func capture(_ index: Int) -> String {
            guard let captureRange = Range(match.range(at: index), in: line) else { return "" }
            return String(line[captureRange])
        }
        
        let user = capture(1)
        guard let pid = Int32(capture(2)) else { return nil }
        guard let cpu = Double(capture(3)) else { return nil }
        guard let mem = Double(capture(4)) else { return nil }
        let command = capture(5)
        
        guard !user.isEmpty, !command.isEmpty else { return nil }
        return (user: user, pid: pid, cpu: cpu, mem: mem, command: command)
    }
    
    private static func extractProcessName(fromExecutablePath executablePath: String) -> String {
        let normalizedPath = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = URL(fileURLWithPath: normalizedPath).lastPathComponent
        
        if name.hasSuffix(".app") {
            return String(name.dropLast(4))
        }
        
        return name
    }
    
    private static func extractProcessName(fromCommandPath commandPath: String) -> String {
        let path = commandPath.components(separatedBy: " ").first ?? commandPath
        let name = path.components(separatedBy: "/").last ?? path
        
        if name.hasSuffix(".app") {
            return String(name.dropLast(4))
        }
        
        return name
    }
    
    private static func extractParentApp(from commandPath: String) -> String? {
        if let range = commandPath.range(of: ".app") {
            let beforeApp = commandPath[..<range.lowerBound]
            let components = beforeApp.components(separatedBy: "/")
            if let appName = components.last {
                return appName
            }
        }
        return nil
    }
    
    private static func extractExecutablePath(from commandPath: String) -> String? {
        let trimmed = commandPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        if !trimmed.contains(" ") {
            return trimmed
        }
        
        if trimmed.hasPrefix("/"),
           let bundleExecutablePath = extractBundleExecutablePath(from: trimmed) {
            return bundleExecutablePath
        }
        
        let firstToken = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first
        guard let firstToken else { return nil }
        let executable = String(firstToken)
        return executable.isEmpty ? nil : executable
    }
    
    private static func resolveExecutablePath(pid: Int32, commandPath: String) -> String? {
        let commandExecutablePath = extractExecutablePath(from: commandPath)
        if let commandExecutablePath,
           shouldTrustCommandExecutablePath(commandExecutablePath, originalCommandPath: commandPath),
           let validatedCommandPath = validatedExecutablePath(commandExecutablePath) {
            cacheExecutablePath(
                pid: pid,
                commandSignature: commandSignature(from: validatedCommandPath),
                executablePath: validatedCommandPath
            )
            return validatedCommandPath
        }
        
        let signature = commandSignature(from: commandExecutablePath ?? commandPath)
        
        if let cachedPath = cachedExecutablePath(pid: pid, commandSignature: signature) {
            return cachedPath
        }
        
        if isExecutablePathKnownMiss(pid: pid, commandSignature: signature) {
            return validatedExecutablePath(commandExecutablePath)
        }
        
        if let pidPath = executablePathFromPID(pid: pid),
           let validatedPIDPath = validatedExecutablePath(pidPath) {
            cacheExecutablePath(
                pid: pid,
                commandSignature: signature,
                executablePath: validatedPIDPath
            )
            return validatedPIDPath
        }
        
        if let commandExecutablePath,
           shouldUseCommandExecutablePath(commandExecutablePath),
           let validatedCommandPath = validatedExecutablePath(commandExecutablePath) {
            cacheExecutablePath(
                pid: pid,
                commandSignature: signature,
                executablePath: validatedCommandPath
            )
            return validatedCommandPath
        }
        
        cacheExecutablePathMiss(pid: pid, commandSignature: signature)
        return nil
    }
    
    private static func executablePathFromPID(pid: Int32) -> String? {
        let bufferSize = Int(MAXPATHLEN) * 4
        var buffer = [CChar](repeating: 0, count: bufferSize)
        let result = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard result > 0 else { return nil }
        return String(cString: buffer)
    }
    
    private static func isSystemPath(_ executablePath: String?) -> Bool {
        guard let executablePath else { return false }
        
        return executablePath.hasPrefix("/System/") ||
            executablePath.hasPrefix("/usr/libexec/") ||
            executablePath.hasPrefix("/usr/sbin/") ||
            executablePath.hasPrefix("/sbin/")
    }
    
    private static func getPhysicalMemoryGB() -> Double {
        Double(Foundation.ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
    }
    
    private static func shouldUseCommandExecutablePath(_ path: String) -> Bool {
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedPath.hasPrefix("/")
    }
    
    private static func validatedExecutablePath(_ path: String?) -> String? {
        guard let path else { return nil }
        
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty, normalizedPath.hasPrefix("/") else {
            return nil
        }
        
        guard FileManager.default.fileExists(atPath: normalizedPath) else {
            return nil
        }
        
        return normalizedPath
    }
    
    private static func shouldTrustCommandExecutablePath(_ extractedPath: String, originalCommandPath: String) -> Bool {
        guard shouldUseCommandExecutablePath(extractedPath) else {
            return false
        }
        
        let trimmedCommand = originalCommandPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedCommand.contains(" ") else {
            return true
        }
        
        // bundle path + spaces は引数切り分けが曖昧になりやすいので、
        // proc_pidpath を優先して正確な実行パスを取得する。
        if isBundleExecutablePath(extractedPath) {
            return false
        }
        
        return true
    }
    
    private static func extractBundleExecutablePath(from commandPath: String) -> String? {
        let markers = ["/Contents/MacOS/", "/Contents/XPCServices/"]
        guard let markerRange = markers.compactMap({
            commandPath.range(of: $0, options: .caseInsensitive)
        }).min(by: { $0.lowerBound < $1.lowerBound }) else {
            return nil
        }
        
        let searchStart = markerRange.upperBound
        let delimiterRanges = [
            commandPath.range(of: " --", range: searchStart..<commandPath.endIndex),
            commandPath.range(of: " /", range: searchStart..<commandPath.endIndex),
            commandPath.range(
                of: #"\s-[A-Za-z0-9_]"#,
                options: .regularExpression,
                range: searchStart..<commandPath.endIndex
            )
        ].compactMap { $0 }
        
        let endIndex = delimiterRanges
            .map(\.lowerBound)
            .min() ?? commandPath.endIndex
        
        let candidate = String(commandPath[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard candidate.hasPrefix("/"), isBundleExecutablePath(candidate) else {
            return nil
        }
        return candidate
    }
    
    private static func isBundleExecutablePath(_ path: String) -> Bool {
        let lowercasedPath = path.lowercased()
        return lowercasedPath.contains(".app/") ||
            lowercasedPath.contains(".xpc/") ||
            lowercasedPath.contains(".appex/") ||
            lowercasedPath.hasSuffix(".app") ||
            lowercasedPath.hasSuffix(".xpc") ||
            lowercasedPath.hasSuffix(".appex")
    }
    
    private static func commandSignature(from source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return String(trimmed.prefix(256))
    }
    
    private static func cachedExecutablePath(pid: Int32, commandSignature: String) -> String? {
        executablePathCacheLock.lock()
        defer { executablePathCacheLock.unlock() }
        
        guard let cached = executablePathCache[pid] else { return nil }
        guard cached.commandSignature == commandSignature else { return nil }
        guard let validatedPath = validatedExecutablePath(cached.executablePath) else {
            executablePathCache.removeValue(forKey: pid)
            return nil
        }
        return validatedPath
    }
    
    private static func isExecutablePathKnownMiss(pid: Int32, commandSignature: String) -> Bool {
        let missKey = ExecutablePathMissKey(pid: pid, commandSignature: commandSignature)
        
        executablePathCacheLock.lock()
        defer { executablePathCacheLock.unlock() }
        return executablePathMissCache.contains(missKey)
    }
    
    private static func cacheExecutablePath(pid: Int32, commandSignature: String, executablePath: String) {
        guard let validatedPath = validatedExecutablePath(executablePath) else {
            return
        }
        
        executablePathCacheLock.lock()
        defer { executablePathCacheLock.unlock() }

        if executablePathCache[pid] == nil {
            executablePathCacheOrder.append(.hit(pid))
        }
        executablePathCache[pid] = ExecutablePathCacheEntry(
            commandSignature: commandSignature,
            executablePath: validatedPath
        )

        let missKey = ExecutablePathMissKey(pid: pid, commandSignature: commandSignature)
        executablePathMissCache.remove(missKey)
        trimExecutablePathCachesIfNeeded()
    }
    
    private static func cacheExecutablePathMiss(pid: Int32, commandSignature: String) {
        executablePathCacheLock.lock()
        defer { executablePathCacheLock.unlock() }

        let missKey = ExecutablePathMissKey(pid: pid, commandSignature: commandSignature)
        if executablePathMissCache.insert(missKey).inserted {
            executablePathCacheOrder.append(.miss(missKey))
        }
        trimExecutablePathCachesIfNeeded()
    }
    
    private static func trimExecutablePathCachesIfNeeded() {
        while executablePathCache.count + executablePathMissCache.count > executablePathCacheLimit {
            if executablePathCacheHeadIndex >= executablePathCacheOrder.count {
                rebuildExecutablePathCacheOrder()
            }

            guard executablePathCacheHeadIndex < executablePathCacheOrder.count else {
                executablePathCache.removeAll(keepingCapacity: true)
                executablePathMissCache.removeAll(keepingCapacity: true)
                executablePathCacheOrder.removeAll(keepingCapacity: true)
                executablePathCacheHeadIndex = 0
                return
            }

            let oldest = executablePathCacheOrder[executablePathCacheHeadIndex]
            executablePathCacheHeadIndex += 1
            switch oldest {
            case .hit(let pid):
                executablePathCache.removeValue(forKey: pid)
            case .miss(let missKey):
                executablePathMissCache.remove(missKey)
            }
        }

        compactExecutablePathCacheOrderIfNeeded()
    }

    private static func rebuildExecutablePathCacheOrder() {
        executablePathCacheOrder = executablePathCache.keys.map(ExecutablePathCacheKey.hit)
        executablePathCacheOrder.append(
            contentsOf: executablePathMissCache.map(ExecutablePathCacheKey.miss)
        )
        executablePathCacheHeadIndex = 0
    }

    private static func compactExecutablePathCacheOrderIfNeeded() {
        guard executablePathCacheHeadIndex >= executablePathCacheCompactionThreshold,
              executablePathCacheHeadIndex * 2 >= executablePathCacheOrder.count else {
            return
        }

        executablePathCacheOrder.removeFirst(executablePathCacheHeadIndex)
        executablePathCacheHeadIndex = 0
    }
}
