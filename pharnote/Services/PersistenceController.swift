import CloudKit
import Combine
import CoreData
import Foundation

@MainActor
final class PersistenceController: ObservableObject {
    struct PresentedError: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    enum SyncState: Equatable {
        case disabled
        case syncing
        case idle
        case unavailable(String)
        case error(String)

        var bannerMessage: String? {
            switch self {
            case .disabled, .idle:
                return nil
            case .syncing:
                return "Syncing with iCloud..."
            case .unavailable(let message):
                return message
            case .error(let message):
                return message
            }
        }

        var isError: Bool {
            switch self {
            case .unavailable, .error:
                return true
            case .disabled, .syncing, .idle:
                return false
            }
        }
    }

    static let shared = PersistenceController()

    @Published private(set) var container: NSPersistentCloudKitContainer
    @Published private(set) var syncState: SyncState = .disabled
    @Published var presentedError: PresentedError?
    @Published private(set) var contextToken = UUID()

    private let userDefaults: UserDefaults
    private let cloudSyncEnabledKey = "icloud_sync_enabled"
    private let cloudKitContainerIdentifier = "iCloud.nodephar.pharnote"

    private var cloudEventObserver: NSObjectProtocol?
    private var accountStatusTask: Task<Void, Never>?

    var isCloudSyncEnabled: Bool {
        userDefaults.bool(forKey: cloudSyncEnabledKey)
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.userDefaults.register(defaults: [cloudSyncEnabledKey: true])

        let loadResult = Self.makeContainer(
            enableCloudSync: userDefaults.bool(forKey: cloudSyncEnabledKey),
            cloudKitContainerIdentifier: cloudKitContainerIdentifier
        )
        self.container = loadResult.container

        Self.configureViewContext(container.viewContext)
        observeCloudEvents()
        handleLoadResult(loadResult)

        if isCloudSyncEnabled {
            refreshICloudAccountStatus()
        }
    }

    deinit {
        if let cloudEventObserver {
            NotificationCenter.default.removeObserver(cloudEventObserver)
        }
        accountStatusTask?.cancel()
    }

    func setCloudSyncEnabled(_ enabled: Bool) {
        guard enabled != isCloudSyncEnabled else { return }
        userDefaults.set(enabled, forKey: cloudSyncEnabledKey)
        reloadPersistentContainer()
    }

    func refreshICloudAccountStatus() {
        guard isCloudSyncEnabled else {
            syncState = .disabled
            return
        }

        accountStatusTask?.cancel()
        accountStatusTask = Task {
            do {
                let status = try await queryAccountStatus()
                guard !Task.isCancelled else { return }

        switch status {
        case .available:
            // Account is available. Do not keep an indefinite "syncing" state.
            syncState = .idle
                case .noAccount:
                    syncState = .unavailable("iCloud unavailable: please sign in.")
                    presentedError = PresentedError(
                        title: "iCloud Sign-In Required",
                        message: "Sign in to iCloud in Settings to enable cross-device sync. Local note editing still works offline."
                    )
                case .restricted:
                    syncState = .unavailable("iCloud unavailable: account is restricted.")
                case .couldNotDetermine, .temporarilyUnavailable:
                    syncState = .unavailable("iCloud unavailable right now. Working offline.")
                @unknown default:
                    syncState = .unavailable("iCloud status could not be determined.")
                }
            } catch {
                guard !Task.isCancelled else { return }
                syncState = .unavailable("iCloud status check failed. Working offline.")
            }
        }
    }

    func saveViewContextIfNeeded() {
        let context = container.viewContext
        guard context.hasChanges else { return }

        do {
            try context.save()
        } catch {
            context.rollback()
            presentedError = PresentedError(
                title: "Save Failed",
                message: error.localizedDescription
            )
        }
    }

    private func reloadPersistentContainer() {
        if let cloudEventObserver {
            NotificationCenter.default.removeObserver(cloudEventObserver)
            self.cloudEventObserver = nil
        }

        syncState = isCloudSyncEnabled ? .syncing : .disabled

        let loadResult = Self.makeContainer(
            enableCloudSync: isCloudSyncEnabled,
            cloudKitContainerIdentifier: cloudKitContainerIdentifier
        )

        container = loadResult.container
        Self.configureViewContext(container.viewContext)
        observeCloudEvents()

        contextToken = UUID()
        handleLoadResult(loadResult)

        if isCloudSyncEnabled {
            refreshICloudAccountStatus()
        }
    }

    private func handleLoadResult(_ result: ContainerLoadResult) {
        if !isCloudSyncEnabled {
            syncState = .disabled
            return
        }

        if let cloudLoadError = result.cloudLoadError {
            syncState = .unavailable("iCloud unavailable. Working offline.")
            presentedError = PresentedError(
                title: "Cloud Sync Unavailable",
                message: "Falling back to offline mode. Error: \(cloudLoadError.localizedDescription)"
            )
            return
        }

        if let fatalError = result.fatalLoadError {
            syncState = .error("Persistent store failed to load.")
            presentedError = PresentedError(
                title: "Database Load Failed",
                message: fatalError.localizedDescription
            )
            return
        }

        // Store loaded successfully. Idle by default, switch to syncing only on actual CloudKit events.
        syncState = .idle
    }

