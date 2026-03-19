import CryptoKit
import Foundation

actor HighlightStructureStore {
    private let fileManager = FileManager.default
    private let fileName = "HighlightStructure.json"

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

    func loadItems(documentURL: URL, pageKey: String) -> [HighlightStructureItem] {
        let fileURL = fileURL(documentURL: documentURL, pageKey: pageKey)
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([HighlightStructureItem].self, from: data)) ?? []
    }

    func saveItems(_ items: [HighlightStructureItem], documentURL: URL, pageKey: String) throws {
        let directoryURL = highlightsDirectoryURL(documentURL: documentURL)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = fileURL(documentURL: documentURL, pageKey: pageKey)
        let data = try encoder.encode(items.sorted(by: { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }))
        try data.write(to: fileURL, options: .atomic)
    }

    func deleteItems(documentURL: URL, pageKey: String) {
        let fileURL = fileURL(documentURL: documentURL, pageKey: pageKey)
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try? fileManager.removeItem(at: fileURL)
    }

    private func highlightsDirectoryURL(documentURL: URL) -> URL {
        documentURL.appendingPathComponent("HighlightStructure", isDirectory: true)
    }

    private func fileURL(documentURL: URL, pageKey: String) -> URL {
        let digest = sha256Hex(pageKey.lowercased())
        return highlightsDirectoryURL(documentURL: documentURL)
            .appendingPathComponent("\(digest).json", isDirectory: false)
    }

    private func sha256Hex(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
