import Combine
import Foundation
import PencilKit
import UIKit

@MainActor
final class BlankNoteEditorViewModel: ObservableObject {
    enum AnnotationTool: String, CaseIterable, Identifiable {
        case pen = "펜"
        case highlighter = "형광펜"
        case eraser = "지우개"
        case lasso = "라쏘"

        var id: String { rawValue }
    }

    struct AnnotationColor: Identifiable {
        let id: Int
        let uiColor: UIColor
        let label: String
    }

    struct AnalysisPreview {
        let pageNumber: Int
        let strokeCount: Int
        let isBookmarked: Bool
        let hasUnsavedChanges: Bool
        let updatedAt: Date
    }

    @Published var isToolPickerVisible: Bool = false
    @Published var selectedTool: AnnotationTool = .pen
    @Published var isToolSelectionActive: Bool = false
    @Published var selectedPenStyle: WritingPenStyle = .ballpoint
    @Published var selectedColorID: Int = 0
    @Published var strokeWidth: Double = 5.0
    @Published private(set) var strokePresetConfiguration: WritingStrokePresetConfiguration
    @Published var isPencilOnlyInputEnabled: Bool = false
    @Published private(set) var canUndo: Bool = false
    @Published private(set) var canRedo: Bool = false
    @Published private(set) var canAnalyzeSelection: Bool = false
    @Published private(set) var pages: [BlankNotePage] = []
    @Published private(set) var currentPageID: UUID?
    @Published private(set) var thumbnails: [UUID: UIImage] = [:]
    @Published private(set) var bookmarkedPageIDs: Set<UUID>
    @Published var errorMessage: String?

    private(set) var document: PharDocument
    let annotationColors: [AnnotationColor] = [
        AnnotationColor(id: 0, uiColor: .black, label: "블랙"),
        AnnotationColor(id: 1, uiColor: .systemBlue, label: "블루"),
        AnnotationColor(id: 2, uiColor: .systemRed, label: "레드"),
        AnnotationColor(id: 3, uiColor: .systemGreen, label: "그린"),
        AnnotationColor(id: 4, uiColor: .systemOrange, label: "오렌지")
    ]

    private let noteStore: BlankNoteStore
    private let libraryStore: LibraryStore
    private let eventLogger: StudyEventLogger
    private let userDefaults: UserDefaults
    private var strokePresetConfigurationsByTool: [AnnotationTool: WritingStrokePresetConfiguration]
    private let requestedInitialPageID: UUID?
    private weak var canvasView: PKCanvasView?
    private var didRequestInitialLoad = false
    private var didLogDocumentOpen = false
    private var isApplyingLoadedDrawing = false
    private var drawingCache: [UUID: PKDrawing] = [:]
    private var dirtyPageIDs: Set<UUID> = []
    private var persistTasks: [UUID: Task<Void, Never>] = [:]
    private var pageLoadToken: UUID = UUID()
    private let thumbnailSize = CGSize(width: 92, height: 120)
    private let sessionID = UUID()
    private let sessionStartedAt = Date()
    private var pageEntryStartedAt = Date()
    private var dwellSecondsByPageID: [UUID: TimeInterval] = [:]
    private var revisitCountByPageID: [UUID: Int] = [:]
    private var toolUsageCounts: [AnnotationTool: Int] = [.pen: 1]
    private var undoCountByPageID: [UUID: Int] = [:]
    private var redoCountByPageID: [UUID: Int] = [:]
    private var lassoActionCountByPageID: [UUID: Int] = [:]
    private var copyActionCountByPageID: [UUID: Int] = [:]
    private var pasteActionCountByPageID: [UUID: Int] = [:]
    private var pageNavigationHistory: [UUID] = []

