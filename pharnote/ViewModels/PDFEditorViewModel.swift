import Foundation
import Combine
import PDFKit
import PencilKit
import SwiftUI
import UIKit

@MainActor
final class PDFEditorViewModel: ObservableObject {
    private static let highlightInkAlpha: CGFloat = 0.28

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
        case paint = "붓/채우기"

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
    @Published var selectedEraserMode: WritingEraserMode
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
    @Published var highlightMode: HighlightStructureMode = .basic
    @Published var selectedHighlightRole: HighlightStructureRole = .core
    @Published private(set) var currentHighlightSnapshot: HighlightStructureSnapshot?
    @Published var isHighlightStructurePanelVisible: Bool = false
    @Published private(set) var storedProgressSnapshot: StudyProgressSnapshot?
    @Published var isReadOnlyMode: Bool = false
    @Published var errorMessage: String?
    @Published private(set) var problemSelection: ProblemSelection?
    @Published private(set) var problemRecognitionResult: ProblemRecognitionResult?
    @Published private(set) var problemReviewSession: ReviewSession?
    @Published private(set) var problemReviewSchema: ReviewSchema?
    @Published private(set) var problemReviewAutosaveStatus: ReviewAutosaveStatus = .idle
    @Published private(set) var reviewedProblemKeys: Set<String> = []
    @Published private(set) var problemReviewMessage: String?
    @Published var isProblemReviewPanelVisible: Bool = false

    @Published private(set) var document: PharDocument
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
    private let highlightStore: HighlightStructureStore
    private let highlightEngine: HighlightStructureEngine
    private let documentOCRService: DocumentOCRService
    private let reviewSessionRepository: ReviewSessionRepository
    private let problemRecognitionService: ProblemRecognitionService
    private let reviewEvidenceMapper: ReviewEvidenceMapper
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
    private var highlightSnapshotTask: Task<Void, Never>?
    private var highlightSyncTask: Task<Void, Never>?
    private var lastHighlightStrokeCountByPageIndex: [Int: Int] = [:]
    private var highlightRoleHexByRole: [HighlightStructureRole: String] = [:]
    private var problemRecognitionTask: Task<Void, Never>?
    private var problemReviewAutosaveTask: Task<Void, Never>?
    private var completedProblemReviewByPageIndex: [Int: AnalysisPostSolveReview] = [:]

