import Foundation

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var documents: [PharDocument] = []
    @Published var selectedFolder: LibraryFolder? = .all
    @Published var searchQuery: String = ""
    @Published var navigationPath: [PharDocument] = []
    @Published var errorMessage: String?

    private let store: LibraryStore

    init(store: LibraryStore = LibraryStore()) {
        self.store = store
        loadDocuments()
    }

    var filteredDocuments: [PharDocument] {
        let filtered: [PharDocument]

        switch selectedFolder ?? .all {
        case .all:
            filtered = documents
        case .blankNotes:
            filtered = documents.filter { $0.type == .blankNote }
        case .pdfs:
            filtered = documents.filter { $0.type == .pdf }
        }

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        if query.isEmpty {
            return filtered.sorted { $0.updatedAt > $1.updatedAt }
        }

        return filtered
            .filter { $0.title.localizedStandardContains(query) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func loadDocuments() {
        do {
            documents = try store.loadIndex().sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            errorMessage = "문서 인덱스 로드 실패: \(error.localizedDescription)"
        }
    }

    func createBlankNote() {
        do {
            let newDocument = try store.createBlankNote(title: nextBlankNoteTitle())
            documents.insert(newDocument, at: 0)
            navigationPath.append(newDocument)
        } catch {
            errorMessage = "새 문서 생성 실패: \(error.localizedDescription)"
        }
    }

    func importPDF(from sourceURL: URL) {
        do {
            let newDocument = try store.importPDF(from: sourceURL)
            documents.insert(newDocument, at: 0)
            navigationPath.append(newDocument)
        } catch {
            errorMessage = "PDF 가져오기 실패: \(error.localizedDescription)"
        }
    }

    private func nextBlankNoteTitle() -> String {
        let nextNumber = documents.filter { $0.type == .blankNote }.count + 1
        return "빈 노트 \(nextNumber)"
    }
}
