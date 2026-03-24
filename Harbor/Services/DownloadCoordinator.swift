import Foundation

enum DownloadEvent: Sendable {
    case started(id: UUID, taskIdentifier: Int)
    case progress(id: UUID, bytesWritten: Int64, expectedBytes: Int64, speedBytesPerSecond: Double)
    case paused(id: UUID, resumeData: Data?)
    case cancelled(id: UUID)
    case finished(
        id: UUID,
        temporaryURL: URL,
        suggestedFilename: String?,
        responseMimeType: String?,
        statusCode: Int?
    )
    case failed(id: UUID, message: String, resumeData: Data?)
}

final class DownloadCoordinator: NSObject, @unchecked Sendable {
    typealias EventHandler = @Sendable (DownloadEvent) -> Void

    private struct TransferSample {
        var lastTotalBytesWritten: Int64
        var sampleDate: Date
        var speedBytesPerSecond: Double
    }

    private struct TaskContext {
        let downloadID: UUID
        let task: URLSessionDownloadTask
        var transferSample: TransferSample
    }

    private let eventHandler: EventHandler
    private let fileManager: FileManager
    private let stateLock = NSLock()
    private let ownedTemporaryDirectory: URL

    private var contexts: [Int: TaskContext] = [:]
    private var taskIdentifiersByDownloadID: [UUID: Int] = [:]
    private var suppressedCompletionTaskIDs: Set<Int> = []

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.httpMaximumConnectionsPerHost = 8
        configuration.allowsConstrainedNetworkAccess = true
        configuration.allowsExpensiveNetworkAccess = true

        let delegateQueue = OperationQueue()
        delegateQueue.name = "DownloadCoordinatorDelegateQueue"
        delegateQueue.maxConcurrentOperationCount = 1

        return URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: delegateQueue
        )
    }()

    init(eventHandler: @escaping EventHandler, fileManager: FileManager = .default) {
        self.eventHandler = eventHandler
        self.fileManager = fileManager
        self.ownedTemporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("HarborDownloads", isDirectory: true)
        super.init()
    }

    deinit {
        session.invalidateAndCancel()
    }

    @discardableResult
    func startDownload(id: UUID, sourceURL: URL, resumeData: Data?) -> Int {
        let task: URLSessionDownloadTask
        if let resumeData {
            task = session.downloadTask(withResumeData: resumeData)
        } else {
            task = session.downloadTask(with: sourceURL)
        }

        let context = TaskContext(
            downloadID: id,
            task: task,
            transferSample: TransferSample(
                lastTotalBytesWritten: 0,
                sampleDate: .now,
                speedBytesPerSecond: 0
            )
        )

        withLock {
            contexts[task.taskIdentifier] = context
            taskIdentifiersByDownloadID[id] = task.taskIdentifier
            suppressedCompletionTaskIDs.remove(task.taskIdentifier)
        }

        task.resume()
        eventHandler(.started(id: id, taskIdentifier: task.taskIdentifier))
        return task.taskIdentifier
    }

    func pauseDownload(id: UUID) {
        guard let context = takeContext(forDownloadID: id, suppressCompletion: true) else {
            return
        }

        context.task.cancel(byProducingResumeData: { [eventHandler] resumeData in
            eventHandler(.paused(id: id, resumeData: resumeData))
        })
    }

    func cancelDownload(id: UUID) {
        guard let context = takeContext(forDownloadID: id, suppressCompletion: true) else {
            return
        }

        context.task.cancel()
        eventHandler(.cancelled(id: id))
    }

    private func takeContext(forDownloadID id: UUID, suppressCompletion: Bool) -> TaskContext? {
        withLock {
            guard let taskIdentifier = taskIdentifiersByDownloadID.removeValue(forKey: id),
                  let context = contexts.removeValue(forKey: taskIdentifier) else {
                return nil
            }

            if suppressCompletion {
                suppressedCompletionTaskIDs.insert(taskIdentifier)
            }

            return context
        }
    }

    private func takeContext(forTaskIdentifier taskIdentifier: Int) -> TaskContext? {
        withLock {
            guard let context = contexts.removeValue(forKey: taskIdentifier) else {
                return nil
            }

            taskIdentifiersByDownloadID.removeValue(forKey: context.downloadID)
            return context
        }
    }

    private func context(for taskIdentifier: Int) -> TaskContext? {
        withLock {
            contexts[taskIdentifier]
        }
    }

    private func updateContext(
        for taskIdentifier: Int,
        _ update: (inout TaskContext) -> Void
    ) -> TaskContext? {
        withLock {
            guard var context = contexts[taskIdentifier] else {
                return nil
            }

            update(&context)
            contexts[taskIdentifier] = context
            return context
        }
    }

    private func shouldIgnoreCompletion(taskIdentifier: Int, error: NSError) -> Bool {
        withLock {
            let suppressed = suppressedCompletionTaskIDs.remove(taskIdentifier) != nil
            return suppressed && error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
        }
    }

    private func withLock<T>(_ work: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return work()
    }

    private func claimTemporaryDownload(
        at location: URL,
        downloadID: UUID
    ) throws -> URL {
        try fileManager.createDirectory(
            at: ownedTemporaryDirectory,
            withIntermediateDirectories: true
        )

        let claimedURL = ownedTemporaryDirectory
            .appendingPathComponent(downloadID.uuidString)
            .appendingPathExtension("download")

        if fileManager.fileExists(atPath: claimedURL.path) {
            try fileManager.removeItem(at: claimedURL)
        }

        try fileManager.moveItem(at: location, to: claimedURL)
        return claimedURL
    }
}

