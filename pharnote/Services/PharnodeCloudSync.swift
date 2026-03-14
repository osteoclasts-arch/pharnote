import Combine
import Foundation

struct PharnodeCloudAcceptedResponse: Codable, Hashable, Sendable {
    var status: String?
    var jobId: UUID?
    var acceptedAt: Date?
}

struct PharnodeCloudClientContext: Codable, Hashable, Sendable {
    var sourceApp: String
    var appVersion: String
    var platform: String
    var locale: String
    var timezone: String
}

struct PharnodeCloudAnalysisUploadRequest: Codable, Hashable, Sendable {
    var bundle: AnalysisBundle
    var result: AnalysisResult?
    var assets: PharnodeCloudBundleAssets?
    var client: PharnodeCloudClientContext
}

struct PharnodeCloudBundleAssets: Codable, Hashable, Sendable {
    var previewImageBase64: String?
    var drawingDataBase64: String?
}

struct PharnodeCloudDashboardUploadRequest: Codable, Hashable, Sendable {
    var snapshot: PharnodeDashboardSnapshot
    var reviewTasks: [AnalysisReviewTask]
    var client: PharnodeCloudClientContext
}

enum PharnodeCloudSyncItemKind: String, Codable, Hashable, CaseIterable, Sendable {
    case analysisBundle = "analysis_bundle"
    case dashboardSnapshot = "dashboard_snapshot"

    var title: String {
        switch self {
        case .analysisBundle: return "분석 번들"
        case .dashboardSnapshot: return "대시보드 스냅샷"
        }
    }
}

enum PharnodeCloudSyncItemStatus: String, Codable, Hashable, CaseIterable, Sendable {
    case queued
    case syncing
    case synced
    case failed

    var title: String {
        switch self {
        case .queued: return "대기"
        case .syncing: return "전송 중"
        case .synced: return "완료"
        case .failed: return "실패"
        }
    }
}

struct PharnodeCloudSyncItem: Codable, Hashable, Identifiable, Sendable {
    var itemId: UUID
    var dedupeKey: String
    var kind: PharnodeCloudSyncItemKind
    var status: PharnodeCloudSyncItemStatus
    var createdAt: Date
    var updatedAt: Date
    var lastAttemptAt: Date?
    var lastSyncedAt: Date?
    var attemptCount: Int
    var payloadFilePath: String
    var referenceId: String
    var title: String
    var lastErrorMessage: String?

    var id: UUID { itemId }
}

enum PharnodeCloudSyncState: Equatable {
    case paused
    case idle
    case syncing
    case error(String)

    var title: String {
        switch self {
        case .paused: return "꺼짐"
        case .idle: return "준비됨"
        case .syncing: return "동기화 중"
        case .error: return "오류"
        }
    }
}

