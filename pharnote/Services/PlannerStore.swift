import Foundation

actor PlannerStore {
    private let fileManager = FileManager.default
    private let rootURL: URL
    private let stateFileName = "PlannerState.json"

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
                .appendingPathComponent("Planner", isDirectory: true)
        }
    }

    func loadState() throws -> PlannerState {
        try ensureDirectories()
        let fileURL = stateURL()
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return PlannerState.defaultState()
        }

        let data = try Data(contentsOf: fileURL)
        let state = try decoder.decode(PlannerState.self, from: data)
        if state.tasks.isEmpty && state.dDayItems.isEmpty {
            return PlannerState.defaultState()
        }
        return state
    }

    func saveState(_ state: PlannerState) throws {
        try ensureDirectories()
        let data = try encoder.encode(state)
        try data.write(to: stateURL(), options: .atomic)
    }

    func reset() throws -> PlannerState {
        let state = PlannerState.defaultState()
        try saveState(state)
        return state
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    private func stateURL() -> URL {
        rootURL.appendingPathComponent(stateFileName, isDirectory: false)
    }
}
