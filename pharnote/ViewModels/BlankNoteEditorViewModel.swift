import Combine
import Foundation
import PencilKit
import SwiftUI
import UIKit

@MainActor
final class BlankNoteEditorViewModel: ObservableObject {
    enum AnnotationTool: String, CaseIterable, Identifiable {
        case pen = "펜"
        case highlighter = "형광펜"
        case eraser = "지우개"
        case lasso = "라쏘"
        case paint = "붓/채우기"
        case text = "텍스트"
        case tape = "테이프"

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
    @Published var dynamicColor: UIColor? = nil
    @Published var savedColorPresets: [UIColor] = []
    @Published var strokeWidth: Double = 5.0
    @Published private(set) var strokePresetConfiguration: WritingStrokePresetConfiguration
    @Published var isPencilOnlyInputEnabled: Bool = false
    @Published private(set) var canUndo: Bool = false
    @Published private(set) var canRedo: Bool = false
    @Published private(set) var canAnalyzeSelection: Bool = false
    @Published var pages: [BlankNotePage] = []
    @Published var activeTextElementID: UUID?
    @Published private(set) var currentPageID: UUID?
    @Published private(set) var thumbnails: [UUID: UIImage] = [:]
    @Published private(set) var bookmarkedPageIDs: Set<UUID>
    @Published var highlightMode: HighlightStructureMode = .basic
    @Published var selectedHighlightRole: HighlightStructureRole = .core
    @Published private(set) var currentHighlightSnapshot: HighlightStructureSnapshot?
    @Published var isHighlightStructurePanelVisible: Bool = false
    @Published var errorMessage: String?
    
    // Lecture Mode & Sync properties
    @Published var isLectureModeEnabled: Bool = false
    @Published var isShowingNudge: Bool = false
    @Published var nudgeNodeId: String?
    
    // Floating Browser Properties
    @Published var lectureWindowPosition: CGPoint = CGPoint(x: 100, y: 100)
    @Published var isLectureWindowPinned: Bool = false
    @Published var lectureWebURL: String = "https://www.google.com" // 기본값

    
    // Tool Cache to prevent infinite re-render loops in SwiftUI/PencilKit
    private var cachedPKTool: PKTool?
    private var lastToolKey: String = ""

    
    // Evidence Binding properties
    @Published var isBindingEvidence: Bool = false
    @Published var evidenceBindingStepId: String? = nil
    var onEvidenceBound: ((String, Int) -> Void)? = nil

    @Published private(set) var document: PharDocument
    let annotationColors: [AnnotationColor] = [
        AnnotationColor(id: 0, uiColor: .black, label: "블랙"),
        AnnotationColor(id: 1, uiColor: .systemBlue, label: "블루"),
        AnnotationColor(id: 2, uiColor: .systemRed, label: "레드"),
        AnnotationColor(id: 3, uiColor: .systemGreen, label: "그린"),
        AnnotationColor(id: 4, uiColor: .systemOrange, label: "오렌지")
    ]

    func saveCurrentDynamicColor() {
        guard let color = dynamicColor else { return }
        if !savedColorPresets.contains(where: { $0 == color }) {
            savedColorPresets.append(color)
        }
    }

    func removeColorPreset(at index: Int) {
        guard savedColorPresets.indices.contains(index) else { return }
        savedColorPresets.remove(at: index)
    }

    private let noteStore: BlankNoteStore
    private let libraryStore: LibraryStore
    private let eventLogger: StudyEventLogger
    private let userDefaults: UserDefaults
    private let highlightStore: HighlightStructureStore
    private let highlightEngine: HighlightStructureEngine
    private let documentOCRService: DocumentOCRService
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
    private var highlightSnapshotTask: Task<Void, Never>?
    private var highlightSyncTask: Task<Void, Never>?
    private var lastHighlightStrokeCountByPageID: [UUID: Int] = [:]
    private var highlightRoleHexByRole: [HighlightStructureRole: String] = [:]
    private static let lecturePopupAllowanceKeyPrefix = "lectureBrowser.popups.allowed."