actor PharnodeCloudOutboxStore {
    private let fileManager = FileManager.default
    private let rootURL: URL
    private let outboxIndexFileName = "OutboxIndex.json"
    private let payloadDirectoryName = "Payloads"

    private lazy var encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private lazy var decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
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
                .appendingPathComponent("CloudSync", isDirectory: true)
        }
    }

    func loadItems() throws -> [PharnodeCloudSyncItem] {
        try ensureDirectories()
        let fileURL = indexURL()
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([PharnodeCloudSyncItem].self, from: data)
    }

    func enqueuePayload<T: Encodable>(
        _ payload: T,
        kind: PharnodeCloudSyncItemKind,
        dedupeKey: String,
        referenceId: String,
        title: String
    ) throws -> PharnodeCloudSyncItem {
        try ensureDirectories()

        var items = try loadItems()
        let now = Date()
        let itemID = UUID.stableAnalysisTaskID(namespace: UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID(), key: dedupeKey)
        let payloadURL = payloadsURL().appendingPathComponent("\(itemID.uuidString).json", isDirectory: false)
        let data = try encoder.encode(payload)
        try data.write(to: payloadURL, options: .atomic)

        let existingSyncedAt = items.first(where: { $0.itemId == itemID })?.lastSyncedAt
        let item = PharnodeCloudSyncItem(
            itemId: itemID,
            dedupeKey: dedupeKey,
            kind: kind,
            status: .queued,
            createdAt: items.first(where: { $0.itemId == itemID })?.createdAt ?? now,
            updatedAt: now,
            lastAttemptAt: nil,
            lastSyncedAt: existingSyncedAt,
            attemptCount: 0,
            payloadFilePath: payloadURL.path,
            referenceId: referenceId,
            title: title,
            lastErrorMessage: nil
        )

        if let index = items.firstIndex(where: { $0.itemId == itemID }) {
            items[index] = item
        } else {
            items.append(item)
        }

        try persist(items)
        return item
    }

    func loadPayload<T: Decodable>(_ type: T.Type, for item: PharnodeCloudSyncItem) throws -> T {
        let data = try Data(contentsOf: URL(fileURLWithPath: item.payloadFilePath))
        return try decoder.decode(type, from: data)
    }

    func markSyncing(itemId: UUID) throws -> PharnodeCloudSyncItem? {
        try update(itemId: itemId) {
            $0.status = .syncing
            $0.lastAttemptAt = Date()
            $0.attemptCount += 1
            $0.updatedAt = Date()
            $0.lastErrorMessage = nil
        }
    }

    func markSynced(itemId: UUID) throws -> PharnodeCloudSyncItem? {
        try update(itemId: itemId) {
            let now = Date()
            $0.status = .synced
            $0.updatedAt = now
            $0.lastSyncedAt = now
            $0.lastErrorMessage = nil
        }
    }

    func markFailed(itemId: UUID, errorMessage: String) throws -> PharnodeCloudSyncItem? {
        try update(itemId: itemId) {
            $0.status = .failed
            $0.updatedAt = Date()
            $0.lastErrorMessage = errorMessage
        }
    }

    private func update(itemId: UUID, transform: (inout PharnodeCloudSyncItem) -> Void) throws -> PharnodeCloudSyncItem? {
        var items = try loadItems()
        guard let index = items.firstIndex(where: { $0.itemId == itemId }) else { return nil }
        transform(&items[index])
        try persist(items)
        return items[index]
    }

    private func persist(_ items: [PharnodeCloudSyncItem]) throws {
        let sorted = items.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.updatedAt > rhs.updatedAt
        }
        let data = try encoder.encode(sorted)
        try data.write(to: indexURL(), options: .atomic)
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: payloadsURL(), withIntermediateDirectories: true)
    }

    private func indexURL() -> URL {
        rootURL.appendingPathComponent(outboxIndexFileName, isDirectory: false)
    }

    private func payloadsURL() -> URL {
        rootURL.appendingPathComponent(payloadDirectoryName, isDirectory: true)
    }
}

struct PharnodeCloudConfiguration: Codable, Hashable, Sendable {
    var isEnabled: Bool
    var baseURLString: String
    var lastSuccessfulSyncAt: Date?

    static let `default` = PharnodeCloudConfiguration(
        isEnabled: false,
        baseURLString: "https://djxxqvglkqqpkmbudksr.supabase.co",
        lastSuccessfulSyncAt: nil
    )
}

struct PharnodeCloudAPIClient {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func uploadAnalysis(
        _ request: PharnodeCloudAnalysisUploadRequest,
        configuration: PharnodeCloudConfiguration,
        token: String
    ) async throws -> PharnodeCloudAcceptedResponse? {
        try await sendJSON(
            request,
            to: "/functions/v1/pharnote-register-bundle",
            configuration: configuration,
            token: token
        )
    }

    func uploadDashboard(
        _ request: PharnodeCloudDashboardUploadRequest,
        configuration: PharnodeCloudConfiguration,
        token: String
    ) async throws -> PharnodeCloudAcceptedResponse? {
        try await sendJSON(
            request,
            to: "/functions/v1/pharnote-sync-dashboard",
            configuration: configuration,
            token: token
        )
    }

    private func sendJSON<T: Encodable>(
        _ payload: T,
        to path: String,
        configuration: PharnodeCloudConfiguration,
        token: String
    ) async throws -> PharnodeCloudAcceptedResponse? {
        guard let baseURL = URL(string: configuration.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw URLError(.badURL)
        }
        let endpoint = baseURL.appending(path: path)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw NSError(domain: "PharnodeCloudAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }

        guard !data.isEmpty else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PharnodeCloudAcceptedResponse.self, from: data)
    }
}

