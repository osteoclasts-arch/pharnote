import Foundation
import PencilKit
import UIKit

@MainActor
final class BlankNoteEditorViewModel: ObservableObject {
    @Published var isToolPickerVisible: Bool = true
    @Published private(set) var canUndo: Bool = false
    @Published private(set) var canRedo: Bool = false
    @Published private(set) var pages: [BlankNotePage] = []
    @Published private(set) var currentPageID: UUID?
    @Published private(set) var thumbnails: [UUID: UIImage] = [:]
    @Published var errorMessage: String?

    let document: PharDocument

    private let noteStore: BlankNoteStore
    private weak var canvasView: PKCanvasView?
    private var didRequestInitialLoad = false
    private var isApplyingLoadedDrawing = false
    private var drawingCache: [UUID: PKDrawing] = [:]
    private var dirtyPageIDs: Set<UUID> = []
    private var persistTasks: [UUID: Task<Void, Never>] = [:]
    private var pageLoadToken: UUID = UUID()
    private let thumbnailSize = CGSize(width: 92, height: 120)

    init(document: PharDocument, noteStore: BlankNoteStore = BlankNoteStore()) {
        self.document = document
        self.noteStore = noteStore
    }

    func attachCanvasView(_ canvasView: PKCanvasView) {
        self.canvasView = canvasView
        if let currentPageID, let drawing = drawingCache[currentPageID] {
            applyDrawingToCanvas(drawing)
        } else {
            applyDrawingToCanvas(PKDrawing())
        }
    }

    func loadInitialContentIfNeeded() {
        guard !didRequestInitialLoad else { return }
        didRequestInitialLoad = true

        Task {
            do {
                let content = try await noteStore.loadOrCreateContent(documentURL: documentURL)
                pages = content.pages
                if currentPageID == nil {
                    currentPageID = pages.first?.id
                }
                await loadThumbnailCacheForAllPages()
                if let currentPageID {
                    await loadAndApplyPage(pageID: currentPageID)
                }
            } catch {
                errorMessage = "노트 로드 실패: \(error.localizedDescription)"
            }
        }
    }

    func selectPage(_ pageID: UUID) {
        guard currentPageID != pageID else { return }
        commitCurrentCanvasToCache()
        saveCurrentPageImmediately()
        currentPageID = pageID

        Task {
            await loadAndApplyPage(pageID: pageID)
        }
    }

    func addPage() {
        commitCurrentCanvasToCache()
        saveCurrentPageImmediately()

        let now = Date()
        let newPage = BlankNotePage(id: UUID(), createdAt: now, updatedAt: now)

        if let currentPageID, let currentIndex = pages.firstIndex(where: { $0.id == currentPageID }) {
            pages.insert(newPage, at: currentIndex + 1)
        } else {
            pages.append(newPage)
        }

        currentPageID = newPage.id
        drawingCache[newPage.id] = PKDrawing()
        applyDrawingToCanvas(PKDrawing())
        saveContentSnapshot()
        Task {
            await evictCacheExceptCurrentAndNeighbors()
        }
    }

    func deleteCurrentPage() {
        guard let currentPageID else { return }
        deletePage(currentPageID)
    }

    func deletePage(_ pageID: UUID) {
        guard pages.count > 1 else { return }
        guard let removeIndex = pages.firstIndex(where: { $0.id == pageID }) else { return }

        persistTasks[pageID]?.cancel()
        persistTasks.removeValue(forKey: pageID)
        dirtyPageIDs.remove(pageID)
        drawingCache.removeValue(forKey: pageID)
        thumbnails.removeValue(forKey: pageID)

        let nextSelectedPageID: UUID?
        if removeIndex < pages.count - 1 {
            nextSelectedPageID = pages[removeIndex + 1].id
        } else {
            nextSelectedPageID = pages[removeIndex - 1].id
        }

        pages.remove(at: removeIndex)

        Task {
            await noteStore.deleteDrawingData(documentURL: documentURL, pageID: pageID)
            await noteStore.deleteThumbnailData(documentURL: documentURL, pageID: pageID)
        }

        if currentPageID == pageID {
            if let nextSelectedPageID {
                currentPageID = nextSelectedPageID
                Task {
                    await loadAndApplyPage(pageID: nextSelectedPageID)
                }
            }
        }

        saveContentSnapshot()
    }

