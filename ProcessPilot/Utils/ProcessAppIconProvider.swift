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
    
    static func icon(forExecutablePath executablePath: String?) -> NSImage? {
        guard let bundlePath = appBundlePath(fromExecutablePath: executablePath) else {
            return nil
        }
        
        cacheLock.lock()
        if let cached = iconCache[bundlePath] {
            cacheLock.unlock()
            return cached
        }
        
        if missCache.contains(bundlePath) {
            cacheLock.unlock()
            return nil
        }
        cacheLock.unlock()
        
        guard FileManager.default.fileExists(atPath: bundlePath) else {
            cacheLock.lock()
            if missCache.insert(bundlePath).inserted {
                missCacheOrder.append(bundlePath)
            }
            trimCachesIfNeededLocked()
            cacheLock.unlock()
            return nil
        }
        
        let image = NSWorkspace.shared.icon(forFile: bundlePath)
        image.size = NSSize(width: 64, height: 64)
        
        cacheLock.lock()
        if iconCache[bundlePath] == nil {
            iconCacheOrder.append(bundlePath)
        }
        iconCache[bundlePath] = image
        missCache.remove(bundlePath)
        trimCachesIfNeededLocked()
        cacheLock.unlock()
        return image
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