extension DownloadCoordinator: URLSessionDownloadDelegate, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let context = updateContext(for: downloadTask.taskIdentifier, { context in
            let now = Date()
            let elapsed = now.timeIntervalSince(context.transferSample.sampleDate)
            guard elapsed >= 0.35 else {
                return
            }

            let deltaBytes = totalBytesWritten - context.transferSample.lastTotalBytesWritten
            let speed = elapsed > 0 ? Double(deltaBytes) / elapsed : context.transferSample.speedBytesPerSecond
            context.transferSample = TransferSample(
                lastTotalBytesWritten: totalBytesWritten,
                sampleDate: now,
                speedBytesPerSecond: speed
            )
        }) else {
            return
        }

        eventHandler(
            .progress(
                id: context.downloadID,
                bytesWritten: totalBytesWritten,
                expectedBytes: totalBytesExpectedToWrite,
                speedBytesPerSecond: context.transferSample.speedBytesPerSecond
            )
        )
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let context = takeContext(forTaskIdentifier: downloadTask.taskIdentifier) else {
            return
        }

        do {
            let claimedURL = try claimTemporaryDownload(
                at: location,
                downloadID: context.downloadID
            )

            eventHandler(
                .finished(
                    id: context.downloadID,
                    temporaryURL: claimedURL,
                    suggestedFilename: downloadTask.response?.suggestedFilename,
                    responseMimeType: downloadTask.response?.mimeType,
                    statusCode: (downloadTask.response as? HTTPURLResponse)?.statusCode
                )
            )
        } catch {
            eventHandler(
                .failed(
                    id: context.downloadID,
                    message: error.localizedDescription,
                    resumeData: nil
                )
            )
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else {
            return
        }

        let nsError = error as NSError
        if shouldIgnoreCompletion(taskIdentifier: task.taskIdentifier, error: nsError) {
            return
        }

        guard let context = takeContext(forTaskIdentifier: task.taskIdentifier) else {
            return
        }

        let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        eventHandler(
            .failed(
                id: context.downloadID,
                message: nsError.localizedDescription,
                resumeData: resumeData
            )
        )
    }
}
