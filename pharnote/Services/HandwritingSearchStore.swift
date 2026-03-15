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

    func search(query: String, limit: Int = 20) throws -> [HandwritingSearchHit] {
        try prepareDirectoriesIfNeeded()
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        let lowercasedQuery = trimmedQuery.lowercased()
        let records = try loadRecords().sorted { $0.indexedAt > $1.indexedAt }
        var hits: [HandwritingSearchHit] = []

        for record in records {
            guard let payloadData = try? Data(contentsOf: URL(fileURLWithPath: record.textPayloadPath)),
                  let payloadText = String(data: payloadData, encoding: .utf8) else {
                continue
            }

            let lowercasedPayload = payloadText.lowercased()
            guard let range = lowercasedPayload.range(of: lowercasedQuery) else { continue }

            let utf16Lower = lowercasedPayload.utf16
            let prefixLength = utf16Lower.distance(from: utf16Lower.startIndex, to: range.lowerBound.samePosition(in: utf16Lower) ?? utf16Lower.startIndex)
            let snippet = snippetAroundMatch(in: payloadText, location: prefixLength, length: trimmedQuery.utf16.count)

            hits.append(
                HandwritingSearchHit(
                    id: UUID(),
                    documentID: record.documentID,
                    pageKey: record.pageKey,
                    indexedAt: record.indexedAt,
                    snippet: snippet,
                    matchedText: trimmedQuery
                )
            )

            if hits.count >= limit {
                break
            }
        }

        return hits
    }

    private func snippetAroundMatch(in text: String, location: Int, length: Int) -> String {
        let characters = Array(text)
        guard !characters.isEmpty else { return text }

        let safeLocation = max(0, min(location, characters.count - 1))
        let start = max(0, safeLocation - 30)
        let end = min(characters.count, safeLocation + max(length, 1) + 30)
        let snippet = String(characters[start..<end]).replacingOccurrences(of: "\n", with: " ")

        let prefix = start > 0 ? "…" : ""
        let suffix = end < characters.count ? "…" : ""
        return prefix + snippet + suffix
    }
}
