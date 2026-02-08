import Foundation
import AppKit

enum ProcessAppIconProvider {
    private static let cacheLimit = 1024
    private static let compactionThreshold = 1024
    private static let cacheLock = NSLock()
    private static var iconCache: [String: NSImage] = [:]
    private static var iconCacheOrder: [String] = []
    private static var iconCacheHeadIndex = 0
    private static var missCache: Set<String> = []
    private static var missCacheOrder: [String] = []
    private static var missCacheHeadIndex = 0
    private static var inFlightLoads: [String: Task<Void, Never>] = [:]

    static func icon(forExecutablePath executablePath: String?) -> NSImage? {
        guard let bundlePath = appBundlePath(fromExecutablePath: executablePath) else {
            return nil
        }

        if let cached = cachedIcon(forBundlePath: bundlePath) {
            return cached
        }

        if isKnownMiss(bundlePath) {
            return nil
        }

        return loadAndCacheIconSynchronously(bundlePath: bundlePath)
    }

    static func cachedIcon(forExecutablePath executablePath: String?) -> NSImage? {
        guard let bundlePath = appBundlePath(fromExecutablePath: executablePath) else {
            return nil
        }

        return cachedIcon(forBundlePath: bundlePath)
    }

    static func loadIcon(forExecutablePath executablePath: String?) async -> NSImage? {
        guard let bundlePath = appBundlePath(fromExecutablePath: executablePath) else {
            return nil
        }

        if let cached = cachedIcon(forBundlePath: bundlePath) {
            return cached
        }

        if isKnownMiss(bundlePath) {
            return nil
        }

        let task = taskForAsyncLoad(bundlePath: bundlePath)
        await task.value
        return cachedIcon(forBundlePath: bundlePath)
    }

    private static func appBundlePath(fromExecutablePath executablePath: String?) -> String? {
        guard let executablePath else { return nil }
        let trimmed = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let nsPath = trimmed as NSString
        for marker in [".app/", ".appex/", ".xpc/"] {
            let markerRange = nsPath.range(of: marker, options: .caseInsensitive)
            if markerRange.location != NSNotFound {
                return nsPath.substring(to: markerRange.location + marker.count - 1)
            }
        }

        let lower = trimmed.lowercased()
        if lower.hasSuffix(".app") || lower.hasSuffix(".appex") || lower.hasSuffix(".xpc") {
            return trimmed
        }

        return nil
    }

    private static func cachedIcon(forBundlePath bundlePath: String) -> NSImage? {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        return iconCache[bundlePath]
    }

    private static func isKnownMiss(_ bundlePath: String) -> Bool {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return missCache.contains(bundlePath)
    }

    private static func taskForAsyncLoad(bundlePath: String) -> Task<Void, Never> {
        cacheLock.lock()
        if let existing = inFlightLoads[bundlePath] {
            cacheLock.unlock()
            return existing
        }

        let task = Task(priority: .utility) {
            await loadAndCacheIconAsynchronously(bundlePath: bundlePath)
        }
        inFlightLoads[bundlePath] = task
        cacheLock.unlock()
        return task
    }

    private static func loadAndCacheIconSynchronously(bundlePath: String) -> NSImage? {
        guard FileManager.default.fileExists(atPath: bundlePath) else {
            cacheMiss(forBundlePath: bundlePath)
            return nil
        }

        let image = loadIconImage(forBundlePath: bundlePath)
        cacheIcon(image, forBundlePath: bundlePath)
        return image
    }

    private static func loadAndCacheIconAsynchronously(bundlePath: String) async {
        defer {
            removeInFlightTask(forBundlePath: bundlePath)
        }

        guard FileManager.default.fileExists(atPath: bundlePath) else {
            cacheMiss(forBundlePath: bundlePath)
            return
        }

        let image = loadIconImage(forBundlePath: bundlePath)
        cacheIcon(image, forBundlePath: bundlePath)
    }

    private static func loadIconImage(forBundlePath bundlePath: String) -> NSImage {
        let image = NSWorkspace.shared.icon(forFile: bundlePath)
        image.size = NSSize(width: 64, height: 64)
        return image
    }

    private static func removeInFlightTask(forBundlePath bundlePath: String) {
        cacheLock.lock()
        inFlightLoads.removeValue(forKey: bundlePath)
        cacheLock.unlock()
    }

    private static func cacheIcon(_ image: NSImage, forBundlePath bundlePath: String) {
        cacheLock.lock()
        if iconCache[bundlePath] == nil {
            iconCacheOrder.append(bundlePath)
        }
        iconCache[bundlePath] = image
        missCache.remove(bundlePath)
        trimCachesIfNeededLocked()
        cacheLock.unlock()
    }

    private static func cacheMiss(forBundlePath bundlePath: String) {
        cacheLock.lock()
        if missCache.insert(bundlePath).inserted {
            missCacheOrder.append(bundlePath)
        }
        trimCachesIfNeededLocked()
        cacheLock.unlock()
    }

    private static func trimCachesIfNeededLocked() {
        while iconCache.count > cacheLimit {
            if iconCacheHeadIndex >= iconCacheOrder.count {
                iconCacheOrder = Array(iconCache.keys)
                iconCacheHeadIndex = 0
                if iconCacheOrder.isEmpty { break }
            }

            let oldest = iconCacheOrder[iconCacheHeadIndex]
            iconCacheHeadIndex += 1
            iconCache.removeValue(forKey: oldest)
        }
        compactIconCacheOrderIfNeededLocked()

        while missCache.count > cacheLimit {
            if missCacheHeadIndex >= missCacheOrder.count {
                missCacheOrder = Array(missCache)
                missCacheHeadIndex = 0
                if missCacheOrder.isEmpty { break }
            }

            let oldest = missCacheOrder[missCacheHeadIndex]
            missCacheHeadIndex += 1
            missCache.remove(oldest)
        }
        compactMissCacheOrderIfNeededLocked()
    }

    private static func compactIconCacheOrderIfNeededLocked() {
        guard iconCacheHeadIndex >= compactionThreshold,
              iconCacheHeadIndex * 2 >= iconCacheOrder.count else {
            return
        }

        iconCacheOrder.removeFirst(iconCacheHeadIndex)
        iconCacheHeadIndex = 0
    }

    private static func compactMissCacheOrderIfNeededLocked() {
        guard missCacheHeadIndex >= compactionThreshold,
              missCacheHeadIndex * 2 >= missCacheOrder.count else {
            return
        }

        missCacheOrder.removeFirst(missCacheHeadIndex)
        missCacheHeadIndex = 0
    }
}
