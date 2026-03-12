import Foundation

struct Aria2BinaryResolver {
    struct Resolution: Equatable, Sendable {
        enum Source: Equatable, Sendable {
            case bundled
            case environmentOverride
            case standardLocation
            case pathLookup

            nonisolated var displayName: String {
                switch self {
                case .bundled:
                    "Bundled with Harbor"
                case .environmentOverride:
                    "ARIA2C_PATH override"
                case .standardLocation:
                    "System installation"
                case .pathLookup:
                    "PATH lookup"
                }
            }
        }

        let url: URL
        let source: Source
    }

    struct Context {
        nonisolated(unsafe) let fileManager: FileManager
        let environment: [String: String]
        let bundledResourceRoots: [URL]
        let candidatePaths: [String]
        let pathLookup: @Sendable () -> URL?

        nonisolated init(
            fileManager: FileManager = .default,
            environment: [String: String] = ProcessInfo.processInfo.environment,
            bundledResourceRoots: [URL] = Self.defaultBundledResourceRoots(),
            candidatePaths: [String] = Self.defaultCandidatePaths,
            pathLookup: @escaping @Sendable () -> URL? = Aria2BinaryResolver.resolveFromPATH
        ) {
            self.fileManager = fileManager
            self.environment = environment
            self.bundledResourceRoots = bundledResourceRoots
            self.candidatePaths = candidatePaths
            self.pathLookup = pathLookup
        }

        nonisolated private static let defaultCandidatePaths = [
            "/opt/homebrew/bin/aria2c",
            "/usr/local/bin/aria2c",
            "/opt/local/bin/aria2c"
        ]

        nonisolated private static func defaultBundledResourceRoots() -> [URL] {
            var roots: [URL] = []
            var seenPaths = Set<String>()

            for resourceURL in [
                Bundle.main.resourceURL,
                Bundle(for: BundleToken.self).resourceURL
            ].compactMap({ $0 }) {
                guard seenPaths.insert(resourceURL.path).inserted else {
                    continue
                }

                roots.append(resourceURL)
            }

            return roots
        }
    }

    nonisolated static let installHint = "Harbor couldn’t find a compatible bundled torrent engine. Reinstall the app, or set `ARIA2C_PATH` to a portable `aria2c` runtime."

    nonisolated static func resolveBinaryURL() -> URL? {
        resolveBinary()?.url
    }

    nonisolated static func resolveBinary(using context: Context = Context()) -> Resolution? {
        if let bundledBinary = resolveBundledRuntime(using: context) {
            return bundledBinary
        }

        if let path = context.environment["ARIA2C_PATH"],
           context.fileManager.isExecutableFile(atPath: path) {
            return Resolution(
                url: URL(fileURLWithPath: path),
                source: .environmentOverride
            )
        }

        for path in context.candidatePaths where context.fileManager.isExecutableFile(atPath: path) {
            return Resolution(
                url: URL(fileURLWithPath: path),
                source: .standardLocation
            )
        }

        guard let pathLookupURL = context.pathLookup() else {
            return nil
        }

        return Resolution(
            url: pathLookupURL,
            source: .pathLookup
        )
    }

    private nonisolated static func resolveBundledRuntime(using context: Context) -> Resolution? {
        for root in context.bundledResourceRoots {
            let candidateURLs = [
                root
                    .appendingPathComponent("TorrentRuntime", isDirectory: true)
                    .appendingPathComponent(runtimeArchitectureName, isDirectory: true)
                    .appendingPathComponent("bin", isDirectory: true)
                    .appendingPathComponent("aria2c", isDirectory: false),
                root
                    .appendingPathComponent("TorrentRuntime", isDirectory: true)
                    .appendingPathComponent("bin", isDirectory: true)
                    .appendingPathComponent("aria2c", isDirectory: false)
            ]

            for binaryURL in candidateURLs where context.fileManager.isExecutableFile(atPath: binaryURL.path) {
                return Resolution(url: binaryURL, source: .bundled)
            }
        }

        return nil
    }

    private nonisolated static func resolveFromPATH() -> URL? {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["aria2c"]
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            path.isEmpty == false else {
            return nil
        }

        return URL(fileURLWithPath: path)
    }

    private nonisolated static var runtimeArchitectureName: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unsupported"
        #endif
    }
}

private final class BundleToken: NSObject {}
