import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class LibraryViewModel: ObservableObject {
    private struct PersistedOpenDocumentTab: Codable {
        let documentID: UUID
        let initialPageKey: String?
    }

    private struct PersistedWorkspaceState: Codable {
        let openTabs: [PersistedOpenDocumentTab]
        let activeDocumentTabID: UUID?
    }

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

    struct OCRSearchResultRow: Identifiable, Hashable {
        let id: UUID
        let document: PharDocument
        let pageKey: String
        let pageLabel: String
        let snippet: String
        let indexedAt: Date
    }

    struct OCRSearchNavigationTarget: Hashable {
        let document: PharDocument
        let pageKey: String
    }

    @Published private(set) var documents: [PharDocument] = []
    @Published var selectedFolder: LibraryFolder? = .all
    @Published var searchQuery: String = ""
    @Published var navigationPath = NavigationPath()
    @Published private(set) var openDocumentTabs: [DocumentEditorLaunchTarget] = []
    @Published private(set) var activeDocumentTabID: UUID?
    @Published var errorMessage: String?
    @Published var pendingPDFImportSelection: PendingPDFImportSelection?
    @Published var selectedStudySubject: StudySubject?
    @Published var selectedStudyProvider: StudyMaterialProvider?
    @Published private(set) var catalogSummary: StudyMaterialCatalogSummary
    @Published var catalogImportPreview: StudyMaterialCatalogImportPreview?
    @Published private(set) var dashboardSnapshot: PharnodeDashboardSnapshot?
    @Published private(set) var dashboardSnapshotJSONString: String?
    @Published private(set) var ocrSearchResults: [OCRSearchResultRow] = []

    private let store: LibraryStore
    private let catalogManager: StudyMaterialCatalogManager
    private let userDefaults: UserDefaults
    private var materialRecognizer: StudyMaterialRecognizer
    private var searchTask: Task<Void, Never>?
    private var didRestoreWorkspaceState = false
    private let workspaceStateDefaultsKey = "pharnote.workspace-state"

    convenience init() {
        self.init(store: LibraryStore(), materialRecognizer: nil, catalogManager: nil)
    }

    init(
        store: LibraryStore,
        materialRecognizer: StudyMaterialRecognizer? = nil,
        catalogManager: StudyMaterialCatalogManager? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.store = store
        let resolvedCatalogManager = catalogManager ?? StudyMaterialCatalogManager()
        self.catalogManager = resolvedCatalogManager
        self.catalogSummary = resolvedCatalogManager.summary()
        self.materialRecognizer = materialRecognizer ?? StudyMaterialRecognizer(catalogStore: resolvedCatalogManager.makeStore())
        self.userDefaults = userDefaults
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

    var hasSearchQuery: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            if didRestoreWorkspaceState {
                reconcileOpenDocumentTabs()
            } else {
                restoreWorkspaceStateIfNeeded()
            }
            refreshDashboardSnapshot()
            refreshOCRSearchResults()
        } catch {
            errorMessage = "문서 인덱스 로드 실패: \(error.localizedDescription)"
        }
    }

    func createBlankNote() {
        do {
            let newDocument = try store.createBlankNote(title: nextBlankNoteTitle())
            documents.insert(newDocument, at: 0)
            refreshDashboardSnapshot()
            openDocument(newDocument)
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

    func importDocument(from sourceURL: URL) {
        switch importedFileKind(for: sourceURL) {
        case .pdf:
            importPDF(from: sourceURL)
        case .image:
            do {
                let newDocument = try store.importImageAsPDF(from: sourceURL)
                documents.insert(newDocument, at: 0)
                refreshDashboardSnapshot()
                openDocument(newDocument)
            } catch {
                errorMessage = "이미지 가져오기 실패: \(error.localizedDescription)"
            }
        case .unsupported:
            errorMessage = "지원하지 않는 파일 형식입니다. PDF 또는 이미지 파일을 선택해 주세요."
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
            openDocument(saved)
        } catch {
            errorMessage = "교재 메타데이터 저장 실패: \(error.localizedDescription)"
        }
    }

    func dismissImportedPDFSelection(openDocument: Bool) {
        guard let pending = pendingPDFImportSelection else { return }
        pendingPDFImportSelection = nil
        if openDocument {
            self.openDocument(pending.document)
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

    func refreshOCRSearchResults() {
        searchTask?.cancel()

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            ocrSearchResults = []
            return
        }

        let documents = self.documents
        searchTask = Task { @MainActor [query] in
            let hits = await SearchInfrastructure.shared.searchHandwriting(query: query, limit: 20)
            guard !Task.isCancelled else { return }

            let mappedResults = hits.compactMap { hit -> OCRSearchResultRow? in
                guard let document = documents.first(where: { $0.id == hit.documentID }) else { return nil }
                guard self.matchesSelectedFolder(document) else { return nil }
                return OCRSearchResultRow(
                    id: hit.id,
                    document: document,
                    pageKey: hit.pageKey,
                    pageLabel: pageLabel(for: hit.pageKey),
                    snippet: hit.snippet,
                    indexedAt: hit.indexedAt
                )
            }

            ocrSearchResults = mappedResults.sorted { $0.indexedAt > $1.indexedAt }
        }
    }

    func openOCRSearchResult(_ result: OCRSearchResultRow) {
        openDocument(result.document, initialPageKey: result.pageKey)
    }

    func openDocument(_ document: PharDocument, initialPageKey: String? = nil) {
        let target = DocumentEditorLaunchTarget(document: document, initialPageKey: initialPageKey)
        if let existingIndex = openDocumentTabs.firstIndex(where: { $0.document.id == document.id }) {
            openDocumentTabs.remove(at: existingIndex)
        }
        openDocumentTabs.append(target)
        activeDocumentTabID = document.id
        setNavigationTarget(target)
        persistWorkspaceState()
    }

    func activateDocumentTab(_ documentID: UUID) {
        guard let existingIndex = openDocumentTabs.firstIndex(where: { $0.document.id == documentID }) else { return }
        let target = openDocumentTabs.remove(at: existingIndex)
        openDocumentTabs.append(target)
        activeDocumentTabID = documentID
        setNavigationTarget(target)
        persistWorkspaceState()
    }

    func closeDocumentTab(_ documentID: UUID) {
        guard let existingIndex = openDocumentTabs.firstIndex(where: { $0.document.id == documentID }) else { return }
        let wasActive = activeDocumentTabID == documentID
        openDocumentTabs.remove(at: existingIndex)

        if wasActive {
            let nextTarget = openDocumentTabs.last
            activeDocumentTabID = nextTarget?.document.id
            setNavigationTarget(nextTarget)
        } else if activeDocumentTabID == nil, let nextTarget = openDocumentTabs.last {
            activeDocumentTabID = nextTarget.document.id
            setNavigationTarget(nextTarget)
        }

        persistWorkspaceState()
    }

    func workspaceDocumentChips(currentDocument: PharDocument) -> [WritingWorkspaceDocumentChip] {
        let sourceTabs = openDocumentTabs.isEmpty ? [DocumentEditorLaunchTarget(document: currentDocument, initialPageKey: nil)] : openDocumentTabs
        let activeDocumentID = activeDocumentTabID ?? currentDocument.id

        return sourceTabs.map { target in
            WritingWorkspaceDocumentChip(
                id: target.document.id,
                title: target.document.title,
                isCurrent: target.document.id == activeDocumentID
            )
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

    private enum ImportedFileKind {
        case pdf
        case image
        case unsupported
    }

    private func importedFileKind(for sourceURL: URL) -> ImportedFileKind {
        if let contentType = try? sourceURL.resourceValues(forKeys: [.contentTypeKey]).contentType {
            if contentType.conforms(to: .pdf) {
                return .pdf
            }
            if contentType.conforms(to: .image) {
                return .image
            }
        }

        let pathExtension = sourceURL.pathExtension.lowercased()
        if let inferredType = UTType(filenameExtension: pathExtension) {
            if inferredType.conforms(to: .pdf) {
                return .pdf
            }
            if inferredType.conforms(to: .image) {
                return .image
            }
        }

        return .unsupported
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
        if let tabIndex = openDocumentTabs.firstIndex(where: { $0.document.id == document.id }) {
            let existing = openDocumentTabs[tabIndex]
            openDocumentTabs[tabIndex] = DocumentEditorLaunchTarget(document: document, initialPageKey: existing.initialPageKey)
            if activeDocumentTabID == document.id && !navigationPath.isEmpty {
                setNavigationTarget(openDocumentTabs[tabIndex])
            }
        }
        persistWorkspaceState()
    }

    private func reconcileOpenDocumentTabs() {
        guard !openDocumentTabs.isEmpty else { return }

        openDocumentTabs = openDocumentTabs.compactMap { target in
            guard let updatedDocument = documents.first(where: { $0.id == target.document.id }) else { return nil }
            return DocumentEditorLaunchTarget(document: updatedDocument, initialPageKey: target.initialPageKey)
        }

        if let activeDocumentTabID,
           !openDocumentTabs.contains(where: { $0.document.id == activeDocumentTabID }) {
            self.activeDocumentTabID = openDocumentTabs.last?.document.id
        }

        if let activeDocumentTabID,
           let activeTarget = openDocumentTabs.first(where: { $0.document.id == activeDocumentTabID }) {
            // "홈 화면" 상태(!navigationPath.isEmpty == false)일 때 자동으로 다시 들어가는 현상을 방지합니다.
            // 사용자가 명시적으로 탭(activeDocumentTabID)을 선택했거나, 초기 복원 과정에서만 네비게이션을 수행해야 합니다.
            // 현재 navigationPath가 비어있다는 것은 사용자가 의도적으로 홈으로 나왔음을 의미할 수 있습니다.
            
            if !navigationPath.isEmpty {
                // 이미 무언가 열려있는 상태에서 탭 전환 등으로 인한 정합성 맞추기
                if !isAlreadyNavigated(to: activeTarget) {
                    setNavigationTarget(activeTarget)
                }
            }
        } else if openDocumentTabs.isEmpty {
            activeDocumentTabID = nil
            if !navigationPath.isEmpty {
                setNavigationTarget(nil)
            }
        }

        persistWorkspaceState()
    }

    private func setNavigationTarget(_ target: DocumentEditorLaunchTarget?) {
        var newPath = NavigationPath()
        if let target {
            newPath.append(target)
        }
        navigationPath = newPath
    }

    private func isAlreadyNavigated(to target: DocumentEditorLaunchTarget) -> Bool {
        // navigationPath가 비어있으면 홈 화면이므로, 어떤 문서 타겟과도 "이미 네비게이션된" 상태가 아닙니다.
        if navigationPath.isEmpty {
            return false
        }
        
        // 현재 활성화된 탭 ID가 타겟과 일치하면 이미 화면이 떠 있는 것으로 간주합니다.
        return activeDocumentTabID == target.document.id
    }

    private func restoreWorkspaceStateIfNeeded() {
        didRestoreWorkspaceState = true

        guard let data = userDefaults.data(forKey: workspaceStateDefaultsKey) else {
            reconcileOpenDocumentTabs()
            return
        }

        let decoder = JSONDecoder()
        guard let persistedState = try? decoder.decode(PersistedWorkspaceState.self, from: data) else {
            userDefaults.removeObject(forKey: workspaceStateDefaultsKey)
            reconcileOpenDocumentTabs()
            return
        }

        openDocumentTabs = persistedState.openTabs.compactMap { persistedTab in
            guard let document = documents.first(where: { $0.id == persistedTab.documentID }) else { return nil }
            return DocumentEditorLaunchTarget(document: document, initialPageKey: persistedTab.initialPageKey)
        }

        if let activeID = persistedState.activeDocumentTabID,
           openDocumentTabs.contains(where: { $0.document.id == activeID }) {
            activeDocumentTabID = activeID
        } else {
            activeDocumentTabID = openDocumentTabs.last?.document.id
        }

        if let activeDocumentTabID,
           let activeTarget = openDocumentTabs.first(where: { $0.document.id == activeDocumentTabID }) {
            setNavigationTarget(activeTarget)
        } else {
            setNavigationTarget(nil)
        }

        persistWorkspaceState()
    }

    private func persistWorkspaceState() {
        let openTabs = openDocumentTabs.map {
            PersistedOpenDocumentTab(
                documentID: $0.document.id,
                initialPageKey: $0.initialPageKey
            )
        }

        guard !openTabs.isEmpty || activeDocumentTabID != nil else {
            userDefaults.removeObject(forKey: workspaceStateDefaultsKey)
            return
        }

        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(
            PersistedWorkspaceState(
                openTabs: openTabs,
                activeDocumentTabID: activeDocumentTabID
            )
        ) else {
            return
        }

        userDefaults.set(data, forKey: workspaceStateDefaultsKey)
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

    private func pageLabel(for pageKey: String) -> String {
        if pageKey.hasPrefix("pdf-page-"),
           let index = Int(pageKey.replacingOccurrences(of: "pdf-page-", with: "")) {
            return "p.\(index + 1)"
        }
        return "필기 페이지"
    }

    private func matchesSelectedFolder(_ document: PharDocument) -> Bool {
        switch selectedFolder ?? .all {
        case .all:
            return true
        case .blankNotes:
            return document.type == .blankNote
        case .pdfs:
            return document.type == .pdf
        }
    }
}
