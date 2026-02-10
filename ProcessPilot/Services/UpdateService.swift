import Foundation
import AppKit

@MainActor
final class UpdateService: ObservableObject {
    @Published private(set) var availableUpdate: AvailableUpdate?
    @Published private(set) var isChecking = false
    
    struct AvailableUpdate: Equatable {
        let version: String
        let releaseURL: URL
        let downloadURL: URL?
    }
    
    private let owner: String
    private let repo: String
    private let session: URLSession
    private let currentVersion: AppVersion
    private let logHandler: (String) -> Void
    
    var isConfigured: Bool {
        !owner.isEmpty && !repo.isEmpty
    }
    
    init(
        session: URLSession = .shared,
        owner: String? = nil,
        repo: String? = nil,
        currentVersionString: String? = nil,
        shouldCheckOnInit: Bool = true,
        logHandler: ((String) -> Void)? = nil
    ) {
        self.owner = UpdateService.loadString(
            override: owner,
            env: "PROCESSPILOT_GITHUB_OWNER",
            plistKey: "PPGitHubOwner"
        )
        self.repo = UpdateService.loadString(
            override: repo,
            env: "PROCESSPILOT_GITHUB_REPO",
            plistKey: "PPGitHubRepo"
        )
        self.session = session
        self.logHandler = logHandler ?? { message in
            print(message)
        }
        
        let version = currentVersionString?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0")
        self.currentVersion = AppVersion(version)
        
        guard isConfigured, shouldCheckOnInit else { return }
        
        Task {
            await checkForUpdates()
        }
    }
    
    func checkForUpdates() async {
        guard isConfigured, !isChecking else { return }
        
        isChecking = true
        defer { isChecking = false }
        
        do {
            let release = try await fetchLatestRelease(owner: owner, repo: repo)
            let latestVersion = AppVersion(release.tagName)
            
            if latestVersion > currentVersion {
                availableUpdate = AvailableUpdate(
                    version: release.tagName,
                    releaseURL: release.htmlURL,
                    downloadURL: release.preferredDownloadURL
                )
            } else {
                availableUpdate = nil
            }
        } catch {
            availableUpdate = nil
            logHandler("Update check failed: \(error)")
        }
    }
    
    func openUpdate() {
        guard let update = availableUpdate else { return }
        NSWorkspace.shared.open(update.downloadURL ?? update.releaseURL)
    }
    
    private func fetchLatestRelease(owner: String, repo: String) async throws -> GitHubRelease {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else {
            throw UpdateError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ProcessPilot", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await session.data(for: request)
        
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw UpdateError.httpStatus(http.statusCode)
        }
        
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }
    
    private static func loadString(override: String?, env: String, plistKey: String) -> String {
        if let value = override?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty {
            return value
        }
        
        if let value = ProcessInfo.processInfo.environment[env]?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty {
            return value
        }
        
        if let value = (Bundle.main.object(forInfoDictionaryKey: plistKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty {
            return value
        }
        
        return ""
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL
        
        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }
    
    let tagName: String
    let htmlURL: URL
    let assets: [Asset]
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
    
    var preferredDownloadURL: URL? {
        if let dmg = assets.first(where: { $0.name.hasSuffix(".dmg") }) {
            return dmg.browserDownloadURL
        }
        if let zip = assets.first(where: { $0.name.hasSuffix(".zip") }) {
            return zip.browserDownloadURL
        }
        return assets.first?.browserDownloadURL
    }
}

private struct AppVersion: Comparable {
    private let components: [Int]
    
    init(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.hasPrefix("v") || trimmed.hasPrefix("V")
            ? String(trimmed.dropFirst())
            : trimmed
        
        if let range = withoutPrefix.range(
            of: #"\d+(\.\d+)*"#,
            options: .regularExpression
        ) {
            self.components = withoutPrefix[range]
                .split(separator: ".")
                .compactMap { Int($0) }
        } else {
            self.components = [0]
        }
    }
    
    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let maxCount = max(lhs.components.count, rhs.components.count)
        
        for index in 0..<maxCount {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        
        return false
    }
}

private enum UpdateError: Error {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
}
