import Foundation

actor NodeAnalysisStore {
    private let fileManager = FileManager.default
    private let rootURL: URL
    private let weaknessesFileName = "WeaknessRecords.json"

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
                .appendingPathComponent("NodeAnalysis", isDirectory: true)
        }
    }

    func loadWeaknessRecords() throws -> [NodeAnalysisWeaknessRecord] {
        try ensureDirectories()
        let fileURL = weaknessesFileURL()
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([NodeAnalysisWeaknessRecord].self, from: data)
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString > rhs.id.uuidString
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    func saveWeaknessRecord(_ record: NodeAnalysisWeaknessRecord) throws {
        var records = try loadWeaknessRecords()
        records.removeAll { $0.id == record.id }
        records.insert(record, at: 0)
        try persist(records)
    }

    private func persist(_ records: [NodeAnalysisWeaknessRecord]) throws {
        try ensureDirectories()
        let data = try encoder.encode(records)
        try data.write(to: weaknessesFileURL(), options: .atomic)
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    private func weaknessesFileURL() -> URL {
        rootURL.appendingPathComponent(weaknessesFileName, isDirectory: false)
    }
}
