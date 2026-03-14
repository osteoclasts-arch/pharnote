import Foundation
import Combine
import PDFKit
import PencilKit
import SwiftUI
import UIKit

@MainActor
final class PDFEditorViewModel: ObservableObject {
    struct SectionDraft: Identifiable, Hashable {
        let id: UUID
        var title: String
        var startPage: Int
    }

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
    }

    struct PDFTextSearchResult: Identifiable {
        let id: UUID
        let pageIndex: Int
        let snippet: String
        let selection: PDFSelection

        init(pageIndex: Int, snippet: String, selection: PDFSelection) {
            self.id = UUID()
            self.pageIndex = pageIndex
            self.snippet = snippet
            self.selection = selection
        }
    }

    struct AnalysisPreview {
        let pageNumber: Int
        let totalPages: Int
        let overlayStrokeCount: Int
        let isBookmarked: Bool
        let hasUnsavedChanges: Bool
        let updatedAt: Date
        let currentSearchMatches: Int
        let inputModeLabel: String
    }

    struct OutlineEntry: Identifiable, Hashable {
        enum Source: String, Hashable {
            case pdf
            case studySection
        }

        let id: String
        let title: String
        let pageIndex: Int
        let depth: Int
        let source: Source
    }

    @Published private(set) var pageCount: Int = 0
    @Published private(set) var currentPageIndex: Int = 0
    @Published private(set) var thumbnails: [Int: UIImage] = [:]
    @Published var pageJumpInput: String = "1"
    @Published var pdfTextSearchQuery: String = ""
    @Published private(set) var pdfTextSearchResults: [PDFTextSearchResult] = []
    @Published private(set) var currentPDFTextSearchResultIndex: Int?
    @Published var selectedTool: AnnotationTool = .pen {
        didSet { refreshEditActionAvailability() }
    }
    @Published var isToolSelectionActive: Bool = false {
        didSet { refreshEditActionAvailability() }
    }
    @Published var selectedPenStyle: WritingPenStyle = .ballpoint
    @Published var selectedColorID: Int = 0
    @Published var strokeWidth: Double = 5.0
    @Published private(set) var strokePresetConfiguration: WritingStrokePresetConfiguration
    @Published var isPencilOnlyInputEnabled: Bool = false
    @Published private(set) var canUndo: Bool = false
    @Published private(set) var canRedo: Bool = false
    @Published private(set) var canCopy: Bool = false
    @Published private(set) var canCut: Bool = false
    @Published private(set) var canPaste: Bool = false
    @Published private(set) var canDelete: Bool = false
    @Published private(set) var bookmarkedPageIndices: Set<Int> = []
    @Published private(set) var outlineEntries: [OutlineEntry] = []
    @Published private(set) var storedProgressSnapshot: StudyProgressSnapshot?
    @Published var isReadOnlyMode: Bool = false
    @Published var errorMessage: String?

    let document: PharDocument
    let annotationColors: [AnnotationColor] = [
        AnnotationColor(id: 0, uiColor: .black),
        AnnotationColor(id: 1, uiColor: .systemBlue),
        AnnotationColor(id: 2, uiColor: .systemRed),
        AnnotationColor(id: 3, uiColor: .systemGreen),
        AnnotationColor(id: 4, uiColor: .systemOrange)
    ]

    private weak var pdfView: PDFView?
    private var pdfDocument: PDFDocument?
    private let thumbnailGenerator = PDFThumbnailGenerator()
    private let overlayStore = PDFOverlayStore()
    private let eventLogger: StudyEventLogger
    private let libraryStore: LibraryStore
    private let userDefaults: UserDefaults
    private var strokePresetConfigurationsByTool: [AnnotationTool: WritingStrokePresetConfiguration]
    private let requestedInitialPageIndex: Int?
    private var thumbnailGenerationTask: Task<Void, Never>?
    private var overlaySaveTasks: [Int: Task<Void, Never>] = [:]
    private var dirtyOverlayPages: Set<Int> = []
    private var overlayDrawingCache: [Int: PKDrawing] = [:]
    private var pageLastEditedAt: [Int: Date] = [:]
    private weak var activeOverlayCanvas: PencilPassthroughCanvasView?
    private var didLoad = false
    private var didLogDocumentOpen = false
    private let thumbnailSize = CGSize(width: 86, height: 112)
    private let sessionID = UUID()
    private let sessionStartedAt = Date()
    private var pageEntryStartedAt = Date()
    private var dwellSecondsByPageIndex: [Int: TimeInterval] = [:]
    private var revisitCountByPageIndex: [Int: Int] = [:]
    private var toolUsageCounts: [AnnotationTool: Int] = [.pen: 1]
    private var undoCountByPageIndex: [Int: Int] = [:]
    private var redoCountByPageIndex: [Int: Int] = [:]
    private var lassoActionCountByPageIndex: [Int: Int] = [:]
    private var copyActionCountByPageIndex: [Int: Int] = [:]
    private var pasteActionCountByPageIndex: [Int: Int] = [:]
    private var pageNavigationHistory: [Int] = []

    init(
        document: PharDocument,
        initialPageKey: String? = nil,
        eventLogger: StudyEventLogger? = nil,
        libraryStore: LibraryStore? = nil,
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
        self.eventLogger = eventLogger ?? StudyEventLogger.shared
        self.libraryStore = libraryStore ?? LibraryStore()
        self.userDefaults = userDefaults
        self.strokePresetConfigurationsByTool = [
            .pen: penPresetConfiguration,
            .highlighter: highlighterPresetConfiguration
        ]
        self._strokePresetConfiguration = Published(initialValue: penPresetConfiguration)
        self.requestedInitialPageIndex = Self.pageIndex(from: initialPageKey)
        self.storedProgressSnapshot = document.progress
        self.bookmarkedPageIndices = Set(
            (userDefaults.array(forKey: Self.bookmarkDefaultsKey(for: document.id)) as? [Int]) ?? []
        )
        self.strokeWidth = penPresetConfiguration.values[penPresetConfiguration.selectedIndex]
    }

    func attachPDFView(_ pdfView: PDFView) {
        self.pdfView = pdfView
        configurePDFView(pdfView)

        if let pdfDocument {
            pdfView.document = pdfDocument
            goToPage(index: currentPageIndex)
        }
    }

    func loadPDFIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        do {
            let pdfURL = try resolvePDFURL()
            guard let loadedDocument = PDFDocument(url: pdfURL) else {
                errorMessage = "PDF 문서를 열 수 없습니다."
                return
            }

            pdfDocument = loadedDocument
            pageCount = loadedDocument.pageCount
            let initialPageIndex = min(max(requestedInitialPageIndex ?? 0, 0), max(loadedDocument.pageCount - 1, 0))
            currentPageIndex = initialPageIndex
            pageJumpInput = "\(initialPageIndex + 1)"
            trimBookmarksToLoadedPageCount()
            logDocumentOpenedIfNeeded()

            if let pdfView {
                pdfView.document = loadedDocument
                goToPage(index: initialPageIndex)
            }

            recordPageVisit(initialPageIndex)
            persistStudyProgress()

            clearPDFTextSearch(resetQuery: false)
            rebuildOutlineEntries()

            generateThumbnails(from: pdfURL)
        } catch {
            errorMessage = "PDF 로드 실패: \(error.localizedDescription)"
        }
    }

    func handlePDFPageChanged(_ currentPage: PDFPage?) {
        guard let currentPage, let pdfDocument else { return }
        let index = pdfDocument.index(for: currentPage)
        guard index != NSNotFound else { return }
        let previousPageIndex = currentPageIndex
        if previousPageIndex != index {
            recordPageExit()
        }
        currentPageIndex = index
        pageJumpInput = "\(index + 1)"

        if previousPageIndex != index {
            saveOverlayPageImmediately(previousPageIndex)
            recordPageVisit(index)
            persistStudyProgress()
        }
        refreshEditActionAvailability()
    }

    func goToPreviousPage() {
        goToPage(index: currentPageIndex - 1)
    }

    func goToNextPage() {
        goToPage(index: currentPageIndex + 1)
    }

    func goToInputPage() {
        guard let input = Int(pageJumpInput) else { return }
        goToPage(index: input - 1)
    }

    func goToPage(index: Int) {
        guard let pdfDocument else { return }
        guard index >= 0 && index < pdfDocument.pageCount else { return }
        guard let page = pdfDocument.page(at: index) else { return }
        pdfView?.go(to: page)
        currentPageIndex = index
        pageJumpInput = "\(index + 1)"
    }

    func thumbnail(at index: Int) -> UIImage? {
        thumbnails[index]
    }

    func stopTasks() {
        thumbnailGenerationTask?.cancel()
        thumbnailGenerationTask = nil
        recordPageExit()
        saveAllOverlayPagesImmediately()
    }

    func closeDocument() async {
        thumbnailGenerationTask?.cancel()
        thumbnailGenerationTask = nil
        recordPageExit()
        await saveAllOverlayPagesImmediatelyAndWait()
        persistStudyProgress()
        guard didLogDocumentOpen else { return }
        eventLogger.log(
            .documentClosed,
            document: document,
            pageID: currentAnalysisPageID,
            sessionID: sessionID,
            payload: [
                "close_reason": .string("editor_disappear")
            ]
        )
        didLogDocumentOpen = false
    }

    private func persistStudyProgress() {
        guard pageCount > 0 else { return }
        let currentPage = max(currentPageIndex + 1, 1)
        let totalPages = max(pageCount, 1)

        Task(priority: .utility) { [document, libraryStore] in
            let updatedDocument = try? libraryStore.updateStudyProgress(
                documentID: document.id,
                currentPage: currentPage,
                totalPages: totalPages
            )
            if let updatedProgress = updatedDocument?.progress {
                await MainActor.run {
                    self.storedProgressSnapshot = updatedProgress
                }
            }
        }
    }

    private static func pageIndex(from pageKey: String?) -> Int? {
        guard let pageKey, pageKey.hasPrefix("pdf-page-") else { return nil }
        return Int(pageKey.replacingOccurrences(of: "pdf-page-", with: ""))
    }

    var canGoPrevious: Bool {
        currentPageIndex > 0
    }

    var canGoNext: Bool {
        currentPageIndex + 1 < pageCount
    }

    var currentPageNumber: Int {
        max(currentPageIndex + 1, 1)
    }

    var sortedBookmarkedPageIndices: [Int] {
        bookmarkedPageIndices.sorted()
    }

    var currentPageOverlayStrokeCount: Int {
        activeOverlayCanvas?.drawing.strokes.count ?? overlayDrawingCache[currentPageIndex]?.strokes.count ?? 0
    }

    var currentPageHasUnsavedChanges: Bool {
        dirtyOverlayPages.contains(currentPageIndex)
    }

    var isCurrentPageBookmarked: Bool {
        bookmarkedPageIndices.contains(currentPageIndex)
    }

    var currentPageUpdatedAt: Date {
        pageLastEditedAt[currentPageIndex] ?? document.updatedAt
    }

    var currentPageSearchMatchCount: Int {
        pdfTextSearchResults.reduce(into: 0) { count, result in
            if result.pageIndex == currentPageIndex {
                count += 1
            }
        }
    }

    var inputModeLabel: String {
        if isReadOnlyMode {
            return "Read Only"
        }
        if !isToolSelectionActive {
            return "Scroll Mode"
        }
        return isPencilOnlyInputEnabled ? "Apple Pencil only" : "Touch annotation enabled"
    }

    var analysisPreview: AnalysisPreview? {
        guard pageCount > 0 else { return nil }
        return AnalysisPreview(
            pageNumber: currentPageNumber,
            totalPages: max(pageCount, 1),
            overlayStrokeCount: currentPageOverlayStrokeCount,
            isBookmarked: isCurrentPageBookmarked,
            hasUnsavedChanges: currentPageHasUnsavedChanges,
            updatedAt: currentPageUpdatedAt,
            currentSearchMatches: currentPageSearchMatchCount,
            inputModeLabel: inputModeLabel
        )
    }

    var currentAnalysisPageID: UUID? {
        guard pageCount > 0 else { return nil }
        return UUID.stableAnalysisPageID(namespace: document.id, pageIndex: currentPageIndex)
    }

    var canAnalyzeCurrentSelection: Bool {
        analysisSource != nil && activeTool == .lasso && (canCopy || canCut || canDelete)
    }

    var currentAnalysisScope: AnalysisScope {
        canAnalyzeCurrentSelection ? .selection : .page
    }

    var sectionProgressHeadline: String? {
        currentProgressSnapshot.sectionProgressLabel
    }

    var sectionProgressSubheadline: String? {
        currentProgressSnapshot.dashboardSubheadline
    }

    var currentSectionTitle: String? {
        currentProgressSnapshot.currentSectionTitle
    }

    var nextSectionTitle: String? {
        currentProgressSnapshot.nextSectionTitle
    }

    var completedSectionCount: Int {
        currentProgressSnapshot.completedSectionCount
    }

    var totalSectionCount: Int {
        currentProgressSnapshot.totalSectionCount
    }

    var overallCompletionRatio: Double {
        currentProgressSnapshot.completionRatio
    }

    var sectionDrafts: [SectionDraft] {
        let sourceSections = currentProgressSnapshot.sections.isEmpty
            ? [StudySectionProgress(id: UUID(), title: "단원 1", startPage: 1, endPage: max(pageCount, 1), status: .current, completionRatio: 0)]
            : currentProgressSnapshot.sections

        return sourceSections
            .sorted { $0.startPage < $1.startPage }
            .enumerated()
            .map { index, section in
                SectionDraft(
                    id: section.id,
                    title: section.title.isEmpty ? "단원 \(index + 1)" : section.title,
                    startPage: section.startPage
                )
            }
    }

    func suggestedNewSectionDraft() -> SectionDraft {
        let existingStarts = Set(sectionDrafts.map(\.startPage))
        var proposedStart = currentPageNumber
        while existingStarts.contains(proposedStart) && proposedStart < max(pageCount, 1) {
            proposedStart += 1
        }
        if existingStarts.contains(proposedStart) {
            proposedStart = max(1, max(pageCount, 1))
        }
        return SectionDraft(
            id: UUID(),
            title: "단원 \(sectionDrafts.count + 1)",
            startPage: proposedStart
        )
    }

    func saveSectionDrafts(_ drafts: [SectionDraft]) async -> Bool {
        let normalizedSections = normalizedSections(from: drafts)

        do {
            if let updatedDocument = try libraryStore.updateStudySections(documentID: document.id, sections: normalizedSections) {
                storedProgressSnapshot = updatedDocument.progress
                rebuildOutlineEntries()
            }
            return true
        } catch {
            errorMessage = "단원 매핑 저장 실패: \(error.localizedDescription)"
            return false
        }
    }

    var analysisSource: PDFPageAnalysisSource? {
        guard pageCount > 0 else { return nil }

        let pageID = UUID.stableAnalysisPageID(namespace: document.id, pageIndex: currentPageIndex)
        let previousPageIds = currentPageIndex > 0
            ? [UUID.stableAnalysisPageID(namespace: document.id, pageIndex: currentPageIndex - 1)]
            : []
        let nextPageIds = currentPageIndex + 1 < pageCount
            ? [UUID.stableAnalysisPageID(namespace: document.id, pageIndex: currentPageIndex + 1)]
            : []
        let drawing = currentOverlayDrawing()

        return PDFPageAnalysisSource(
            document: document,
            pageId: pageID,
            pageIndex: currentPageIndex,
            pageCount: pageCount,
            previousPageIds: previousPageIds,
            nextPageIds: nextPageIds,
            pageState: currentPageState(),
            previewImageData: thumbnails[currentPageIndex]?.pngData(),
            drawingData: drawing.strokes.isEmpty ? nil : drawing.dataRepresentation(),
            drawingStats: drawingStats(for: drawing),
            pdfTextBlocks: currentPDFPageText().map { [AnalysisTextBlock(kind: "pdf-text", text: $0, pageIndex: currentPageIndex)] } ?? [],
            manualTags: [],
            bookmarks: isCurrentPageBookmarked ? ["page-bookmark"] : [],
            sessionId: sessionID,
            dwellMs: currentDwellMilliseconds(for: currentPageIndex),
            foregroundEditsMs: currentForegroundEditMilliseconds(for: drawing),
            revisitCount: revisitCountByPageIndex[currentPageIndex, default: 0],
            toolUsage: toolUsageCounts
                .map { AnalysisToolUsage(tool: $0.key.rawValue, count: $0.value) }
                .sorted { $0.tool < $1.tool },
            lassoActions: lassoActionCountByPageIndex[currentPageIndex, default: 0],
            copyActions: copyActionCountByPageIndex[currentPageIndex, default: 0],
            pasteActions: pasteActionCountByPageIndex[currentPageIndex, default: 0],
            undoCount: undoCountByPageIndex[currentPageIndex, default: 0],
            redoCount: redoCountByPageIndex[currentPageIndex, default: 0],
            zoomEventCount: 0,
            navigationPath: pageNavigationHistory.map { "page-\($0 + 1)" },
            sourceFingerprint: resolvePDFFileName(),
            postSolveReview: nil
        )
    }

    var canGoToPreviousPDFTextResult: Bool {
        guard let currentPDFTextSearchResultIndex else { return false }
        return !pdfTextSearchResults.isEmpty && currentPDFTextSearchResultIndex > 0
    }

    var canGoToNextPDFTextResult: Bool {
        guard let currentPDFTextSearchResultIndex else { return false }
        return !pdfTextSearchResults.isEmpty && currentPDFTextSearchResultIndex + 1 < pdfTextSearchResults.count
    }

    var activeTool: AnnotationTool? {
        isToolSelectionActive ? selectedTool : nil
    }

    var isCanvasInputEnabled: Bool {
        !isReadOnlyMode && isToolSelectionActive
    }

    var allowsPDFNavigation: Bool {
        !isCanvasInputEnabled
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

    func selectTool(_ tool: AnnotationTool) {
        if selectedTool == tool && isToolSelectionActive {
            isToolSelectionActive = false
            applyPDFInteractionMode()
            return
        }

        selectedTool = tool
        isToolSelectionActive = true
        toolUsageCounts[tool, default: 0] += 1
        if tool == .lasso {
            lassoActionCountByPageIndex[currentPageIndex, default: 0] += 1
        }
        eventLogger.log(
            .annotationToolSelected,
            document: document,
            pageID: currentAnalysisPageID,
            sessionID: sessionID,
            payload: [
                "tool": .string(tool.rawValue),
                "source": .string("toolbar")
            ]
        )
        if let inkTool = activeInkTool(for: tool) {
            applyStrokePresetConfiguration(for: inkTool)
        }
        applyPDFInteractionMode()
    }

    func deactivateToolSelection() {
        guard isToolSelectionActive else { return }
        isToolSelectionActive = false
        applyPDFInteractionMode()
    }

    func uiColorForColorID(_ id: Int) -> UIColor {
        annotationColors.first(where: { $0.id == id })?.uiColor ?? .black
    }

    func swiftUIColorForColorID(_ id: Int) -> Color {
        Color(uiColor: uiColorForColorID(id))
    }

    func updateSelectedColor(_ colorID: Int) {
        selectedColorID = colorID
    }

    func selectPenStyle(_ penStyle: WritingPenStyle) {
        selectedPenStyle = penStyle
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
        refreshEditActionAvailability()
        applyPDFInteractionMode()
        eventLogger.log(
            .inputModeChanged,
            document: document,
            pageID: currentAnalysisPageID,
            sessionID: sessionID,
            payload: [
                "allows_finger_drawing": .bool(!isPencilOnlyInputEnabled)
            ]
        )
    }

    func toggleReadOnlyMode() {
        isReadOnlyMode.toggle()
        refreshEditActionAvailability()
        applyPDFInteractionMode()
    }

    func toggleCurrentPageBookmark() {
        toggleBookmark(for: currentPageIndex)
    }

    func toggleBookmark(for pageIndex: Int) {
        var updatedBookmarks = bookmarkedPageIndices
        let isBookmarked: Bool
        if updatedBookmarks.contains(pageIndex) {
            updatedBookmarks.remove(pageIndex)
            isBookmarked = false
        } else {
            updatedBookmarks.insert(pageIndex)
            isBookmarked = true
        }
        bookmarkedPageIndices = updatedBookmarks
        persistBookmarks()
        eventLogger.log(
            .pageBookmarkToggled,
            document: document,
            pageID: UUID.stableAnalysisPageID(namespace: document.id, pageIndex: pageIndex),
            sessionID: sessionID,
            payload: [
                "bookmarked": .bool(isBookmarked),
                "page_index": .integer(pageIndex)
            ]
        )
    }

    func isPageBookmarked(_ pageIndex: Int) -> Bool {
        bookmarkedPageIndices.contains(pageIndex)
    }

    func goToPage(pageKey: String?) {
        guard let pageIndex = Self.pageIndex(from: pageKey) else { return }
        goToPage(index: pageIndex)
    }

    func pageTitle(for pageIndex: Int) -> String {
        "페이지 \(pageIndex + 1)"
    }

    func pageSectionTitle(for pageIndex: Int) -> String? {
        let displayPage = pageIndex + 1
        return currentProgressSnapshot.sections.first(where: { $0.contains(page: displayPage) })?.title
    }

    func pageSubtitle(for pageIndex: Int) -> String? {
        var parts: [String] = []

        if let sectionTitle = pageSectionTitle(for: pageIndex), !sectionTitle.isEmpty {
            parts.append(sectionTitle)
        }
        if isPageBookmarked(pageIndex) {
            parts.append("북마크")
        }
        if isPageDirty(pageIndex) {
            parts.append("편집 중")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    func pageIndex(forLinkURL url: URL) -> Int? {
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            if let page = components.queryItems?.first(where: { $0.name.caseInsensitiveCompare("page") == .orderedSame })?.value.flatMap(Int.init) {
                return min(max(page - 1, 0), max(pageCount - 1, 0))
            }
            if let pageIndex = components.queryItems?.first(where: { $0.name.caseInsensitiveCompare("pageIndex") == .orderedSame })?.value.flatMap(Int.init) {
                return min(max(pageIndex, 0), max(pageCount - 1, 0))
            }
        }

        if let fragment = url.fragment?.lowercased() {
            if let page = fragment
                .replacingOccurrences(of: "page=", with: "")
                .split(separator: "&")
                .first
                .flatMap({ Int($0) }) {
                return min(max(page - 1, 0), max(pageCount - 1, 0))
            }
        }

        return nil
    }

    func isPageDirty(_ pageIndex: Int) -> Bool {
        dirtyOverlayPages.contains(pageIndex)
    }

    func currentTool() -> PKTool {
        switch selectedTool {
        case .pen:
            return makePenTool()
        case .highlighter:
            let color = uiColorForColorID(selectedColorID).withAlphaComponent(0.35)
            return PKInkingTool(.marker, color: color, width: CGFloat(strokeWidth))
        case .eraser:
            return PKEraserTool(.vector)
        case .lasso:
            return PKLassoTool()
        }
    }

    func currentDrawingPolicy() -> PKCanvasViewDrawingPolicy {
        isPencilOnlyInputEnabled ? .pencilOnly : .anyInput
    }

    func allowsFingerDrawing() -> Bool {
        isCanvasInputEnabled && !isPencilOnlyInputEnabled
    }

    func loadOverlayDrawing(for pageIndex: Int) async -> PKDrawing {
        if let cached = overlayDrawingCache[pageIndex] {
            return cached
        }

        if let data = await overlayStore.loadDrawingData(documentURL: documentURL, pageIndex: pageIndex),
           let drawing = try? PKDrawing(data: data) {
            overlayDrawingCache[pageIndex] = drawing
            return drawing
        }

        let emptyDrawing = PKDrawing()
        overlayDrawingCache[pageIndex] = emptyDrawing
        return emptyDrawing
    }

    func overlayDrawingDidChange(pageIndex: Int, drawing: PKDrawing) {
        overlayDrawingCache[pageIndex] = drawing
        dirtyOverlayPages.insert(pageIndex)
        pageLastEditedAt[pageIndex] = Date()
        objectWillChange.send()
        scheduleOverlaySave(pageIndex: pageIndex)
        refreshEditActionAvailability()
    }

    func saveAllOverlayPagesImmediately() {
        Task {
            await saveAllOverlayPagesImmediatelyAndWait()
        }
    }

    func saveAllOverlayPagesImmediatelyAndWait() async {
        overlaySaveTasks.values.forEach { $0.cancel() }
        overlaySaveTasks.removeAll()

        let dirtyPages = Array(dirtyOverlayPages)
        for pageIndex in dirtyPages {
            await persistOverlayPageIfNeeded(pageIndex: pageIndex, force: true)
        }
    }

    func setActiveOverlayCanvas(_ canvas: PencilPassthroughCanvasView?) {
        activeOverlayCanvas = canvas
        objectWillChange.send()
        refreshEditActionAvailability()
        applyPDFInteractionMode()
    }

    func refreshCanvasInteractionState() {
        refreshEditActionAvailability()
    }

    func undo() {
        guard let canvas = activeOverlayCanvas else { return }
        canvas.becomeFirstResponder()
        canvas.undoManager?.undo()
        undoCountByPageIndex[currentPageIndex, default: 0] += 1
        eventLogger.log(
            .undoInvoked,
            document: document,
            pageID: currentAnalysisPageID,
            sessionID: sessionID,
            payload: [
                "source": .string("toolbar")
            ]
        )
        markCurrentPageDirtyFromCanvas()
    }

    func redo() {
        guard let canvas = activeOverlayCanvas else { return }
        canvas.becomeFirstResponder()
        canvas.undoManager?.redo()
        redoCountByPageIndex[currentPageIndex, default: 0] += 1
        eventLogger.log(
            .redoInvoked,
            document: document,
            pageID: currentAnalysisPageID,
            sessionID: sessionID,
            payload: [
                "source": .string("toolbar")
            ]
        )
        markCurrentPageDirtyFromCanvas()
    }

    func copySelection() {
        guard activeTool == .lasso, let canvas = activeOverlayCanvas else { return }
        canvas.becomeFirstResponder()
        canvas.copy(nil)
        copyActionCountByPageIndex[currentPageIndex, default: 0] += 1
        refreshEditActionAvailability()
    }

    func cutSelection() {
        guard activeTool == .lasso, let canvas = activeOverlayCanvas else { return }
        canvas.becomeFirstResponder()
        canvas.cut(nil)
        copyActionCountByPageIndex[currentPageIndex, default: 0] += 1
        markCurrentPageDirtyFromCanvas()
    }

    func pasteSelection() {
        guard let canvas = activeOverlayCanvas else { return }
        canvas.becomeFirstResponder()
        canvas.paste(nil)
        pasteActionCountByPageIndex[currentPageIndex, default: 0] += 1
        markCurrentPageDirtyFromCanvas()
    }

    func deleteSelection() {
        guard activeTool == .lasso, let canvas = activeOverlayCanvas else { return }
        canvas.becomeFirstResponder()
        canvas.delete(nil)
        markCurrentPageDirtyFromCanvas()
    }

    func performPDFTextSearch() {
        guard let pdfDocument else { return }
        let query = pdfTextSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            clearPDFTextSearch()
            return
        }

        let selections = pdfDocument.findString(query, withOptions: [.caseInsensitive, .diacriticInsensitive])
        let results: [PDFTextSearchResult] = selections.compactMap { selection in
            guard let page = selection.pages.first else { return nil }
            let pageIndex = pdfDocument.index(for: page)
            guard pageIndex != NSNotFound else { return nil }
            return PDFTextSearchResult(
                pageIndex: pageIndex,
                snippet: makeSearchSnippet(from: selection, fallbackQuery: query),
                selection: selection
            )
        }

        pdfTextSearchResults = results

        guard !results.isEmpty else {
            currentPDFTextSearchResultIndex = nil
            pdfView?.highlightedSelections = nil
            return
        }

        goToPDFTextSearchResult(at: 0)
    }

    func clearPDFTextSearch(resetQuery: Bool = true) {
        if resetQuery {
            pdfTextSearchQuery = ""
        }
        pdfTextSearchResults = []
        currentPDFTextSearchResultIndex = nil
        pdfView?.highlightedSelections = nil
    }

    func goToPreviousPDFTextResult() {
        guard canGoToPreviousPDFTextResult,
              let currentPDFTextSearchResultIndex else { return }
        goToPDFTextSearchResult(at: currentPDFTextSearchResultIndex - 1)
    }

    func goToNextPDFTextResult() {
        guard canGoToNextPDFTextResult,
              let currentPDFTextSearchResultIndex else { return }
        goToPDFTextSearchResult(at: currentPDFTextSearchResultIndex + 1)
    }

    func goToPDFTextSearchResult(at index: Int) {
        guard index >= 0 && index < pdfTextSearchResults.count else { return }
        currentPDFTextSearchResultIndex = index
        let result = pdfTextSearchResults[index]
        pdfView?.go(to: result.selection)
        updatePDFTextSearchHighlights(selectedIndex: index)
    }

    private func configurePDFView(_ pdfView: PDFView) {
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .systemGroupedBackground
        pdfView.displaysPageBreaks = true
        applyPDFInteractionMode()
    }

    private func rebuildOutlineEntries() {
        let pdfEntries = flattenedOutlineEntries()
        outlineEntries = pdfEntries.isEmpty ? fallbackOutlineEntries() : pdfEntries
    }

    private func flattenedOutlineEntries() -> [OutlineEntry] {
        guard let pdfDocument, let outlineRoot = pdfDocument.outlineRoot else { return [] }

        var entries: [OutlineEntry] = []

        func visit(_ outline: PDFOutline, depth: Int) {
            if let pageIndex = outlinePageIndex(outline, in: pdfDocument) {
                let normalizedLabel = outline.label?.trimmingCharacters(in: .whitespacesAndNewlines)
                let title: String
                if let normalizedLabel, !normalizedLabel.isEmpty {
                    title = normalizedLabel
                } else {
                    title = pageTitle(for: pageIndex)
                }
                entries.append(
                    OutlineEntry(
                        id: "pdf-\(depth)-\(pageIndex)-\(entries.count)",
                        title: title,
                        pageIndex: pageIndex,
                        depth: depth,
                        source: .pdf
                    )
                )
            }

            for childIndex in 0..<outline.numberOfChildren {
                guard let child = outline.child(at: childIndex) else { continue }
                visit(child, depth: depth + 1)
            }
        }

        for childIndex in 0..<outlineRoot.numberOfChildren {
            guard let child = outlineRoot.child(at: childIndex) else { continue }
            visit(child, depth: 0)
        }

        return entries
    }

    private func fallbackOutlineEntries() -> [OutlineEntry] {
        currentProgressSnapshot.sections
            .sorted { $0.startPage < $1.startPage }
            .enumerated()
            .map { index, section in
                let pageIndex = min(max(section.startPage - 1, 0), max(pageCount - 1, 0))
                return OutlineEntry(
                    id: "section-\(section.id.uuidString)-\(index)",
                    title: section.title.isEmpty ? pageTitle(for: pageIndex) : section.title,
                    pageIndex: pageIndex,
                    depth: 0,
                    source: .studySection
                )
            }
    }

    private func outlinePageIndex(_ outline: PDFOutline, in document: PDFDocument) -> Int? {
        if let destination = outline.destination, let page = destination.page {
            let index = document.index(for: page)
            return index == NSNotFound ? nil : index
        }

        if let action = outline.action as? PDFActionGoTo, let page = action.destination.page {
            let index = document.index(for: page)
            return index == NSNotFound ? nil : index
        }

        return nil
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

    private func generateThumbnails(from pdfURL: URL) {
        thumbnailGenerationTask?.cancel()
        thumbnails = [:]

        thumbnailGenerationTask = Task {
            let thumbnailDataMap = await thumbnailGenerator.generateThumbnailData(
                pdfURL: pdfURL,
                targetSize: thumbnailSize
            )

            if Task.isCancelled { return }

            var decodedImages: [Int: UIImage] = [:]
            for (index, data) in thumbnailDataMap {
                if let image = UIImage(data: data) {
                    decodedImages[index] = image
                }
            }
            thumbnails = decodedImages
        }
    }

    private func resolvePDFURL() throws -> URL {
        let packageURL = URL(fileURLWithPath: document.path, isDirectory: true)
        let preferredURL = packageURL.appendingPathComponent("Original.pdf", isDirectory: false)

        if FileManager.default.fileExists(atPath: preferredURL.path) {
            return preferredURL
        }

        let files = try FileManager.default.contentsOfDirectory(
            at: packageURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        if let fallbackPDFURL = files.first(where: { $0.pathExtension.lowercased() == "pdf" }) {
            return fallbackPDFURL
        }

        throw NSError(
            domain: "pharnote.pdf",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: "문서 패키지에서 PDF 파일을 찾지 못했습니다."]
        )
    }

    private func scheduleOverlaySave(pageIndex: Int) {
        overlaySaveTasks[pageIndex]?.cancel()
        overlaySaveTasks[pageIndex] = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            await self?.persistOverlayPageIfNeeded(pageIndex: pageIndex, force: false)
        }
    }

    private func saveOverlayPageImmediately(_ pageIndex: Int) {
        overlaySaveTasks[pageIndex]?.cancel()
        overlaySaveTasks.removeValue(forKey: pageIndex)

        Task {
            await persistOverlayPageIfNeeded(pageIndex: pageIndex, force: true)
        }
    }

    private func persistOverlayPageIfNeeded(pageIndex: Int, force: Bool) async {
        overlaySaveTasks.removeValue(forKey: pageIndex)
        guard force || dirtyOverlayPages.contains(pageIndex) else { return }
        guard let drawing = overlayDrawingCache[pageIndex] else { return }

        do {
            try await overlayStore.saveDrawingData(
                drawing.dataRepresentation(),
                documentURL: documentURL,
                pageIndex: pageIndex
            )
            dirtyOverlayPages.remove(pageIndex)
            pageLastEditedAt[pageIndex] = Date()
            let stats = drawingStats(for: drawing)
            let pageID = UUID.stableAnalysisPageID(namespace: document.id, pageIndex: pageIndex)
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
            SearchInfrastructure.shared.enqueueHandwritingIndexJob(
                documentID: document.id,
                pageKey: "pdf-page-\(pageIndex)"
            )
            objectWillChange.send()
        } catch {
            errorMessage = "PDF 필기 저장 실패: \(error.localizedDescription)"
        }
    }

    private func markCurrentPageDirtyFromCanvas() {
        guard let canvas = activeOverlayCanvas else { return }
        overlayDrawingCache[currentPageIndex] = canvas.drawing
        dirtyOverlayPages.insert(currentPageIndex)
        pageLastEditedAt[currentPageIndex] = Date()
        objectWillChange.send()
        scheduleOverlaySave(pageIndex: currentPageIndex)
        refreshEditActionAvailability()
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
        refreshEditActionAvailability()
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
            refreshEditActionAvailability()
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

    private func refreshEditActionAvailability() {
        guard isCanvasInputEnabled, let canvas = activeOverlayCanvas else {
            canUndo = false
            canRedo = false
            canCopy = false
            canCut = false
            canPaste = false
            canDelete = false
            return
        }

        canvas.becomeFirstResponder()

        canUndo = canvas.undoManager?.canUndo ?? false
        canRedo = canvas.undoManager?.canRedo ?? false
        canPaste = canvas.canPerformAction(#selector(UIResponderStandardEditActions.paste(_:)), withSender: nil)

        if activeTool == .lasso {
            canCopy = canvas.canPerformAction(#selector(UIResponderStandardEditActions.copy(_:)), withSender: nil)
            canCut = canvas.canPerformAction(#selector(UIResponderStandardEditActions.cut(_:)), withSender: nil)
            canDelete = canvas.canPerformAction(#selector(UIResponderStandardEditActions.delete(_:)), withSender: nil)
        } else {
            canCopy = false
            canCut = false
            canDelete = false
        }
    }

    private func updatePDFTextSearchHighlights(selectedIndex: Int?) {
        guard !pdfTextSearchResults.isEmpty else {
            pdfView?.highlightedSelections = nil
            return
        }

        var highlightedSelections: [PDFSelection] = []
        for (index, result) in pdfTextSearchResults.enumerated() {
            guard let copiedSelection = result.selection.copy() as? PDFSelection else { continue }
            if selectedIndex == index {
                copiedSelection.color = UIColor.systemOrange.withAlphaComponent(0.45)
            } else {
                copiedSelection.color = UIColor.systemYellow.withAlphaComponent(0.3)
            }
            highlightedSelections.append(copiedSelection)
        }

        pdfView?.highlightedSelections = highlightedSelections
    }

    private func applyPDFInteractionMode() {
        guard let pdfView else { return }
        let allowsNavigation = allowsPDFNavigation
        let isMarkupModeEnabled = isCanvasInputEnabled

        pdfView.isInMarkupMode = isMarkupModeEnabled
        if isMarkupModeEnabled {
            pdfView.clearSelection()
        }

        descendantScrollViews(in: pdfView).forEach { scrollView in
            guard !(scrollView is PKCanvasView) else { return }

            scrollView.isScrollEnabled = allowsNavigation
            scrollView.panGestureRecognizer.isEnabled = allowsNavigation
            scrollView.panGestureRecognizer.allowedTouchTypes = allowsNavigation
                ? [NSNumber(value: UITouch.TouchType.direct.rawValue)]
                : []
            scrollView.pinchGestureRecognizer?.isEnabled = allowsNavigation
            scrollView.pinchGestureRecognizer?.allowedTouchTypes = allowsNavigation
                ? [NSNumber(value: UITouch.TouchType.direct.rawValue)]
                : []
        }
    }

    private func descendantScrollViews(in rootView: UIView) -> [UIScrollView] {
        var scrollViews: [UIScrollView] = []

        rootView.subviews.forEach { subview in
            if let scrollView = subview as? UIScrollView {
                scrollViews.append(scrollView)
            }
            scrollViews.append(contentsOf: descendantScrollViews(in: subview))
        }

        return scrollViews
    }

    private func makeSearchSnippet(from selection: PDFSelection, fallbackQuery: String) -> String {
        let baseText = selection.string?.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseText, !baseText.isEmpty else { return fallbackQuery }
        if baseText.count <= 80 { return baseText }
        return String(baseText.prefix(80)) + "..."
    }

    private func currentOverlayDrawing() -> PKDrawing {
        if let activeOverlayCanvas {
            return activeOverlayCanvas.drawing
        }
        return overlayDrawingCache[currentPageIndex] ?? PKDrawing()
    }

    private func currentPDFPageText() -> String? {
        guard let pdfDocument, let page = pdfDocument.page(at: currentPageIndex) else { return nil }
        let text = page.string?
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    private var currentProgressSnapshot: StudyProgressSnapshot {
        let baseProgress = storedProgressSnapshot ?? document.progress
        let totalPages = max(pageCount, baseProgress?.totalPages ?? 1)
        let currentPage = currentPageNumber
        let furthestPage = max(baseProgress?.furthestPage ?? currentPage, currentPage)

        return StudyProgressSnapshot(
            currentPage: currentPage,
            totalPages: totalPages,
            furthestPage: furthestPage,
            completionRatio: min(Double(furthestPage) / Double(totalPages), 1.0),
            lastStudiedAt: baseProgress?.lastStudiedAt ?? Date(),
            sections: resolvedSectionSnapshots(currentPage: currentPage, furthestPage: furthestPage)
        )
    }

    private func resolvedSectionSnapshots(currentPage: Int, furthestPage: Int) -> [StudySectionProgress] {
        let sections = (storedProgressSnapshot ?? document.progress)?.sections ?? []
        guard !sections.isEmpty else { return [] }

        return sections.map { section in
            let completedPages = min(max(furthestPage - section.startPage + 1, 0), section.pageCount)
            let ratio = min(Double(completedPages) / Double(section.pageCount), 1.0)
            let status: StudySectionStatus

            if currentPage > section.endPage {
                status = .completed
            } else if section.contains(page: currentPage) {
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

    private func normalizedSections(from drafts: [SectionDraft]) -> [StudySectionProgress] {
        let totalPages = max(pageCount, 1)
        let cleanedDrafts = drafts
            .map { draft in
                SectionDraft(
                    id: draft.id,
                    title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    startPage: min(max(draft.startPage, 1), totalPages)
                )
            }
            .sorted { lhs, rhs in
                if lhs.startPage == rhs.startPage {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.startPage < rhs.startPage
            }

        var uniqueDrafts: [SectionDraft] = []
        var lastStartPage = 0

        for draft in cleanedDrafts {
            let nextStartPage = min(max(draft.startPage, lastStartPage + 1), totalPages)
            guard nextStartPage <= totalPages else { continue }
            uniqueDrafts.append(
                SectionDraft(
                    id: draft.id,
                    title: draft.title.isEmpty ? "단원 \(uniqueDrafts.count + 1)" : draft.title,
                    startPage: nextStartPage
                )
            )
            lastStartPage = nextStartPage
        }

        if uniqueDrafts.isEmpty {
            uniqueDrafts = [SectionDraft(id: UUID(), title: "단원 1", startPage: 1)]
        }

        return uniqueDrafts.enumerated().map { index, draft in
            let nextStartPage = index + 1 < uniqueDrafts.count ? uniqueDrafts[index + 1].startPage : totalPages + 1
            return StudySectionProgress(
                id: draft.id,
                title: draft.title,
                startPage: draft.startPage,
                endPage: max(min(nextStartPage - 1, totalPages), draft.startPage),
                status: .upcoming,
                completionRatio: 0
            )
        }
    }

    private func currentPageState() -> [String] {
        var state: [String] = []
        if isCurrentPageBookmarked {
            state.append("bookmarked")
        }
        if currentPageHasUnsavedChanges {
            state.append("dirty-local")
        }
        if currentPageOverlayStrokeCount > 0 {
            state.append("annotated")
        }
        if currentPageSearchMatchCount > 0 {
            state.append("search-hit")
        }
        return state
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

    private func currentDwellMilliseconds(for pageIndex: Int) -> Int {
        var totalSeconds = dwellSecondsByPageIndex[pageIndex, default: 0]
        if currentPageIndex == pageIndex {
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
        let elapsed = Date().timeIntervalSince(pageEntryStartedAt)
        dwellSecondsByPageIndex[currentPageIndex, default: 0] += Date().timeIntervalSince(pageEntryStartedAt)
        eventLogger.log(
            .pageExit,
            document: document,
            pageID: currentAnalysisPageID,
            sessionID: sessionID,
            payload: [
                "page_index": .integer(currentPageIndex),
                "exit_reason": .string("page_change"),
                "elapsed_ms": .integer(Int(elapsed * 1000))
            ]
        )
        pageEntryStartedAt = Date()
    }

    private func recordPageVisit(_ pageIndex: Int) {
        pageEntryStartedAt = Date()
        revisitCountByPageIndex[pageIndex, default: 0] += 1
        pageNavigationHistory.append(pageIndex)
        if pageNavigationHistory.count > 10 {
            pageNavigationHistory.removeFirst(pageNavigationHistory.count - 10)
        }
        eventLogger.log(
            .pageEnter,
            document: document,
            pageID: UUID.stableAnalysisPageID(namespace: document.id, pageIndex: pageIndex),
            sessionID: sessionID,
            payload: [
                "page_index": .integer(pageIndex),
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
            pageID: currentAnalysisPageID,
            sessionID: sessionID,
            payload: [
                "entry_source": .string("library")
            ]
        )
    }

    private func resolvePDFFileName() -> String? {
        (try? resolvePDFURL()).map(\.lastPathComponent)
    }

    private func trimBookmarksToLoadedPageCount() {
        let filtered = bookmarkedPageIndices.filter { $0 >= 0 && $0 < pageCount }
        guard filtered != bookmarkedPageIndices else { return }
        bookmarkedPageIndices = filtered
        persistBookmarks()
    }

    private func persistBookmarks() {
        userDefaults.set(Array(bookmarkedPageIndices).sorted(), forKey: Self.bookmarkDefaultsKey(for: document.id))
    }

    private var documentURL: URL {
        URL(fileURLWithPath: document.path, isDirectory: true)
    }

    private static func bookmarkDefaultsKey(for documentID: UUID) -> String {
        "pharnote.pdf.bookmarks.\(documentID.uuidString)"
    }
}