    init(
        document: PharDocument,
        initialPageKey: String? = nil,
        noteStore: BlankNoteStore = BlankNoteStore(),
        libraryStore: LibraryStore? = nil,
        eventLogger: StudyEventLogger? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        let penPresetConfiguration = WritingStrokePresetStore.configuration(
            toolKey: Self.strokePresetToolKey(for: .pen),
            userDefaults: userDefaults
        )
        let highlighterPresetConfiguration = WritingStrokePresetStore.configuration(
            toolKey: Self.strokePresetToolKey(for: .highlighter),
            userDefaults: userDefaults
        )

        self.document = document
        self.noteStore = noteStore
        self.libraryStore = libraryStore ?? LibraryStore()
        self.eventLogger = eventLogger ?? StudyEventLogger.shared
        self.userDefaults = userDefaults
        self.strokePresetConfigurationsByTool = [
            .pen: penPresetConfiguration,
            .highlighter: highlighterPresetConfiguration
        ]
        self._strokePresetConfiguration = Published(initialValue: penPresetConfiguration)
        self.requestedInitialPageID = initialPageKey.flatMap { UUID(uuidString: $0) }
        self.bookmarkedPageIDs = Set((userDefaults.stringArray(forKey: "pharnote.bookmarks.\(document.id.uuidString)") ?? []).compactMap(UUID.init(uuidString:)))
        self.strokeWidth = penPresetConfiguration.values[penPresetConfiguration.selectedIndex]
    }

