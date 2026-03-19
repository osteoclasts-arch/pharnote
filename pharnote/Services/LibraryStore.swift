import Foundation
import PDFKit
import UIKit

struct PharnodeDashboardSnapshot: Codable, Hashable {
    let version: Int
    let generatedAt: Date
    let materials: [PharnodeDashboardMaterialProgress]
}

struct PharnodeDashboardMaterialProgress: Codable, Hashable, Identifiable {
    let documentId: UUID
    let documentTitle: String
    let documentType: PharDocument.DocumentType
    let provider: String?
    let subject: String?
    let canonicalTitle: String?
    let currentPage: Int?
    let totalPages: Int?
    let furthestPage: Int?
    let completionRatio: Double?
    let lastStudiedAt: Date?
    let currentSection: String?
    let nextSection: String?
    let completedSectionCount: Int?
    let totalSectionCount: Int?
    let sectionHeadline: String?
    let sectionSubheadline: String?
    let sections: [PharnodeDashboardSectionProgress]

    var id: UUID { documentId }

    var percentComplete: Int {
        Int(((completionRatio ?? 0) * 100).rounded())
    }
}

struct PharnodeDashboardSectionProgress: Codable, Hashable, Identifiable {
    let title: String
    let startPage: Int
    let endPage: Int
    let status: String
    let completionRatio: Double

    var id: String { "\(title)-\(startPage)-\(endPage)" }

    var percentComplete: Int {
        Int((completionRatio * 100).rounded())
    }
}

final class LibraryStore {
    enum StoreError: LocalizedError {
        case documentsPathIsNotDirectory
        case invalidPDFSource
        case invalidImageSource

        var errorDescription: String? {
            switch self {
            case .documentsPathIsNotDirectory:
                return "Documents 경로가 디렉토리가 아닙니다."
            case .invalidPDFSource:
                return "유효한 PDF 파일이 아닙니다."
            case .invalidImageSource:
                return "유효한 이미지 파일이 아닙니다."
            }
        }
    }

    private struct LibraryIndex: Codable {
        let version: Int
        let documents: [PharDocument]
    }

    private struct FolderIndex: Codable {
        let version: Int
        let folders: [UserLibraryFolder]
    }

    private let fileManager: FileManager
    private let indexFileName = "LibraryIndex.json"
    private let foldersFileName = "LibraryFolders.json"
    private let dashboardFileName = "PharnodeDashboardSnapshot.json"
    private let ubiquityContainerIdentifier = "iCloud.nodephar.pharnote"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    private var localDocumentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var ubiquitousDocumentsDirectory: URL? {
        fileManager.url(forUbiquityContainerIdentifier: ubiquityContainerIdentifier)?
            .appendingPathComponent("Documents", isDirectory: true)
    }

    private var documentsDirectory: URL {
        ubiquitousDocumentsDirectory ?? localDocumentsDirectory
    }

    private var indexFileURL: URL {
        documentsDirectory.appendingPathComponent(indexFileName, isDirectory: false)
    }

    private var dashboardFileURL: URL {
        documentsDirectory.appendingPathComponent(dashboardFileName, isDirectory: false)
    }

    private var foldersFileURL: URL {
        documentsDirectory.appendingPathComponent(foldersFileName, isDirectory: false)
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
        return decoded.documents.map { normalizeDocumentPath($0, relativeTo: documentsDirectory) }
    }

    func saveIndex(_ documents: [PharDocument]) throws {
        try ensureDocumentsDirectoryExists()

        let index = LibraryIndex(version: 1, documents: documents)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(index)
        try data.write(to: indexFileURL, options: .atomic)
        try writeDashboardSnapshot(documents, using: encoder)
    }