    func pageNumber(for pageID: UUID) -> Int {
        guard let index = pages.firstIndex(where: { $0.id == pageID }) else { return 0 }
        return index + 1
    }

    func thumbnail(for pageID: UUID) -> UIImage? {
        thumbnails[pageID]
    }

    var canDeletePage: Bool {
        pages.count > 1
    }

    func canvasDidChange() {
        guard !isApplyingLoadedDrawing else { return }
        guard let currentPageID, let canvasView else { return }
        drawingCache[currentPageID] = canvasView.drawing
        dirtyPageIDs.insert(currentPageID)
        refreshUndoRedoState()
        scheduleDebouncedPersist(for: currentPageID)
    }

    func toggleToolPicker() {
        isToolPickerVisible.toggle()
    }

    func undo() {
        canvasView?.undoManager?.undo()
        commitCurrentCanvasToCache()
        saveCurrentPageDebounced()
    }

    func redo() {
        canvasView?.undoManager?.redo()
        commitCurrentCanvasToCache()
        saveCurrentPageDebounced()
    }

    func saveImmediately() {
        commitCurrentCanvasToCache()
        persistTasks.values.forEach { $0.cancel() }
        persistTasks.removeAll()
        let dirtyIDs = Array(dirtyPageIDs)
        Task {
            for pageID in dirtyIDs {
                await persistPageIfNeeded(pageID, force: true)
            }
            saveContentSnapshot()
        }
    }

    private func saveCurrentPageDebounced() {
        guard let currentPageID else { return }
        scheduleDebouncedPersist(for: currentPageID)
    }

    private func saveCurrentPageImmediately() {
        guard let currentPageID else { return }
        persistTasks[currentPageID]?.cancel()
        persistTasks.removeValue(forKey: currentPageID)
        Task {
            await persistPageIfNeeded(currentPageID, force: true)
        }
    }