    func attachCanvasView(_ canvasView: PKCanvasView) {
        self.canvasView = canvasView
        applyCanvasConfiguration()

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
                let initialPageID = requestedInitialPageID.flatMap { requestedID in
                    pages.contains(where: { $0.id == requestedID }) ? requestedID : nil
                }
                currentPageID = initialPageID ?? currentPageID ?? pages.first?.id
                logDocumentOpenedIfNeeded()
                if let currentPageID {
                    recordPageVisit(currentPageID)
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
        recordPageExit()
        currentPageID = pageID
        recordPageVisit(pageID)

        Task {
            await loadAndApplyPage(pageID: pageID)
        }
    }

    func addPage() {
        commitCurrentCanvasToCache()
        saveCurrentPageImmediately()
        recordPageExit()

        let now = Date()
        let newPage = BlankNotePage(id: UUID(), createdAt: now, updatedAt: now)

        if let currentPageID, let currentIndex = pages.firstIndex(where: { $0.id == currentPageID }) {
            pages.insert(newPage, at: currentIndex + 1)
        } else {
            pages.append(newPage)
        }

        currentPageID = newPage.id
        recordPageVisit(newPage.id)
        drawingCache[newPage.id] = PKDrawing()
        applyDrawingToCanvas(PKDrawing())
        touchDocumentUpdatedAt()
        Task {
            await saveContentSnapshot()
        }
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
        bookmarkedPageIDs.remove(pageID)
        persistBookmarks()

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

        if currentPageID == pageID, let nextSelectedPageID {
            currentPageID = nextSelectedPageID
            recordPageVisit(nextSelectedPageID)
            Task {
                await loadAndApplyPage(pageID: nextSelectedPageID)
            }
        }

        touchDocumentUpdatedAt()
        Task {
            await saveContentSnapshot()
        }
    }

    func pageNumber(for pageID: UUID) -> Int {
        guard let index = pages.firstIndex(where: { $0.id == pageID }) else { return 0 }
        return index + 1
    }

    func thumbnail(for pageID: UUID) -> UIImage? {
        thumbnails[pageID]
    }

    func isPageBookmarked(_ pageID: UUID) -> Bool {
        bookmarkedPageIDs.contains(pageID)
    }

    func isPageDirty(_ pageID: UUID) -> Bool {
        dirtyPageIDs.contains(pageID)
    }

    var canDeletePage: Bool {
        pages.count > 1
    }

    var activeTool: AnnotationTool? {
        isToolSelectionActive ? selectedTool : nil
    }

    var isCanvasInputEnabled: Bool {
        isToolSelectionActive
    }

    var isEditingInkTool: Bool {
        guard let activeTool else { return false }
        return activeTool == .pen || activeTool == .highlighter
    }

    var currentToolLabel: String {
        activeTool?.rawValue ?? "스크롤"
    }

    func isToolSelected(_ tool: AnnotationTool) -> Bool {
        activeTool == tool
    }

    var currentPageNumber: Int {
        guard let currentPageID else { return 0 }
        return pageNumber(for: currentPageID)
    }

    var currentPageStrokeCount: Int {
        guard let currentPageID else { return 0 }
        return currentDrawing(for: currentPageID).strokes.count
    }

    var currentPageHasUnsavedChanges: Bool {
        guard let currentPageID else { return false }
        return dirtyPageIDs.contains(currentPageID)
    }

    var isCurrentPageBookmarked: Bool {
        guard let currentPageID else { return false }
        return bookmarkedPageIDs.contains(currentPageID)
    }

    var currentPageUpdatedAt: Date {
        guard let currentPageID,
              let page = pages.first(where: { $0.id == currentPageID }) else {
            return document.updatedAt
        }
        return page.updatedAt
    }

    var analysisPreview: AnalysisPreview? {
        guard currentPageID != nil else { return nil }
        return AnalysisPreview(
            pageNumber: currentPageNumber,
            strokeCount: currentPageStrokeCount,
            isBookmarked: isCurrentPageBookmarked,
            hasUnsavedChanges: currentPageHasUnsavedChanges,
            updatedAt: currentPageUpdatedAt
        )
    }

    var currentAnalysisPageID: UUID? {
        currentPageID
    }

    var canAnalyzeCurrentSelection: Bool {
        analysisSource != nil && activeTool == .lasso && canAnalyzeSelection
    }

    var currentAnalysisScope: AnalysisScope {
        canAnalyzeCurrentSelection ? .selection : .page
    }

    var analysisSource: BlankNoteAnalysisSource? {
        guard let currentPageID,
              let currentIndex = pages.firstIndex(where: { $0.id == currentPageID }) else {
            return nil
        }

        let drawing = currentDrawing(for: currentPageID)
        let previousPageIDs = currentIndex > 0 ? [pages[currentIndex - 1].id] : []
        let nextPageIDs = currentIndex + 1 < pages.count ? [pages[currentIndex + 1].id] : []
        let pageState = currentPageState(for: currentPageID)

        return BlankNoteAnalysisSource(
            document: document,
            pageId: currentPageID,
            pageIndex: currentIndex,
            pageCount: pages.count,
            previousPageIds: previousPageIDs,
            nextPageIds: nextPageIDs,
            pageState: pageState,
            previewImageData: thumbnails[currentPageID]?.pngData(),
            drawingData: drawing.strokes.isEmpty ? nil : drawing.dataRepresentation(),
            drawingStats: drawingStats(for: drawing),
            manualTags: [],
            bookmarks: isCurrentPageBookmarked ? ["page-bookmark"] : [],
            sessionId: sessionID,
            dwellMs: currentDwellMilliseconds(for: currentPageID),
            foregroundEditsMs: currentForegroundEditMilliseconds(for: drawing),
            revisitCount: revisitCountByPageID[currentPageID, default: 0],
            toolUsage: toolUsageCounts
                .map { AnalysisToolUsage(tool: $0.key.rawValue, count: $0.value) }
                .sorted { $0.tool < $1.tool },
            lassoActions: lassoActionCountByPageID[currentPageID, default: 0],
            copyActions: copyActionCountByPageID[currentPageID, default: 0],
            pasteActions: pasteActionCountByPageID[currentPageID, default: 0],
            undoCount: undoCountByPageID[currentPageID, default: 0],
            redoCount: redoCountByPageID[currentPageID, default: 0],
            navigationPath: navigationPathLabels(),
            postSolveReview: nil
        )
    }

    func canvasDidChange() {
        guard !isApplyingLoadedDrawing else { return }
        guard let currentPageID, let canvasView else { return }
        drawingCache[currentPageID] = canvasView.drawing
        dirtyPageIDs.insert(currentPageID)
        refreshUndoRedoState()
        scheduleDebouncedPersist(for: currentPageID)
    }

    func refreshCanvasInteractionState() {
        refreshUndoRedoState()
    }

    func selectTool(_ tool: AnnotationTool) {
        if selectedTool == tool && isToolSelectionActive {
            isToolSelectionActive = false
            applyCanvasConfiguration()
            refreshUndoRedoState()
            return
        }

        selectedTool = tool
        isToolSelectionActive = true
        toolUsageCounts[tool, default: 0] += 1
        if tool == .lasso, let currentPageID {
            lassoActionCountByPageID[currentPageID, default: 0] += 1
        }
        eventLogger.log(
            .annotationToolSelected,
            document: document,
            pageID: currentPageID,
            sessionID: sessionID,
            payload: [
                "tool": .string(tool.rawValue),
                "source": .string("toolbar")
            ]
        )
        if let inkTool = activeInkTool(for: tool) {
            applyStrokePresetConfiguration(for: inkTool)
        } else {
            applyCanvasConfiguration()
        }
        refreshUndoRedoState()
    }

    func updateSelectedColor(_ colorID: Int) {
        selectedColorID = colorID
        applyCanvasConfiguration()
    }

    func selectPenStyle(_ penStyle: WritingPenStyle) {
        selectedPenStyle = penStyle
        applyCanvasConfiguration()
    }

    func selectStrokeWidth(_ width: Double) {
        guard let inkTool = activeInkTool() else { return }
        updateStrokePreset(width, at: strokePresetConfiguration.selectedIndex, for: inkTool)
    }

    func selectStrokePreset(at index: Int) {
        guard let inkTool = activeInkTool() else { return }
        guard let currentConfiguration = strokePresetConfigurationsByTool[inkTool] else { return }
        guard index >= 0 && index < currentConfiguration.values.count else { return }

        let updatedConfiguration = WritingStrokePresetConfiguration(
            values: currentConfiguration.values,
            selectedIndex: index
        )
        strokePresetConfigurationsByTool[inkTool] = updatedConfiguration
        persistStrokePresetConfiguration(updatedConfiguration, for: inkTool)
        applyStrokePresetConfiguration(for: inkTool)
    }

    func updateStrokePreset(_ width: Double, at index: Int) {
        guard let inkTool = activeInkTool() else { return }
        updateStrokePreset(width, at: index, for: inkTool)
    }

    func togglePencilOnlyInput() {
        isPencilOnlyInputEnabled.toggle()
        applyCanvasConfiguration()
        eventLogger.log(
            .inputModeChanged,
            document: document,
            pageID: currentPageID,
            sessionID: sessionID,
            payload: [
                "allows_finger_drawing": .bool(!isPencilOnlyInputEnabled)
            ]
        )
    }

    func toggleToolPicker() {
        isToolPickerVisible.toggle()
    }

    func toggleCurrentPageBookmark() {
        guard let currentPageID else { return }
        var updatedBookmarks = bookmarkedPageIDs
        let isBookmarked: Bool
        if updatedBookmarks.contains(currentPageID) {
            updatedBookmarks.remove(currentPageID)
            isBookmarked = false
        } else {
            updatedBookmarks.insert(currentPageID)
            isBookmarked = true
        }
        bookmarkedPageIDs = updatedBookmarks
        persistBookmarks()
        eventLogger.log(
            .pageBookmarkToggled,
            document: document,
            pageID: currentPageID,
            sessionID: sessionID,
            payload: [
                "bookmarked": .bool(isBookmarked),
                "page_index": .integer(pageNumber(for: currentPageID) - 1)
            ]
        )
    }

    func undo() {
        canvasView?.undoManager?.undo()
        if let currentPageID {
            undoCountByPageID[currentPageID, default: 0] += 1
            eventLogger.log(
                .undoInvoked,
                document: document,
                pageID: currentPageID,
                sessionID: sessionID,
                payload: [
                    "source": .string("toolbar")
                ]
            )
        }
        commitCurrentCanvasToCache()
        saveCurrentPageDebounced()
    }

    func redo() {
        canvasView?.undoManager?.redo()
        if let currentPageID {
            redoCountByPageID[currentPageID, default: 0] += 1
            eventLogger.log(
                .redoInvoked,
                document: document,
                pageID: currentPageID,
                sessionID: sessionID,
                payload: [
                    "source": .string("toolbar")
                ]
            )
        }
        commitCurrentCanvasToCache()
        saveCurrentPageDebounced()
    }

    func currentTool() -> PKTool {
        switch selectedTool {
        case .pen:
            return makePenTool()
        case .highlighter:
            let color = uiColorForColorID(selectedColorID).withAlphaComponent(0.34)
            return PKInkingTool(.marker, color: color, width: CGFloat(strokeWidth + 2))
        case .eraser:
            return PKEraserTool(.vector)
        case .lasso:
            return PKLassoTool()
        }
    }

    func currentDrawingPolicy() -> PKCanvasViewDrawingPolicy {
        isPencilOnlyInputEnabled ? .pencilOnly : .anyInput
    }

    func uiColorForColorID(_ id: Int) -> UIColor {
        annotationColors.first(where: { $0.id == id })?.uiColor ?? .black
    }

    func saveImmediately() {
        Task {
            await saveImmediatelyAndWait()
        }
    }

    func saveImmediatelyAndWait() async {
        commitCurrentCanvasToCache()
        recordPageExit()
        persistTasks.values.forEach { $0.cancel() }
        persistTasks.removeAll()
        let dirtyIDs = Array(dirtyPageIDs)
        for pageID in dirtyIDs {
            await persistPageIfNeeded(pageID, force: true)
        }
        await saveContentSnapshot()
    }

    func closeDocument() async {
        await saveImmediatelyAndWait()
        guard didLogDocumentOpen else { return }
        eventLogger.log(
            .documentClosed,
            document: document,
            pageID: currentPageID,
            sessionID: sessionID,
            payload: [
                "close_reason": .string("editor_disappear")
            ]
        )
        didLogDocumentOpen = false
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
            await saveContentSnapshot()
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
            touchDocumentUpdatedAt()
            await saveContentSnapshot()
            let stats = drawingStats(for: drawing)
            let pageIndex = pages.firstIndex(where: { $0.id == pageID }) ?? max(currentPageNumber - 1, 0)
            eventLogger.log(
                .strokeBatchCommitted,
                document: document,
                pageID: pageID,
                sessionID: sessionID,
                payload: [
                    "page_index": .integer(pageIndex),
                    "stroke_count_total": .integer(stats.strokeCount),
                    "ink_length_estimate": .double(stats.inkLengthEstimate),
                    "highlight_coverage": .double(stats.highlightCoverage),
                    "erase_ratio": .double(stats.eraseRatio),
                    "tool": .string(selectedTool.rawValue)
                ]
            )
            eventLogger.log(
                .canvasSaved,
                document: document,
                pageID: pageID,
                sessionID: sessionID,
                payload: [
                    "page_index": .integer(pageIndex),
                    "save_reason": .string(force ? "force" : "debounce")
                ]
            )
            await refreshThumbnail(for: pageID, drawingData: drawingData)
            SearchInfrastructure.shared.enqueueHandwritingIndexJob(
                documentID: document.id,
                pageKey: pageID.uuidString.lowercased()
            )
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
        applyCanvasConfiguration()
        refreshUndoRedoState()
    }

    private func applyCanvasConfiguration() {
        guard let canvasView else { return }
        canvasView.tool = currentTool()
        canvasView.drawingPolicy = currentDrawingPolicy()
        canvasView.isUserInteractionEnabled = isCanvasInputEnabled
        if #available(iOS 18.0, *) {
            canvasView.isDrawingEnabled = isCanvasInputEnabled
        }
    }