    func loadFolders() throws -> [UserLibraryFolder] {
        try ensureDocumentsDirectoryExists()

        guard fileManager.fileExists(atPath: foldersFileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: foldersFileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let decoded = try? decoder.decode(FolderIndex.self, from: data) {
            return decoded.folders.sorted { $0.updatedAt > $1.updatedAt }
        }

        return []
    }

    func saveFolders(_ folders: [UserLibraryFolder]) throws {
        try ensureDocumentsDirectoryExists()
        let index = FolderIndex(version: 1, folders: folders)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(index)
        try data.write(to: foldersFileURL, options: .atomic)
    }

    @discardableResult
    func createFolder(name: String, accentHex: UInt = 0xF1E1D0) throws -> UserLibraryFolder {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return UserLibraryFolder(name: "새 폴더", accentHex: accentHex) }

        var folders = try loadFolders()
        let folder = UserLibraryFolder(name: trimmed, accentHex: accentHex)
        folders.append(folder)
        try saveFolders(folders)
        return folder
    }

    @discardableResult
    func updateFolder(_ updatedFolder: UserLibraryFolder) throws -> UserLibraryFolder {
        var folders = try loadFolders()
        if let index = folders.firstIndex(where: { $0.id == updatedFolder.id }) {
            folders[index] = updatedFolder
        } else {
            folders.append(updatedFolder)
        }
        try saveFolders(folders)
        return updatedFolder
    }

    func deleteFolder(_ folderID: UUID) throws {
        var folders = try loadFolders()
        folders.removeAll { $0.id == folderID }
        try saveFolders(folders)

        var documents = try loadIndex()
        var changed = false
        for index in documents.indices where documents[index].folderID == folderID {
            documents[index].folderID = nil
            changed = true
        }
        if changed {
            try saveIndex(documents)
        }
    }

    @discardableResult
    func updateDocumentFolder(documentID: UUID, folderID: UUID?) throws -> PharDocument? {
        var documents = try loadIndex()
        guard let index = documents.firstIndex(where: { $0.id == documentID }) else { return nil }
        documents[index].folderID = folderID
        documents[index].updatedAt = Date()
        try saveIndex(documents)
        return documents[index]
    }

    func loadDashboardSnapshot() throws -> PharnodeDashboardSnapshot {
        try ensureDocumentsDirectoryExists()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if fileManager.fileExists(atPath: dashboardFileURL.path) {
            let data = try Data(contentsOf: dashboardFileURL)
            return try decoder.decode(PharnodeDashboardSnapshot.self, from: data)
        }

        return makeDashboardSnapshot(from: try loadIndex())
    }

    func loadDashboardSnapshotJSONString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(loadDashboardSnapshot())
        return String(decoding: data, as: UTF8.self)
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
    func importPDF(
        from sourceURL: URL,
        suggestedMaterial: StudyMaterialMetadata? = nil,
        pageCountHint: Int? = nil
    ) throws -> PharDocument {
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
        let loadedPDFDocument = PDFDocument(url: destinationPDFURL)
        let pdfPageCount = pageCountHint ?? loadedPDFDocument?.pageCount
        let sections = loadedPDFDocument.map(extractSections(from:)) ?? []
        let initialProgress = pdfPageCount.map {
            StudyProgressSnapshot(
                currentPage: 1,
                totalPages: $0,
                furthestPage: 1,
                completionRatio: $0 > 0 ? (1.0 / Double($0)) : 0,
                lastStudiedAt: now,
                sections: Self.sectionSnapshots(for: 1, totalPages: $0, sections: sections)
            )
        }

        var documents = try loadIndex()
        let document = PharDocument(
            id: id,
            title: title,
            createdAt: now,
            updatedAt: now,
            type: .pdf,
            path: packageURL.path,
            studyMaterial: suggestedMaterial,
            progress: initialProgress
        )
        documents.append(document)
        try saveIndex(documents)
        return document
    }

