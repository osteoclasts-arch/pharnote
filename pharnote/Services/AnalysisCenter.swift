import Combine
import Foundation

@MainActor
final class AnalysisCenter: ObservableObject {
    @Published private(set) var queueEntries: [AnalysisQueueEntry] = []
    @Published private(set) var results: [AnalysisResult] = []
    @Published private(set) var reviewTasks: [AnalysisReviewTask] = []
    @Published private(set) var latestBundle: AnalysisBundle?
    @Published private(set) var latestResult: AnalysisResult?
    @Published private(set) var lastQueuedEntry: AnalysisQueueEntry?
    @Published private(set) var isEnqueuing: Bool = false
    @Published var errorMessage: String?

    private let queueStore: AnalysisQueueStore
    private let analysisEngine: AnalysisPipelineEngine
    private let ocrService: DocumentOCRService
    private var resultsByPageKey: [String: AnalysisResult] = [:]
    private var resultsByBundleId: [UUID: AnalysisResult] = [:]
    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    init(
        queueStore: AnalysisQueueStore = AnalysisQueueStore(),
        analysisEngine: AnalysisPipelineEngine = AnalysisPipelineEngine(),
        ocrService: DocumentOCRService = DocumentOCRService()
    ) {
        self.queueStore = queueStore
        self.analysisEngine = analysisEngine
        self.ocrService = ocrService

        Task {
            await refreshQueue()
        }
    }

    var queuedCount: Int {
        queueEntries.filter { $0.status == .queued }.count
    }

    var completedCount: Int {
        queueEntries.filter { $0.status == .completed }.count
    }

    var failedCount: Int {
        queueEntries.filter { $0.status == .failed }.count
    }

    var pendingReviewTaskCount: Int {
        reviewTasks.filter { $0.status == .pending }.count
    }

    var dueSoonReviewTaskCount: Int {
        reviewTasks.filter(\.isDueSoon).count
    }

    var nextReviewTask: AnalysisReviewTask? {
        reviewTasks
            .filter { $0.status == .pending }
            .sorted { lhs, rhs in
                if lhs.dueAt == rhs.dueAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.dueAt < rhs.dueAt
            }
            .first
    }

    func refreshQueue() async {
        do {
            async let loadedEntries = queueStore.loadEntries()
            async let loadedResults = queueStore.loadResults()
            async let loadedReviewTasks = queueStore.loadReviewTasks()
            let (entries, results, reviewTasks) = try await (loadedEntries, loadedResults, loadedReviewTasks)
            queueEntries = deduplicatedEntries(entries)
            applyResults(results)
            self.reviewTasks = deduplicatedReviewTasks(reviewTasks)
        } catch {
            errorMessage = "분석 큐 로드 실패: \(error.localizedDescription)"
        }
    }

    func result(for documentId: UUID, pageId: UUID) -> AnalysisResult? {
        resultsByPageKey[pageKey(documentId: documentId, pageId: pageId)]
    }

    func result(for bundleId: UUID) -> AnalysisResult? {
        resultsByBundleId[bundleId]
    }

    func ocrPreview(for source: BlankNoteAnalysisSource) async -> OCRPreviewSummary {
        let ocrBlocks = await ocrService.recognizeBlankNoteBlocks(source: source)
        return makeOCRPreviewSummary(ocrBlocks: ocrBlocks, supportingBlocks: [])
    }

    func ocrPreview(for source: PDFPageAnalysisSource) async -> OCRPreviewSummary {
        let ocrBlocks = await ocrService.recognizePDFBlocks(source: source)
        return makeOCRPreviewSummary(ocrBlocks: ocrBlocks, supportingBlocks: source.pdfTextBlocks)
    }

    func inspection(for bundleId: UUID) async -> AnalysisInspection? {
        let entry: AnalysisQueueEntry?
        if let cachedEntry = queueEntries.first(where: { $0.bundleId == bundleId }) {
            entry = cachedEntry
        } else {
            let loadedEntries = try? await queueStore.loadEntries()
            entry = loadedEntries?.first(where: { $0.bundleId == bundleId })
        }

        guard let entry else { return nil }

        do {
            let bundle = try await queueStore.loadBundle(bundleId: bundleId)
            let result = try await queueStore.loadResult(bundleId: bundleId)
            return AnalysisInspection(
                entry: entry,
                bundle: bundle,
                result: result,
                bundleJSON: prettyJSONString(for: bundle),
                resultJSON: result.map(prettyJSONString(for:))
            )
        } catch {
            errorMessage = "분석 기록 로드 실패: \(error.localizedDescription)"
            return nil
        }
    }

