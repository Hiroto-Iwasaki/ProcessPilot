import Foundation

struct ProcessDescriptions {
    private typealias DescriptionCandidate = (key: String, value: String)
    
    private static let unresolvedDescription = "不明なプロセス"
    private static let bundleSuffixes = [".app", ".xpc", ".appex"]
    private static let bundlePathMarkers = [".app/", ".xpc/", ".appex/"]
    private static let bundleDescriptionCacheLimit = 2048
    private static let cacheOrderCompactionThreshold = 1024
    private static var bundleDescriptionCache: [String: String] = [:]
    private static var bundleDescriptionMissCache: Set<String> = []
    private static var bundleDescriptionCacheOrder: [String] = []
    private static var bundleDescriptionMissCacheOrder: [String] = []
    private static var bundleDescriptionCacheHeadIndex = 0
    private static var bundleDescriptionMissCacheHeadIndex = 0
    private static let cacheLock = NSLock()
    
    // 一般的なmacOSプロセスの説明辞書
    static let descriptions: [String: String] = [
        // カーネル・システム基幹
        "kernel_task": "macOSカーネル - システムの中核（終了不可）",
        "launchd": "システム・サービス管理デーモン（終了不可）",
        "WindowServer": "画面描画・ウィンドウ管理（終了不可）",
        "loginwindow": "ログイン画面とセッション管理",
        "SystemUIServer": "メニューバーとシステムUI管理",
        "Dock": "Dockとアプリケーション切り替え",
        "Finder": "ファイル管理とデスクトップ",
        
        // Spotlight・検索
        "mds": "Spotlight メタデータサーバー",
        "mds_stores": "Spotlight インデックス作成",
        "mdworker": "Spotlight インデックスワーカー",
        "mdworker_shared": "Spotlight 共有インデックス処理",
        
        // オーディオ・ビデオ
        "coreaudiod": "システムオーディオ管理",
        "audioclocksyncd": "オーディオ同期サービス",
        "VDCAssistant": "カメラ（FaceTime）制御",
        "avconferenced": "ビデオ会議サービス",
        
        // ネットワーク
        "networkd": "ネットワーク接続管理",
        "mDNSResponder": "Bonjour/ローカルネットワーク検出",
        "configd": "システム設定デーモン",
        "airportd": "Wi-Fi 管理",
        "WiFiAgent": "Wi-Fi 接続アシスタント",
        "bluetoothd": "Bluetooth 管理",
        
        // セキュリティ
        "securityd": "セキュリティフレームワーク",
        "trustd": "証明書検証サービス",
        "keybagd": "暗号化キー管理",
        "TouchBarServer": "Touch Bar 管理",
        "biomed": "生体認証管理",
        "secd": "セキュリティデーモン",
        
        // iCloud・同期
        "cloudd": "iCloud 同期サービス",
        "cloudpaird": "iCloud ペアリング",
        "cloudphotod": "iCloud 写真同期",
        "bird": "iCloud Drive 同期",
        "nsurlsessiond": "バックグラウンドダウンロード",
        "assistantd": "Siri アシスタント",
        
        // 通知・メッセージ
        "apsd": "Apple Push Notification Service",
        "notificationcenter": "通知センター",
        "usernoted": "ユーザー通知デーモン",
        "UserNotificationCenter": "通知表示管理",
        "imagent": "iMessage デーモン",
        "identityservicesd": "Apple ID 認証サービス",
        
        // グラフィック・GPU
        "MTLCompilerService": "Metal シェーダーコンパイル",
        "gpuinfod": "GPU 情報サービス",
        "distnoted": "分散通知サービス",
        
        // 電源・パフォーマンス
        "powerd": "電源管理デーモン",
        "thermalmonitord": "温度監視サービス",
        "coreduetd": "バッテリー最適化",
        "dasd": "デュエットアクティビティスケジューラ",
        
        // 入力・アクセシビリティ
        "hidd": "ヒューマンインターフェースデバイス管理",
        "universalaccessd": "アクセシビリティサービス",
        "talagent": "テキスト入力アシスタント",
        
        // ストレージ・ディスク
        "fseventsd": "ファイルシステムイベント監視",
        "diskarbitrationd": "ディスクマウント管理",
        "diskmanagementd": "ディスク管理サービス",
        "fsck_apfs": "APFS ファイルシステムチェック",
        
        // アプリケーション関連
        "lsd": "Launch Services デーモン",
        "coreservicesd": "コアサービス管理",
        "pbs": "ペーストボードサービス",
        "sharedfilelistd": "共有ファイルリスト管理",
        "iconservicesagent": "アイコンキャッシュサービス",
        
        // Time Machine
        "backupd": "Time Machine バックアップ",
        "backupd-helper": "Time Machine ヘルパー",
        
        // Xcode・開発ツール
        "Xcode": "統合開発環境",
        "sourcekit-servi": "Swift 言語サービス",
        "SourceKitService": "コード補完・分析",
        "swiftc": "Swift コンパイラ",
        "clang": "C/C++/Objective-C コンパイラ",
        "lldb": "デバッガ",
        "Simulator": "iOS/watchOS シミュレータ",
        "IBAgent": "Interface Builder エージェント",
        "xcrun": "Xcode コマンドラインツール",
        
        // ブラウザ
        "Safari": "Safari ウェブブラウザ",
        "com.apple.WebKi": "Safari レンダリングエンジン",
        "Safari Web Cont": "Safari ウェブコンテンツ",
        "Google Chrome": "Chrome ウェブブラウザ",
        "Google Chrome H": "Chrome ヘルパープロセス",
        "firefox": "Firefox ウェブブラウザ",
        
        // 一般的なアプリ
        "Mail": "メールクライアント",
        "Calendar": "カレンダーアプリ",
        "Notes": "メモアプリ",
        "Reminders": "リマインダーアプリ",
        "Music": "ミュージックアプリ",
        "Photos": "写真アプリ",
        "Preview": "ファイルプレビュー",
        "TextEdit": "テキストエディタ",
        "Terminal": "ターミナル",
        "Activity Monito": "アクティビティモニタ",
        "System Preferen": "システム環境設定",
        "App Store": "App Store",
        
        // 開発者ツール
        "node": "Node.js ランタイム",
        "python": "Python インタープリタ",
        "python3": "Python 3 インタープリタ",
        "ruby": "Ruby インタープリタ",
        "java": "Java 仮想マシン",
        "docker": "Docker コンテナエンジン",
        "code": "Visual Studio Code",
        "code-helper": "VS Code ヘルパー",
        
        // その他
        "cfprefsd": "設定ファイル管理",
        "logd": "システムログサービス",
        "syslogd": "システムログデーモン",
        "cron": "定期実行スケジューラ",
        "cupsd": "プリントサービス",
        "locationd": "位置情報サービス",
        "mediaremoted": "メディアリモート制御",
        "softwareupdated": "ソフトウェアアップデート",
        "syspolicyd": "システムポリシー管理",
        "commerce": "App Store 購入サービス",
        "storeaccountd": "App Store アカウント管理",
        "storeassetd": "App Store アセット管理",
    ]
    
