import Combine
import Foundation
import SQLite3
import UIKit

nonisolated enum StudyEventType: String, Codable, Sendable {
    case appForegrounded = "app_foregrounded"
    case appBackgrounded = "app_backgrounded"
    case documentOpened = "document_opened"
    case documentClosed = "document_closed"
    case pageEnter = "page_enter"
    case pageExit = "page_exit"
    case annotationToolSelected = "annotation_tool_selected"
    case highlightModeSelected = "highlight_mode_selected"
    case highlightRoleSelected = "highlight_role_selected"
    case structuredHighlightCaptured = "structured_highlight_captured"
    case highlightStructureRefreshed = "highlight_structure_refreshed"
    case inputModeChanged = "input_mode_changed"
    case pageBookmarkToggled = "page_bookmark_toggled"
    case undoInvoked = "undo_invoked"
    case redoInvoked = "redo_invoked"
    case strokeBatchCommitted = "stroke_batch_committed"
    case canvasSaved = "canvas_saved"
}

nonisolated enum StudyEventValue: Hashable, Codable, Sendable {
    case string(String)
    case integer(Int)
    case double(Double)
    case bool(Bool)
    case object([String: StudyEventValue])
    case array([StudyEventValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: StudyEventValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([StudyEventValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported event payload value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

typealias StudyEventPayload = [String: StudyEventValue]

nonisolated struct StudyEventRecord: Codable, Identifiable, Hashable, Sendable {
    let eventID: UUID
    let schemaVersion: Int
    let eventType: StudyEventType
    let eventTime: Date
    let sequenceNo: Int
    let learnerID: UUID
    let deviceID: UUID
    let installationID: UUID
    let sessionID: UUID?
    let documentID: UUID?
    let pageID: UUID?
    let documentType: PharDocument.DocumentType?
    let appVersion: String
    let buildNumber: String
    let platform: String
    let payload: StudyEventPayload

    var id: UUID { eventID }

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case schemaVersion = "schema_version"
        case eventType = "event_type"
        case eventTime = "event_time"
        case sequenceNo = "sequence_no"
        case learnerID = "learner_id"
        case deviceID = "device_id"
        case installationID = "installation_id"
        case sessionID = "session_id"
        case documentID = "document_id"
        case pageID = "page_id"
        case documentType = "document_type"
        case appVersion = "app_version"
        case buildNumber = "build_number"
        case platform
        case payload
    }
}

@MainActor
final class StudyEventLogger: ObservableObject {
    static let shared = StudyEventLogger()

    @Published private(set) var lastPersistError: String?

    private let store: StudyEventStore
    private let userDefaults: UserDefaults
    private let encoder: JSONEncoder
    private let learnerKey = "pharnote.event.learner_id"
    private let deviceKey = "pharnote.event.device_id"
    private let installationKey = "pharnote.event.installation_id"
    private let sequenceKey = "pharnote.event.sequence_no"
    private let appVersion: String
    private let buildNumber: String

    init(
        store: StudyEventStore = StudyEventStore(),
        userDefaults: UserDefaults = .standard,
        bundle: Bundle = .main
    ) {
        self.store = store
        self.userDefaults = userDefaults
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        self.buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    func log(
        _ eventType: StudyEventType,
        document: PharDocument? = nil,
        pageID: UUID? = nil,
        sessionID: UUID? = nil,
        payload: StudyEventPayload = [:]
    ) {
        let sequenceNo = nextSequenceNumber()
        let record = StudyEventRecord(
            eventID: UUID(),
            schemaVersion: 1,
            eventType: eventType,
            eventTime: Date(),
            sequenceNo: sequenceNo,
            learnerID: stableUUID(forKey: learnerKey),
            deviceID: stableUUID(forKey: deviceKey),
            installationID: stableUUID(forKey: installationKey),
            sessionID: sessionID,
            documentID: document?.id,
            pageID: pageID,
            documentType: document?.type,
            appVersion: appVersion,
            buildNumber: buildNumber,
            platform: "iPadOS",
            payload: payload
        )

        Task {
            do {
                try await store.append(record, encoder: encoder)
            } catch {
                await MainActor.run {
                    self.lastPersistError = error.localizedDescription
                }
            }
        }
    }

    private func stableUUID(forKey key: String) -> UUID {
        if let rawValue = userDefaults.string(forKey: key),
           let existing = UUID(uuidString: rawValue) {
            return existing
        }

        let newValue = UUID()
        userDefaults.set(newValue.uuidString, forKey: key)
        return newValue
    }

    private func nextSequenceNumber() -> Int {
        let next = userDefaults.integer(forKey: sequenceKey) + 1
        userDefaults.set(next, forKey: sequenceKey)
        return next
    }
}

actor StudyEventStore {
    private let dbURL: URL
    private var db: OpaquePointer?
    private var isConfigured = false

    init(fileManager: FileManager = .default) {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directoryURL = baseURL.appendingPathComponent("pharnote", isDirectory: true)
        self.dbURL = directoryURL.appendingPathComponent("study-events.sqlite", isDirectory: false)
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    func append(_ record: StudyEventRecord, encoder: JSONEncoder) throws {
        try openIfNeeded()
        let payloadData = try encoder.encode(record.payload)
        let payloadJSONString = String(data: payloadData, encoding: .utf8) ?? "{}"
        let createdAt = ISO8601DateFormatter().string(from: Date())
        let eventTime = ISO8601DateFormatter().string(from: record.eventTime)

        let sql = """
        INSERT INTO raw_events (
            event_id,
            schema_version,
            event_type,
            event_time,
            sequence_no,
            learner_id,
            installation_id,
            device_id,
            session_id,
            document_id,
            page_id,
            document_type,
            app_version,
            build_number,
            platform,
            payload_json,
            created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StudyEventStoreError.prepareFailed(message: lastErrorMessage())
        }
        defer { sqlite3_finalize(statement) }

        bindText(record.eventID.uuidString, to: 1, in: statement)
        sqlite3_bind_int(statement, 2, Int32(record.schemaVersion))
        bindText(record.eventType.rawValue, to: 3, in: statement)
        bindText(eventTime, to: 4, in: statement)
        sqlite3_bind_int64(statement, 5, sqlite3_int64(record.sequenceNo))
        bindText(record.learnerID.uuidString, to: 6, in: statement)
        bindText(record.installationID.uuidString, to: 7, in: statement)
        bindText(record.deviceID.uuidString, to: 8, in: statement)
        bindOptionalText(record.sessionID?.uuidString, to: 9, in: statement)
        bindOptionalText(record.documentID?.uuidString, to: 10, in: statement)
        bindOptionalText(record.pageID?.uuidString, to: 11, in: statement)
        bindOptionalText(record.documentType?.rawValue, to: 12, in: statement)
        bindText(record.appVersion, to: 13, in: statement)
        bindText(record.buildNumber, to: 14, in: statement)
        bindText(record.platform, to: 15, in: statement)
        bindText(payloadJSONString, to: 16, in: statement)
        bindText(createdAt, to: 17, in: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StudyEventStoreError.insertFailed(message: lastErrorMessage())
        }
    }

    func fetchPendingRecords(limit: Int) throws -> [StudyEventRecord] {
        try openIfNeeded()
        
        let sql = """
        SELECT 
            event_id, schema_version, event_type, event_time, sequence_no,
            learner_id, device_id, installation_id, session_id, document_id,
            page_id, document_type, app_version, build_number, platform, payload_json
        FROM raw_events
        WHERE sync_state = 'pending'
        ORDER BY event_time ASC
        LIMIT ?;
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StudyEventStoreError.prepareFailed(message: lastErrorMessage())
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_int(statement, 1, Int32(limit))
        
        var records: [StudyEventRecord] = []
        let decoder = JSONDecoder()
        
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let eventIDRaw = columnText(at: 0, in: statement),
                  let eventID = UUID(uuidString: eventIDRaw),
                  let eventTypeRaw = columnText(at: 2, in: statement),
                  let eventType = StudyEventType(rawValue: eventTypeRaw),
                  let eventTimeStr = columnText(at: 3, in: statement),
                  let eventTime = ISO8601DateFormatter().date(from: eventTimeStr),
                  let learnerIDRaw = columnText(at: 5, in: statement),
                  let learnerID = UUID(uuidString: learnerIDRaw),
                  let deviceIDRaw = columnText(at: 6, in: statement),
                  let deviceID = UUID(uuidString: deviceIDRaw),
                  let installationIDRaw = columnText(at: 7, in: statement),
                  let installationID = UUID(uuidString: installationIDRaw),
                  let payloadJSON = columnText(at: 15, in: statement),
                  let payloadData = payloadJSON.data(using: .utf8),
                  let payload = try? decoder.decode(StudyEventPayload.self, from: payloadData)
            else { continue }
            
            let record = StudyEventRecord(
                eventID: eventID,
                schemaVersion: Int(sqlite3_column_int(statement, 1)),
                eventType: eventType,
                eventTime: eventTime,
                sequenceNo: Int(sqlite3_column_int64(statement, 4)),
                learnerID: learnerID,
                deviceID: deviceID,
                installationID: installationID,
                sessionID: columnText(at: 8, in: statement).flatMap { UUID(uuidString: $0) },
                documentID: columnText(at: 9, in: statement).flatMap { UUID(uuidString: $0) },
                pageID: columnText(at: 10, in: statement).flatMap { UUID(uuidString: $0) },
                documentType: columnText(at: 11, in: statement).flatMap { PharDocument.DocumentType(rawValue: $0) },
                appVersion: columnText(at: 12, in: statement) ?? "",
                buildNumber: columnText(at: 13, in: statement) ?? "",
                platform: columnText(at: 14, in: statement) ?? "",
                payload: payload
            )
            records.append(record)
        }
        
        return records
    }

    func updateSyncState(eventIDs: [UUID], newState: String) throws {
        try openIfNeeded()
        guard !eventIDs.isEmpty else { return }
        
        let placeholders = Array(repeating: "?", count: eventIDs.count).joined(separator: ", ")
        let sql = "UPDATE raw_events SET sync_state = ? WHERE event_id IN (\(placeholders));"
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StudyEventStoreError.prepareFailed(message: lastErrorMessage())
        }
        defer { sqlite3_finalize(statement) }
        
        bindText(newState, to: 1, in: statement)
        for (index, id) in eventIDs.enumerated() {
            bindText(id.uuidString, to: Int32(index + 2), in: statement)
        }
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StudyEventStoreError.insertFailed(message: lastErrorMessage())
        }
    }

    private func openIfNeeded() throws {
        guard !isConfigured else { return }

        try FileManager.default.createDirectory(at: dbURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        if sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            throw StudyEventStoreError.openFailed(message: lastErrorMessage())
        }

        let createTableSQL = """
        CREATE TABLE IF NOT EXISTS raw_events (
            event_id TEXT PRIMARY KEY,
            schema_version INTEGER NOT NULL,
            event_type TEXT NOT NULL,
            event_time TEXT NOT NULL,
            sequence_no INTEGER NOT NULL,
            learner_id TEXT NOT NULL,
            installation_id TEXT NOT NULL,
            device_id TEXT NOT NULL,
            session_id TEXT,
            document_id TEXT,
            page_id TEXT,
            document_type TEXT,
            app_version TEXT NOT NULL,
            build_number TEXT NOT NULL,
            platform TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            created_at TEXT NOT NULL,
            sync_state TEXT NOT NULL DEFAULT 'pending'
        );
        CREATE UNIQUE INDEX IF NOT EXISTS idx_raw_events_install_sequence ON raw_events(installation_id, sequence_no);
        CREATE INDEX IF NOT EXISTS idx_raw_events_session_time ON raw_events(session_id, event_time);
        CREATE INDEX IF NOT EXISTS idx_raw_events_page_time ON raw_events(page_id, event_time);
        """

        guard sqlite3_exec(db, createTableSQL, nil, nil, nil) == SQLITE_OK else {
            throw StudyEventStoreError.migrationFailed(message: lastErrorMessage())
        }

        isConfigured = true
    }

    private func columnText(at index: Int32, in statement: OpaquePointer?) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: cString)
    }

    private func bindText(_ value: String, to index: Int32, in statement: OpaquePointer?) {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    private func bindOptionalText(_ value: String?, to index: Int32, in statement: OpaquePointer?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        bindText(value, to: index, in: statement)
    }

    private func lastErrorMessage() -> String {
        guard let db, let cString = sqlite3_errmsg(db) else {
            return "Unknown SQLite error"
        }
        return String(cString: cString)
    }
}

nonisolated(unsafe) private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum StudyEventStoreError: LocalizedError {
    case openFailed(message: String)
    case migrationFailed(message: String)
    case prepareFailed(message: String)
    case insertFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            return "Event DB open failed: \(message)"
        case .migrationFailed(let message):
            return "Event DB migration failed: \(message)"
        case .prepareFailed(let message):
            return "Event DB prepare failed: \(message)"
        case .insertFailed(let message):
            return "Event DB insert failed: \(message)"
        }
    }
}

