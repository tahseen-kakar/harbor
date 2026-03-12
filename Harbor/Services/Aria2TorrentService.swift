import Foundation
import OSLog

enum TorrentEngineError: LocalizedError {
    case binaryNotFound
    case startupFailed(String)
    case invalidSource
    case invalidResponse
    case rpc(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            "Torrent support requires aria2c. \(Aria2BinaryResolver.installHint)"
        case let .startupFailed(message):
            "Couldn’t start the torrent engine. \(message)"
        case .invalidSource:
            "This download source isn’t valid for the torrent engine."
        case .invalidResponse:
            "The torrent engine returned an invalid response."
        case let .rpc(message):
            message
        }
    }
}

struct TorrentStatusSnapshot: Sendable {
    let gid: String
    let status: String
    let totalLength: Int64
    let completedLength: Int64
    let downloadSpeed: Double
    let uploadSpeed: Double
    let errorMessage: String?
    let metadataName: String?
    let primaryPath: String?
}

actor Aria2TorrentService {
    private struct RPCEnvelope<Result: Decodable>: Decodable {
        let result: Result?
        let error: RPCFailure?
    }

    private struct RPCFailure: Decodable {
        let code: Int
        let message: String
    }

    private struct VersionPayload: Decodable {
        let version: String
    }

    private struct StatusPayload: Decodable {
        let gid: String
        let status: String
        let totalLength: String?
        let completedLength: String?
        let downloadSpeed: String?
        let uploadSpeed: String?
        let errorMessage: String?
        let files: [FilePayload]?
        let bittorrent: BittorrentPayload?
    }

    private struct FilePayload: Decodable {
        let path: String?
        let selected: String?
    }

    private struct BittorrentPayload: Decodable {
        let info: InfoPayload?
    }

    private struct InfoPayload: Decodable {
        let name: String?
    }

    nonisolated private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Harbor",
        category: "TorrentEngine"
    )

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 10
        return URLSession(configuration: configuration)
    }()

    private var process: Process?
    private var rpcPort: Int?
    private var rpcSecret: String?
    private var stderrPipe: Pipe?

    deinit {
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
    }

    func resolvedBinaryPath() -> String? {
        Aria2BinaryResolver.resolveBinaryURL()?.path
    }

    func addDownload(
        sourceKind: DownloadSourceKind,
        sourceURL: URL,
        destinationFolderPath: String
    ) async throws -> String {
        logger.info("Starting torrent add request for source kind \(String(describing: sourceKind), privacy: .public)")
        try await ensureDaemonRunning()

        let options: [String: String] = [
            "dir": destinationFolderPath,
            "pause": "false"
        ]

        switch sourceKind {
        case .magnetLink:
            let gid = try await rpcCall(method: "aria2.addUri", params: [
                authorizedToken(),
                [sourceURL.absoluteString],
                options
            ], as: String.self)
            logger.info("aria2 accepted magnet download with gid \(gid, privacy: .public)")
            return gid
        case .torrentFile:
            let torrentData = try Data(contentsOf: sourceURL)
            let gid = try await rpcCall(method: "aria2.addTorrent", params: [
                authorizedToken(),
                torrentData.base64EncodedString(),
                [],
                options
            ], as: String.self)
            logger.info("aria2 accepted torrent file with gid \(gid, privacy: .public)")
            return gid
        case .directURL:
            throw TorrentEngineError.invalidSource
        }
    }

    func pause(gid: String) async throws {
        _ = try await rpcCall(method: "aria2.forcePause", params: [
            authorizedToken(),
            gid
        ], as: String.self)
    }

    func unpause(gid: String) async throws {
        _ = try await rpcCall(method: "aria2.unpause", params: [
            authorizedToken(),
            gid
        ], as: String.self)
    }

    func remove(gid: String) async {
        _ = try? await rpcCall(method: "aria2.forceRemove", params: [
            authorizedToken(),
            gid
        ], as: String.self)
        _ = try? await rpcCall(method: "aria2.removeDownloadResult", params: [
            authorizedToken(),
            gid
        ], as: String.self)
    }

    func status(for gid: String) async throws -> TorrentStatusSnapshot {
        try await ensureDaemonRunning()

        let payload = try await rpcCall(method: "aria2.tellStatus", params: [
            authorizedToken(),
            gid,
            [
                "gid",
                "status",
                "totalLength",
                "completedLength",
                "downloadSpeed",
                "uploadSpeed",
                "errorMessage",
                "files",
                "bittorrent"
            ]
        ], as: StatusPayload.self)

        let filePaths = payload.files?
            .compactMap(\.path)
            .filter { $0.isEmpty == false } ?? []

        return TorrentStatusSnapshot(
            gid: payload.gid,
            status: payload.status,
            totalLength: Int64(payload.totalLength ?? "") ?? 0,
            completedLength: Int64(payload.completedLength ?? "") ?? 0,
            downloadSpeed: Double(payload.downloadSpeed ?? "") ?? 0,
            uploadSpeed: Double(payload.uploadSpeed ?? "") ?? 0,
            errorMessage: payload.errorMessage,
            metadataName: payload.bittorrent?.info?.name,
            primaryPath: preferredPath(from: filePaths)
        )
    }

    private func ensureDaemonRunning() async throws {
        if let process, process.isRunning, rpcPort != nil, rpcSecret != nil {
            return
        }

        guard let binaryURL = Aria2BinaryResolver.resolveBinaryURL() else {
            throw TorrentEngineError.binaryNotFound
        }

        logger.info("Launching aria2 from \(binaryURL.path, privacy: .public)")

        let port = Int.random(in: 18_000 ... 28_000)
        let secret = UUID().uuidString.replacingOccurrences(of: "-", with: "")

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = [
            "--enable-rpc=true",
            "--rpc-listen-all=false",
            "--rpc-listen-port=\(port)",
            "--rpc-secret=\(secret)",
            "--seed-time=0",
            "--bt-save-metadata=true",
            "--follow-torrent=true",
            "--allow-overwrite=false",
            "--auto-file-renaming=true",
            "--summary-interval=0",
            "--max-concurrent-downloads=64",
            "--check-certificate=true",
            "--console-log-level=notice"
        ]
        process.standardOutput = Pipe()
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        installReadabilityHandler(for: stderrPipe)

        do {
            try process.run()
        } catch {
            logger.error("Failed to launch aria2: \(error.localizedDescription, privacy: .public)")
            throw TorrentEngineError.startupFailed(error.localizedDescription)
        }

        self.process = process
        self.rpcPort = port
        self.rpcSecret = secret
        self.stderrPipe = stderrPipe
        logger.info("aria2 process started on RPC port \(port, privacy: .public)")

        for _ in 0 ..< 20 {
            if process.isRunning == false {
                logger.error("aria2 exited before RPC became available")
                throw TorrentEngineError.startupFailed("aria2c exited before opening RPC.")
            }

            do {
                _ = try await rpcCall(method: "aria2.getVersion", params: [
                    authorizedToken()
                ], as: VersionPayload.self)
                logger.info("aria2 RPC is ready")
                return
            } catch {
                logger.debug("aria2 RPC not ready yet: \(error.localizedDescription, privacy: .public)")
                try? await Task.sleep(for: .milliseconds(250))
            }
        }

        logger.error("Timed out waiting for aria2 RPC readiness")
        throw TorrentEngineError.startupFailed("Timed out waiting for aria2 RPC.")
    }

    private func rpcURL() throws -> URL {
        guard let rpcPort else {
            throw TorrentEngineError.invalidResponse
        }

        return URL(string: "http://127.0.0.1:\(rpcPort)/jsonrpc")!
    }

    private func authorizedToken() throws -> String {
        guard let rpcSecret else {
            throw TorrentEngineError.invalidResponse
        }

        return "token:\(rpcSecret)"
    }

    private func rpcCall<Result: Decodable>(
        method: String,
        params: [Any],
        as type: Result.Type
    ) async throws -> Result {
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": UUID().uuidString,
            "method": method,
            "params": params
        ]

        var request = URLRequest(url: try rpcURL())
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 5

        let (data, _) = try await session.data(for: request)
        let envelope = try JSONDecoder().decode(RPCEnvelope<Result>.self, from: data)

        if let error = envelope.error {
            throw TorrentEngineError.rpc(error.message)
        }

        guard let result = envelope.result else {
            throw TorrentEngineError.invalidResponse
        }

        return result
    }

    private nonisolated func installReadabilityHandler(for pipe: Pipe) {
        let logger = self.logger
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard data.isEmpty == false,
                  let output = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  output.isEmpty == false else {
                return
            }

            logger.notice("aria2: \(output, privacy: .public)")
        }
    }

    private func preferredPath(from filePaths: [String]) -> String? {
        guard filePaths.isEmpty == false else {
            return nil
        }

        if filePaths.count == 1 {
            return filePaths[0]
        }

        let splitComponents = filePaths.map {
            URL(fileURLWithPath: $0).pathComponents
        }

        guard var sharedComponents = splitComponents.first else {
            return filePaths[0]
        }

        for components in splitComponents.dropFirst() {
            while sharedComponents.isEmpty == false,
                  components.starts(with: sharedComponents) == false {
                sharedComponents.removeLast()
            }
        }

        guard sharedComponents.isEmpty == false else {
            return URL(fileURLWithPath: filePaths[0]).deletingLastPathComponent().path
        }

        let commonPath = NSString.path(withComponents: sharedComponents)
        return commonPath.isEmpty ? filePaths[0] : commonPath
    }
}
