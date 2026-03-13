import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class DownloadCenter {
    @ObservationIgnored private let settings: AppSettingsStore
    @ObservationIgnored private let persistence: DownloadPersistence
    @ObservationIgnored private let destinationResolver: DownloadDestinationResolver
    @ObservationIgnored private var coordinator: DownloadCoordinator! = nil
    @ObservationIgnored private let torrentService: Aria2TorrentService
    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private var persistTask: Task<Void, Never>?
    @ObservationIgnored private var torrentRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var hasShownTorrentBinaryAlert = false

    var downloads: [DownloadItem] = []
    var selectedFilter: DownloadFilter = .all
    var selectedDownloadID: UUID?
    var searchText = ""
    var sortMode: DownloadSortMode = .newest
    var isPresentingAddSheet = false
    var activeAlert: UserAlert?

    init(
        settings: AppSettingsStore,
        persistence: DownloadPersistence = DownloadPersistence(),
        destinationResolver: DownloadDestinationResolver = DownloadDestinationResolver(),
        torrentService: Aria2TorrentService = Aria2TorrentService()
    ) {
        self.settings = settings
        self.persistence = persistence
        self.destinationResolver = destinationResolver
        self.torrentService = torrentService
        self.coordinator = DownloadCoordinator { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event)
            }
        }
    }

    deinit {
        persistTask?.cancel()
        torrentRefreshTask?.cancel()
    }

    func initializeIfNeeded() async {
        guard hasLoaded == false else {
            return
        }

        hasLoaded = true
        startTorrentRefreshLoopIfNeeded()

        do {
            let records = try await persistence.load()
            let restoredItems = records
                .sorted { $0.createdAt > $1.createdAt }
                .map { record in
                    let item = DownloadItem(record: record)
                    item.taskIdentifier = nil
                    item.speedBytesPerSecond = 0

                    if item.backend == .aria2 {
                        item.backendIdentifier = nil
                    }

                    if record.status == .queued || record.status == .preparing || record.status == .downloading {
                        item.status = settings.startDownloadsAutomatically ? .queued : .paused
                        if settings.startDownloadsAutomatically == false {
                            item.lastError = "Paused after relaunch."
                        }
                    }

                    return item
                }

            downloads = restoredItems
            selectedDownloadID = downloads.first?.id

            if settings.startDownloadsAutomatically {
                startNextQueuedDownloadsIfNeeded()
            }
        } catch {
            activeAlert = UserAlert(
                title: "Couldn’t Restore Downloads",
                message: error.localizedDescription
            )
        }
    }

    var filteredDownloads: [DownloadItem] {
        let filtered = downloads.filter { item in
            guard selectedFilter.includes(item) else {
                return false
            }

            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard query.isEmpty == false else {
                return true
            }

            return item.displayName.localizedCaseInsensitiveContains(query)
                || item.sourceDisplayText.localizedCaseInsensitiveContains(query)
                || item.sourceHost.localizedCaseInsensitiveContains(query)
        }

        switch sortMode {
        case .newest:
            return filtered.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return filtered.sorted { $0.createdAt < $1.createdAt }
        case .name:
            return filtered.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        case .progress:
            return filtered.sorted { lhs, rhs in
                (lhs.progressValue ?? 0) > (rhs.progressValue ?? 0)
            }
        case .speed:
            return filtered.sorted { lhs, rhs in
                lhs.speedBytesPerSecond > rhs.speedBytesPerSecond
            }
        }
    }

    var selectedDownload: DownloadItem? {
        guard let selectedDownloadID else {
            return nil
        }

        return downloads.first { $0.id == selectedDownloadID }
    }

    var totalActiveSpeed: Double {
        downloads
            .filter(\.isRunning)
            .reduce(0) { $0 + $1.speedBytesPerSecond }
    }

    var totalDownloadSpeed: Double {
        downloads.reduce(0) { $0 + $1.speedBytesPerSecond }
    }

    var totalUploadSpeed: Double {
        downloads.reduce(0) { $0 + $1.uploadBytesPerSecond }
    }

    var hasActiveDownloads: Bool {
        downloads.contains(where: \.isRunning)
    }

    var activeDownloadCount: Int {
        downloads.filter { $0.status == .queued || $0.isRunning }.count
    }

    func count(for filter: DownloadFilter) -> Int {
        downloads.filter { filter.includes($0) }.count
    }

    func presentAddSheet() {
        isPresentingAddSheet = true
    }

    func queueDownload(_ request: AddDownloadRequest) {
        let backend: DownloadBackend = request.sourceKind == .directURL ? .urlSession : .aria2
        let preferredFilename: String?
        if request.sourceKind.supportsCustomFilename {
            preferredFilename = destinationResolver.resolvedFilename(
                custom: request.customFilename,
                responseSuggestedFilename: nil,
                sourceURL: request.sourceURL
            )
        } else {
            preferredFilename = nil
        }

        let item = DownloadItem(
            sourceURL: request.sourceURL,
            sourceKind: request.sourceKind,
            backend: backend,
            preferredFilename: preferredFilename,
            destinationFolderPath: request.destinationFolder.path,
            status: request.shouldStartImmediately ? .queued : .paused
        )

        if request.sourceKind == .magnetLink {
            item.metadataName = MagnetLinkMetadata(url: request.sourceURL).displayName
        }

        downloads.insert(item, at: 0)
        selectedDownloadID = item.id
        isPresentingAddSheet = false

        if request.shouldStartImmediately {
            startOrQueueDownload(id: item.id)
        } else {
            schedulePersist()
        }
    }

    func togglePauseResumeForSelection() {
        guard let selectedDownloadID else {
            return
        }

        togglePauseResume(id: selectedDownloadID)
    }

    func togglePauseResume(id: UUID) {
        guard let item = item(for: id) else {
            return
        }

        if item.canPause {
            pauseDownload(id: id)
        } else if item.canResume {
            startOrQueueDownload(id: id)
        }
    }

    func retrySelectedDownload() {
        guard let selectedDownloadID else {
            return
        }

        retryDownload(id: selectedDownloadID)
    }

    func retryDownload(id: UUID) {
        guard let item = item(for: id) else {
            return
        }

        item.lastError = nil
        item.finishedAt = nil
        item.speedBytesPerSecond = 0
        item.uploadBytesPerSecond = 0
        item.updatedAt = .now

        if item.backend == .urlSession {
            item.fileLocationPath = nil
            if item.status == .completed || item.status == .cancelled {
                item.bytesWritten = 0
                item.expectedBytes = 0
                item.progress = 0
                item.resumeData = nil
            }
        } else {
            if let backendIdentifier = item.backendIdentifier {
                Task {
                    await torrentService.remove(gid: backendIdentifier)
                }
            }

            item.backendIdentifier = nil
            item.fileLocationPath = nil
            item.bytesWritten = 0
            item.expectedBytes = 0
            item.progress = 0
        }

        startOrQueueDownload(id: id)
    }

    func pauseAll() {
        for item in downloads {
            if item.canPause {
                pauseDownload(id: item.id)
            } else if item.status == .queued {
                item.status = .paused
                item.updatedAt = .now
            }
        }

        schedulePersist()
    }

    func resumeAll() {
        downloads
            .filter(\.canResume)
            .forEach { startOrQueueDownload(id: $0.id) }
    }

    func cancelSelectedDownload() {
        guard let selectedDownloadID else {
            return
        }

        cancelDownload(id: selectedDownloadID)
    }

    func cancelDownload(id: UUID) {
        guard let item = item(for: id) else {
            return
        }

        switch item.backend {
        case .urlSession:
            if item.taskIdentifier != nil {
                coordinator.cancelDownload(id: id)
            }
        case .aria2:
            if let backendIdentifier = item.backendIdentifier {
                Task {
                    await torrentService.remove(gid: backendIdentifier)
                }
            }
        }

        item.status = .cancelled
        item.taskIdentifier = nil
        item.backendIdentifier = nil
        item.speedBytesPerSecond = 0
        item.updatedAt = .now
        schedulePersist()
        startNextQueuedDownloadsIfNeeded()
    }

    func removeSelectedDownload() {
        guard let selectedDownloadID else {
            return
        }

        removeDownload(id: selectedDownloadID)
    }

    func removeDownload(id: UUID) {
        guard let item = item(for: id) else {
            return
        }

        if item.backend == .urlSession, item.taskIdentifier != nil {
            coordinator.cancelDownload(id: id)
        } else if item.backend == .aria2, let backendIdentifier = item.backendIdentifier {
            Task {
                await torrentService.remove(gid: backendIdentifier)
            }
        }

        downloads.removeAll { $0.id == id }

        if selectedDownloadID == id {
            selectedDownloadID = filteredDownloads.first?.id ?? downloads.first?.id
        }

        schedulePersist()
        startNextQueuedDownloadsIfNeeded()
    }

    func clearCompleted() {
        cleanupBackendIdentifiers(for: downloads.filter { $0.status == .completed })
        downloads.removeAll { $0.status == .completed }
        if selectedDownload?.status == .completed {
            selectedDownloadID = filteredDownloads.first?.id ?? downloads.first?.id
        }
        schedulePersist()
    }

    func clearFailed() {
        cleanupBackendIdentifiers(for: downloads.filter { $0.status == .failed })
        downloads.removeAll { $0.status == .failed }
        if selectedDownload?.status == .failed {
            selectedDownloadID = filteredDownloads.first?.id ?? downloads.first?.id
        }
        schedulePersist()
    }

    func revealSelectedInFinder() {
        guard let selectedDownloadID else {
            return
        }

        revealInFinder(id: selectedDownloadID)
    }

    func revealInFinder(id: UUID) {
        guard let item = item(for: id) else {
            return
        }

        if let fileLocationPath = item.fileLocationPath {
            NSWorkspace.shared.selectFile(fileLocationPath, inFileViewerRootedAtPath: "")
        } else {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: item.destinationFolderPath)
        }
    }

    func openSelectedDownload() {
        guard let selectedDownloadID else {
            return
        }

        openDownload(id: selectedDownloadID)
    }

    func openDownload(id: UUID) {
        guard let url = item(for: id)?.fileLocationURL else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func copySourceURL(id: UUID) {
        guard let sourceText = item(for: id)?.sourceDisplayText else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(sourceText, forType: .string)
    }

    private func startOrQueueDownload(id: UUID) {
        guard let item = item(for: id) else {
            return
        }

        if item.backend == .urlSession, item.taskIdentifier != nil {
            return
        }

        if currentRunningDownloadsCount >= settings.maxConcurrentDownloads {
            item.status = .queued
            item.updatedAt = .now
            schedulePersist()
            return
        }

        item.lastError = nil
        item.finishedAt = nil
        item.speedBytesPerSecond = 0
        item.updatedAt = .now

        switch item.backend {
        case .urlSession:
            item.status = .preparing
            item.taskIdentifier = coordinator.startDownload(
                id: item.id,
                sourceURL: item.sourceURL,
                resumeData: item.resumeData
            )
            item.resumeData = nil
            item.startedAt = item.startedAt ?? .now
            schedulePersist()

        case .aria2:
            item.status = .preparing
            item.startedAt = item.startedAt ?? .now
            schedulePersist()
            Task { @MainActor [weak self] in
                await self?.startTorrentDownload(id: id)
            }
        }
    }

    private func startTorrentDownload(id: UUID) async {
        guard let currentItem = item(for: id) else {
            return
        }

        let hadBackendIdentifier = currentItem.backendIdentifier != nil

        do {
            if let backendIdentifier = currentItem.backendIdentifier {
                try await torrentService.unpause(gid: backendIdentifier)
            } else {
                let backendIdentifier = try await torrentService.addDownload(
                    sourceKind: currentItem.sourceKind,
                    sourceURL: currentItem.sourceURL,
                    destinationFolderPath: currentItem.destinationFolderPath
                )
                guard let refreshedItem = item(for: id) else {
                    await torrentService.remove(gid: backendIdentifier)
                    return
                }
                refreshedItem.backendIdentifier = backendIdentifier
            }

            guard let refreshedItem = item(for: id) else {
                return
            }

            refreshedItem.status = .downloading
            refreshedItem.updatedAt = .now
            schedulePersist()
        } catch {
            guard let refreshedItem = item(for: id) else {
                return
            }

            if hadBackendIdentifier, isTransientTorrentEngineError(error) {
                refreshedItem.status = .paused
                refreshedItem.speedBytesPerSecond = 0
                refreshedItem.uploadBytesPerSecond = 0
                refreshedItem.updatedAt = .now
                refreshedItem.lastError = error.localizedDescription
                schedulePersist()
                return
            }

            refreshedItem.status = .failed
            refreshedItem.backendIdentifier = nil
            refreshedItem.speedBytesPerSecond = 0
            refreshedItem.uploadBytesPerSecond = 0
            refreshedItem.updatedAt = .now
            refreshedItem.lastError = error.localizedDescription
            presentTorrentErrorIfNeeded(error)
            schedulePersist()
            startNextQueuedDownloadsIfNeeded()
        }
    }

    private func pauseDownload(id: UUID) {
        guard let item = item(for: id) else {
            return
        }

        item.status = .paused
        item.taskIdentifier = nil
        item.speedBytesPerSecond = 0
        item.uploadBytesPerSecond = 0
        item.updatedAt = .now

        switch item.backend {
        case .urlSession:
            coordinator.pauseDownload(id: id)
        case .aria2:
            if let backendIdentifier = item.backendIdentifier {
                Task {
                    try? await torrentService.pause(gid: backendIdentifier)
                }
            }
        }

        schedulePersist()
        startNextQueuedDownloadsIfNeeded()
    }

    private var currentRunningDownloadsCount: Int {
        downloads.filter(\.isRunning).count
    }

    private func startNextQueuedDownloadsIfNeeded() {
        let availableSlots = max(settings.maxConcurrentDownloads - currentRunningDownloadsCount, 0)
        guard availableSlots > 0 else {
            return
        }

        let queuedItems = downloads
            .filter { $0.status == .queued }
            .sorted { $0.createdAt < $1.createdAt }

        for item in queuedItems.prefix(availableSlots) {
            startOrQueueDownload(id: item.id)
        }
    }

    private func startTorrentRefreshLoopIfNeeded() {
        guard torrentRefreshTask == nil else {
            return
        }

        torrentRefreshTask = Task { [weak self] in
            while Task.isCancelled == false {
                await self?.refreshTorrentDownloads()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refreshTorrentDownloads() async {
        let torrentItems = downloads.filter {
            $0.backend == .aria2 && $0.backendIdentifier != nil
        }

        guard torrentItems.isEmpty == false else {
            return
        }

        var didMutate = false

        for item in torrentItems {
            guard let backendIdentifier = item.backendIdentifier else {
                continue
            }

            do {
                let snapshot = try await torrentService.status(for: backendIdentifier)
                apply(snapshot: snapshot, to: item)
                didMutate = true
            } catch {
                if isTransientTorrentEngineError(error) {
                    item.speedBytesPerSecond = 0
                    item.uploadBytesPerSecond = 0
                    item.updatedAt = .now
                    item.lastError = error.localizedDescription
                    didMutate = true
                    continue
                }

                item.status = .failed
                item.backendIdentifier = nil
                item.speedBytesPerSecond = 0
                item.uploadBytesPerSecond = 0
                item.updatedAt = .now
                item.lastError = error.localizedDescription
                didMutate = true
            }
        }

        if didMutate {
            schedulePersist()
        }
    }

    private func apply(snapshot: TorrentStatusSnapshot, to item: DownloadItem) {
        item.bytesWritten = snapshot.completedLength
        item.expectedBytes = max(snapshot.totalLength, 0)
        if snapshot.totalLength > 0 {
            item.progress = Double(snapshot.completedLength) / Double(snapshot.totalLength)
        }
        item.speedBytesPerSecond = snapshot.downloadSpeed
        item.uploadBytesPerSecond = snapshot.uploadSpeed
        item.metadataName = snapshot.metadataName ?? item.metadataName
        item.updatedAt = .now

        if let primaryPath = snapshot.primaryPath {
            item.fileLocationPath = primaryPath
        }

        switch snapshot.status {
        case "active":
            item.status = .downloading
            item.lastError = nil

        case "waiting":
            item.status = .queued

        case "paused":
            item.status = .paused
            item.speedBytesPerSecond = 0
            item.uploadBytesPerSecond = 0

        case "error":
            item.status = .failed
            item.lastError = snapshot.errorMessage ?? "Torrent engine reported an error."
            item.speedBytesPerSecond = 0
            item.uploadBytesPerSecond = 0
            let gid = snapshot.gid
            item.backendIdentifier = nil
            Task {
                await torrentService.remove(gid: gid)
            }
            startNextQueuedDownloadsIfNeeded()

        case "complete":
            item.status = .completed
            item.progress = 1
            item.bytesWritten = max(item.bytesWritten, item.expectedBytes)
            item.finishedAt = item.finishedAt ?? .now
            item.lastError = nil
            item.speedBytesPerSecond = 0
            item.uploadBytesPerSecond = 0
            let gid = snapshot.gid
            item.backendIdentifier = nil
            Task {
                await torrentService.remove(gid: gid)
            }
            startNextQueuedDownloadsIfNeeded()

        case "removed":
            item.status = .cancelled
            item.speedBytesPerSecond = 0
            item.uploadBytesPerSecond = 0
            item.backendIdentifier = nil
            startNextQueuedDownloadsIfNeeded()

        default:
            break
        }
    }

    private func handle(_ event: DownloadEvent) {
        switch event {
        case let .started(id, taskIdentifier):
            guard let item = item(for: id) else {
                return
            }

            item.taskIdentifier = taskIdentifier
            item.status = .downloading
            item.updatedAt = .now
            item.uploadBytesPerSecond = 0

        case let .progress(id, bytesWritten, expectedBytes, speedBytesPerSecond):
            guard let item = item(for: id) else {
                return
            }

            item.bytesWritten = bytesWritten
            item.expectedBytes = max(expectedBytes, item.expectedBytes)
            if expectedBytes > 0 {
                item.progress = Double(bytesWritten) / Double(expectedBytes)
            }
            item.speedBytesPerSecond = speedBytesPerSecond
            item.uploadBytesPerSecond = 0
            item.updatedAt = .now

        case let .paused(id, resumeData):
            guard let item = item(for: id) else {
                return
            }

            item.resumeData = resumeData
            item.taskIdentifier = nil
            item.status = .paused
            item.speedBytesPerSecond = 0
            item.uploadBytesPerSecond = 0
            item.updatedAt = .now
            startNextQueuedDownloadsIfNeeded()

        case let .cancelled(id):
            guard let item = item(for: id) else {
                return
            }

            item.status = .cancelled
            item.taskIdentifier = nil
            item.speedBytesPerSecond = 0
            item.uploadBytesPerSecond = 0
            item.updatedAt = .now
            startNextQueuedDownloadsIfNeeded()

        case let .failed(id, message, resumeData):
            guard let item = item(for: id) else {
                return
            }

            item.taskIdentifier = nil
            item.status = .failed
            item.lastError = message
            item.resumeData = resumeData
            item.speedBytesPerSecond = 0
            item.uploadBytesPerSecond = 0
            item.updatedAt = .now
            startNextQueuedDownloadsIfNeeded()

        case let .finished(id, temporaryURL, suggestedFilename):
            guard let item = item(for: id) else {
                return
            }

            do {
                let destinationURL = try destinationResolver.moveDownloadedFile(
                    from: temporaryURL,
                    customFilename: item.preferredFilename,
                    responseSuggestedFilename: suggestedFilename,
                    sourceURL: item.sourceURL,
                    into: item.destinationFolderURL
                )

                item.fileLocationPath = destinationURL.path
                item.preferredFilename = destinationURL.lastPathComponent
                item.status = .completed
                item.progress = 1
                item.expectedBytes = max(item.expectedBytes, item.bytesWritten)
                item.bytesWritten = max(item.bytesWritten, item.expectedBytes)
                item.finishedAt = .now
                item.lastError = nil
                item.resumeData = nil
            } catch {
                item.status = .failed
                item.lastError = error.localizedDescription
            }

            item.taskIdentifier = nil
            item.speedBytesPerSecond = 0
            item.uploadBytesPerSecond = 0
            item.updatedAt = .now
            startNextQueuedDownloadsIfNeeded()
        }

        schedulePersist()
    }

    private func item(for id: UUID) -> DownloadItem? {
        downloads.first { $0.id == id }
    }

    private func cleanupBackendIdentifiers(for items: [DownloadItem]) {
        let backendIdentifiers = items
            .filter { $0.backend == .aria2 }
            .compactMap(\.backendIdentifier)

        guard backendIdentifiers.isEmpty == false else {
            return
        }

        Task {
            for backendIdentifier in backendIdentifiers {
                await torrentService.remove(gid: backendIdentifier)
            }
        }
    }

    private func presentTorrentErrorIfNeeded(_ error: Error) {
        if hasShownTorrentBinaryAlert,
           case TorrentEngineError.binaryNotFound = error {
            return
        }

        if case TorrentEngineError.binaryNotFound = error {
            hasShownTorrentBinaryAlert = true
        }

        activeAlert = UserAlert(
            title: torrentErrorTitle(for: error),
            message: error.localizedDescription
        )
    }

    private func isTransientTorrentEngineError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet:
                return true
            default:
                break
            }
        }

        if case let TorrentEngineError.startupFailed(message) = error {
            return message.localizedCaseInsensitiveContains("timed out")
        }

        return false
    }

    private func torrentErrorTitle(for error: Error) -> String {
        if case TorrentEngineError.binaryNotFound = error {
            return "Torrent Support Needs aria2"
        }

        return "Torrent Engine Error"
    }

    private func schedulePersist() {
        let records = downloads.map { $0.makeRecord() }

        persistTask?.cancel()
        persistTask = Task { [persistence] in
            try? await Task.sleep(for: .milliseconds(250))
            try? await persistence.save(records)
        }
    }
}