    private func refreshUndoRedoState() {
        canUndo = canvasView?.undoManager?.canUndo ?? false
        canRedo = canvasView?.undoManager?.canRedo ?? false
        refreshSelectionAvailability()
    }

    private func refreshSelectionAvailability() {
        guard activeTool == .lasso, let canvasView else {
            canAnalyzeSelection = false
            return
        }

        canvasView.becomeFirstResponder()
        canAnalyzeSelection =
            canvasView.canPerformAction(#selector(UIResponderStandardEditActions.copy(_:)), withSender: nil)
            || canvasView.canPerformAction(#selector(UIResponderStandardEditActions.cut(_:)), withSender: nil)
            || canvasView.canPerformAction(#selector(UIResponderStandardEditActions.delete(_:)), withSender: nil)
    }

    private func makePenTool() -> PKInkingTool {
        let baseColor = uiColorForColorID(selectedColorID)

        switch selectedPenStyle {
        case .ballpoint:
            return PKInkingTool(.pen, color: baseColor, width: CGFloat(strokeWidth))
        case .pencil:
            let texturedColor = baseColor.withAlphaComponent(0.88)
            let texturedWidth = CGFloat(max(strokeWidth * 1.15, 1.8))
            return PKInkingTool(.pencil, color: texturedColor, width: texturedWidth)
        }
    }

    private func updatePageTimestamp(_ pageID: UUID) {
        guard let index = pages.firstIndex(where: { $0.id == pageID }) else { return }
        pages[index].updatedAt = Date()
    }

    private func saveContentSnapshot() async {
        let snapshot = BlankNoteContent(version: 2, pages: pages)
        do {
            try await noteStore.saveContent(snapshot, documentURL: documentURL)
        } catch {
            errorMessage = "노트 메타데이터 저장 실패: \(error.localizedDescription)"
        }
    }

    private func activeInkTool(for tool: AnnotationTool? = nil) -> AnnotationTool? {
        switch tool ?? selectedTool {
        case .pen:
            return .pen
        case .highlighter:
            return .highlighter
        case .eraser, .lasso:
            return nil
        }
    }

    private func applyStrokePresetConfiguration(for tool: AnnotationTool) {
        guard let configuration = strokePresetConfigurationsByTool[tool] else { return }
        strokePresetConfiguration = configuration
        strokeWidth = configuration.values[configuration.selectedIndex]
        applyCanvasConfiguration()
    }

    private func updateStrokePreset(_ width: Double, at index: Int, for tool: AnnotationTool) {
        guard var configuration = strokePresetConfigurationsByTool[tool] else { return }
        guard index >= 0 && index < configuration.values.count else { return }

        var updatedValues = configuration.values
        updatedValues[index] = min(max(width, 1), 16)
        configuration = WritingStrokePresetConfiguration(values: updatedValues, selectedIndex: index)

        strokePresetConfigurationsByTool[tool] = configuration
        persistStrokePresetConfiguration(configuration, for: tool)

        if activeInkTool() == tool {
            strokePresetConfiguration = configuration
            strokeWidth = configuration.values[index]
            applyCanvasConfiguration()
        }
    }

    private func persistStrokePresetConfiguration(_ configuration: WritingStrokePresetConfiguration, for tool: AnnotationTool) {
        WritingStrokePresetStore.save(
            toolKey: Self.strokePresetToolKey(for: tool),
            values: configuration.values,
            selectedIndex: configuration.selectedIndex,
            userDefaults: userDefaults
        )
    }

    private func touchDocumentUpdatedAt() {
        var updatedDocument = document
        updatedDocument.updatedAt = pages.map(\.updatedAt).max() ?? Date()
        if let savedDocument = try? libraryStore.updateDocument(updatedDocument) {
            document = savedDocument
        } else {
            document = updatedDocument
        }
    }

    private static func strokePresetToolKey(for tool: AnnotationTool) -> String {
        switch tool {
        case .pen:
            return "pen"
        case .highlighter:
            return "highlighter"
        case .eraser, .lasso:
            return "pen"
        }
    }

    private func currentDrawing(for pageID: UUID) -> PKDrawing {
        if currentPageID == pageID, let canvasView {
            return canvasView.drawing
        }
        return drawingCache[pageID] ?? PKDrawing()
    }

    private func drawingStats(for drawing: PKDrawing) -> AnalysisDrawingStats {
        let strokeCount = drawing.strokes.count
        let inkLengthEstimate = drawing.strokes.reduce(0.0) { partialResult, stroke in
            let bounds = stroke.renderBounds
            return partialResult + Double(bounds.width + bounds.height)
        }
        let highlightCoverage = activeTool == .highlighter && strokeCount > 0 ? 0.25 : 0.0
        return AnalysisDrawingStats(
            strokeCount: strokeCount,
            inkLengthEstimate: inkLengthEstimate,
            eraseRatio: 0,
            highlightCoverage: highlightCoverage
        )
    }

    private func currentPageState(for pageID: UUID) -> [String] {
        var state: [String] = []
        if bookmarkedPageIDs.contains(pageID) {
            state.append("bookmarked")
        }
        if dirtyPageIDs.contains(pageID) {
            state.append("dirty-local")
        }
        if currentDrawing(for: pageID).strokes.isEmpty == false {
            state.append("annotated")
        }
        return state
    }

    private func currentDwellMilliseconds(for pageID: UUID) -> Int {
        var totalSeconds = dwellSecondsByPageID[pageID, default: 0]
        if currentPageID == pageID {
            totalSeconds += Date().timeIntervalSince(pageEntryStartedAt)
        }
        return Int(totalSeconds * 1000)
    }

    private func currentForegroundEditMilliseconds(for drawing: PKDrawing) -> Int {
        let sessionSeconds = Date().timeIntervalSince(sessionStartedAt)
        let activityRatio = min(Double(drawing.strokes.count) / 80.0, 1.0)
        return Int(sessionSeconds * activityRatio * 1000)
    }

    private func recordPageExit() {
        guard let currentPageID else { return }
        let elapsed = Date().timeIntervalSince(pageEntryStartedAt)
        dwellSecondsByPageID[currentPageID, default: 0] += Date().timeIntervalSince(pageEntryStartedAt)
        eventLogger.log(
            .pageExit,
            document: document,
            pageID: currentPageID,
            sessionID: sessionID,
            payload: [
                "page_index": .integer(pageNumber(for: currentPageID) - 1),
                "exit_reason": .string("page_change"),
                "elapsed_ms": .integer(Int(elapsed * 1000))
            ]
        )
        pageEntryStartedAt = Date()
    }

    private func recordPageVisit(_ pageID: UUID) {
        pageEntryStartedAt = Date()
        revisitCountByPageID[pageID, default: 0] += 1
        pageNavigationHistory.append(pageID)
        if pageNavigationHistory.count > 10 {
            pageNavigationHistory.removeFirst(pageNavigationHistory.count - 10)
        }
        eventLogger.log(
            .pageEnter,
            document: document,
            pageID: pageID,
            sessionID: sessionID,
            payload: [
                "page_index": .integer(pageNumber(for: pageID) - 1),
                "entry_source": .string("editor")
            ]
        )
    }

    private func logDocumentOpenedIfNeeded() {
        guard !didLogDocumentOpen else { return }
        didLogDocumentOpen = true
        eventLogger.log(
            .documentOpened,
            document: document,
            pageID: currentPageID,
            sessionID: sessionID,
            payload: [
                "entry_source": .string("library")
            ]
        )
    }

    private func navigationPathLabels() -> [String] {
        pageNavigationHistory.compactMap { pageID in
            guard let index = pages.firstIndex(where: { $0.id == pageID }) else { return nil }
            return "page-\(index + 1)"
        }
    }

    private func persistBookmarks() {
        userDefaults.set(bookmarkedPageIDs.map(\.uuidString).sorted(), forKey: bookmarkStorageKey)
    }

    private var bookmarkStorageKey: String {
        "pharnote.bookmarks.\(document.id.uuidString)"
    }

    private var documentURL: URL {
        URL(fileURLWithPath: document.path, isDirectory: true)
    }
}
