import Foundation

enum PharnoteShareConstants {
    static let appGroupIdentifier = "group.nodephar.pharnote.shared"
    static let urlScheme = "pharnote"
    static let importHost = "import-share"
    static let incomingDirectoryName = "IncomingShares"
}

struct PharnoteIncomingShareReference: Hashable, Codable {
    let token: String
    let originalFileName: String
}

struct PharnoteShareImportURL: Hashable {
    let token: String

    static func parse(_ url: URL) -> PharnoteShareImportURL? {
        guard url.scheme == PharnoteShareConstants.urlScheme else { return nil }
        guard url.host == PharnoteShareConstants.importHost else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return PharnoteShareImportURL(token: token)
    }

    func makeURL() -> URL? {
        var components = URLComponents()
        components.scheme = PharnoteShareConstants.urlScheme
        components.host = PharnoteShareConstants.importHost
        components.queryItems = [
            URLQueryItem(name: "token", value: token)
        ]
        return components.url
    }
}

final class PharnoteSharedIncomingDocumentStore {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func persistIncomingFile(from sourceURL: URL) throws -> PharnoteIncomingShareReference {
        let token = UUID().uuidString.lowercased()
        let directoryURL = try incomingDirectoryURL().appendingPathComponent(token, isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let fileName = normalizedIncomingFileName(for: sourceURL, token: token)
        let destinationURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)

        let scopedAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if scopedAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        var coordinationError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: sourceURL, options: [], error: &coordinationError) { coordinatedURL in
            do {
                if self.fileManager.fileExists(atPath: destinationURL.path) {
                    try self.fileManager.removeItem(at: destinationURL)
                }
                try self.fileManager.copyItem(at: coordinatedURL, to: destinationURL)
            } catch {
                copyError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let copyError {
            throw copyError
        }

        return PharnoteIncomingShareReference(token: token, originalFileName: fileName)
    }

    func incomingFileURL(for token: String) -> URL? {
        let directoryURL = incomingDirectoryURL().appendingPathComponent(token, isDirectory: true)
        guard fileManager.fileExists(atPath: directoryURL.path) else { return nil }

        let contents = (try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)) ?? []
        return contents.sorted { $0.lastPathComponent < $1.lastPathComponent }.first
    }

    func removeIncomingFile(for token: String) {
        let directoryURL = incomingDirectoryURL().appendingPathComponent(token, isDirectory: true)
        guard fileManager.fileExists(atPath: directoryURL.path) else { return }
        try? fileManager.removeItem(at: directoryURL)
    }

    private func incomingDirectoryURL() -> URL {
        guard let groupURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: PharnoteShareConstants.appGroupIdentifier
        ) else {
            return fileManager.temporaryDirectory.appendingPathComponent(PharnoteShareConstants.incomingDirectoryName, isDirectory: true)
        }

        return groupURL.appendingPathComponent(PharnoteShareConstants.incomingDirectoryName, isDirectory: true)
    }

    private func normalizedIncomingFileName(for sourceURL: URL, token: String) -> String {
        let original = sourceURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !original.isEmpty {
            return original
        }

        let ext = sourceURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        if ext.isEmpty {
            return "\(token).pdf"
        }
        return "\(token).\(ext)"
    }
}