    init(
        document: PharDocument,
        initialPageKey: String? = nil,
        noteStore: BlankNoteStore = BlankNoteStore(),
        libraryStore: LibraryStore? = nil,
        eventLogger: StudyEventLogger? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        let highlightStore = HighlightStructureStore()
        let highlightEngine = HighlightStructureEngine()
        let documentOCRService = DocumentOCRService()
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
        self.highlightStore = highlightStore
        self.highlightEngine = highlightEngine
        self.documentOCRService = documentOCRService
        self.strokePresetConfigurationsByTool = [
            .pen: penPresetConfiguration,
            .highlighter: highlighterPresetConfiguration
        ]
        self._strokePresetConfiguration = Published(initialValue: penPresetConfiguration)
        self.requestedInitialPageID = initialPageKey.flatMap { UUID(uuidString: $0) }
        self.bookmarkedPageIDs = Set((userDefaults.stringArray(forKey: "pharnote.bookmarks.\(document.id.uuidString)") ?? []).compactMap(UUID.init(uuidString:)))
        self.strokeWidth = penPresetConfiguration.values[penPresetConfiguration.selectedIndex]
        self.loadHighlightPalettePresets()
    }

    func lecturePopupAllowed(for urlString: String) -> Bool {
        guard let key = lecturePopupAllowanceKey(for: urlString) else { return false }
        return userDefaults.bool(forKey: key)
    }

    func setLecturePopupAllowed(_ allowed: Bool, for urlString: String) {
        guard let key = lecturePopupAllowanceKey(for: urlString) else { return }
        userDefaults.set(allowed, forKey: key)
    }

    func lecturePopupAllowedStorageKey(for urlString: String) -> String? {
        lecturePopupAllowanceKey(for: urlString)
    }

    private func lecturePopupAllowanceKey(for urlString: String) -> String? {
        guard let url = normalizedLectureURL(from: urlString),
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            return nil
        }
        return Self.lecturePopupAllowanceKeyPrefix + host
    }

