import Foundation

actor HandwritingSearchStore {
    private let fileManager = FileManager.default

    private lazy var rootDirectoryURL: URL = {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent(SearchIndexStorageLayout.rootDirectoryName, isDirectory: true)
    }()

    private var metadataDirectoryURL: URL {
        rootDirectoryURL.appendingPathComponent(SearchIndexStorageLayout.metadataDirectoryName, isDirectory: true)
    }

    private var payloadDirectoryURL: URL {
        rootDirectoryURL.appendingPathComponent(SearchIndexStorageLayout.payloadDirectoryName, isDirectory: true)
    }

    private var handwritingPayloadDirectoryURL: URL {
        payloadDirectoryURL.appendingPathComponent(SearchIndexStorageLayout.handwritingPayloadDirectoryName, isDirectory: true)
    }

    private var jobsFileURL: URL {
        metadataDirectoryURL.appendingPathComponent(SearchIndexStorageLayout.jobsFileName, isDirectory: false)
    }

    private var recordsFileURL: URL {
        metadataDirectoryURL.appendingPathComponent(SearchIndexStorageLayout.recordsFileName, isDirectory: false)
    }

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

    func prepareDirectoriesIfNeeded() throws {
        try fileManager.createDirectory(at: metadataDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: handwritingPayloadDirectoryURL, withIntermediateDirectories: true)
    }

    func loadJobs() throws -> [HandwritingIndexJob] {
        try prepareDirectoriesIfNeeded()
        guard fileManager.fileExists(atPath: jobsFileURL.path) else { return [] }
        let data = try Data(contentsOf: jobsFileURL)
        return try decoder.decode([HandwritingIndexJob].self, from: data)
    }

    func saveJobs(_ jobs: [HandwritingIndexJob]) throws {
        try prepareDirectoriesIfNeeded()
        let data = try encoder.encode(jobs)
        try data.write(to: jobsFileURL, options: .atomic)
    }

    func loadRecords() throws -> [HandwritingIndexRecord] {
        try prepareDirectoriesIfNeeded()
        guard fileManager.fileExists(atPath: recordsFileURL.path) else { return [] }
        let data = try Data(contentsOf: recordsFileURL)
        return try decoder.decode([HandwritingIndexRecord].self, from: data)
    }

    func saveRecords(_ records: [HandwritingIndexRecord]) throws {
        try prepareDirectoriesIfNeeded()
        let data = try encoder.encode(records)
        try data.write(to: recordsFileURL, options: .atomic)
    }

    func saveHandwritingTextPayload(_ text: String, job: HandwritingIndexJob) throws -> String {
        try prepareDirectoriesIfNeeded()
        let payloadFileName = "\(job.documentID.uuidString)_\(job.pageKey).txt"
        let payloadURL = handwritingPayloadDirectoryURL.appendingPathComponent(payloadFileName, isDirectory: false)
        let payloadData = Data(text.utf8)
        try payloadData.write(to: payloadURL, options: .atomic)
        return payloadURL.path
    }
}
