import Foundation

actor AnalysisQueueStore {
    private let fileManager = FileManager.default
    private let rootURL: URL
    private let queueIndexFileName = "QueueIndex.json"
    private let reviewTaskIndexFileName = "ReviewTasks.json"
    private let bundlesDirectoryName = "Bundles"
    private let bundleFileName = "bundle.json"
    private let resultFileName = "result.json"

    private lazy var decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private lazy var encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    init(rootURL: URL? = nil) {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let localFileManager = FileManager.default
            let applicationSupport = localFileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? localFileManager.temporaryDirectory
            self.rootURL = applicationSupport
                .appendingPathComponent("pharnote", isDirectory: true)
                .appendingPathComponent("AnalysisQueue", isDirectory: true)
        }
    }

    func loadEntries() throws -> [AnalysisQueueEntry] {
        try ensureDirectories()
        let indexURL = queueIndexURL()
        guard fileManager.fileExists(atPath: indexURL.path) else { return [] }
        let data = try Data(contentsOf: indexURL)
        return try decoder.decode([AnalysisQueueEntry].self, from: data)
    }

    func loadBundle(bundleId: UUID) throws -> AnalysisBundle {
        try ensureDirectories()
        let bundleURL = bundleFileURL(for: bundleId)
        let data = try Data(contentsOf: bundleURL)
        return try decoder.decode(AnalysisBundle.self, from: data)
    }

    func loadResult(bundleId: UUID) throws -> AnalysisResult? {
        try ensureDirectories()
        let resultURL = resultFileURL(for: bundleId)
        guard fileManager.fileExists(atPath: resultURL.path) else { return nil }
        let data = try Data(contentsOf: resultURL)
        return try decoder.decode(AnalysisResult.self, from: data)
    }

    func loadResults() throws -> [AnalysisResult] {
        try ensureDirectories()
        let bundleDirectories = try fileManager.contentsOfDirectory(
            at: bundlesURL(),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        return try bundleDirectories.compactMap { directory in
            let resultURL = directory.appendingPathComponent(resultFileName, isDirectory: false)
            guard fileManager.fileExists(atPath: resultURL.path) else { return nil }
            let data = try Data(contentsOf: resultURL)
            return try decoder.decode(AnalysisResult.self, from: data)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    func loadReviewTasks() throws -> [AnalysisReviewTask] {
        try ensureDirectories()
        let fileURL = reviewTaskIndexURL()
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([AnalysisReviewTask].self, from: data)
            .sorted { lhs, rhs in
                if lhs.status == rhs.status {
                    return lhs.dueAt < rhs.dueAt
                }
                return lhs.status == .pending
            }
    }

    func enqueue(
        bundle: AnalysisBundle,
        previewImageData: Data?,
        drawingData: Data?
    ) throws -> AnalysisQueueEntry {
        try ensureDirectories()

        let bundleDirectory = bundleDirectoryURL(for: bundle.bundleId)
        try fileManager.createDirectory(at: bundleDirectory, withIntermediateDirectories: true)

        var storedBundle = bundle

        if let previewImageData {
            let previewURL = bundleDirectory.appendingPathComponent(AnalysisBundleAssetName.previewImage, isDirectory: false)
            try previewImageData.write(to: previewURL, options: .atomic)
            storedBundle.content.previewImageRef = previewURL.path
        }

        if let drawingData {
            let drawingURL = bundleDirectory.appendingPathComponent(AnalysisBundleAssetName.drawingData, isDirectory: false)
            try drawingData.write(to: drawingURL, options: .atomic)
            storedBundle.content.drawingRef = drawingURL.path
        }

        let bundleFileURL = bundleFileURL(for: storedBundle.bundleId)
        let bundleData = try encoder.encode(storedBundle)
        try bundleData.write(to: bundleFileURL, options: .atomic)

        var entries = try loadEntries()
        let entry = AnalysisQueueEntry(
            bundleId: storedBundle.bundleId,
            createdAt: storedBundle.createdAt,
            documentId: storedBundle.document.documentId,
            documentTitle: storedBundle.document.title,
            documentType: storedBundle.document.documentType,
            pageLabel: "p.\(storedBundle.page.pageIndex + 1)",
            studyIntent: storedBundle.behavior.studyIntent,
            scope: storedBundle.scope,
            status: .queued,
            bundleFilePath: bundleFileURL.path,
            lastErrorMessage: nil
        )
        entries.removeAll { $0.bundleId == entry.bundleId }
        entries.insert(entry, at: 0)
        try persistEntries(entries)
        return entry
    }

    func saveResult(_ result: AnalysisResult, for bundleId: UUID) throws -> AnalysisQueueEntry? {
        try ensureDirectories()

        let resultURL = resultFileURL(for: bundleId)
        let data = try encoder.encode(result)
        try data.write(to: resultURL, options: .atomic)

        var entries = try loadEntries()
        guard let index = entries.firstIndex(where: { $0.bundleId == bundleId }) else {
            return nil
        }

        entries[index].status = .completed
        entries[index].lastErrorMessage = nil
        try persistEntries(entries)
        return entries[index]
    }

    func markFailed(bundleId: UUID, errorMessage: String) throws -> AnalysisQueueEntry? {
        try ensureDirectories()

        var entries = try loadEntries()
        guard let index = entries.firstIndex(where: { $0.bundleId == bundleId }) else {
            return nil
        }

        entries[index].status = .failed
        entries[index].lastErrorMessage = errorMessage
        try persistEntries(entries)
        return entries[index]
    }

    func upsertReviewTasks(_ tasks: [AnalysisReviewTask]) throws {
        try ensureDirectories()

        var existing = try loadReviewTasks()
        for task in tasks {
            if let index = existing.firstIndex(where: { $0.taskId == task.taskId }) {
                existing[index] = task
            } else {
                existing.append(task)
            }
        }

        try persistReviewTasks(existing)
    }

    func updateReviewTaskStatus(taskId: UUID, status: AnalysisReviewTaskStatus) throws -> AnalysisReviewTask? {
        try ensureDirectories()

        var tasks = try loadReviewTasks()
        guard let index = tasks.firstIndex(where: { $0.taskId == taskId }) else { return nil }
        tasks[index].status = status
        tasks[index].updatedAt = Date()
        try persistReviewTasks(tasks)
        return tasks[index]
    }

    private func persistEntries(_ entries: [AnalysisQueueEntry]) throws {
        let data = try encoder.encode(entries)
        try data.write(to: queueIndexURL(), options: .atomic)
    }

    private func persistReviewTasks(_ tasks: [AnalysisReviewTask]) throws {
        let sortedTasks = tasks.sorted { lhs, rhs in
            if lhs.status == rhs.status {
                if lhs.dueAt == rhs.dueAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.dueAt < rhs.dueAt
            }
            return lhs.status == .pending
        }
        let data = try encoder.encode(sortedTasks)
        try data.write(to: reviewTaskIndexURL(), options: .atomic)
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: bundlesURL(), withIntermediateDirectories: true)
    }

    private func queueIndexURL() -> URL {
        rootURL.appendingPathComponent(queueIndexFileName, isDirectory: false)
    }

    private func reviewTaskIndexURL() -> URL {
        rootURL.appendingPathComponent(reviewTaskIndexFileName, isDirectory: false)
    }

    private func bundlesURL() -> URL {
        rootURL.appendingPathComponent(bundlesDirectoryName, isDirectory: true)
    }

    private func bundleDirectoryURL(for bundleId: UUID) -> URL {
        bundlesURL().appendingPathComponent(bundleId.uuidString, isDirectory: true)
    }

    private func bundleFileURL(for bundleId: UUID) -> URL {
        bundleDirectoryURL(for: bundleId).appendingPathComponent(bundleFileName, isDirectory: false)
    }

    private func resultFileURL(for bundleId: UUID) -> URL {
        bundleDirectoryURL(for: bundleId).appendingPathComponent(resultFileName, isDirectory: false)
    }
}