    private func normalizedLectureURL(from urlString: String) -> URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(trimmed)")
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
                    await refreshHighlightSnapshot(for: currentPageID)
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
            await refreshHighlightSnapshot(for: pageID)
        }
    }

    func addPage() {
        commitCurrentCanvasToCache()
        saveCurrentPageImmediately()
        recordPageExit()

        let now = Date()
        let newPage = BlankNotePage(
            id: UUID(),
            createdAt: now,
            updatedAt: now,
            paperSize: currentPagePaperSize,
            backgroundStyle: currentPageBackgroundStyle
        )

        if let currentPageID, let currentIndex = pages.firstIndex(where: { $0.id == currentPageID }) {
            pages.insert(newPage, at: currentIndex + 1)
        } else {
            pages.append(newPage)
        }

        currentPageID = newPage.id
        recordPageVisit(newPage.id)
        drawingCache[newPage.id] = PKDrawing()
        lastHighlightStrokeCountByPageID[newPage.id] = 0
        applyDrawingToCanvas(PKDrawing())
        touchDocumentUpdatedAt()
        Task {
            await evictCacheExceptCurrentAndNeighbors()
            await refreshHighlightSnapshot(for: newPage.id)
        }
    }

    func duplicatePage(_ pageID: UUID) {
        guard let sourceIndex = pages.firstIndex(where: { $0.id == pageID }) else { return }
        
        commitCurrentCanvasToCache()
        saveCurrentPageImmediately()

        let now = Date()
        let newPageID = UUID()
        let sourcePage = pages[sourceIndex]
        let newPage = BlankNotePage(
            id: newPageID,
            createdAt: now,
            updatedAt: now,
            paperSize: sourcePage.paperSize,
            backgroundStyle: sourcePage.backgroundStyle
        )
        
        pages.insert(newPage, at: sourceIndex + 1)
        
        Task {
            // Copy physical data in Store
            if let sourceData = await noteStore.loadDrawingData(documentURL: documentURL, pageID: pageID) {
                try? await noteStore.saveDrawingData(sourceData, documentURL: documentURL, pageID: newPageID)
                if let drawing = try? PKDrawing(data: sourceData) {
                    drawingCache[newPageID] = drawing
                    lastHighlightStrokeCountByPageID[newPageID] = drawing.strokes.count
                }
            }

            let sourcePageKey = pageID.uuidString.lowercased()
            let destinationPageKey = newPageID.uuidString.lowercased()
            let sourceItems = await highlightStore.loadItems(documentURL: documentURL, pageKey: sourcePageKey)
            if !sourceItems.isEmpty {
                let copiedItems = sourceItems.map { item in
                    var copied = item
                    copied.id = UUID()
                    copied.pageKey = destinationPageKey
                    copied.pageLabel = "페이지 \(pageNumber(for: newPageID))"
                    copied.createdAt = Date()
                    copied.updatedAt = Date()
                    return copied
                }
                try? await highlightStore.saveItems(copiedItems, documentURL: documentURL, pageKey: destinationPageKey)
            }
            
            if let thumbData = await noteStore.loadThumbnailData(documentURL: documentURL, pageID: pageID) {
                try? await noteStore.saveThumbnailData(thumbData, documentURL: documentURL, pageID: newPageID)
                if let image = UIImage(data: thumbData) {
                    thumbnails[newPageID] = image
                }
            }
            
            await saveContentSnapshot()
            touchDocumentUpdatedAt()
            await refreshHighlightSnapshot(for: newPageID)
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
        lastHighlightStrokeCountByPageID.removeValue(forKey: pageID)

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
            await highlightStore.deleteItems(documentURL: documentURL, pageKey: pageID.uuidString.lowercased())
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
        isToolSelectionActive && selectedTool != .text
    }

    var isEditingInkTool: Bool {
        guard let activeTool else { return false }
        return activeTool == .pen || activeTool == .highlighter || activeTool == .paint
    }

    var currentToolLabel: String {
        if activeTool == .highlighter && highlightMode == .structured {
            return "구조화 · \(selectedHighlightRole.title)"
        }
        return activeTool?.rawValue ?? "스크롤"
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

    var currentPagePaperSize: BlankNotePaperSize {
        guard let currentPageID,
              let page = pages.first(where: { $0.id == currentPageID }) else {
            return .a4
        }
        return page.paperSize
    }

    var currentPageBackgroundStyle: BlankNoteBackgroundStyle {
        guard let currentPageID,
              let page = pages.first(where: { $0.id == currentPageID }) else {
            return .plain
        }
        return page.backgroundStyle
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
        syncStructuredHighlightsIfNeeded(pageID: currentPageID, drawing: canvasView.drawing)
        scheduleHighlightSnapshotRefresh(pageID: currentPageID)
        scheduleDebouncedPersist(for: currentPageID)
    }

    func refreshCanvasInteractionState() {
        refreshUndoRedoState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.refreshUndoRedoState()
        }
    }

    func handleCanvasTap(at point: CGPoint) {
        let drawing = drawingCache[currentPageID ?? UUID()] ?? canvasView?.drawing ?? PKDrawing()

        if isBindingEvidence {
            var closestStroke: PKStroke?
            var minDistance: CGFloat = 50.0
            
            for stroke in drawing.strokes {
                let bounds = stroke.renderBounds
                let extendedBounds = bounds.insetBy(dx: -minDistance, dy: -minDistance)
                if extendedBounds.contains(point) {
                    for pathPoint in stroke.path {
                        let dist = hypot(pathPoint.location.x - point.x, pathPoint.location.y - point.y)
                        if dist < minDistance {
                            minDistance = dist
                            closestStroke = stroke
                        }
                    }
                }
            }
            
            if let targetStroke = closestStroke {
                let strokeTime = targetStroke.path.creationDate
                let delayMs = Int(strokeTime.timeIntervalSince(sessionStartedAt) * 1000)
                let finalDelayMs = max(0, delayMs)
                
                // UUID for stroke reference
                let strokeId = UUID().uuidString
                onEvidenceBound?(strokeId, finalDelayMs)
            }
            return
        }

        guard selectedTool == .paint, self.currentPageID != nil else { return }
        
        // Setup fill stroke generator based on bounding box
        let generateFillStroke: (CGRect, UIColor) -> PKStroke = { bounds, color in
            // Generate a zig-zag fill stroke, or simply a massive dot covering the area
            // Due to PKStroke limitations, creating a single dot stroke with massive width is the easiest way to fill an area.
            // Using a square-like or round marker ink with a large size.
            let size = max(bounds.width, bounds.height) * 1.5
            let ink = PKInk(.pen, color: color)
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let path = PKStrokePath(controlPoints: [
                PKStrokePoint(location: center, timeOffset: 0.0, size: CGSize(width: size, height: size), opacity: 1.0, force: 1.0, azimuth: 0.0, altitude: .pi/2)
            ], creationDate: Date())
            let stroke = PKStroke(ink: ink, path: path)
            return stroke
        }
        
        let fillColor = uiColorForColorID(selectedColorID)
        
        // Find tapped closed shape
        let hitStrokeIndex = drawing.strokes.lastIndex { stroke in
            // Basic hit detection for closed shapes (assuming strokes have >= 4 points)
            let points = stroke.path.map { $0.location }
            guard points.count >= 4 else { return false }
            guard let first = points.first, let last = points.last, first.distance(to: last) < 50 else { return false }
            
            // Check bounding box first
            let minX = points.map { $0.x }.min() ?? 0
            let maxX = points.map { $0.x }.max() ?? 0
            let minY = points.map { $0.y }.min() ?? 0
            let maxY = points.map { $0.y }.max() ?? 0
            let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            
            if !bounds.contains(point) { return false }
            
            // Ray-casting for polygon membership
            var contains = false
            var j = points.count - 1
            for i in 0..<points.count {
                if (points[i].y < point.y && points[j].y >= point.y) || (points[j].y < point.y && points[i].y >= point.y) {
                    if points[i].x + (point.y - points[i].y) / (points[j].y - points[i].y) * (points[j].x - points[i].x) < point.x {
                        contains.toggle()
                    }
                }
                j = i
            }
            return contains
        }
        
        var updatedStrokes = drawing.strokes
        let isShapeFill = hitStrokeIndex != nil
        
        if let index = hitStrokeIndex {
            let hitStroke = updatedStrokes[index]
            let points = hitStroke.path.map(\.location)
            let minX = points.map(\.x).min() ?? 0
            let maxX = points.map(\.x).max() ?? 0
            let minY = points.map(\.y).min() ?? 0
            let maxY = points.map(\.y).max() ?? 0
            let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            
            // Insert fill stroke exactly BEFORE the shape stroke, so the shape outline is visible above it.
            let fillStroke = generateFillStroke(bounds, fillColor)
            updatedStrokes.insert(fillStroke, at: index)
        } else {
            // Background fill
            let bounds = CGRect(x: -5000, y: -5000, width: 10000, height: 10000)
            let fillStroke = generateFillStroke(bounds, fillColor)
            updatedStrokes.insert(fillStroke, at: 0) // Background is always at the absolute bottom
        }
        
        let newDrawing = PKDrawing(strokes: updatedStrokes)
        
        // Save history state
        let originalDrawing = drawing
        canvasView?.undoManager?.registerUndo(withTarget: self, handler: { target in
            target.canvasView?.drawing = originalDrawing
            target.canvasDidChange()
        })
        canvasView?.undoManager?.setActionName(isShapeFill ? "Shape Fill" : "Background Fill")
        
        canvasView?.drawing = newDrawing
        canvasDidChange()
    }

    func insertCapturedImage(_ image: UIImage) {
        // 이미지를 워크스페이스(첨부파일)로 삽입하거나 혹은 캔버스 배경으로 설정할 수 있습니다.
        // 여기서는 워크스페이스 컨트롤러를 통해 이미지 첨부로 처리하도록 유도합니다.
        // ( BlankNoteEditorView에서 workspaceController.importImageData 호출을 중계 )
        NotificationCenter.default.post(
            name: NSNotification.Name("BlankNoteInsertCapturedImage"),
            object: image
        )
    }
    
    // MARK: - Text Elements
    
    func addTextElement(at point: CGPoint) {
        guard let currentPageID = currentPageID else { return }
        
        let newElement = PharTextElement(
            id: UUID(),
            text: "",
            x: Double(point.x),
            y: Double(point.y),
            fontSize: 20,
            fontWeight: "regular",
            isItalic: false,
            alignment: "left",
            colorHex: "#000000"
        )
        
        if let index = pages.firstIndex(where: { $0.id == currentPageID }) {
            pages[index].textElements.append(newElement)
            activeTextElementID = newElement.id
            canvasDidChange()
            scheduleHighlightSnapshotRefresh(pageID: currentPageID)
        }
    }
    
    func updateTextElement(_ element: PharTextElement) {
        guard let currentPageID = currentPageID else { return }
        if let pageIndex = pages.firstIndex(where: { $0.id == currentPageID }) {
            if let elementIndex = pages[pageIndex].textElements.firstIndex(where: { $0.id == element.id }) {
                pages[pageIndex].textElements[elementIndex] = element
                canvasDidChange()
                scheduleHighlightSnapshotRefresh(pageID: currentPageID)
            }
        }
    }

    func updateCurrentPagePaperSize(_ paperSize: BlankNotePaperSize) {
        updateCurrentPageLayout(paperSize: paperSize, backgroundStyle: nil)
    }

    func updateCurrentPageBackgroundStyle(_ backgroundStyle: BlankNoteBackgroundStyle) {
        updateCurrentPageLayout(paperSize: nil, backgroundStyle: backgroundStyle)
    }
    
    func deleteTextElement(id: UUID) {
        guard let currentPageID = currentPageID else { return }
        if let pageIndex = pages.firstIndex(where: { $0.id == currentPageID }) {
            pages[pageIndex].textElements.removeAll { $0.id == id }
            if activeTextElementID == id {
                activeTextElementID = nil
            }
            canvasDidChange()
            scheduleHighlightSnapshotRefresh(pageID: currentPageID)
        }
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
        if tool == .lasso || tool == .paint, let currentPageID {
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
        if tool == .highlighter && highlightMode == .structured {
            isHighlightStructurePanelVisible = true
            if let currentPageID {
                lastHighlightStrokeCountByPageID[currentPageID] = currentDrawing(for: currentPageID).strokes.count
            }
            scheduleHighlightSnapshotRefresh(pageID: currentPageID)
        }
        refreshUndoRedoState()
    }

    func deactivateToolSelection() {
        guard isToolSelectionActive else { return }
        isToolSelectionActive = false
        applyCanvasConfiguration()
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

    func selectHighlightMode(_ mode: HighlightStructureMode) {
        guard highlightMode != mode else { return }
        highlightMode = mode
        eventLogger.log(
            .highlightModeSelected,
            document: document,
            pageID: currentPageID,
            sessionID: sessionID,
            payload: [
                "mode": .string(mode.rawValue)
            ]
        )

        if mode == .structured {
            isHighlightStructurePanelVisible = true
            if let currentPageID {
                lastHighlightStrokeCountByPageID[currentPageID] = currentDrawing(for: currentPageID).strokes.count
            }
        }

        applyCanvasConfiguration()
        scheduleHighlightSnapshotRefresh(pageID: currentPageID)
    }

    func selectHighlightRole(_ role: HighlightStructureRole) {
        guard selectedHighlightRole != role else { return }
        selectedHighlightRole = role
        eventLogger.log(
            .highlightRoleSelected,
            document: document,
            pageID: currentPageID,
            sessionID: sessionID,
            payload: [
                "role": .string(role.rawValue)
            ]
        )
        if highlightMode == .structured {
            isHighlightStructurePanelVisible = true
            applyCanvasConfiguration()
            scheduleHighlightSnapshotRefresh(pageID: currentPageID)
        }
    }

    func toggleHighlightStructurePanel() {
        isHighlightStructurePanelVisible.toggle()
    }

    func highlightColor(for role: HighlightStructureRole) -> UIColor {
        HighlightColorCodec.uiColor(
            from: highlightColorHex(for: role),
            fallback: HighlightColorCodec.uiColor(from: role.defaultColorHex)
        )
    }

    func highlightColorBinding(for role: HighlightStructureRole) -> Binding<Color> {
        Binding(
            get: { Color(uiColor: self.highlightColor(for: role)) },
            set: { newColor in
                self.updateHighlightRoleColor(UIColor(newColor), for: role)
            }
        )
    }

    func updateHighlightRoleColor(_ color: UIColor, for role: HighlightStructureRole) {
        let hex = HighlightColorCodec.hexString(from: color)
        highlightRoleHexByRole[role] = hex
        userDefaults.set(hex, forKey: highlightRolePaletteKey(for: role))
        if selectedHighlightRole == role {
            applyCanvasConfiguration()
        }
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
        let currentKey = [
            selectedTool.rawValue,
            highlightMode.rawValue,
            selectedHighlightRole.rawValue,
            highlightColorHex(for: selectedHighlightRole),
            "\(selectedColorID)",
            "\(strokeWidth)",
            selectedPenStyle.rawValue
        ].joined(separator: "-")
        if let cached = cachedPKTool, currentKey == lastToolKey {
            return cached
        }
        
        let tool: PKTool
        switch selectedTool {
        case .pen:
            tool = makePenTool()
        case .highlighter:
            let color = highlightMode == .structured
                ? highlightColor(for: selectedHighlightRole).withAlphaComponent(0.34)
                : uiColorForColorID(selectedColorID).withAlphaComponent(0.34)
            tool = PKInkingTool(.marker, color: color, width: CGFloat(strokeWidth + 12))
        case .eraser:
            tool = PKEraserTool(.vector)
        case .tape:
            let tapeColor = UIColor(PharTheme.ColorToken.accentButter).withAlphaComponent(0.92)
            tool = PKInkingTool(.marker, color: tapeColor, width: CGFloat(strokeWidth * 2.5))
        case .lasso, .paint, .text:
            tool = PKLassoTool()
        }
        
        cachedPKTool = tool
        lastToolKey = currentKey
        return tool
    }

    func currentDrawingPolicy() -> PKCanvasViewDrawingPolicy {
        isPencilOnlyInputEnabled ? .pencilOnly : .anyInput
    }

    func uiColorForColorID(_ id: Int) -> UIColor {
        if id == 999, let dynamic = dynamicColor {
            return dynamic
        }
        return annotationColors.first(where: { $0.id == id })?.uiColor ?? .black
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

    func updateDocument(_ document: PharDocument) {
        self.document = document
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
            lastHighlightStrokeCountByPageID[pageID] = drawing.strokes.count
            scheduleHighlightSnapshotRefresh(pageID: pageID)
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

    private func scheduleHighlightSnapshotRefresh(pageID: UUID?) {
        highlightSnapshotTask?.cancel()
        guard let pageID else {
            currentHighlightSnapshot = nil
            return
        }

        highlightSnapshotTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            await self?.refreshHighlightSnapshot(for: pageID)
        }
    }

    private func refreshHighlightSnapshot(for pageID: UUID) async {
        guard currentPageID == pageID else { return }
        let pageKey = pageID.uuidString.lowercased()
        let pageLabel = "페이지 \(pageNumber(for: pageID))"
        let referenceText = await highlightReferenceText(for: pageID)
        let items = await highlightStore.loadItems(documentURL: documentURL, pageKey: pageKey)
        let snapshot = highlightEngine.buildSnapshot(
            pageKey: pageKey,
            pageLabel: pageLabel,
            items: items,
            referenceText: referenceText,
            generatedAt: Date()
        )
        currentHighlightSnapshot = snapshot
        eventLogger.log(
            .highlightStructureRefreshed,
            document: document,
            pageID: pageID,
            sessionID: sessionID,
            payload: [
                "page_key": .string(pageKey),
                "item_count": .integer(snapshot.totalCount)
            ]
        )
    }

    private func highlightReferenceText(for pageID: UUID) async -> String? {
        guard let page = pages.first(where: { $0.id == pageID }) else { return nil }
        let textElementsText = page.textElements
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        if !textElementsText.isEmpty {
            return textElementsText
        }

        guard highlightMode == .structured else { return nil }
        guard let blankSource = analysisSource else { return nil }

        let blocks = await documentOCRService.recognizeBlankNoteBlocks(source: blankSource)
        let joined = blocks.map(\.text).joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }

    private func syncStructuredHighlightsIfNeeded(pageID: UUID, drawing: PKDrawing) {
        guard highlightMode == .structured else {
            return
        }

        let currentCount = drawing.strokes.count
        let lastCount = lastHighlightStrokeCountByPageID[pageID] ?? currentCount
        if currentCount == lastCount {
            return
        }

        if currentCount > lastCount, selectedTool != .highlighter {
            lastHighlightStrokeCountByPageID[pageID] = currentCount
            return
        }

        highlightSyncTask?.cancel()
        highlightSyncTask = Task { [weak self] in
            await self?.syncStructuredHighlights(pageID: pageID, drawing: drawing, previousCount: lastCount)
        }
    }

    private func syncStructuredHighlights(pageID: UUID, drawing: PKDrawing, previousCount: Int) async {
        let pageKey = pageID.uuidString.lowercased()
        let pageLabel = "페이지 \(pageNumber(for: pageID))"
        var items = await highlightStore.loadItems(documentURL: documentURL, pageKey: pageKey)
        let currentCount = drawing.strokes.count

        if currentCount < previousCount {
            items = highlightEngine.syncItems(currentItems: items, drawing: drawing)
        } else if currentCount > previousCount {
            let appendedStrokes = drawing.strokes.dropFirst(previousCount)
            let referenceText = await highlightReferenceText(for: pageID)
            let newItems = appendedStrokes.map { stroke in
                highlightEngine.captureItem(
                    documentID: document.id,
                    pageKey: pageKey,
                    pageLabel: pageLabel,
                    mode: .structured,
                    role: selectedHighlightRole,
                    colorHex: highlightColorHex(for: selectedHighlightRole),
                    stroke: stroke,
                    referenceText: referenceText
                )
            }
            items.append(contentsOf: newItems)
        }

        lastHighlightStrokeCountByPageID[pageID] = currentCount
        if items.isEmpty {
            await highlightStore.deleteItems(documentURL: documentURL, pageKey: pageKey)
        } else {
            try? await highlightStore.saveItems(items, documentURL: documentURL, pageKey: pageKey)
        }
        touchDocumentUpdatedAt()
        await refreshHighlightSnapshot(for: pageID)
    }

    private func highlightColorHex(for role: HighlightStructureRole) -> String {
        highlightRoleHexByRole[role] ?? role.defaultColorHex
    }

    private func loadHighlightPalettePresets() {
        var presets: [HighlightStructureRole: String] = [:]
        for role in HighlightStructureRole.allCases {
            presets[role] = userDefaults.string(forKey: highlightRolePaletteKey(for: role)) ?? role.defaultColorHex
        }
        highlightRoleHexByRole = presets
    }

    private func highlightRolePaletteKey(for role: HighlightStructureRole) -> String {
        "pharnote.highlight.role.\(role.rawValue)"
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
        case .fountain:
            return PKInkingTool(.fountainPen, color: baseColor, width: CGFloat(strokeWidth))
        case .brush:
            return PKInkingTool(.marker, color: baseColor, width: CGFloat(strokeWidth * 1.5))
        case .monoline:
            return PKInkingTool(.monoline, color: baseColor, width: CGFloat(strokeWidth))
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

    private func updateCurrentPageLayout(
        paperSize: BlankNotePaperSize?,
        backgroundStyle: BlankNoteBackgroundStyle?
    ) {
        guard let currentPageID,
              let index = pages.firstIndex(where: { $0.id == currentPageID }) else { return }
        if let paperSize {
            pages[index].paperSize = paperSize
        }
        if let backgroundStyle {
            pages[index].backgroundStyle = backgroundStyle
        }
        touchDocumentUpdatedAt()
        Task {
            await saveContentSnapshot()
        }
    }

    private func saveContentSnapshot() async {
        let snapshot = BlankNoteContent(version: 4, pages: pages)
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
        case .tape:
            return .tape
        case .eraser, .lasso, .paint, .text:
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
        case .tape:
            return "tape"
        case .eraser, .lasso, .paint, .text:
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