    @discardableResult
    func importImageAsPDF(from sourceURL: URL) throws -> PharDocument {
        try ensureDocumentsDirectoryExists()

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
        var importError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: sourceURL, options: [], error: &coordinationError) { coordinatedURL in
            do {
                let imageData = try Data(contentsOf: coordinatedURL)
                guard let image = UIImage(data: imageData) else {
                    throw StoreError.invalidImageSource
                }
                let pdfData = makeSinglePagePDFData(from: image)
                try pdfData.write(to: destinationPDFURL, options: .atomic)
            } catch {
                importError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let importError {
            throw importError
        }

        let title = sourceURL.deletingPathExtension().lastPathComponent.isEmpty
            ? "이미지 \(id.uuidString.prefix(6))"
            : sourceURL.deletingPathExtension().lastPathComponent

        let initialProgress = StudyProgressSnapshot(
            currentPage: 1,
            totalPages: 1,
            furthestPage: 1,
            completionRatio: 1,
            lastStudiedAt: now,
            sections: []
        )

        var documents = try loadIndex()
        let document = PharDocument(
            id: id,
            title: title,
            createdAt: now,
            updatedAt: now,
            type: .pdf,
            path: packageURL.path,
            progress: initialProgress
        )
        documents.append(document)
        try saveIndex(documents)
        return document
    }

    @discardableResult
    func updateDocument(_ updatedDocument: PharDocument) throws -> PharDocument {
        var documents = try loadIndex()
        guard let index = documents.firstIndex(where: { $0.id == updatedDocument.id }) else {
            try saveIndex(documents)
            return updatedDocument
        }
        documents[index] = updatedDocument
        try saveIndex(documents)
        return updatedDocument
    }

    @discardableResult
    func updateStudyProgress(documentID: UUID, currentPage: Int, totalPages: Int) throws -> PharDocument? {
        var documents = try loadIndex()
        guard let index = documents.firstIndex(where: { $0.id == documentID }) else { return nil }

        let now = Date()
        var document = documents[index]
        let existingFurthest = document.progress?.furthestPage ?? 0
        let nextFurthest = max(existingFurthest, currentPage)
        let safeTotalPages = max(totalPages, 1)

        document.progress = StudyProgressSnapshot(
            currentPage: max(currentPage, 1),
            totalPages: safeTotalPages,
            furthestPage: max(nextFurthest, 1),
            completionRatio: min(Double(max(nextFurthest, 1)) / Double(safeTotalPages), 1.0),
            lastStudiedAt: now,
            sections: Self.sectionSnapshots(
                for: max(currentPage, 1),
                totalPages: safeTotalPages,
                sections: document.progress?.sections ?? Self.fallbackSections(totalPages: safeTotalPages)
            )
        )
        document.updatedAt = now

        documents[index] = document
        try saveIndex(documents)
        return document
    }

    @discardableResult
    func updateStudySections(documentID: UUID, sections: [StudySectionProgress]) throws -> PharDocument? {
        var documents = try loadIndex()
        guard let index = documents.firstIndex(where: { $0.id == documentID }) else { return nil }

        var document = documents[index]
        let now = Date()
        let totalPages = max(document.progress?.totalPages ?? sections.last?.endPage ?? 1, 1)
        let currentPage = min(max(document.progress?.currentPage ?? 1, 1), totalPages)
        let furthestPage = min(max(document.progress?.furthestPage ?? currentPage, 1), totalPages)
        let safeSections = sections.isEmpty ? Self.fallbackSections(totalPages: totalPages) : sections

        document.progress = StudyProgressSnapshot(
            currentPage: currentPage,
            totalPages: totalPages,
            furthestPage: furthestPage,
            completionRatio: min(Double(furthestPage) / Double(totalPages), 1.0),
            lastStudiedAt: document.progress?.lastStudiedAt ?? now,
            sections: Self.sectionSnapshots(
                for: currentPage,
                totalPages: totalPages,
                sections: safeSections
            )
        )
        document.updatedAt = now

        documents[index] = document
        try saveIndex(documents)
        return document
    }

    private func ensureDocumentsDirectoryExists() throws {
        if let ubiquitousDocumentsDirectory {
            try ensureDirectoryExists(at: ubiquitousDocumentsDirectory)
            try migrateLocalDocumentsIfNeeded(to: ubiquitousDocumentsDirectory)
        }

        try ensureDirectoryExists(at: documentsDirectory)
    }

    private func ensureDirectoryExists(at directoryURL: URL) throws {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory)

        if exists && !isDirectory.boolValue {
            throw StoreError.documentsPathIsNotDirectory
        }

        if !exists {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    private func migrateLocalDocumentsIfNeeded(to destinationURL: URL) throws {
        guard destinationURL.path != localDocumentsDirectory.path else { return }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: localDocumentsDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return
        }

        let localContents = try fileManager.contentsOfDirectory(
            at: localDocumentsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        guard !localContents.isEmpty else { return }

        for itemURL in localContents {
            let destinationItemURL = destinationURL.appendingPathComponent(itemURL.lastPathComponent, isDirectory: false)
            guard !fileManager.fileExists(atPath: destinationItemURL.path) else { continue }
            try fileManager.copyItem(at: itemURL, to: destinationItemURL)
        }
    }

    private func writeDashboardSnapshot(_ documents: [PharDocument], using encoder: JSONEncoder) throws {
        let snapshot = makeDashboardSnapshot(from: documents)
        let data = try encoder.encode(snapshot)
        try data.write(to: dashboardFileURL, options: .atomic)
    }

    private func makeDashboardSnapshot(from documents: [PharDocument]) -> PharnodeDashboardSnapshot {
        PharnodeDashboardSnapshot(
            version: 1,
            generatedAt: Date(),
            materials: documents
                .filter { $0.type == .pdf || $0.type == .lesson || $0.studyMaterial != nil }
                .sorted { $0.updatedAt > $1.updatedAt }
                .map {
                    PharnodeDashboardMaterialProgress(
                        documentId: $0.id,
                        documentTitle: $0.title,
                        documentType: $0.type,
                        provider: $0.studyProviderTitle,
                        subject: $0.studySubjectTitle,
                        canonicalTitle: $0.studyMaterial?.canonicalTitle,
                        currentPage: $0.progress?.currentPage,
                        totalPages: $0.progress?.totalPages,
                        furthestPage: $0.progress?.furthestPage,
                        completionRatio: $0.progress?.completionRatio,
                        lastStudiedAt: $0.progress?.lastStudiedAt,
                        currentSection: $0.progress?.currentSectionTitle,
                        nextSection: $0.progress?.nextSectionTitle,
                        completedSectionCount: $0.progress?.completedSectionCount,
                        totalSectionCount: $0.progress?.totalSectionCount,
                        sectionHeadline: $0.progress?.dashboardHeadline,
                        sectionSubheadline: $0.progress?.dashboardSubheadline,
                        sections: ($0.progress?.sections ?? []).map {
                            PharnodeDashboardSectionProgress(
                                title: $0.title,
                                startPage: $0.startPage,
                                endPage: $0.endPage,
                                status: $0.status.rawValue,
                                completionRatio: $0.completionRatio
                            )
                        }
                    )
                }
        )
    }

    private func extractSections(from document: PDFDocument) -> [StudySectionProgress] {
        guard let outlineRoot = document.outlineRoot else {
            return Self.fallbackSections(totalPages: document.pageCount)
        }

        var collected: [(title: String, page: Int)] = []

        func walk(_ outline: PDFOutline) {
            for childIndex in 0 ..< outline.numberOfChildren {
                guard let child = outline.child(at: childIndex) else { continue }
                let title = child.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !title.isEmpty, let pageIndex = outlinePageIndex(for: child, in: document) {
                    let page = max(pageIndex + 1, 1)
                    collected.append((title: title, page: page))
                }
                walk(child)
            }
        }

        walk(outlineRoot)

        let normalized = collected
            .sorted {
                if $0.page == $1.page {
                    return $0.title.count > $1.title.count
                }
                return $0.page < $1.page
            }
            .reduce(into: [(title: String, page: Int)]()) { partial, item in
                guard partial.last?.title != item.title || partial.last?.page != item.page else { return }
                partial.append(item)
            }

        guard !normalized.isEmpty else {
            return Self.fallbackSections(totalPages: document.pageCount)
        }

        return normalized.enumerated().map { index, item in
            let nextPage = index + 1 < normalized.count ? normalized[index + 1].page : document.pageCount + 1
            return StudySectionProgress(
                id: UUID(),
                title: item.title,
                startPage: item.page,
                endPage: max(min(nextPage - 1, document.pageCount), item.page),
                status: .upcoming,
                completionRatio: 0
            )
        }
    }

    private func outlinePageIndex(for outline: PDFOutline, in document: PDFDocument) -> Int? {
        if let page = outline.destination?.page {
            let pageIndex = document.index(for: page)
            return pageIndex == NSNotFound ? nil : pageIndex
        }

        if let goToAction = outline.action as? PDFActionGoTo {
            guard let page = goToAction.destination.page else { return nil }
            let pageIndex = document.index(for: page)
            return pageIndex == NSNotFound ? nil : pageIndex
        }

        return nil
    }

    private static func sectionSnapshots(
        for currentPage: Int,
        totalPages: Int,
        sections: [StudySectionProgress]
    ) -> [StudySectionProgress] {
        let safeSections = sections.isEmpty ? fallbackSections(totalPages: totalPages) : sections
        let furthestPage = max(currentPage, 1)

        return safeSections.map { section in
            let completedPages = min(max(furthestPage - section.startPage + 1, 0), max(section.endPage - section.startPage + 1, 1))
            let pageCount = max(section.endPage - section.startPage + 1, 1)
            let ratio = min(Double(completedPages) / Double(pageCount), 1.0)
            let status: StudySectionStatus

            if furthestPage > section.endPage {
                status = .completed
            } else if furthestPage >= section.startPage {
                status = .current
            } else {
                status = .upcoming
            }

            return StudySectionProgress(
                id: section.id,
                title: section.title,
                startPage: section.startPage,
                endPage: section.endPage,
                status: status,
                completionRatio: ratio
            )
        }
    }

    private static func fallbackSections(totalPages: Int) -> [StudySectionProgress] {
        let safeTotal = max(totalPages, 1)
        let chunkSize = max(Int(ceil(Double(safeTotal) / 4.0)), 1)
        var sections: [StudySectionProgress] = []
        var startPage = 1

        while startPage <= safeTotal {
            let endPage = min(startPage + chunkSize - 1, safeTotal)
            sections.append(
                StudySectionProgress(
                    id: UUID(),
                    title: "Section \(sections.count + 1)",
                    startPage: startPage,
                    endPage: endPage,
                    status: .upcoming,
                    completionRatio: 0
                )
            )
            startPage = endPage + 1
        }

        return sections
    }

    private func makeSinglePagePDFData(from image: UIImage) -> Data {
        let imageSize = image.size
        let pageRect = CGRect(
            origin: .zero,
            size: CGSize(
                width: max(imageSize.width, 1),
                height: max(imageSize.height, 1)
            )
        )

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { context in
            context.beginPage()
            image.draw(in: pageRect)
        }
    }

    private func normalizeDocumentPath(_ document: PharDocument, relativeTo rootURL: URL) -> PharDocument {
        let lastPathComponent = URL(fileURLWithPath: document.path).lastPathComponent
        guard !lastPathComponent.isEmpty else { return document }

        var normalized = document
        normalized.path = rootURL.appendingPathComponent(lastPathComponent, isDirectory: true).path
        return normalized
    }
}
