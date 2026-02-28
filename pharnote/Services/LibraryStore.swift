import Foundation

final class LibraryStore {
    enum StoreError: LocalizedError {
        case documentsPathIsNotDirectory
        case invalidPDFSource

        var errorDescription: String? {
            switch self {
            case .documentsPathIsNotDirectory:
                return "Documents 경로가 디렉토리가 아닙니다."
            case .invalidPDFSource:
                return "유효한 PDF 파일이 아닙니다."
            }
        }
    }

    private struct LibraryIndex: Codable {
        let version: Int
        let documents: [PharDocument]
    }

    private let fileManager: FileManager
    private let indexFileName = "LibraryIndex.json"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var indexFileURL: URL {
        documentsDirectory.appendingPathComponent(indexFileName, isDirectory: false)
    }

    func loadIndex() throws -> [PharDocument] {
        try ensureDocumentsDirectoryExists()

        guard fileManager.fileExists(atPath: indexFileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: indexFileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LibraryIndex.self, from: data)
        return decoded.documents
    }

    func saveIndex(_ documents: [PharDocument]) throws {
        try ensureDocumentsDirectoryExists()

        let index = LibraryIndex(version: 1, documents: documents)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(index)
        try data.write(to: indexFileURL, options: .atomic)
    }

    @discardableResult
    func createBlankNote(title: String) throws -> PharDocument {
        try ensureDocumentsDirectoryExists()

        let now = Date()
        let id = UUID()
        let packageURL = documentsDirectory.appendingPathComponent("\(id.uuidString).pharnote", isDirectory: true)
        try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: false)

        let seed = BlankNoteContent.initial(now: now)
        let seedEncoder = JSONEncoder()
        seedEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        seedEncoder.dateEncodingStrategy = .iso8601
        let seedData = try seedEncoder.encode(seed)
        let seedFileURL = packageURL.appendingPathComponent("NoteContent.json", isDirectory: false)
        try seedData.write(to: seedFileURL, options: .atomic)

        var documents = try loadIndex()
        let document = PharDocument(
            id: id,
            title: title,
            createdAt: now,
            updatedAt: now,
            type: .blankNote,
            path: packageURL.path
        )
        documents.append(document)
        try saveIndex(documents)
        return document
    }

    @discardableResult
    func importPDF(from sourceURL: URL) throws -> PharDocument {
        try ensureDocumentsDirectoryExists()

        guard sourceURL.pathExtension.lowercased() == "pdf" else {
            throw StoreError.invalidPDFSource
        }

        let scopedAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if scopedAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let now = Date()
        let id = UUID()
        let packageURL = documentsDirectory.appendingPathComponent("\(id.uuidString).pharnote", isDirectory: true)
        try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: false)

        let destinationPDFURL = packageURL.appendingPathComponent("Original.pdf", isDirectory: false)

        var coordinationError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: sourceURL, options: [], error: &coordinationError) { coordinatedURL in
            do {
                try fileManager.copyItem(at: coordinatedURL, to: destinationPDFURL)
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

        let title = sourceURL.deletingPathExtension().lastPathComponent.isEmpty
            ? "PDF \(id.uuidString.prefix(6))"
            : sourceURL.deletingPathExtension().lastPathComponent

        var documents = try loadIndex()
        let document = PharDocument(
            id: id,
            title: title,
            createdAt: now,
            updatedAt: now,
            type: .pdf,
            path: packageURL.path
        )
        documents.append(document)
        try saveIndex(documents)
        return document
    }

    private func ensureDocumentsDirectoryExists() throws {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: documentsDirectory.path, isDirectory: &isDirectory)

        if exists && !isDirectory.boolValue {
            throw StoreError.documentsPathIsNotDirectory
        }

        if !exists {
            try fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true)
        }
    }
}