@MainActor
final class PharnodeCloudSyncManager: ObservableObject {
    @Published private(set) var configuration: PharnodeCloudConfiguration
    @Published private(set) var outboxItems: [PharnodeCloudSyncItem] = []
    @Published private(set) var syncState: PharnodeCloudSyncState = .paused
    @Published private(set) var authTokenConfigured: Bool = false
    @Published var errorMessage: String?

    private let userDefaults: UserDefaults
    private let authManager: PharnodeSupabaseAuthManager
    private let outboxStore: PharnodeCloudOutboxStore
    private let apiClient: PharnodeCloudAPIClient
    private let analysisQueueStore: AnalysisQueueStore
    private let libraryStore: LibraryStore
    private let analysisCenter: AnalysisCenter
    private var cancellables: Set<AnyCancellable> = []
    private let configurationKey = "pharnode_cloud_configuration"

    init(
        analysisCenter: AnalysisCenter,
        authManager: PharnodeSupabaseAuthManager,
        userDefaults: UserDefaults = .standard,
        outboxStore: PharnodeCloudOutboxStore = PharnodeCloudOutboxStore(),
        apiClient: PharnodeCloudAPIClient? = nil,
        analysisQueueStore: AnalysisQueueStore = AnalysisQueueStore(),
        libraryStore: LibraryStore? = nil
    ) {
        self.analysisCenter = analysisCenter
        self.authManager = authManager
        self.userDefaults = userDefaults
        self.outboxStore = outboxStore
        self.apiClient = apiClient ?? PharnodeCloudAPIClient()
        self.analysisQueueStore = analysisQueueStore
        self.libraryStore = libraryStore ?? LibraryStore()
        self.configuration = Self.loadConfiguration(from: userDefaults, key: configurationKey)
        self.authTokenConfigured = authManager.isAuthenticated

        observeAuthState()
        observeAnalysisOutputs()

        Task {
            await refreshOutbox()
            await backfillPendingPayloads()
            await syncPendingIfPossible(trigger: "startup")
        }
    }

    var pendingCount: Int {
        outboxItems.filter { $0.status == .queued || $0.status == .failed || $0.status == .syncing }.count
    }

    var failedCount: Int {
        outboxItems.filter { $0.status == .failed }.count
    }

    var lastSuccessfulSyncAt: Date? {
        configuration.lastSuccessfulSyncAt
    }

    var nextPendingItem: PharnodeCloudSyncItem? {
        outboxItems.first(where: { $0.status == .queued || $0.status == .failed })
    }

    func updateConfiguration(baseURLString: String, isEnabled: Bool) async {
        let normalizedBaseURL = normalizedURLString(baseURLString)
        configuration = PharnodeCloudConfiguration(
            isEnabled: isEnabled,
            baseURLString: normalizedBaseURL,
            lastSuccessfulSyncAt: configuration.lastSuccessfulSyncAt
        )
        persistConfiguration()
        authManager.updateBaseURL(normalizedBaseURL)
        await syncPendingIfPossible(trigger: "configuration-update")
    }

    func enqueueDashboardSnapshot() async {
        do {
            let snapshot = try libraryStore.loadDashboardSnapshot()
            let payload = PharnodeCloudDashboardUploadRequest(
                snapshot: snapshot,
                reviewTasks: analysisCenter.reviewTasks,
                client: makeClientContext()
            )
            _ = try await outboxStore.enqueuePayload(
                payload,
                kind: .dashboardSnapshot,
                dedupeKey: "dashboard::latest",
                referenceId: snapshot.generatedAt.ISO8601Format(),
                title: "Dashboard snapshot"
            )
            await refreshOutbox()
        } catch {
            errorMessage = "대시보드 스냅샷 적재 실패: \(error.localizedDescription)"
        }
    }

    func syncNow() async {
        await backfillPendingPayloads()
        await syncPendingIfPossible(trigger: "manual")
    }