    init(
        document: PharDocument,
        initialPageKey: String? = nil,
        eventLogger: StudyEventLogger? = nil,
        libraryStore: LibraryStore? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        let highlightStore = HighlightStructureStore()
        let highlightEngine = HighlightStructureEngine()
        let documentOCRService = DocumentOCRService()
        let reviewSessionRepository = ReviewSessionRepository()
        let problemRecognitionService = ProblemRecognitionService(documentOCRService: documentOCRService)
        let reviewEvidenceMapper = ReviewEvidenceMapper()
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
        self.highlightStore = highlightStore
        self.highlightEngine = highlightEngine
        self.documentOCRService = documentOCRService
        self.reviewSessionRepository = reviewSessionRepository
        self.problemRecognitionService = problemRecognitionService
        self.reviewEvidenceMapper = reviewEvidenceMapper
        self.strokePresetConfigurationsByTool = [
            .pen: penPresetConfiguration,
            .highlighter: highlighterPresetConfiguration
        ]
        self._selectedEraserMode = Published(initialValue: WritingEraserMode.load(from: userDefaults))
        self._strokePresetConfiguration = Published(initialValue: penPresetConfiguration)
        self.requestedInitialPageIndex = Self.pageIndex(from: initialPageKey)
        self.storedProgressSnapshot = document.progress
        self.bookmarkedPageIndices = Set(
            (userDefaults.array(forKey: Self.bookmarkDefaultsKey(for: document.id)) as? [Int]) ?? []
        )
        self.strokeWidth = penPresetConfiguration.values[penPresetConfiguration.selectedIndex]
        loadHighlightPalettePresets()
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
            lastHighlightStrokeCountByPageIndex[initialPageIndex] = currentOverlayDrawing().strokes.count

            clearPDFTextSearch(resetQuery: false)
            rebuildOutlineEntries()
            scheduleHighlightSnapshotRefresh(pageIndex: initialPageIndex)

            generateThumbnails(from: pdfURL)
            Task { [weak self] in
                await self?.refreshReviewHistory()
            }
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
        lastHighlightStrokeCountByPageIndex[index] = currentOverlayDrawing().strokes.count
        scheduleHighlightSnapshotRefresh(pageIndex: index)
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

    func updateDocument(_ document: PharDocument) {
        self.document = document
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

    var isProblemSelectionModeActive: Bool {
        isToolSelected(.lasso) && !isReadOnlyMode
    }

    var canAnalyzeCurrentSelection: Bool {
        problemSelection != nil || problemRecognitionResult?.bestMatch != nil
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

    func handleProblemSelection(_ selection: ProblemSelection) {
        guard !isReadOnlyMode else { return }
        problemSelection = selection
        problemRecognitionResult = ProblemRecognitionResult(
            selectionId: selection.id,
            bestMatch: nil,
            candidates: [],
            confidence: 0,
            status: .matching,
            recognitionText: nil,
            reason: "matching"
        )
        problemReviewSession = nil
        problemReviewSchema = nil
        problemReviewMessage = nil
        problemReviewAutosaveStatus = .idle
        isProblemReviewPanelVisible = false

        problemRecognitionTask?.cancel()
        problemRecognitionTask = Task { [weak self] in
            await self?.recognizeProblemSelection(selection)
        }
    }

    func clearProblemSelection() {
        problemRecognitionTask?.cancel()
        problemReviewAutosaveTask?.cancel()
        problemSelection = nil
        problemRecognitionResult = nil
        problemReviewSession = nil
        problemReviewSchema = nil
        problemReviewMessage = nil
        problemReviewAutosaveStatus = .idle
        isProblemReviewPanelVisible = false
    }

    func startProblemReview(using candidate: ProblemMatch? = nil) {
        Task { [weak self] in
            await self?.startProblemReviewAsync(using: candidate)
        }
    }

    func changeProblemMatch() {
        problemReviewMessage = "후보를 다시 고를 수 있도록 현재 매칭을 보류했습니다."
        problemRecognitionResult = ProblemRecognitionResult(
            selectionId: problemSelection?.id ?? UUID(),
            bestMatch: nil,
            candidates: problemRecognitionResult?.candidates ?? [],
            confidence: 0,
            status: .ambiguous,
            recognitionText: problemRecognitionResult?.recognitionText,
            reason: "manual_change_requested"
        )
        isProblemReviewPanelVisible = true
    }

    func updateProblemReviewAnswer(
        stepId: String,
        selectedOptionIds: [String],
        freeText: String? = nil
    ) {
        guard let session = problemReviewSession else { return }
        var updatedSession = session
        let now = Date()
        let existing = updatedSession.answers.first(where: { $0.stepId == stepId })
        let answer = ReviewAnswer(
            id: existing?.id ?? UUID(),
            stepId: stepId,
            selectedOptionIds: selectedOptionIds,
            freeText: trimmedNonEmpty(freeText),
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )

        updatedSession.answers.removeAll { $0.stepId == stepId }
        updatedSession.answers.append(answer)
        updatedSession.updatedAt = now
        updatedSession.status = .inProgress
        updatedSession.derivedTags = reviewEvidenceMapper.derivedEvidence(
            for: updatedSession,
            schema: problemReviewSchema ?? ReviewSchemaRegistry.schema(for: updatedSession.subject)
        )
        updatedSession.lastAutosavedAt = nil
        problemReviewSession = updatedSession
        problemReviewAutosaveStatus = .saving
        scheduleProblemReviewAutosave()

        if let schema = problemReviewSchema, updatedSession.answers.count >= schema.steps.count {
            Task { [weak self] in
                await self?.completeCurrentProblemReview()
            }
        }
    }

    func goBackInProblemReview() {
        guard var session = problemReviewSession, !session.answers.isEmpty else { return }
        session.answers.removeLast()
        session.updatedAt = Date()
        session.derivedTags = reviewEvidenceMapper.derivedEvidence(
            for: session,
            schema: problemReviewSchema ?? ReviewSchemaRegistry.schema(for: session.subject)
        )
        session.lastAutosavedAt = nil
        problemReviewSession = session
        problemReviewAutosaveStatus = .saving
        scheduleProblemReviewAutosave()
    }

    func abandonCurrentProblemReview() {
        problemReviewAutosaveTask?.cancel()
        guard let session = problemReviewSession else {
            clearProblemSelection()
            return
        }

        var updatedSession = session
        updatedSession.status = .abandoned
        updatedSession.updatedAt = Date()
        updatedSession.autosaveVersion += 1
        Task {
            try? await reviewSessionRepository.upsert(updatedSession)
        }

        problemReviewSession = nil
        problemReviewSchema = nil
        isProblemReviewPanelVisible = false
        problemReviewAutosaveStatus = .idle
        problemReviewMessage = "복기를 중단했습니다."
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
            postSolveReview: completedProblemReviewByPageIndex[currentPageIndex]
        )
    }

    private func refreshReviewHistory() async {
        do {
            let sessions = try await reviewSessionRepository.loadSessions(for: document.id)
            var completedKeys: Set<String> = []
            var completedByPage: [Int: AnalysisPostSolveReview] = [:]

            for session in sessions where session.status == .completed {
                completedKeys.insert(reviewIdentityKey(for: session))
                if completedByPage[session.pageIndex] == nil {
                    let schema = problemReviewSchema ?? ReviewSchemaRegistry.schema(for: session.subject)
                    completedByPage[session.pageIndex] = reviewEvidenceMapper.makePostSolveReview(
                        from: session,
                        schema: schema
                    )
                }
            }

            reviewedProblemKeys = completedKeys
            for (pageIndex, payload) in completedByPage {
                completedProblemReviewByPageIndex[pageIndex] = payload
            }
        } catch {
            problemReviewMessage = "복기 기록을 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func recognizeProblemSelection(_ selection: ProblemSelection) async {
        let selectionText = selection.recognitionText ?? currentPDFPageText()
        let selectionBlocks = currentPDFPageText().map { [AnalysisTextBlock(kind: "pdf-text", text: $0, pageIndex: selection.pageIndex)] } ?? []
        let context = ProblemRecognitionContext(
            document: document,
            selection: selection,
            pageTextBlocks: selectionBlocks,
            hint: nil,
            pastQuestionsConfiguration: PastQuestionsConfigurationStore.shared.configuration
        )

        let result = await problemRecognitionService.recognize(context)
        var updatedSelection = selection
        updatedSelection.recognitionStatus = result.status
        updatedSelection.recognitionText = result.recognitionText ?? selectionText
        updatedSelection.recognizedMatch = result.bestMatch
        problemSelection = updatedSelection
        problemRecognitionResult = result
        problemReviewMessage = recognitionMessage(for: result)
        isProblemReviewPanelVisible = true
    }

    private func startProblemReviewAsync(using candidate: ProblemMatch?) async {
        guard let selection = problemSelection else { return }

        let match = candidate ?? problemRecognitionResult?.bestMatch
        let subject = match?.subject ?? document.studyMaterial?.subject ?? .unspecified
        let schema = ReviewSchemaRegistry.schema(for: subject)
        let sessionSelection = update(selection, with: match, status: .matched)
        let resumeKey = reviewIdentityKey(for: sessionSelection, match: match)

        do {
            if let existingDraft = try await reviewSessionRepository.loadLatestDraft(for: resumeKey) {
                var resumed = existingDraft
                resumed.selection = sessionSelection
                resumed.problemMatch = match ?? existingDraft.problemMatch
                resumed.subject = subject
                resumed.status = .inProgress
                resumed.updatedAt = Date()
                resumed.lastAutosavedAt = Date()
                resumed.autosaveVersion += 1
                resumed.derivedTags = reviewEvidenceMapper.derivedEvidence(for: resumed, schema: schema)
                try await reviewSessionRepository.upsert(resumed)
                problemSelection = sessionSelection
                problemReviewSession = resumed
                problemReviewSchema = schema
                problemReviewAutosaveStatus = .saved
                isProblemReviewPanelVisible = true
                problemReviewMessage = "진행 중인 복기를 이어갑니다."
                return
            }

            var session = ReviewSession(
                id: UUID(),
                userId: nil,
                documentId: document.id,
                pageId: sessionSelection.pageId,
                pageIndex: sessionSelection.pageIndex,
                selectionId: sessionSelection.id,
                selection: sessionSelection,
                canonicalProblemId: match?.canonicalProblemId,
                problemMatch: match,
                subject: subject,
                status: .draft,
                startedAt: Date(),
                updatedAt: Date(),
                completedAt: nil,
                schemaVersion: schema.version,
                answers: [],
                derivedTags: [],
                autosaveVersion: 0,
                lastAutosavedAt: nil,
                lastAutosaveErrorMessage: nil
            )
            session.derivedTags = reviewEvidenceMapper.derivedEvidence(for: session, schema: schema)
            try await reviewSessionRepository.upsert(session)

            session.status = .inProgress
            session.updatedAt = Date()
            session.lastAutosavedAt = Date()
            session.autosaveVersion += 1
            session.derivedTags = reviewEvidenceMapper.derivedEvidence(for: session, schema: schema)
            try await reviewSessionRepository.upsert(session)

            problemSelection = sessionSelection
            problemReviewSession = session
            problemReviewSchema = schema
            problemReviewAutosaveStatus = .saved
            isProblemReviewPanelVisible = true
            problemReviewMessage = match == nil ? "기본 복기 세트를 시작합니다." : "복기를 시작합니다."
        } catch {
            problemReviewAutosaveStatus = .retryNeeded
            problemReviewMessage = "복기를 시작하지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func update(_ selection: ProblemSelection, with match: ProblemMatch?, status: ProblemSelectionRecognitionStatus) -> ProblemSelection {
        var updated = selection
        updated.recognizedMatch = match
        updated.recognitionStatus = status
        updated.updatedAt = Date()
        if updated.recognitionText == nil {
            updated.recognitionText = currentPDFPageText()
        }
        return updated
    }

    private func scheduleProblemReviewAutosave() {
        problemReviewAutosaveTask?.cancel()
        problemReviewAutosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            await self?.autosaveCurrentProblemReviewSession()
        }
    }

    private func autosaveCurrentProblemReviewSession() async {
        guard var session = problemReviewSession, let schema = problemReviewSchema else { return }
        problemReviewAutosaveStatus = .saving
        session.updatedAt = Date()
        session.lastAutosavedAt = Date()
        session.autosaveVersion += 1
        session.derivedTags = reviewEvidenceMapper.derivedEvidence(for: session, schema: schema)

        do {
            try await reviewSessionRepository.upsert(session)
            problemReviewSession = session
            problemReviewAutosaveStatus = .saved
            problemReviewMessage = "저장됨"
        } catch {
            session.lastAutosaveErrorMessage = error.localizedDescription
            problemReviewSession = session
            problemReviewAutosaveStatus = .retryNeeded
            problemReviewMessage = "저장 실패: \(error.localizedDescription)"
        }
    }

    private func completeCurrentProblemReview() async {
        guard var session = problemReviewSession, let schema = problemReviewSchema else { return }
        session.status = .completed
        session.completedAt = Date()
        session.updatedAt = Date()
        session.lastAutosavedAt = Date()
        session.autosaveVersion += 1
        session.derivedTags = reviewEvidenceMapper.derivedEvidence(for: session, schema: schema)

        do {
            try await reviewSessionRepository.upsert(session)
            problemReviewSession = session
            problemReviewAutosaveStatus = .saved
            problemReviewMessage = "복기가 저장되었습니다."
            reviewedProblemKeys.insert(reviewIdentityKey(for: session))
            completedProblemReviewByPageIndex[session.pageIndex] = reviewEvidenceMapper.makePostSolveReview(from: session, schema: schema)
            isProblemReviewPanelVisible = false
        } catch {
            problemReviewSession = session
            problemReviewAutosaveStatus = .retryNeeded
            problemReviewMessage = "복기 저장 실패: \(error.localizedDescription)"
        }
    }

    private func recognitionMessage(for result: ProblemRecognitionResult) -> String? {
        switch result.status {
        case .matched:
            return result.bestMatch.map { "\($0.displayTitle) 인식됨" } ?? "문제를 인식했습니다."
        case .ambiguous:
            return "후보가 여러 개입니다. 확인이 필요합니다."
        case .failed:
            return "일치하는 문제를 바로 찾지 못했습니다."
        case .idle, .matching:
            return nil
        }
    }

    private func reviewIdentityKey(for session: ReviewSession) -> String {
        if let canonical = trimmedNonEmpty(session.canonicalProblemId) {
            return canonical
        }
        if let matchKey = trimmedNonEmpty(session.problemMatch?.canonicalProblemId) {
            return matchKey
        }
        return session.selection.selectionSignature
    }

    private func reviewIdentityKey(for selection: ProblemSelection, match: ProblemMatch?) -> String {
        if let canonical = trimmedNonEmpty(match?.canonicalProblemId) {
            return canonical
        }
        return selection.selectionSignature
    }

    private func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
        !isReadOnlyMode && isToolSelectionActive && activeTool != .lasso
    }

    var allowsPDFNavigation: Bool {
        true
    }

    var isEditingInkTool: Bool {
        guard let activeTool else { return false }
        return activeTool == .pen || activeTool == .highlighter || activeTool == .paint
    }

    var currentToolLabel: String {
        if activeTool == .eraser {
            return selectedEraserMode.accessibilityLabel
        }
        if activeTool == .highlighter && highlightMode == .structured {
            return "구조화 · \(selectedHighlightRole.title)"
        }
        return activeTool?.rawValue ?? "스크롤"
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
        if tool == .pen || tool == .highlighter || tool == .paint || tool == .eraser {
            isPencilOnlyInputEnabled = true
        }
        toolUsageCounts[tool, default: 0] += 1
        if tool == .lasso || tool == .paint {
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
        if tool == .highlighter && highlightMode == .structured {
            isHighlightStructurePanelVisible = true
            lastHighlightStrokeCountByPageIndex[currentPageIndex] = currentOverlayDrawing().strokes.count
            scheduleHighlightSnapshotRefresh(pageIndex: currentPageIndex)
        }
        applyPDFInteractionMode()
    }

    func selectEraserMode(_ mode: WritingEraserMode) {
        guard selectedEraserMode != mode else { return }
        selectedEraserMode = mode
        mode.save(in: userDefaults)
        if selectedTool == .eraser && isToolSelectionActive {
            applyPDFInteractionMode()
        }
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

    func selectHighlightMode(_ mode: HighlightStructureMode) {
        guard highlightMode != mode else { return }
        highlightMode = mode
        eventLogger.log(
            .highlightModeSelected,
            document: document,
            pageID: currentAnalysisPageID,
            sessionID: sessionID,
            payload: [
                "mode": .string(mode.rawValue)
            ]
        )

        if mode == .structured {
            isHighlightStructurePanelVisible = true
            lastHighlightStrokeCountByPageIndex[currentPageIndex] = currentOverlayDrawing().strokes.count
        }

        applyPDFInteractionMode()
        scheduleHighlightSnapshotRefresh(pageIndex: currentPageIndex)
    }

    func selectHighlightRole(_ role: HighlightStructureRole) {
        guard selectedHighlightRole != role else { return }
        selectedHighlightRole = role
        eventLogger.log(
            .highlightRoleSelected,
            document: document,
            pageID: currentAnalysisPageID,
            sessionID: sessionID,
            payload: [
                "role": .string(role.rawValue)
            ]
        )
        if highlightMode == .structured {
            isHighlightStructurePanelVisible = true
            applyPDFInteractionMode()
            scheduleHighlightSnapshotRefresh(pageIndex: currentPageIndex)
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
            applyPDFInteractionMode()
        }
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
            let color = highlightMode == .structured
                ? highlightColor(for: selectedHighlightRole).withAlphaComponent(Self.highlightInkAlpha)
                : uiColorForColorID(selectedColorID).withAlphaComponent(Self.highlightInkAlpha)
            return PKInkingTool(.pen, color: color, width: CGFloat(strokeWidth + 10))
        case .eraser:
            return makeEraserTool()
        case .lasso, .paint:
            return PKLassoTool()
        }
    }

    func currentDrawingPolicy() -> PKCanvasViewDrawingPolicy {
        isPencilOnlyInputEnabled ? .pencilOnly : .anyInput
    }

    func allowsFingerDrawing() -> Bool {
        isCanvasInputEnabled && !isPencilOnlyInputEnabled
    }

    func currentToolSignature() -> String {
        [
            selectedTool.rawValue,
            selectedEraserMode.rawValue,
            highlightMode.rawValue,
            selectedHighlightRole.rawValue,
            highlightColorHex(for: selectedHighlightRole),
            "\(selectedColorID)",
            "\(strokeWidth)"
        ].joined(separator: "-")
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
        syncStructuredHighlightsIfNeeded(pageIndex: pageIndex, drawing: drawing)
        scheduleHighlightSnapshotRefresh(pageIndex: pageIndex)
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
        if let canvas {
            lastHighlightStrokeCountByPageIndex[currentPageIndex] = canvas.drawing.strokes.count
            scheduleHighlightSnapshotRefresh(pageIndex: currentPageIndex)
        }
        refreshEditActionAvailability()
        applyPDFInteractionMode()
    }

    func refreshCanvasInteractionState() {
        refreshEditActionAvailability()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.refreshEditActionAvailability()
        }
    }

    func handleCanvasTap(at point: CGPoint, pageIndex: Int) {
        guard activeTool == .paint, let canvas = activeOverlayCanvas else { return }
        
        let generateFillStroke: (CGRect, UIColor) -> PKStroke = { bounds, color in
            let size = max(bounds.width, bounds.height) * 1.5
            let ink = PKInk(.pen, color: color)
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let path = PKStrokePath(controlPoints: [
                PKStrokePoint(location: center, timeOffset: 0, size: CGSize(width: size, height: size), opacity: 1, force: 1, azimuth: 0, altitude: .pi/2)
            ], creationDate: Date())
            let stroke = PKStroke(ink: ink, path: path)
            return stroke
        }
        
        let drawing = overlayDrawingCache[pageIndex] ?? canvas.drawing
        let fillColor = uiColorForColorID(selectedColorID)
        
        let hitStrokeIndex = drawing.strokes.lastIndex { stroke in
            let points = stroke.path.map { $0.location }
            guard points.count >= 4 else { return false }
            guard let first = points.first, let last = points.last, first.distance(to: last) < 50 else { return false }
            
            let minX = points.map(\.x).min() ?? 0
            let maxX = points.map(\.x).max() ?? 0
            let minY = points.map(\.y).min() ?? 0
            let maxY = points.map(\.y).max() ?? 0
            let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            if !bounds.contains(point) { return false }
            
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
            
            let fillStroke = generateFillStroke(bounds, fillColor)
            updatedStrokes.insert(fillStroke, at: index)
        } else {
            let bounds = CGRect(x: -5000, y: -5000, width: 10000, height: 10000)
            let fillStroke = generateFillStroke(bounds, fillColor)
            updatedStrokes.insert(fillStroke, at: 0)
        }
        
        let newDrawing = PKDrawing(strokes: updatedStrokes)
        
        canvas.undoManager?.registerUndo(withTarget: self, handler: { target in
            target.overlayDrawingDidChange(pageIndex: pageIndex, drawing: drawing)
            if target.currentPageIndex == pageIndex {
                target.activeOverlayCanvas?.drawing = drawing
            }
        })
        canvas.undoManager?.setActionName(isShapeFill ? "Shape Fill" : "Background Fill")
        
        canvas.drawing = newDrawing
        overlayDrawingDidChange(pageIndex: pageIndex, drawing: newDrawing)
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
        case .fountain:
            return PKInkingTool(.pen, color: baseColor, width: CGFloat(strokeWidth))
        case .brush:
            return PKInkingTool(.marker, color: baseColor.withAlphaComponent(0.85), width: CGFloat(strokeWidth * 1.5))
        case .monoline:
            return PKInkingTool(.pen, color: baseColor, width: CGFloat(max(strokeWidth * 0.85, 1)))
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
        let drawing = canvas.drawing
        overlayDrawingCache[currentPageIndex] = drawing
        dirtyOverlayPages.insert(currentPageIndex)
        pageLastEditedAt[currentPageIndex] = Date()
        objectWillChange.send()
        syncStructuredHighlightsIfNeeded(pageIndex: currentPageIndex, drawing: drawing)
        scheduleHighlightSnapshotRefresh(pageIndex: currentPageIndex)
        scheduleOverlaySave(pageIndex: currentPageIndex)
        refreshEditActionAvailability()
    }

    private func activeInkTool(for tool: AnnotationTool? = nil) -> AnnotationTool? {
        switch tool ?? selectedTool {
        case .pen:
            return .pen
        case .highlighter:
            return .highlighter
        case .eraser, .lasso, .paint:
            return nil
        }
    }

    private func makeEraserTool() -> PKTool {
        let eraserType = selectedEraserMode.eraserType
        if #available(iOS 16.4, *), let width = selectedEraserMode.toolWidth() {
            return PKEraserTool(eraserType, width: width)
        }
        return PKEraserTool(eraserType)
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
        case .eraser, .lasso, .paint:
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

    private func currentOverlayDrawing(for pageIndex: Int) -> PKDrawing {
        if pageIndex == currentPageIndex, let activeOverlayCanvas {
            return activeOverlayCanvas.drawing
        }
        return overlayDrawingCache[pageIndex] ?? PKDrawing()
    }

    private func currentPDFPageText() -> String? {
        guard let pdfDocument, let page = pdfDocument.page(at: currentPageIndex) else { return nil }
        let text = page.string?
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    private func scheduleHighlightSnapshotRefresh(pageIndex: Int?) {
        highlightSnapshotTask?.cancel()
        guard let pageIndex else {
            currentHighlightSnapshot = nil
            return
        }

        highlightSnapshotTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            await self?.refreshHighlightSnapshot(for: pageIndex)
        }
    }

    private func refreshHighlightSnapshot(for pageIndex: Int) async {
        guard pageIndex == currentPageIndex else { return }
        let pageKey = "pdf-page-\(pageIndex)"
        let pageLabel = pageTitle(for: pageIndex)
        let referenceText = await highlightReferenceText(for: pageIndex)
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
            pageID: UUID.stableAnalysisPageID(namespace: document.id, pageIndex: pageIndex),
            sessionID: sessionID,
            payload: [
                "page_key": .string(pageKey),
                "item_count": .integer(snapshot.totalCount)
            ]
        )
    }

    private func highlightReferenceText(for pageIndex: Int) async -> String? {
        if let pdfText = currentPDFPageText(), pageIndex == currentPageIndex {
            return pdfText
        }

        if pageIndex == currentPageIndex, let source = analysisSource {
            let blocks = await documentOCRService.recognizePDFBlocks(source: source)
            let joined = blocks.map(\.text).joined(separator: "\n")
            if !joined.isEmpty {
                return joined
            }
        }

        return nil
    }

    private func syncStructuredHighlightsIfNeeded(pageIndex: Int, drawing: PKDrawing) {
        guard highlightMode == .structured else { return }

        let currentCount = drawing.strokes.count
        let lastCount = lastHighlightStrokeCountByPageIndex[pageIndex] ?? currentCount
        if currentCount == lastCount {
            return
        }

        if currentCount > lastCount, selectedTool != .highlighter {
            lastHighlightStrokeCountByPageIndex[pageIndex] = currentCount
            return
        }

        highlightSyncTask?.cancel()
        highlightSyncTask = Task { [weak self] in
            await self?.syncStructuredHighlights(pageIndex: pageIndex, drawing: drawing, previousCount: lastCount)
        }
    }

    private func syncStructuredHighlights(pageIndex: Int, drawing: PKDrawing, previousCount: Int) async {
        let pageKey = "pdf-page-\(pageIndex)"
        let pageLabel = pageTitle(for: pageIndex)
        var items = await highlightStore.loadItems(documentURL: documentURL, pageKey: pageKey)
        let currentCount = drawing.strokes.count

        if currentCount < previousCount {
            items = highlightEngine.syncItems(currentItems: items, drawing: drawing)
        } else if currentCount > previousCount {
            let appendedStrokes = drawing.strokes.dropFirst(previousCount)
            let referenceText = await highlightReferenceText(for: pageIndex)
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

        lastHighlightStrokeCountByPageIndex[pageIndex] = currentCount
        if items.isEmpty {
            await highlightStore.deleteItems(documentURL: documentURL, pageKey: pageKey)
        } else {
            try? await highlightStore.saveItems(items, documentURL: documentURL, pageKey: pageKey)
        }
        touchDocumentUpdatedAt()
        await refreshHighlightSnapshot(for: pageIndex)
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

    private func touchDocumentUpdatedAt() {
        var updatedDocument = document
        updatedDocument.updatedAt = pageLastEditedAt.values.max() ?? Date()
        if let savedDocument = try? libraryStore.updateDocument(updatedDocument) {
            document = savedDocument
        } else {
            document = updatedDocument
        }
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
