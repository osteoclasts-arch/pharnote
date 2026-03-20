import Foundation

actor ReviewSessionRepository {
    private let fileManager = FileManager.default
    private let rootURL: URL
    private let sessionsFileName = "ReviewSessions.json"

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
            let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.rootURL = applicationSupport
                .appendingPathComponent("pharnote", isDirectory: true)
                .appendingPathComponent("ReviewSessions", isDirectory: true)
        }
    }

    func loadAllSessions() throws -> [ReviewSession] {
        try ensureDirectories()
        let fileURL = sessionsFileURL()
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }

        let data = try Data(contentsOf: fileURL)
        let payload = try decoder.decode(ReviewSessionStorePayload.self, from: data)
        return payload.sessions.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.startedAt > rhs.startedAt
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    func loadSessions(for documentId: UUID, pageIndex: Int? = nil) throws -> [ReviewSession] {
        let sessions = try loadAllSessions()
        return sessions.filter { session in
            session.documentId == documentId && (pageIndex == nil || session.pageIndex == pageIndex)
        }
    }

    func loadLatestSession(for resumeKey: String) throws -> ReviewSession? {
        let sessions = try loadAllSessions()
        return sessions.first(where: { $0.resumeKey == resumeKey })
    }

    func loadLatestDraft(for resumeKey: String) throws -> ReviewSession? {
        let sessions = try loadAllSessions()
        return sessions.first(where: { $0.resumeKey == resumeKey && $0.status != .completed && $0.status != .abandoned })
    }

    func upsert(_ session: ReviewSession) throws {
        var sessions = try loadAllSessions()
        sessions.removeAll { $0.id == session.id }
        sessions.insert(session, at: 0)
        try persist(sessions)
    }

    func markAbandoned(sessionId: UUID) throws {
        var sessions = try loadAllSessions()
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        var session = sessions[index]
        session.status = .abandoned
        session.updatedAt = Date()
        session.lastAutosavedAt = Date()
        session.autosaveVersion += 1
        sessions[index] = session
        try persist(sessions)
    }

    private func persist(_ sessions: [ReviewSession]) throws {
        try ensureDirectories()
        let payload = ReviewSessionStorePayload(sessions: sessions.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.startedAt > rhs.startedAt
            }
            return lhs.updatedAt > rhs.updatedAt
        })
        let data = try encoder.encode(payload)
        try data.write(to: sessionsFileURL(), options: .atomic)
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    private func sessionsFileURL() -> URL {
        rootURL.appendingPathComponent(sessionsFileName, isDirectory: false)
    }
}