    func refreshOutbox() async {
        do {
            outboxItems = try await outboxStore.loadItems()
            syncState = resolvedSyncState()
        } catch {
            errorMessage = "클라우드 아웃박스 로드 실패: \(error.localizedDescription)"
            syncState = .error(error.localizedDescription)
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func handleAppDidBecomeActive() async {
        await enqueueDashboardSnapshot()
        await syncPendingIfPossible(trigger: "foreground")
    }

    private func observeAnalysisOutputs() {
        analysisCenter.$latestResult
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task {
                    await self.enqueueLatestAnalysisBundle()
                    await self.enqueueDashboardSnapshot()
                    await self.syncPendingIfPossible(trigger: "analysis-updated")
                }
            }
            .store(in: &cancellables)

        analysisCenter.$reviewTasks
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task {
                    await self.enqueueDashboardSnapshot()
                    await self.syncPendingIfPossible(trigger: "review-updated")
                }
            }
            .store(in: &cancellables)
    }

    private func observeAuthState() {
        authManager.$session
            .receive(on: DispatchQueue.main)
            .sink { [weak self] session in
                guard let self else { return }
                self.authTokenConfigured = session != nil
                if session != nil {
                    Task {
                        await self.syncPendingIfPossible(trigger: "auth-updated")
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func enqueueLatestAnalysisBundle() async {
        guard let bundle = analysisCenter.latestBundle else { return }
        do {
            let dedupeKey = "bundle::\(bundle.bundleId.uuidString.lowercased())"
            if try await hasSuccessfullySyncedItem(for: dedupeKey) {
                return
            }
            let result = analysisCenter.result(for: bundle.bundleId)
            
            // Perform heavy asset encoding in a background task
            let assets = try await Task.detached(priority: .background) { () -> PharnodeCloudBundleAssets in
                let imagePath = bundle.content.previewImageRef
                let drawingPath = bundle.content.drawingRef
                
                func base64IfPresent(at path: String?) throws -> String? {
                    guard let path, FileManager.default.fileExists(atPath: path) else { return nil }
                    let data = try Data(contentsOf: URL(fileURLWithPath: path))
                    return data.base64EncodedString()
                }
                
                return PharnodeCloudBundleAssets(
                    previewImageBase64: try base64IfPresent(at: imagePath),
                    drawingDataBase64: try base64IfPresent(at: drawingPath)
                )
            }.value

            let payload = PharnodeCloudAnalysisUploadRequest(
                bundle: bundle,
                result: result,
                assets: assets,
                client: makeClientContext()
            )
            _ = try await outboxStore.enqueuePayload(
                payload,
                kind: .analysisBundle,
                dedupeKey: dedupeKey,
                referenceId: bundle.bundleId.uuidString,
                title: "\(bundle.document.title) · p.\(bundle.page.pageIndex + 1)"
            )
            await refreshOutbox()
        } catch {
            errorMessage = "분석 번들 적재 실패: \(error.localizedDescription)"
        }
    }

    private func backfillPendingPayloads() async {
        do {
            let entries = try await analysisQueueStore.loadEntries()
            for entry in entries where entry.status == .completed {
                guard let bundle = try await safeLoadBundle(bundleId: entry.bundleId) else { continue }
                let dedupeKey = "bundle::\(bundle.bundleId.uuidString.lowercased())"
                if try await hasSuccessfullySyncedItem(for: dedupeKey) {
                    continue
                }
                let result = try await analysisQueueStore.loadResult(bundleId: entry.bundleId)
                
                // Move asset processing to background
                let assets = try await Task.detached(priority: .background) { () -> PharnodeCloudBundleAssets in
                    let imagePath = bundle.content.previewImageRef
                    let drawingPath = bundle.content.drawingRef
                    
                    func base64IfPresent(at path: String?) throws -> String? {
                        guard let path, FileManager.default.fileExists(atPath: path) else { return nil }
                        let data = try Data(contentsOf: URL(fileURLWithPath: path))
                        return data.base64EncodedString()
                    }
                    
                    return PharnodeCloudBundleAssets(
                        previewImageBase64: try base64IfPresent(at: imagePath),
                        drawingDataBase64: try base64IfPresent(at: drawingPath)
                    )
                }.value

                let payload = PharnodeCloudAnalysisUploadRequest(
                    bundle: bundle,
                    result: result,
                    assets: assets,
                    client: makeClientContext()
                )
                _ = try await outboxStore.enqueuePayload(
                    payload,
                    kind: .analysisBundle,
                    dedupeKey: dedupeKey,
                    referenceId: bundle.bundleId.uuidString,
                    title: "\(bundle.document.title) · p.\(bundle.page.pageIndex + 1)"
                )
            }

            await enqueueDashboardSnapshot()
            await refreshOutbox()
        } catch {
            errorMessage = "클라우드 백필 실패: \(error.localizedDescription)"
        }
    }

    private func syncPendingIfPossible(trigger: String) async {
        guard configuration.isEnabled else {
            syncState = .paused
            return
        }
        guard authTokenConfigured, let token = await authManager.validAccessToken(), !token.isEmpty else {
            syncState = .error("Supabase 로그인이 필요합니다.")
            return
        }
        guard URL(string: configuration.baseURLString) != nil else {
            syncState = .error("Supabase project URL이 올바르지 않습니다.")
            return
        }

        do {
            let currentItems = try await outboxStore.loadItems()
            let pendingItems = currentItems.filter { $0.status == .queued || $0.status == .failed }
            guard !pendingItems.isEmpty else {
                outboxItems = currentItems
                syncState = .idle
                return
            }

            syncState = .syncing

            for item in pendingItems {
                _ = try await outboxStore.markSyncing(itemId: item.itemId)

                do {
                    switch item.kind {
                    case .analysisBundle:
                        let payload = try await outboxStore.loadPayload(PharnodeCloudAnalysisUploadRequest.self, for: item)
                        _ = try await apiClient.uploadAnalysis(payload, configuration: configuration, token: token)
                    case .dashboardSnapshot:
                        let payload = try await outboxStore.loadPayload(PharnodeCloudDashboardUploadRequest.self, for: item)
                        _ = try await apiClient.uploadDashboard(payload, configuration: configuration, token: token)
                    }
                    _ = try await outboxStore.markSynced(itemId: item.itemId)
                    configuration.lastSuccessfulSyncAt = Date()
                    persistConfiguration()
                } catch {
                    _ = try await outboxStore.markFailed(itemId: item.itemId, errorMessage: error.localizedDescription)
                    errorMessage = "클라우드 전송 실패(\(item.kind.title)): \(error.localizedDescription)"
                }
            }

            outboxItems = try await outboxStore.loadItems()
            syncState = resolvedSyncState()
        } catch {
            errorMessage = "클라우드 동기화 실패(\(trigger)): \(error.localizedDescription)"
            syncState = .error(error.localizedDescription)
        }
    }

    private func resolvedSyncState() -> PharnodeCloudSyncState {
        guard configuration.isEnabled else { return .paused }
        if let failed = outboxItems.first(where: { $0.status == .failed }), let lastErrorMessage = failed.lastErrorMessage {
            return .error(lastErrorMessage)
        }
        if outboxItems.contains(where: { $0.status == .syncing }) {
            return .syncing
        }
        return .idle
    }

    private func persistConfiguration() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(configuration) {
            userDefaults.set(data, forKey: configurationKey)
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

    private func normalizedURLString(_ candidate: String) -> String {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return PharnodeCloudConfiguration.default.baseURLString }
        let normalized = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        if normalized.hasPrefix("http://") || normalized.hasPrefix("https://") {
            return normalized
        }
        return "https://\(normalized)"
    }


    private func safeLoadBundle(bundleId: UUID) async throws -> AnalysisBundle? {
        do {
            return try await analysisQueueStore.loadBundle(bundleId: bundleId)
        } catch {
            return nil
        }
    }

    private func hasSuccessfullySyncedItem(for dedupeKey: String) async throws -> Bool {
        try await outboxStore.loadItems().contains {
            $0.dedupeKey == dedupeKey && $0.status == .synced
        }
    }

    private static func loadConfiguration(from userDefaults: UserDefaults, key: String) -> PharnodeCloudConfiguration {
        guard let data = userDefaults.data(forKey: key) else { return .default }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(PharnodeCloudConfiguration.self, from: data)) ?? .default
    }
}