    private static let partialDescriptionIndex: [Character: [DescriptionCandidate]] = {
        var index: [Character: [DescriptionCandidate]] = [:]
        
        for (key, value) in descriptions {
            let normalizedKey = key.lowercased()
            guard let initial = normalizedKey.first else { continue }
            index[initial, default: []].append((normalizedKey, value))
        }
        
        for key in index.keys {
            index[key]?.sort { lhs, rhs in
                lhs.key.count > rhs.key.count
            }
        }
        
        return index
    }()
    
    // システムプロセス（終了すると問題が起きる可能性があるもの）
    static let systemProcesses: Set<String> = [
        "kernel_task",
        "launchd",
        "WindowServer",
        "loginwindow",
        "SystemUIServer",
        "Dock",
        "Finder",
        "mds",
        "mds_stores",
        "coreaudiod",
        "networkd",
        "securityd",
        "trustd",
        "keybagd",
        "configd",
        "powerd",
        "thermalmonitord",
        "hidd",
        "fseventsd",
        "diskarbitrationd",
        "lsd",
        "coreservicesd",
        "cfprefsd",
        "logd",
        "syslogd",
        "apsd",
        "cloudd",
        "identityservicesd",
        "bluetoothd",
        "airportd",
        "locationd",
    ]
    
    // 終了不可プロセス
    static let criticalProcesses: Set<String> = [
        "kernel_task",
        "launchd",
        "WindowServer",
    ]
    
    static func getDescription(for processName: String, executablePath: String? = nil) -> String {
        let normalizedProcessName = processName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 完全一致で検索
        if let desc = descriptions[normalizedProcessName] {
            return desc
        }
        
        if let partialDescription = getPartialMatchDescription(for: normalizedProcessName) {
            return partialDescription
        }
        
        if shouldAttemptBundleDescriptionLookup(executablePath: executablePath),
           let bundleDescription = getBundleDescription(from: executablePath) {
            return bundleDescription
        }
        
        return unresolvedDescription
    }
    
    static func isSystemProcess(_ processName: String) -> Bool {
        systemProcesses.contains(processName) ||
        systemProcesses.contains { processName.hasPrefix($0) }
    }
    
    static func isCriticalProcess(_ processName: String) -> Bool {
        criticalProcesses.contains(processName) ||
        criticalProcesses.contains { processName.hasPrefix($0) }
    }
    
    private static func shouldAttemptBundleDescriptionLookup(executablePath: String?) -> Bool {
        guard let executablePath else { return false }
        
        let lowerPath = executablePath.lowercased()
        
        if bundleSuffixes.contains(where: { lowerPath.hasSuffix($0) }) {
            return true
        }
        
        return bundlePathMarkers.contains(where: { lowerPath.contains($0) })
    }
    
