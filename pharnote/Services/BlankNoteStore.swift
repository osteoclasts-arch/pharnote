import CoreGraphics
import Foundation
import PencilKit
import UIKit

actor BlankNoteStore {
    enum StoreError: LocalizedError {
        case invalidNoteContentFormat

        var errorDescription: String? {
            switch self {
            case .invalidNoteContentFormat:
                return "노트 메타데이터 형식이 유효하지 않습니다."
            }
        }
    }

    private struct LegacyBlankNoteSeed: Codable {
        let version: Int
        let pages: Int
    }

    private let fileManager = FileManager.default
    private let noteContentFileName = "NoteContent.json"
    private let drawingsDirectoryName = "Drawings"
    private let thumbnailsDirectoryName = "Thumbnails"

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

    func loadOrCreateContent(documentURL: URL) throws -> BlankNoteContent {
        try ensureDocumentDirectoryExists(documentURL)

        let contentURL = noteContentURL(documentURL: documentURL)
        guard fileManager.fileExists(atPath: contentURL.path) else {
            let initial = BlankNoteContent.initial()
            try saveContent(initial, documentURL: documentURL)
            return initial
        }

        let data = try Data(contentsOf: contentURL)

        if var content = try? decoder.decode(BlankNoteContent.self, from: data) {
            if content.pages.isEmpty {
                content = BlankNoteContent.initial()
                try saveContent(content, documentURL: documentURL)
            }
            if let firstPageID = content.pages.first?.id {
                try migrateLegacySinglePageDrawingIfNeeded(documentURL: documentURL, firstPageID: firstPageID)
            }
            return content
        }

        if let legacy = try? decoder.decode(LegacyBlankNoteSeed.self, from: data) {
            let pageCount = max(1, legacy.pages)
            let now = Date()
            let pages = (0..<pageCount).map { _ in
                BlankNotePage(id: UUID(), createdAt: now, updatedAt: now)
            }
            let migrated = BlankNoteContent(version: 2, pages: pages)
            try saveContent(migrated, documentURL: documentURL)
            if let firstPageID = migrated.pages.first?.id {
                try migrateLegacySinglePageDrawingIfNeeded(documentURL: documentURL, firstPageID: firstPageID)
            }
            return migrated
        }

        throw StoreError.invalidNoteContentFormat
    }

    func saveContent(_ content: BlankNoteContent, documentURL: URL) throws {
        try ensureDocumentDirectoryExists(documentURL)
        let contentURL = noteContentURL(documentURL: documentURL)
        let data = try encoder.encode(content)
        try data.write(to: contentURL, options: .atomic)
    }

    func loadDrawingData(documentURL: URL, pageID: UUID) -> Data? {
        let fileURL = drawingFileURL(documentURL: documentURL, pageID: pageID)
        return try? Data(contentsOf: fileURL)
    }

    func saveDrawingData(_ data: Data, documentURL: URL, pageID: UUID) throws {
        let directoryURL = drawingsDirectoryURL(documentURL: documentURL)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = drawingFileURL(documentURL: documentURL, pageID: pageID)
        try data.write(to: fileURL, options: .atomic)
    }

    func deleteDrawingData(documentURL: URL, pageID: UUID) {
        let fileURL = drawingFileURL(documentURL: documentURL, pageID: pageID)
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try? fileManager.removeItem(at: fileURL)
    }

    func loadThumbnailData(documentURL: URL, pageID: UUID) -> Data? {
        let fileURL = thumbnailFileURL(documentURL: documentURL, pageID: pageID)
        return try? Data(contentsOf: fileURL)
    }

    func saveThumbnailData(_ data: Data, documentURL: URL, pageID: UUID) throws {
        let directoryURL = thumbnailsDirectoryURL(documentURL: documentURL)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = thumbnailFileURL(documentURL: documentURL, pageID: pageID)
        try data.write(to: fileURL, options: .atomic)
    }

    func deleteThumbnailData(documentURL: URL, pageID: UUID) {
        let fileURL = thumbnailFileURL(documentURL: documentURL, pageID: pageID)
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try? fileManager.removeItem(at: fileURL)
    }

    func generateThumbnailPNG(from drawingData: Data, thumbnailSize: CGSize, scale: CGFloat) -> Data? {
        guard let drawing = try? PKDrawing(data: drawingData) else { return nil }
        let image = drawing.image(from: CGRect(origin: .zero, size: thumbnailSize), scale: scale)
        return image.pngData()
    }

    private func migrateLegacySinglePageDrawingIfNeeded(documentURL: URL, firstPageID: UUID) throws {
        let legacyURL = documentURL.appendingPathComponent("drawing.data", isDirectory: false)
        guard fileManager.fileExists(atPath: legacyURL.path) else { return }

        let migratedURL = drawingFileURL(documentURL: documentURL, pageID: firstPageID)
        guard !fileManager.fileExists(atPath: migratedURL.path) else { return }

        try fileManager.createDirectory(at: drawingsDirectoryURL(documentURL: documentURL), withIntermediateDirectories: true)
        try fileManager.copyItem(at: legacyURL, to: migratedURL)
    }

    private func ensureDocumentDirectoryExists(_ documentURL: URL) throws {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: documentURL.path, isDirectory: &isDirectory)
        if exists && isDirectory.boolValue {
            return
        }
        if exists && !isDirectory.boolValue {
            try fileManager.removeItem(at: documentURL)
        }
        try fileManager.createDirectory(at: documentURL, withIntermediateDirectories: true)
    }

    private func noteContentURL(documentURL: URL) -> URL {
        documentURL.appendingPathComponent(noteContentFileName, isDirectory: false)
    }

    private func drawingsDirectoryURL(documentURL: URL) -> URL {
        documentURL.appendingPathComponent(drawingsDirectoryName, isDirectory: true)
    }

    private func drawingFileURL(documentURL: URL, pageID: UUID) -> URL {
        drawingsDirectoryURL(documentURL: documentURL)
            .appendingPathComponent("\(pageID.uuidString).drawing", isDirectory: false)
    }

    private func thumbnailsDirectoryURL(documentURL: URL) -> URL {
        documentURL.appendingPathComponent(thumbnailsDirectoryName, isDirectory: true)
    }

    private func thumbnailFileURL(documentURL: URL, pageID: UUID) -> URL {
        thumbnailsDirectoryURL(documentURL: documentURL)
            .appendingPathComponent("\(pageID.uuidString).png", isDirectory: false)
    }
}