    private func observeCloudEvents() {
        cloudEventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated { [weak self] in
                self?.handleCloudEvent(notification)
            }
        }
    }

    private func handleCloudEvent(_ notification: Notification) {
        guard
            isCloudSyncEnabled,
            let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event
        else {
            return
        }

        if let error = event.error {
            syncState = .error("Sync failed: \(error.localizedDescription)")
            presentedError = PresentedError(
                title: "Sync Error",
                message: error.localizedDescription
            )
            return
        }

        if event.endDate == nil {
            syncState = .syncing
        } else {
            syncState = .idle
        }
    }

    private func queryAccountStatus() async throws -> CKAccountStatus {
        try await withCheckedThrowingContinuation { continuation in
            CKContainer(identifier: cloudKitContainerIdentifier).accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    private struct ContainerLoadResult {
        let container: NSPersistentCloudKitContainer
        let cloudLoadError: Error?
        let fatalLoadError: Error?
    }

    private static func makeContainer(
        enableCloudSync: Bool,
        cloudKitContainerIdentifier: String
    ) -> ContainerLoadResult {
        let managedObjectModel = Self.makeManagedObjectModel()

        let cloudContainer = NSPersistentCloudKitContainer(
            name: "ParNote",
            managedObjectModel: managedObjectModel
        )
        cloudContainer.persistentStoreDescriptions = [
            makeStoreDescription(
                enableCloudSync: enableCloudSync,
                cloudKitContainerIdentifier: cloudKitContainerIdentifier
            )
        ]

        var cloudLoadError: Error?
        cloudContainer.loadPersistentStores { _, error in
            cloudLoadError = error
        }

        if cloudLoadError == nil {
            return ContainerLoadResult(
                container: cloudContainer,
                cloudLoadError: nil,
                fatalLoadError: nil
            )
        }

        // Cloud store failed. Fallback to local-only store for offline mode.
        let localContainer = NSPersistentCloudKitContainer(
            name: "ParNote",
            managedObjectModel: managedObjectModel
        )
        localContainer.persistentStoreDescriptions = [
            makeStoreDescription(enableCloudSync: false, cloudKitContainerIdentifier: cloudKitContainerIdentifier)
        ]

        var localLoadError: Error?
        localContainer.loadPersistentStores { _, error in
            localLoadError = error
        }

        return ContainerLoadResult(
            container: localContainer,
            cloudLoadError: enableCloudSync ? cloudLoadError : nil,
            fatalLoadError: localLoadError
        )
    }

    private static func makeStoreDescription(
        enableCloudSync: Bool,
        cloudKitContainerIdentifier: String
    ) -> NSPersistentStoreDescription {
        let storeURL = NSPersistentContainer.defaultDirectoryURL().appendingPathComponent("ParNote.sqlite")
        let description = NSPersistentStoreDescription(url: storeURL)
        description.type = NSSQLiteStoreType
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.shouldAddStoreAsynchronously = false
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        if enableCloudSync {
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: cloudKitContainerIdentifier
            )
        } else {
            description.cloudKitContainerOptions = nil
        }

        return description
    }

    private static func configureViewContext(_ viewContext: NSManagedObjectContext) {
        viewContext.automaticallyMergesChangesFromParent = true
        viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        viewContext.undoManager = UndoManager()

        do {
            try viewContext.setQueryGenerationFrom(.current)
        } catch {
            // Query generation pinning is best-effort.
        }
    }

    private static func makeManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let noteEntity = NSEntityDescription()
        noteEntity.name = "Note"
        noteEntity.managedObjectClassName = NSStringFromClass(Note.self)

        let id = NSAttributeDescription()
        id.name = "id"
        id.attributeType = .UUIDAttributeType
        id.isOptional = true

        let title = NSAttributeDescription()
        title.name = "title"
        title.attributeType = .stringAttributeType
        title.isOptional = true

        let body = NSAttributeDescription()
        body.name = "body"
        body.attributeType = .stringAttributeType
        body.isOptional = true

        let createdAt = NSAttributeDescription()
        createdAt.name = "createdAt"
        createdAt.attributeType = .dateAttributeType
        createdAt.isOptional = true

        let updatedAt = NSAttributeDescription()
        updatedAt.name = "updatedAt"
        updatedAt.attributeType = .dateAttributeType
        updatedAt.isOptional = true

        let tags = NSAttributeDescription()
        tags.name = "tags"
        tags.attributeType = .stringAttributeType
        tags.isOptional = true

        let isLocked = NSAttributeDescription()
        isLocked.name = "isLocked"
        isLocked.attributeType = .booleanAttributeType
        isLocked.isOptional = false
        isLocked.defaultValue = false

        noteEntity.properties = [id, title, body, createdAt, updatedAt, tags, isLocked]
        model.entities = [noteEntity]

        return model
    }
}