    func enqueueBlankNote(
        source: BlankNoteAnalysisSource,
        scope: AnalysisScope,
        studyIntent: AnalysisStudyIntent
    ) async {
        let ocrBlocks = await ocrService.recognizeBlankNoteBlocks(source: source)

        await enqueue(
            previewImageData: source.previewImageData,
            drawingData: source.drawingData
        ) {
            AnalysisBundle(
                bundleVersion: 1,
                bundleId: UUID(),
                createdAt: Date(),
                sourceApp: "pharnote",
                scope: scope,
                document: AnalysisDocumentContext(
                    documentId: source.document.id,
                    documentType: source.document.type,
                    title: source.document.title,
                    subject: source.document.analysisSubjectLabel,
                    collectionId: source.document.studyMaterial?.catalogEntryID,
                    sourceFingerprint: nil
                ),
                page: AnalysisPageContext(
                    pageId: source.pageId,
                    pageIndex: source.pageIndex,
                    pageCount: source.pageCount,
                    selectionRect: nil,
                    template: nil,
                    pageState: source.pageState
                ),
                content: AnalysisContentContext(
                    previewImageRef: nil,
                    drawingRef: nil,
                    drawingStats: source.drawingStats,
                    typedBlocks: [],
                    pdfTextBlocks: [],
                    ocrTextBlocks: ocrBlocks,
                    manualTags: source.manualTags,
                    bookmarks: source.bookmarks
                ),
                behavior: AnalysisBehaviorContext(
                    sessionId: source.sessionId,
                    studyIntent: studyIntent,
                    dwellMs: source.dwellMs,
                    foregroundEditsMs: source.foregroundEditsMs,
                    revisitCount: source.revisitCount,
                    toolUsage: source.toolUsage,
                    lassoActions: source.lassoActions,
                    copyActions: source.copyActions,
                    pasteActions: source.pasteActions,
                    undoCount: source.undoCount,
                    redoCount: source.redoCount,
                    zoomEventCount: 0,
                    navigationPath: source.navigationPath,
                    postSolveReview: source.postSolveReview
                ),
                context: AnalysisExecutionContext(
                    previousPageIds: source.previousPageIds,
                    nextPageIds: source.nextPageIds,
                    previousAnalysisIds: previousAnalysisIds(for: source.document.id, pageId: source.pageId),
                    examDate: nil,
                    locale: Locale.current.identifier,
                    timezone: TimeZone.current.identifier
                ),
                privacy: AnalysisPrivacyContext(
                    containsPdfText: false,
                    containsHandwriting: (source.drawingStats.strokeCount > 0),
                    userInitiated: true
                )
            )
        }
    }