    private static func getBundleDescription(from executablePath: String?) -> String? {
        guard let executablePath else { return nil }
        guard let bundleURL = resolveBundleURL(from: executablePath) else { return nil }
        let bundleCacheKey = bundleURL.standardizedFileURL.path
        
        cacheLock.lock()
        if let cached = bundleDescriptionCache[bundleCacheKey] {
            cacheLock.unlock()
            return cached
        }
        if bundleDescriptionMissCache.contains(bundleCacheKey) {
            cacheLock.unlock()
            return nil
        }
        cacheLock.unlock()
        
        guard let bundleDescription = loadBundleDescription(from: bundleURL) else {
            cacheLock.lock()
            if bundleDescriptionMissCache.insert(bundleCacheKey).inserted {
                bundleDescriptionMissCacheOrder.append(bundleCacheKey)
            }
            trimBundleDescriptionMissCacheIfNeededLocked()
            cacheLock.unlock()
            return nil
        }
        
        cacheLock.lock()
        if bundleDescriptionCache[bundleCacheKey] == nil {
            bundleDescriptionCacheOrder.append(bundleCacheKey)
        }
        bundleDescriptionCache[bundleCacheKey] = bundleDescription
        bundleDescriptionMissCache.remove(bundleCacheKey)
        trimBundleDescriptionCacheIfNeededLocked()
        cacheLock.unlock()
        return bundleDescription
    }
    
    private static func resolveBundleURL(from executablePath: String) -> URL? {
        var currentURL = URL(fileURLWithPath: executablePath)
        
        while currentURL.path != "/" {
            let lowerPath = currentURL.path.lowercased()
            if bundleSuffixes.contains(where: { lowerPath.hasSuffix($0) }) {
                return currentURL
            }
            currentURL.deleteLastPathComponent()
        }
        
        return nil
    }
    
    private static func loadBundleDescription(from bundleURL: URL) -> String? {
        let infoPlistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        
        let bundleName = plist["CFBundleDisplayName"] as? String ?? plist["CFBundleName"] as? String
        let bundleIdentifier = plist["CFBundleIdentifier"] as? String
        
        switch (bundleName, bundleIdentifier) {
        case let (name?, identifier?) where !name.isEmpty && !identifier.isEmpty:
            return "\(name) (\(identifier))"
        case let (name?, _) where !name.isEmpty:
            return name
        case let (_, identifier?) where !identifier.isEmpty:
            return identifier
        default:
            return nil
        }
    }
    
    private static func getPartialMatchDescription(for processName: String) -> String? {
        let normalizedProcessName = processName.lowercased()
        guard let initial = normalizedProcessName.first,
              let candidates = partialDescriptionIndex[initial] else {
            return nil
        }
        
        for candidate in candidates where
            normalizedProcessName.hasPrefix(candidate.key) ||
            candidate.key.hasPrefix(normalizedProcessName) {
            return candidate.value
        }
        
        return nil
    }
    
    private static func trimBundleDescriptionCacheIfNeededLocked() {
        while bundleDescriptionCache.count > bundleDescriptionCacheLimit {
            if bundleDescriptionCacheHeadIndex >= bundleDescriptionCacheOrder.count {
                bundleDescriptionCacheOrder = Array(bundleDescriptionCache.keys)
                bundleDescriptionCacheHeadIndex = 0
                if bundleDescriptionCacheOrder.isEmpty { break }
            }
            
            let oldest = bundleDescriptionCacheOrder[bundleDescriptionCacheHeadIndex]
            bundleDescriptionCacheHeadIndex += 1
            bundleDescriptionCache.removeValue(forKey: oldest)
        }
        compactBundleDescriptionCacheOrderIfNeededLocked()
    }
    
    private static func trimBundleDescriptionMissCacheIfNeededLocked() {
        while bundleDescriptionMissCache.count > bundleDescriptionCacheLimit {
            if bundleDescriptionMissCacheHeadIndex >= bundleDescriptionMissCacheOrder.count {
                bundleDescriptionMissCacheOrder = Array(bundleDescriptionMissCache)
                bundleDescriptionMissCacheHeadIndex = 0
                if bundleDescriptionMissCacheOrder.isEmpty { break }
            }
            
            let oldest = bundleDescriptionMissCacheOrder[bundleDescriptionMissCacheHeadIndex]
            bundleDescriptionMissCacheHeadIndex += 1
            bundleDescriptionMissCache.remove(oldest)
        }
        compactBundleDescriptionMissCacheOrderIfNeededLocked()
    }
    
    private static func compactBundleDescriptionCacheOrderIfNeededLocked() {
        guard bundleDescriptionCacheHeadIndex >= cacheOrderCompactionThreshold,
              bundleDescriptionCacheHeadIndex * 2 >= bundleDescriptionCacheOrder.count else {
            return
        }
        
        bundleDescriptionCacheOrder.removeFirst(bundleDescriptionCacheHeadIndex)
        bundleDescriptionCacheHeadIndex = 0
    }
    
    private static func compactBundleDescriptionMissCacheOrderIfNeededLocked() {
        guard bundleDescriptionMissCacheHeadIndex >= cacheOrderCompactionThreshold,
              bundleDescriptionMissCacheHeadIndex * 2 >= bundleDescriptionMissCacheOrder.count else {
            return
        }
        
        bundleDescriptionMissCacheOrder.removeFirst(bundleDescriptionMissCacheHeadIndex)
        bundleDescriptionMissCacheHeadIndex = 0
    }
}
