import Combine
import Foundation

@MainActor
final class LibraryViewModel: ObservableObject {
    struct StudySectionDraft: Identifiable, Hashable {
        let id: UUID
        var title: String
        var startPage: Int
    }

    struct PendingPDFImportSelection: Identifiable {
        let id = UUID()
        var document: PharDocument
        var suggestion: StudyMaterialImportSuggestion
    }

    struct MaterialShelf: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let documents: [PharDocument]
    }

    @Published private(set) var documents: [PharDocument] = []
    @Published var selectedFolder: LibraryFolder? = .all
    @Published var searchQuery: String = ""
    @Published var navigationPath: [PharDocument] = []
    @Published var errorMessage: String?
    @Published var pendingPDFImportSelection: PendingPDFImportSelection?
    @Published var selectedStudySubject: StudySubject?
    @Published var selectedStudyProvider: StudyMaterialProvider?
    @Published private(set) var catalogSummary: StudyMaterialCatalogSummary
    @Published var catalogImportPreview: StudyMaterialCatalogImportPreview?
    @Published private(set) var dashboardSnapshot: PharnodeDashboardSnapshot?
    @Published private(set) var dashboardSnapshotJSONString: String?

    private let store: LibraryStore
    private let catalogManager: StudyMaterialCatalogManager
    private var materialRecognizer: StudyMaterialRecognizer

    convenience init() {
        self.init(store: LibraryStore(), materialRecognizer: nil, catalogManager: nil)
    }

    init(
        store: LibraryStore,
        materialRecognizer: StudyMaterialRecognizer? = nil,
        catalogManager: StudyMaterialCatalogManager? = nil
    ) {
        self.store = store
        let resolvedCatalogManager = catalogManager ?? StudyMaterialCatalogManager()
        self.catalogManager = resolvedCatalogManager
        self.catalogSummary = resolvedCatalogManager.summary()
        self.materialRecognizer = materialRecognizer ?? StudyMaterialRecognizer(catalogStore: resolvedCatalogManager.makeStore())
        loadDocuments()
    }

    var selectedFolderTitle: String {
        (selectedFolder ?? .all).detailTitle
    }

    var totalDocumentCount: Int {
        documents.count
    }

    var blankNoteCount: Int {
        documents.filter { $0.type == .blankNote }.count
    }

    var pdfCount: Int {
        documents.filter { $0.type == .pdf }.count
    }

    var filteredDocuments: [PharDocument] {
        let filtered = documentsForCurrentFolder(matching: searchQuery)
        return filtered.sorted { $0.updatedAt > $1.updatedAt }
    }

    var continueStudyingDocuments: [PharDocument] {
        Array(filteredDocuments.prefix(4))
    }

    var highlightedBlankNotes: [PharDocument] {
        Array(documents(for: .blankNotes, matching: searchQuery).prefix(6))
    }

    var highlightedPDFs: [PharDocument] {
        Array(documents(for: .pdfs, matching: searchQuery).prefix(6))
    }

    var manageablePDFDocuments: [PharDocument] {
        documents
            .filter { $0.type == .pdf }
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    var availableStudySubjects: [StudySubject] {
        Array(
            Set(visibleMaterialBaseDocuments.compactMap { $0.studyMaterial?.subject })
        )
        .sorted { $0.displayOrder < $1.displayOrder }
    }

    var availableStudyProviders: [StudyMaterialProvider] {
        Array(
            Set(visibleMaterialBaseDocuments.compactMap { $0.studyMaterial?.provider })
        )
        .sorted { $0.displayOrder < $1.displayOrder }
    }

    var hasActiveMaterialFilters: Bool {
        selectedStudySubject != nil || selectedStudyProvider != nil
    }

    var materialShelves: [MaterialShelf] {
        let materialDocuments = filteredMaterialDocuments
        guard !materialDocuments.isEmpty else { return [] }

        let sortedDocuments = materialDocuments.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            return lhs.updatedAt > rhs.updatedAt
        }

        if let selectedStudyProvider, let selectedStudySubject {
            return [
                MaterialShelf(
                    id: "focused-shelf",
                    title: "\(selectedStudyProvider.title) · \(selectedStudySubject.title)",
                    subtitle: "PDF \(sortedDocuments.count)권",
                    documents: sortedDocuments
                )
            ]
        }

        if selectedStudyProvider != nil {
            return makeShelves(from: sortedDocuments, groupedBy: { $0.studySubjectTitle ?? "미분류 과목" })
        }

        return makeShelves(from: sortedDocuments, groupedBy: { $0.studyProviderTitle ?? "미분류 출처" })
    }

    func count(for folder: LibraryFolder) -> Int {
        documents(for: folder, matching: "").count
    }

    func loadDocuments() {
        do {
            documents = try store.loadIndex().sorted { $0.updatedAt > $1.updatedAt }
            refreshDashboardSnapshot()
        } catch {
            errorMessage = "문서 인덱스 로드 실패: \(error.localizedDescription)"
        }
    }

    func createBlankNote() {
        do {
            let newDocument = try store.createBlankNote(title: nextBlankNoteTitle())
            documents.insert(newDocument, at: 0)
            refreshDashboardSnapshot()
            navigationPath.append(newDocument)
        } catch {
            errorMessage = "새 문서 생성 실패: \(error.localizedDescription)"
        }
    }

    func importPDF(from sourceURL: URL) {
        do {
            let suggestion = materialRecognizer.suggest(from: sourceURL)
            let initialMaterial = suggestion.resolvedMetadata(
                title: suggestion.normalizedTitle,
                provider: suggestion.provider,
                subject: suggestion.subject
            )
            let newDocument = try store.importPDF(
                from: sourceURL,
                suggestedMaterial: initialMaterial,
                pageCountHint: suggestion.totalPages
            )
            documents.insert(newDocument, at: 0)
            refreshDashboardSnapshot()
            pendingPDFImportSelection = PendingPDFImportSelection(document: newDocument, suggestion: suggestion)
        } catch {
            errorMessage = "PDF 가져오기 실패: \(error.localizedDescription)"
        }
    }

    func applyImportedPDFSelection(
        documentID: UUID,
        title: String,
        provider: StudyMaterialProvider,
        subject: StudySubject
    ) {
        guard let pending = pendingPDFImportSelection, pending.document.id == documentID else { return }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = trimmedTitle.isEmpty ? pending.document.title : trimmedTitle

        var updatedDocument = pending.document
        updatedDocument.title = resolvedTitle
        updatedDocument.updatedAt = Date()
        updatedDocument.studyMaterial = pending.suggestion.resolvedMetadata(
            title: resolvedTitle,
            provider: provider,
            subject: subject
        )

        do {
            let saved = try store.updateDocument(updatedDocument)
            replaceDocument(saved)
            refreshDashboardSnapshot()
            pendingPDFImportSelection = nil
            navigationPath.append(saved)
        } catch {
            errorMessage = "교재 메타데이터 저장 실패: \(error.localizedDescription)"
        }
    }

    func dismissImportedPDFSelection(openDocument: Bool) {
        guard let pending = pendingPDFImportSelection else { return }
        pendingPDFImportSelection = nil
        if openDocument {
            navigationPath.append(pending.document)
        }
    }

    func toggleStudySubject(_ subject: StudySubject?) {
        if selectedStudySubject == subject {
            selectedStudySubject = nil
        } else {
            selectedStudySubject = subject
        }
    }

    func toggleStudyProvider(_ provider: StudyMaterialProvider?) {
        if selectedStudyProvider == provider {
            selectedStudyProvider = nil
        } else {
            selectedStudyProvider = provider
        }
    }

    func clearStudyMaterialFilters() {
        selectedStudySubject = nil
        selectedStudyProvider = nil
    }

    func importStudyMaterialCatalog(from sourceURL: URL) {
        do {
            catalogImportPreview = try catalogManager.previewImport(from: sourceURL)
        } catch {
            errorMessage = "교재 카탈로그 가져오기 실패: \(error.localizedDescription)"
        }
    }

    func confirmStudyMaterialCatalogImport() {
        guard let catalogImportPreview else { return }
        do {
            catalogSummary = try catalogManager.importCatalog(preview: catalogImportPreview)
            materialRecognizer = StudyMaterialRecognizer(catalogStore: catalogManager.makeStore())
            self.catalogImportPreview = nil
        } catch {
            errorMessage = "교재 카탈로그 저장 실패: \(error.localizedDescription)"
        }
    }

    func cancelStudyMaterialCatalogImport() {
        catalogImportPreview = nil
    }

    func resetImportedStudyMaterialCatalog() {
        do {
            catalogSummary = try catalogManager.resetImportedCatalog()
            materialRecognizer = StudyMaterialRecognizer(catalogStore: catalogManager.makeStore())
            catalogImportPreview = nil
        } catch {
            errorMessage = "교재 카탈로그 초기화 실패: \(error.localizedDescription)"
        }
    }

    func refreshDashboardSnapshot() {
        do {
            dashboardSnapshot = try store.loadDashboardSnapshot()
            dashboardSnapshotJSONString = try store.loadDashboardSnapshotJSONString()
        } catch {
            dashboardSnapshot = nil
            dashboardSnapshotJSONString = nil
            errorMessage = "대시보드 스냅샷 로드 실패: \(error.localizedDescription)"
        }
    }

    func sectionDrafts(for document: PharDocument) -> [StudySectionDraft] {
        let sourceSections = document.progress?.sections.isEmpty == false
            ? (document.progress?.sections ?? [])
            : [StudySectionProgress(
                id: UUID(),
                title: "단원 1",
                startPage: 1,
                endPage: max(document.progress?.totalPages ?? 1, 1),
                status: .current,
                completionRatio: 0
            )]

        return sourceSections
            .sorted { $0.startPage < $1.startPage }
            .enumerated()
            .map { index, section in
                StudySectionDraft(
                    id: section.id,
                    title: section.title.isEmpty ? "단원 \(index + 1)" : section.title,
                    startPage: section.startPage
                )
            }
    }

    func suggestedSectionDraft(for document: PharDocument, existingDrafts: [StudySectionDraft]) -> StudySectionDraft {
        let totalPages = max(document.progress?.totalPages ?? 1, 1)
        let existingStarts = Set(existingDrafts.map(\.startPage))
        var proposedStart = min(max(document.progress?.currentPage ?? 1, 1), totalPages)

        while existingStarts.contains(proposedStart) && proposedStart < totalPages {
            proposedStart += 1
        }

        if existingStarts.contains(proposedStart) {
            proposedStart = totalPages
        }

        return StudySectionDraft(
            id: UUID(),
            title: "단원 \(existingDrafts.count + 1)",
            startPage: proposedStart
        )
    }

    func saveStudyMaterialAdministration(
        documentID: UUID,
        title: String,
        provider: StudyMaterialProvider,
        subject: StudySubject,
        sectionDrafts: [StudySectionDraft]
    ) -> Bool {
        guard let existingDocument = documents.first(where: { $0.id == documentID }) else {
            errorMessage = "수정할 교재를 찾을 수 없습니다."
            return false
        }

        let resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? existingDocument.title
            : title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSections = normalizedSections(from: sectionDrafts, totalPages: max(existingDocument.progress?.totalPages ?? 1, 1))

        do {
            var updatedDocument = existingDocument
            updatedDocument.title = resolvedTitle
            updatedDocument.updatedAt = Date()
            updatedDocument.studyMaterial = updatedStudyMaterial(
                for: existingDocument,
                resolvedTitle: resolvedTitle,
                provider: provider,
                subject: subject
            )

            let savedDocument = try store.updateDocument(updatedDocument)
            let finalDocument = try store.updateStudySections(documentID: savedDocument.id, sections: normalizedSections) ?? savedDocument
            replaceDocument(finalDocument)
            refreshDashboardSnapshot()
            return true
        } catch {
            errorMessage = "교재 정보 저장 실패: \(error.localizedDescription)"
            return false
        }
    }

    private var visibleMaterialBaseDocuments: [PharDocument] {
        guard (selectedFolder ?? .all) != .blankNotes else { return [] }
        return documents(for: .pdfs, matching: searchQuery)
    }

    private var filteredMaterialDocuments: [PharDocument] {
        visibleMaterialBaseDocuments.filter { document in
            let matchesSubject: Bool
            if let selectedStudySubject {
                matchesSubject = document.studyMaterial?.subject == selectedStudySubject
            } else {
                matchesSubject = true
            }

            let matchesProvider: Bool
            if let selectedStudyProvider {
                matchesProvider = document.studyMaterial?.provider == selectedStudyProvider
            } else {
                matchesProvider = true
            }

            return matchesSubject && matchesProvider
        }
    }

    private func nextBlankNoteTitle() -> String {
        let nextNumber = documents.filter { $0.type == .blankNote }.count + 1
        return "빈 노트 \(nextNumber)"
    }

    private func updatedStudyMaterial(
        for document: PharDocument,
        resolvedTitle: String,
        provider: StudyMaterialProvider,
        subject: StudySubject
    ) -> StudyMaterialMetadata? {
        let previous = document.studyMaterial

        guard provider != .unspecified || subject != .unspecified || previous != nil else {
            return nil
        }

        return StudyMaterialMetadata(
            catalogEntryID: previous?.catalogEntryID,
            canonicalTitle: resolvedTitle,
            provider: provider,
            subject: subject,
            recognitionConfidence: previous?.recognitionConfidence ?? 0.9,
            recognitionQuery: previous?.recognitionQuery,
            matchedSignals: previous?.matchedSignals ?? []
        )
    }

    private func normalizedSections(from drafts: [StudySectionDraft], totalPages: Int) -> [StudySectionProgress] {
        let safeTotalPages = max(totalPages, 1)
        let cleanedDrafts = drafts
            .map { draft in
                StudySectionDraft(
                    id: draft.id,
                    title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    startPage: min(max(draft.startPage, 1), safeTotalPages)
                )
            }
            .sorted { lhs, rhs in
                if lhs.startPage == rhs.startPage {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.startPage < rhs.startPage
            }

        var uniqueDrafts: [StudySectionDraft] = []
        var lastStartPage = 0

        for draft in cleanedDrafts {
            let nextStartPage = min(max(draft.startPage, lastStartPage + 1), safeTotalPages)
            guard nextStartPage <= safeTotalPages else { continue }
            uniqueDrafts.append(
                StudySectionDraft(
                    id: draft.id,
                    title: draft.title.isEmpty ? "단원 \(uniqueDrafts.count + 1)" : draft.title,
                    startPage: nextStartPage
                )
            )
            lastStartPage = nextStartPage
        }

        if uniqueDrafts.isEmpty {
            uniqueDrafts = [StudySectionDraft(id: UUID(), title: "단원 1", startPage: 1)]
        }

        return uniqueDrafts.enumerated().map { index, draft in
            let nextStartPage = index + 1 < uniqueDrafts.count ? uniqueDrafts[index + 1].startPage : safeTotalPages + 1
            return StudySectionProgress(
                id: draft.id,
                title: draft.title,
                startPage: draft.startPage,
                endPage: max(min(nextStartPage - 1, safeTotalPages), draft.startPage),
                status: .upcoming,
                completionRatio: 0
            )
        }
    }

    private func replaceDocument(_ document: PharDocument) {
        if let index = documents.firstIndex(where: { $0.id == document.id }) {
            documents[index] = document
            documents.sort { $0.updatedAt > $1.updatedAt }
        }
    }

    private func documentsForCurrentFolder(matching query: String) -> [PharDocument] {
        documents(for: selectedFolder ?? .all, matching: query)
    }

    private func documents(for folder: LibraryFolder, matching query: String) -> [PharDocument] {
        let base: [PharDocument]

        switch folder {
        case .all:
            base = documents
        case .blankNotes:
            base = documents.filter { $0.type == .blankNote }
        case .pdfs:
            base = documents.filter { $0.type == .pdf }
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return base }

        return base.filter { document in
            if document.title.localizedStandardContains(trimmedQuery) {
                return true
            }
            if let material = document.studyMaterial {
                if material.canonicalTitle.localizedStandardContains(trimmedQuery) {
                    return true
                }
                if material.provider.title.localizedStandardContains(trimmedQuery) {
                    return true
                }
                if material.subject.title.localizedStandardContains(trimmedQuery) {
                    return true
                }
            }
            return false
        }
    }

    private func makeShelves(
        from documents: [PharDocument],
        groupedBy titleProvider: (PharDocument) -> String
    ) -> [MaterialShelf] {
        let grouped = Dictionary(grouping: documents, by: titleProvider)

        return grouped
            .map { title, documents in
                MaterialShelf(
                    id: title,
                    title: title,
                    subtitle: "PDF \(documents.count)권",
                    documents: documents
                )
            }
            .sorted { lhs, rhs in
                if lhs.documents.count == rhs.documents.count {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.documents.count > rhs.documents.count
            }
    }
}
