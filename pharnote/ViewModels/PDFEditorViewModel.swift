import Foundation
import PDFKit
import PencilKit
import SwiftUI
import UIKit

@MainActor
final class PDFEditorViewModel: ObservableObject {
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
    @Published var selectedColorID: Int = 0
    @Published var strokeWidth: Double = 5.0
    @Published var isPencilOnlyInputEnabled: Bool = true
    @Published private(set) var canUndo: Bool = false
    @Published private(set) var canRedo: Bool = false
    @Published private(set) var canCopy: Bool = false
    @Published private(set) var canCut: Bool = false
    @Published private(set) var canPaste: Bool = false
    @Published private(set) var canDelete: Bool = false
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
    private var thumbnailGenerationTask: Task<Void, Never>?
    private var overlaySaveTasks: [Int: Task<Void, Never>] = [:]
    private var dirtyOverlayPages: Set<Int> = []
    private var overlayDrawingCache: [Int: PKDrawing] = [:]
    private weak var activeOverlayCanvas: PencilPassthroughCanvasView?
    private var didLoad = false
    private let thumbnailSize = CGSize(width: 86, height: 112)

    init(document: PharDocument) {
        self.document = document
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
            currentPageIndex = 0
            pageJumpInput = "1"

            if let pdfView {
                pdfView.document = loadedDocument
                goToPage(index: 0)
            }

            clearPDFTextSearch(resetQuery: false)

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
        currentPageIndex = index
        pageJumpInput = "\(index + 1)"

        if previousPageIndex != index {
            saveOverlayPageImmediately(previousPageIndex)
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
        saveAllOverlayPagesImmediately()
    }

    var canGoPrevious: Bool {
        currentPageIndex > 0
    }

    var canGoNext: Bool {
        currentPageIndex + 1 < pageCount
    }

    var canGoToPreviousPDFTextResult: Bool {
        guard let currentPDFTextSearchResultIndex else { return false }
        return !pdfTextSearchResults.isEmpty && currentPDFTextSearchResultIndex > 0
    }

    var canGoToNextPDFTextResult: Bool {
        guard let currentPDFTextSearchResultIndex else { return false }
        return !pdfTextSearchResults.isEmpty && currentPDFTextSearchResultIndex + 1 < pdfTextSearchResults.count
    }

    var isEditingInkTool: Bool {
        selectedTool == .pen || selectedTool == .highlighter
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

    func togglePencilOnlyInput() {
        isPencilOnlyInputEnabled.toggle()
        refreshEditActionAvailability()
    }

    func currentTool() -> PKTool {
        switch selectedTool {
        case .pen:
            return PKInkingTool(.pen, color: uiColorForColorID(selectedColorID), width: CGFloat(strokeWidth))
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
        !isPencilOnlyInputEnabled
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
        scheduleOverlaySave(pageIndex: pageIndex)
        refreshEditActionAvailability()
    }

    func saveAllOverlayPagesImmediately() {
        overlaySaveTasks.values.forEach { $0.cancel() }
        overlaySaveTasks.removeAll()

        let dirtyPages = Array(dirtyOverlayPages)
        Task {
            for pageIndex in dirtyPages {
                await persistOverlayPageIfNeeded(pageIndex: pageIndex, force: true)
            }
        }
    }

    func setActiveOverlayCanvas(_ canvas: PencilPassthroughCanvasView?) {
        activeOverlayCanvas = canvas
        refreshEditActionAvailability()
    }

    func undo() {
        guard let canvas = activeOverlayCanvas else { return }
        canvas.becomeFirstResponder()
        canvas.undoManager?.undo()
        markCurrentPageDirtyFromCanvas()
    }

    func redo() {
        guard let canvas = activeOverlayCanvas else { return }
        canvas.becomeFirstResponder()
        canvas.undoManager?.redo()
        markCurrentPageDirtyFromCanvas()
    }

    func copySelection() {
        guard selectedTool == .lasso, let canvas = activeOverlayCanvas else { return }
        canvas.becomeFirstResponder()
        canvas.copy(nil)
        refreshEditActionAvailability()
    }

    func cutSelection() {
        guard selectedTool == .lasso, let canvas = activeOverlayCanvas else { return }
        canvas.becomeFirstResponder()
        canvas.cut(nil)
        markCurrentPageDirtyFromCanvas()
    }

    func pasteSelection() {
        guard let canvas = activeOverlayCanvas else { return }
        canvas.becomeFirstResponder()
        canvas.paste(nil)
        markCurrentPageDirtyFromCanvas()
    }

    func deleteSelection() {
        guard selectedTool == .lasso, let canvas = activeOverlayCanvas else { return }
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
            guard let page = (selection.pages.first as? PDFPage) else { return nil }
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
        } catch {
            errorMessage = "PDF 필기 저장 실패: \(error.localizedDescription)"
        }
    }

    private func markCurrentPageDirtyFromCanvas() {
        guard let canvas = activeOverlayCanvas else { return }
        overlayDrawingCache[currentPageIndex] = canvas.drawing
        dirtyOverlayPages.insert(currentPageIndex)
        scheduleOverlaySave(pageIndex: currentPageIndex)
        refreshEditActionAvailability()
    }

    private func refreshEditActionAvailability() {
        guard let canvas = activeOverlayCanvas else {
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

        if selectedTool == .lasso {
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

    private func makeSearchSnippet(from selection: PDFSelection, fallbackQuery: String) -> String {
        let baseText = selection.string?.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseText, !baseText.isEmpty else { return fallbackQuery }
        if baseText.count <= 80 { return baseText }
        return String(baseText.prefix(80)) + "..."
    }

    private var documentURL: URL {
        URL(fileURLWithPath: document.path, isDirectory: true)
    }
}
