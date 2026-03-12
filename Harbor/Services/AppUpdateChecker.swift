import Foundation

enum AppUpdateChecker {
    enum CheckResult: Equatable {
        case upToDate(currentVersion: String)
        case updateAvailable(currentVersion: String, release: Release)
    }

    struct Release: Decodable, Equatable {
        struct Asset: Decodable, Equatable {
            let name: String
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let id: Int
        let name: String
        let tagName: String
        let htmlURL: URL
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case assets
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }

        var version: String {
            AppUpdateChecker.normalizedVersion(tagName)
        }

        var displayName: String {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedName.isEmpty ? "Harbor \(version)" : trimmedName
        }

        var preferredDownloadURL: URL {
            preferredAsset?.browserDownloadURL ?? htmlURL
        }

        private var preferredAsset: Asset? {
            assets.first(where: { $0.name.localizedCaseInsensitiveContains(".dmg") })
                ?? assets.first(where: { $0.name.localizedCaseInsensitiveContains(".pkg") })
                ?? assets.first(where: { $0.name.localizedCaseInsensitiveContains(".zip") })
        }
    }

    enum Error: LocalizedError {
        case invalidResponse
        case unsupportedCurrentVersion

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Harbor could not read the latest release information from GitHub."
            case .unsupportedCurrentVersion:
                return "Harbor could not determine the installed app version."
            }
        }
    }

    private static let owner = "tahseen-kakar"
    private static let repository = "harbor"

    static func checkForUpdates(
        session: URLSession = .shared,
        bundle: Bundle = .main
    ) async throws -> CheckResult {
        let currentVersion = try currentAppVersion(bundle: bundle)
        let latestRelease = try await fetchLatestRelease(session: session)

        if compareVersions(currentVersion, latestRelease.version) == .orderedAscending {
            return .updateAvailable(currentVersion: currentVersion, release: latestRelease)
        }

        return .upToDate(currentVersion: currentVersion)
    }

    static func currentAppVersion(bundle: Bundle = .main) throws -> String {
        guard let rawVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            throw Error.unsupportedCurrentVersion
        }

        let version = normalizedVersion(rawVersion)
        guard version.isEmpty == false else {
            throw Error.unsupportedCurrentVersion
        }

        return version
    }

    private static func fetchLatestRelease(session: URLSession) async throws -> Release {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Harbor/\(currentUserAgentVersion())", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw Error.invalidResponse
        }

        let decoder = JSONDecoder()
        return try decoder.decode(Release.self, from: data)
    }

    private static func currentUserAgentVersion() -> String {
        (try? currentAppVersion()) ?? "unknown"
    }

    static func normalizedVersion(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let strippedPrefix = trimmed.replacingOccurrences(
            of: #"^[vV]"#,
            with: "",
            options: .regularExpression
        )
        let baseVersion = strippedPrefix.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        return String(baseVersion).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsComponents = versionComponents(from: lhs)
        let rhsComponents = versionComponents(from: rhs)
        let maxCount = max(lhsComponents.count, rhsComponents.count)

        for index in 0 ..< maxCount {
            let lhsValue = lhsComponents.indices.contains(index) ? lhsComponents[index] : 0
            let rhsValue = rhsComponents.indices.contains(index) ? rhsComponents[index] : 0

            if lhsValue < rhsValue {
                return .orderedAscending
            }

            if lhsValue > rhsValue {
                return .orderedDescending
            }
        }

        return .orderedSame
    }

    private static func versionComponents(from version: String) -> [Int] {
        normalizedVersion(version)
            .split(separator: ".")
            .map { Int($0) ?? 0 }
    }
}