    func enqueuePDFPage(
        source: PDFPageAnalysisSource,
        scope: AnalysisScope,
        studyIntent: AnalysisStudyIntent
    ) async {
        let ocrBlocks = await ocrService.recognizePDFBlocks(source: source)

        await enqueue(
            previewImageData: source.previewImageData,
            drawingData: source.drawingData
        ) {
            AnalysisBundle(
                bundleVersion: 1,
                bundleId: UUID(),
                createdAt: Date(),
                sourceApp: "pharnote",
                scope: scope,
                document: AnalysisDocumentContext(
                    documentId: source.document.id,
                    documentType: source.document.type,
                    title: source.document.title,
                    subject: source.document.analysisSubjectLabel,
                    collectionId: source.document.studyMaterial?.catalogEntryID,
                    sourceFingerprint: source.sourceFingerprint
                ),
                page: AnalysisPageContext(
                    pageId: source.pageId,
                    pageIndex: source.pageIndex,
                    pageCount: source.pageCount,
                    selectionRect: nil,
                    template: nil,
                    pageState: source.pageState
                ),
                content: AnalysisContentContext(
                    previewImageRef: nil,
                    drawingRef: nil,
                    drawingStats: source.drawingStats,
                    typedBlocks: [],
                    pdfTextBlocks: source.pdfTextBlocks,
                    ocrTextBlocks: ocrBlocks,
                    manualTags: source.manualTags,
                    bookmarks: source.bookmarks
                ),
                behavior: AnalysisBehaviorContext(
                    sessionId: source.sessionId,
                    studyIntent: studyIntent,
                    dwellMs: source.dwellMs,
                    foregroundEditsMs: source.foregroundEditsMs,
                    revisitCount: source.revisitCount,
                    toolUsage: source.toolUsage,
                    lassoActions: source.lassoActions,
                    copyActions: source.copyActions,
                    pasteActions: source.pasteActions,
                    undoCount: source.undoCount,
                    redoCount: source.redoCount,
                    zoomEventCount: source.zoomEventCount,
                    navigationPath: source.navigationPath,
                    postSolveReview: source.postSolveReview
                ),
                context: AnalysisExecutionContext(
                    previousPageIds: source.previousPageIds,
                    nextPageIds: source.nextPageIds,
                    previousAnalysisIds: previousAnalysisIds(for: source.document.id, pageId: source.pageId),
                    examDate: nil,
                    locale: Locale.current.identifier,
                    timezone: TimeZone.current.identifier
                ),
                privacy: AnalysisPrivacyContext(
                    containsPdfText: !source.pdfTextBlocks.isEmpty,
                    containsHandwriting: (source.drawingStats.strokeCount > 0),
                    userInitiated: true
                )
            )
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func markReviewTaskCompleted(_ task: AnalysisReviewTask) async {
        do {
            guard let updatedTask = try await queueStore.updateReviewTaskStatus(taskId: task.taskId, status: .completed) else { return }
            replaceReviewTask(updatedTask)
        } catch {
            errorMessage = "복습 작업 완료 처리 실패: \(error.localizedDescription)"
        }
    }

    func dismissReviewTask(_ task: AnalysisReviewTask) async {
        do {
            guard let updatedTask = try await queueStore.updateReviewTaskStatus(taskId: task.taskId, status: .dismissed) else { return }
            replaceReviewTask(updatedTask)
        } catch {
            errorMessage = "복습 작업 제외 실패: \(error.localizedDescription)"
        }
    }

    private func enqueue(
        previewImageData: Data?,
        drawingData: Data?,
        buildBundle: () -> AnalysisBundle
    ) async {
        isEnqueuing = true
        defer { isEnqueuing = false }

        let bundle = buildBundle()

        do {
            let entry = try await queueStore.enqueue(bundle: bundle, previewImageData: previewImageData, drawingData: drawingData)
            latestBundle = try await queueStore.loadBundle(bundleId: entry.bundleId)
            lastQueuedEntry = entry
            queueEntries.insert(entry, at: 0)
            queueEntries = deduplicatedEntries(queueEntries)

            let analysisResult = await analysisEngine.analyze(bundle: latestBundle ?? bundle)
            latestResult = analysisResult
            _ = try await queueStore.saveResult(analysisResult, for: entry.bundleId)
            let generatedReviewTasks = makeReviewTasks(for: analysisResult, bundle: latestBundle ?? bundle)
            if !generatedReviewTasks.isEmpty {
                try await queueStore.upsertReviewTasks(generatedReviewTasks)
            }
            resultsByBundleId[analysisResult.bundleId] = analysisResult
            results = deduplicatedResults(Array(resultsByBundleId.values))
            resultsByPageKey[pageKey(documentId: analysisResult.documentId, pageId: analysisResult.pageId)] = analysisResult
            latestResult = results.first
            queueEntries = deduplicatedEntries(try await queueStore.loadEntries())
            reviewTasks = deduplicatedReviewTasks(try await queueStore.loadReviewTasks())
            if let updatedEntry = queueEntries.first(where: { $0.bundleId == entry.bundleId }) {
                lastQueuedEntry = updatedEntry
            }
        } catch {
            if let failureEntry = try? await queueStore.markFailed(bundleId: bundle.bundleId, errorMessage: error.localizedDescription) {
                replaceQueueEntry(failureEntry)
                lastQueuedEntry = failureEntry
            }
            errorMessage = "분석 번들 처리 실패: \(error.localizedDescription)"
        }
    }

    private func previousAnalysisIds(for documentId: UUID, pageId: UUID) -> [UUID] {
        guard let result = result(for: documentId, pageId: pageId) else { return [] }
        return [result.analysisId]
    }

    private func pageKey(documentId: UUID, pageId: UUID) -> String {
        "\(documentId.uuidString.lowercased())::\(pageId.uuidString.lowercased())"
    }

    private func applyResults(_ loadedResults: [AnalysisResult]) {
        results = deduplicatedResults(loadedResults)
        resultsByBundleId = Dictionary(uniqueKeysWithValues: results.map { ($0.bundleId, $0) })

        var latestPageResults: [String: AnalysisResult] = [:]
        for result in results {
            let key = pageKey(documentId: result.documentId, pageId: result.pageId)
            if latestPageResults[key] == nil {
                latestPageResults[key] = result
            }
        }
        resultsByPageKey = latestPageResults
        latestResult = results.first
    }

    private func deduplicatedEntries(_ entries: [AnalysisQueueEntry]) -> [AnalysisQueueEntry] {
        var seen = Set<UUID>()
        var deduplicated: [AnalysisQueueEntry] = []

        for entry in entries {
            guard !seen.contains(entry.bundleId) else { continue }
            seen.insert(entry.bundleId)
            deduplicated.append(entry)
        }

        return deduplicated.sorted { $0.createdAt > $1.createdAt }
    }

    private func deduplicatedResults(_ loadedResults: [AnalysisResult]) -> [AnalysisResult] {
        var grouped: [UUID: AnalysisResult] = [:]

        for result in loadedResults.sorted(by: { $0.createdAt > $1.createdAt }) {
            if grouped[result.analysisId] == nil {
                grouped[result.analysisId] = result
            }
        }

        return grouped.values.sorted { $0.createdAt > $1.createdAt }
    }

    private func deduplicatedReviewTasks(_ loadedTasks: [AnalysisReviewTask]) -> [AnalysisReviewTask] {
        var grouped: [UUID: AnalysisReviewTask] = [:]

        for task in loadedTasks.sorted(by: { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.updatedAt > rhs.updatedAt
        }) {
            if grouped[task.taskId] == nil {
                grouped[task.taskId] = task
            }
        }

        return grouped.values.sorted { lhs, rhs in
            if lhs.status == rhs.status {
                if lhs.dueAt == rhs.dueAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.dueAt < rhs.dueAt
            }
            return lhs.status == .pending
        }
    }

    private func makeReviewTasks(for result: AnalysisResult, bundle: AnalysisBundle) -> [AnalysisReviewTask] {
        let createdAt = result.createdAt
        let dueAt = Calendar.current.date(
            byAdding: .hour,
            value: max(result.reviewPlan.recommendedHoursUntilReview, 1),
            to: createdAt
        ) ?? createdAt.addingTimeInterval(60 * 60 * 12)

        let documentTitle = bundle.document.title
        let pageLabel = "p.\(bundle.page.pageIndex + 1)"
        let subjectLabel = result.classification?.subjectLabel ?? bundle.document.subject
        let unitLabel = result.classification?.unitLabel
        let weakestConcept = result.conceptNodes.sorted { lhs, rhs in
            if lhs.masteryScore == rhs.masteryScore {
                return lhs.confidenceScore < rhs.confidenceScore
            }
            return lhs.masteryScore < rhs.masteryScore
        }.first

        var tasks: [AnalysisReviewTask] = [
            AnalysisReviewTask(
                taskId: UUID.stableAnalysisTaskID(namespace: result.bundleId, key: "revisit-page"),
                createdAt: createdAt,
                updatedAt: createdAt,
                dueAt: dueAt,
                status: .pending,
                kind: .revisitPage,
                analysisId: result.analysisId,
                bundleId: result.bundleId,
                documentId: result.documentId,
                pageId: result.pageId,
                documentTitle: documentTitle,
                pageLabel: pageLabel,
                title: "\(pageLabel) 다시 보기",
                detail: result.reviewPlan.reviewReason,
                subjectLabel: subjectLabel,
                unitLabel: unitLabel,
                conceptLabel: weakestConcept?.label
            )
        ]

        if let weakestConcept, weakestConcept.masteryScore < 0.78 {
            tasks.append(
                AnalysisReviewTask(
                    taskId: UUID.stableAnalysisTaskID(namespace: result.bundleId, key: "practice-\(weakestConcept.nodeId)"),
                    createdAt: createdAt,
                    updatedAt: createdAt,
                    dueAt: dueAt,
                    status: .pending,
                    kind: .practiceConcept,
                    analysisId: result.analysisId,
                    bundleId: result.bundleId,
                    documentId: result.documentId,
                    pageId: result.pageId,
                    documentTitle: documentTitle,
                    pageLabel: pageLabel,
                    title: "\(weakestConcept.label) 다시 연습",
                    detail: "현재 숙련도 \(Int((weakestConcept.masteryScore * 100).rounded()))%로 추정됩니다. 같은 개념 문제를 3개 이상 다시 풀어 보세요.",
                    subjectLabel: subjectLabel,
                    unitLabel: unitLabel,
                    conceptLabel: weakestConcept.label
                )
            )
        }

        if result.classification?.studyMode == .conceptSummary, result.summary.masteryScore < 0.72 {
            tasks.append(
                AnalysisReviewTask(
                    taskId: UUID.stableAnalysisTaskID(namespace: result.bundleId, key: "restructure-notes"),
                    createdAt: createdAt,
                    updatedAt: createdAt,
                    dueAt: dueAt,
                    status: .pending,
                    kind: .restructureNotes,
                    analysisId: result.analysisId,
                    bundleId: result.bundleId,
                    documentId: result.documentId,
                    pageId: result.pageId,
                    documentTitle: documentTitle,
                    pageLabel: pageLabel,
                    title: "개념 정리 다시 구조화",
                    detail: "정의, 핵심 조건, 예시를 분리해서 다시 적으면 분석 품질과 복습 효율이 올라갑니다.",
                    subjectLabel: subjectLabel,
                    unitLabel: unitLabel,
                    conceptLabel: weakestConcept?.label
                )
            )
        }

        return deduplicatedReviewTasks(tasks)
    }

    private func prettyJSONString<T: Encodable>(for value: T) -> String {
        guard let data = try? jsonEncoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "JSON encoding failed."
        }
        return string
    }

    private func replaceQueueEntry(_ updatedEntry: AnalysisQueueEntry) {
        if let index = queueEntries.firstIndex(where: { $0.bundleId == updatedEntry.bundleId }) {
            queueEntries[index] = updatedEntry
        } else {
            queueEntries.insert(updatedEntry, at: 0)
        }
        queueEntries = deduplicatedEntries(queueEntries)
    }

    private func replaceReviewTask(_ updatedTask: AnalysisReviewTask) {
        if let index = reviewTasks.firstIndex(where: { $0.taskId == updatedTask.taskId }) {
            reviewTasks[index] = updatedTask
        } else {
            reviewTasks.append(updatedTask)
        }
        reviewTasks = deduplicatedReviewTasks(reviewTasks)
    }

    private func makeOCRPreviewSummary(
        ocrBlocks: [AnalysisTextBlock],
        supportingBlocks: [AnalysisTextBlock]
    ) -> OCRPreviewSummary {
        let recognizedCharacterCount = ocrBlocks.reduce(into: 0) { partial, block in
            partial += block.text.count
        }

        let topLines = ocrBlocks
            .map(\.text)
            .flatMap { $0.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }

        let combinedSource = (ocrBlocks + supportingBlocks).map(\.text).joined(separator: "\n")
        return OCRPreviewSummary(
            recognizedBlockCount: ocrBlocks.count,
            scannedPageBlockCount: ocrBlocks.filter { $0.kind == "ocr-scanned-page" }.count,
            handwritingBlockCount: ocrBlocks.filter { $0.kind == "ocr-handwriting" }.count,
            recognizedCharacterCount: recognizedCharacterCount,
            topLines: Array(topLines.prefix(4)),
            problemCandidates: Array(extractedProblemCandidates(from: combinedSource).prefix(4)),
            hasMathSignal: hasMathSignal(in: combinedSource)
        )
    }

    private func extractedProblemCandidates(from text: String) -> [String] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var candidates = lines.filter { line in
            line.range(of: #"^(예제|문제|기출|실전)\s*\d+"#, options: .regularExpression) != nil ||
            line.range(of: #"^\d+[\.\)]"#, options: .regularExpression) != nil ||
            line.contains("①") || line.contains("②") || line.contains("③") || line.contains("④") || line.contains("⑤")
        }

        if candidates.isEmpty {
            candidates = lines.filter { line in
                hasMathSignal(in: line) && line.count >= 8
            }
        }

        return candidates
    }

    private func hasMathSignal(in text: String) -> Bool {
        let patterns = [
            #"[0-9][\s]*[×x+\-=/][\s]*[0-9a-zA-Z]"#,
            #"(?i)\b(lim|log|ln|sin|cos|tan|sec|csc|cot)\b"#,
            #"[∫Σπ√]"#
        ]

        return patterns.contains { pattern in
            text.range(of: pattern, options: .regularExpression) != nil
        }
    }
}