@MainActor
final class StudyEventSyncEngine: ObservableObject {
    private let store: StudyEventStore
    private let apiClient: PharnodeCloudAPIClient
    private let authManager: PharnodeSupabaseAuthManager
    private let syncManager: PharnodeCloudSyncManager
    
    private var cancellables: Set<AnyCancellable> = []
    private var isSyncing = false
    
    init(
        store: StudyEventStore = StudyEventStore(),
        apiClient: PharnodeCloudAPIClient = PharnodeCloudAPIClient(),
        authManager: PharnodeSupabaseAuthManager,
        syncManager: PharnodeCloudSyncManager
    ) {
        self.store = store
        self.apiClient = apiClient
        self.authManager = authManager
        self.syncManager = syncManager
        
        setupObservers()
    }
    
    private func setupObservers() {
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { await self?.syncPendingEvents() }
            }
            .store(in: &cancellables)
            
        syncManager.$configuration
            .map { $0.isEnabled }
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in
                Task { await self?.syncPendingEvents() }
            }
            .store(in: &cancellables)
    }
    
    func syncPendingEvents() async {
        guard syncManager.configuration.isEnabled else { return }
        guard !isSyncing else { return }
        
        guard let token = await authManager.validAccessToken(), !token.isEmpty else {
            return
        }
        
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            let batchSize = 50
            var hasMore = true
            
            while hasMore {
                let records = try await store.fetchPendingRecords(limit: batchSize)
                guard !records.isEmpty else {
                    hasMore = false
                    continue
                }
                
                let request = PharnodeCloudStudyEventsUploadRequest(
                    events: records,
                    client: makeClientContext()
                )
                
                _ = try await apiClient.uploadStudyEvents(
                    request,
                    configuration: syncManager.configuration,
                    token: token
                )
                
                let eventIDs = records.map { $0.eventID }
                try await store.updateSyncState(eventIDs: eventIDs, newState: "synced")
                
                if records.count < batchSize {
                    hasMore = false
                }
            }
        } catch {
            print("StudyEventSyncEngine: Sync failed - \(error.localizedDescription)")
        }
    }
    
    private func makeClientContext() -> PharnodeCloudClientContext {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return PharnodeCloudClientContext(
            sourceApp: "pharnote",
            appVersion: version,
            platform: "iPadOS",
            locale: Locale.current.identifier,
            timezone: TimeZone.current.identifier
        )
    }
}