    private func scheduleDebouncedPersist(for pageID: UUID) {
        persistTasks[pageID]?.cancel()
        persistTasks[pageID] = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            await self?.persistPageIfNeeded(pageID, force: false)
        }
    }

    private func persistPageIfNeeded(_ pageID: UUID, force: Bool) async {
        persistTasks.removeValue(forKey: pageID)
        guard force || dirtyPageIDs.contains(pageID) else { return }
        guard let drawing = drawingCache[pageID] else { return }

        let drawingData = drawing.dataRepresentation()

        do {
            try await noteStore.saveDrawingData(drawingData, documentURL: documentURL, pageID: pageID)
            dirtyPageIDs.remove(pageID)
            updatePageTimestamp(pageID)
            saveContentSnapshot()
            await refreshThumbnail(for: pageID, drawingData: drawingData)
        } catch {
            errorMessage = "필기 저장 실패: \(error.localizedDescription)"
        }
    }

    private func loadAndApplyPage(pageID: UUID) async {
        pageLoadToken = UUID()
        let token = pageLoadToken

        do {
            let drawing = try await drawingForPage(pageID)

            guard token == pageLoadToken else { return }
            guard currentPageID == pageID else { return }

            applyDrawingToCanvas(drawing)
            await preloadNeighborPages(around: pageID)
            await evictCacheExceptCurrentAndNeighbors()
        } catch {
            errorMessage = "페이지 로드 실패: \(error.localizedDescription)"
        }
    }

    private func drawingForPage(_ pageID: UUID) async throws -> PKDrawing {
        if let cached = drawingCache[pageID] {
            return cached
        }

        if let data = await noteStore.loadDrawingData(documentURL: documentURL, pageID: pageID),
           let drawing = try? PKDrawing(data: data) {
            drawingCache[pageID] = drawing
            return drawing
        }

        let empty = PKDrawing()
        drawingCache[pageID] = empty
        return empty
    }

    private func preloadNeighborPages(around pageID: UUID) async {
        guard let index = pages.firstIndex(where: { $0.id == pageID }) else { return }

        var neighborIDs: [UUID] = []
        if index > 0 {
            neighborIDs.append(pages[index - 1].id)
        }
        if index < pages.count - 1 {
            neighborIDs.append(pages[index + 1].id)
        }

        for neighborID in neighborIDs where drawingCache[neighborID] == nil {
            _ = try? await drawingForPage(neighborID)
        }
    }

    private func evictCacheExceptCurrentAndNeighbors() async {
        guard let currentPageID,
              let currentIndex = pages.firstIndex(where: { $0.id == currentPageID }) else {
            drawingCache.removeAll()
            return
        }

        var keepIDs: Set<UUID> = [currentPageID]
        if currentIndex > 0 {
            keepIDs.insert(pages[currentIndex - 1].id)
        }
        if currentIndex < pages.count - 1 {
            keepIDs.insert(pages[currentIndex + 1].id)
        }

        let removable = drawingCache.keys.filter { !keepIDs.contains($0) }
        for pageID in removable {
            if dirtyPageIDs.contains(pageID) {
                await persistPageIfNeeded(pageID, force: true)
            }
            drawingCache.removeValue(forKey: pageID)
        }
    }

    private func refreshThumbnail(for pageID: UUID, drawingData: Data) async {
        guard let pngData = await noteStore.generateThumbnailPNG(
            from: drawingData,
            thumbnailSize: thumbnailSize,
            scale: 2.0
        ) else {
            thumbnails.removeValue(forKey: pageID)
            return
        }

        if let image = UIImage(data: pngData) {
            thumbnails[pageID] = image
        }

        try? await noteStore.saveThumbnailData(pngData, documentURL: documentURL, pageID: pageID)
    }

    private func loadThumbnailCacheForAllPages() async {
        for page in pages {
            if let cachedData = await noteStore.loadThumbnailData(documentURL: documentURL, pageID: page.id),
               let image = UIImage(data: cachedData) {
                thumbnails[page.id] = image
                continue
            }

            if let drawingData = await noteStore.loadDrawingData(documentURL: documentURL, pageID: page.id) {
                await refreshThumbnail(for: page.id, drawingData: drawingData)
            }
        }
    }

    private func commitCurrentCanvasToCache() {
        guard let currentPageID, let canvasView else { return }
        drawingCache[currentPageID] = canvasView.drawing
        dirtyPageIDs.insert(currentPageID)
        refreshUndoRedoState()
    }

    private func applyDrawingToCanvas(_ drawing: PKDrawing) {
        guard let canvasView else { return }
        isApplyingLoadedDrawing = true
        canvasView.drawing = drawing
        isApplyingLoadedDrawing = false
        refreshUndoRedoState()
    }

    private func refreshUndoRedoState() {
        canUndo = canvasView?.undoManager?.canUndo ?? false
        canRedo = canvasView?.undoManager?.canRedo ?? false
    }

    private func updatePageTimestamp(_ pageID: UUID) {
        guard let index = pages.firstIndex(where: { $0.id == pageID }) else { return }
        pages[index].updatedAt = Date()
    }

    private func saveContentSnapshot() {
        let snapshot = BlankNoteContent(version: 2, pages: pages)
        Task {
            do {
                try await noteStore.saveContent(snapshot, documentURL: documentURL)
            } catch {
                errorMessage = "노트 메타데이터 저장 실패: \(error.localizedDescription)"
            }
        }
    }

    private var documentURL: URL {
        URL(fileURLWithPath: document.path, isDirectory: true)
    }
}
