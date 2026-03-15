import Foundation
import PDFKit

enum StudyMaterialProvider: String, Codable, CaseIterable, Hashable, Identifiable {
    case unspecified
    case sdijBooks
    case sdijLecture
    case orbiBooks
    case ebs
    case megastudy
    case daesung
    case etoos
    case other

    var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .unspecified: return "미지정"
        case .sdijBooks: return "시대인재북스"
        case .sdijLecture: return "시대인재 현강"
        case .orbiBooks: return "오르비북스"
        case .ebs: return "EBS"
        case .megastudy: return "메가스터디"
        case .daesung: return "대성마이맥"
        case .etoos: return "이투스"
        case .other: return "기타"
        }
    }

    nonisolated var displayOrder: Int {
        switch self {
        case .unspecified: return 0
        case .sdijBooks: return 1
        case .sdijLecture: return 2
        case .orbiBooks: return 3
        case .ebs: return 4
        case .megastudy: return 5
        case .daesung: return 6
        case .etoos: return 7
        case .other: return 8
        }
    }

    fileprivate var matchingTokens: [String] {
        switch self {
        case .unspecified:
            return []
        case .sdijBooks:
            return ["시대인재북스", "sdijbooks", "시대인재 books", "시대인재북스 교재"]
        case .sdijLecture:
            return ["시대인재 현강", "시대인재 현강자료", "sdij 현강", "현강 자료", "현장강의"]
        case .orbiBooks:
            return ["오르비북스", "orbi books", "orbi", "orbi books 교재"]
        case .ebs:
            return ["ebs", "수능특강", "수능완성", "ebsi"]
        case .megastudy:
            return ["메가스터디", "megastudy"]
        case .daesung:
            return ["대성마이맥", "대성", "mimac", "ds"]
        case .etoos:
            return ["이투스", "etoos"]
        case .other:
            return []
        }
    }
}

enum StudySubject: String, Codable, CaseIterable, Hashable, Identifiable {
    case unspecified
    case korean
    case math
    case english
    case koreanHistory
    case socialInquiry
    case physics
    case chemistry
    case biology
    case earthScience
    case essay

    var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .unspecified: return "미지정"
        case .korean: return "국어"
        case .math: return "수학"
        case .english: return "영어"
        case .koreanHistory: return "한국사"
        case .socialInquiry: return "사탐"
        case .physics: return "물리"
        case .chemistry: return "화학"
        case .biology: return "생명과학"
        case .earthScience: return "지구과학"
        case .essay: return "논술"
        }
    }

    nonisolated var displayOrder: Int {
        switch self {
        case .unspecified: return 0
        case .korean: return 1
        case .math: return 2
        case .english: return 3
        case .koreanHistory: return 4
        case .socialInquiry: return 5
        case .physics: return 6
        case .chemistry: return 7
        case .biology: return 8
        case .earthScience: return 9
        case .essay: return 10
        }
    }

    fileprivate var matchingTokens: [String] {
        switch self {
        case .unspecified:
            return []
        case .korean:
            return ["국어", "문학", "독서", "화작", "언매"]
        case .math:
            return ["수학", "미적", "기하", "확통", "수1", "수2", "미적분"]
        case .english:
            return ["영어", "영단어", "듣기", "독해", "영문법"]
        case .koreanHistory:
            return ["한국사"]
        case .socialInquiry:
            return ["사문", "생윤", "윤사", "한지", "세지", "정법", "경제", "동사", "세계사", "사회탐구", "사탐"]
        case .physics:
            return ["물리", "역학", "전자기", "물1", "물2"]
        case .chemistry:
            return ["화학", "화1", "화2"]
        case .biology:
            return ["생명", "생물", "생1", "생2"]
        case .earthScience:
            return ["지구과학", "지과", "지1", "지2"]
        case .essay:
            return ["논술", "구술", "면접"]
        }
    }
}

struct StudyMaterialMetadata: Codable, Hashable {
    var catalogEntryID: String?
    var canonicalTitle: String
    var provider: StudyMaterialProvider
    var subject: StudySubject
    var recognitionConfidence: Double
    var recognitionQuery: String?
    var matchedSignals: [String]
}

struct StudyMaterialCatalogEntry: Codable, Hashable, Identifiable {
    var id: String
    var canonicalTitle: String
    var provider: StudyMaterialProvider
    var subject: StudySubject
    var aliases: [String]
}

enum StudySectionStatus: String, Codable, Hashable {
    case upcoming
    case current
    case completed

    nonisolated var title: String {
        switch self {
        case .upcoming:
            return "예정"
        case .current:
            return "진행 중"
        case .completed:
            return "완료"
        }
    }
}

struct StudySectionProgress: Codable, Hashable, Identifiable {
    var id: UUID
    var title: String
    var startPage: Int
    var endPage: Int
    var status: StudySectionStatus
    var completionRatio: Double

    nonisolated var pageCount: Int {
        max(endPage - startPage + 1, 1)
    }

    nonisolated var percentComplete: Int {
        Int((completionRatio * 100).rounded())
    }

    nonisolated func contains(page: Int) -> Bool {
        page >= startPage && page <= endPage
    }
}

struct StudyProgressSnapshot: Codable, Hashable {
    var currentPage: Int
    var totalPages: Int
    var furthestPage: Int
    var completionRatio: Double
    var lastStudiedAt: Date
    var sections: [StudySectionProgress]

    nonisolated var percentComplete: Int {
        Int((completionRatio * 100).rounded())
    }

    nonisolated var totalSectionCount: Int {
        sections.count
    }

    nonisolated var completedSectionCount: Int {
        sections.filter { $0.status == .completed }.count
    }

    nonisolated var currentSection: StudySectionProgress? {
        sections.first(where: { $0.status == .current })
            ?? sections.first(where: { $0.contains(page: currentPage) })
    }

    nonisolated var nextSection: StudySectionProgress? {
        guard let currentSection else {
            return sections.first(where: { $0.status == .upcoming || $0.startPage > currentPage })
        }
        return sections
            .filter { $0.startPage > currentSection.endPage }
            .sorted { $0.startPage < $1.startPage }
            .first
    }

    nonisolated var currentSectionTitle: String? {
        currentSection?.title
    }

    nonisolated var sectionProgressLabel: String? {
        guard totalSectionCount > 0 else { return nil }
        if let currentSection {
            let currentOrdinal = sections.firstIndex(where: { $0.id == currentSection.id }).map { $0 + 1 } ?? (completedSectionCount + 1)
            return "단원 \(min(currentOrdinal, totalSectionCount))/\(totalSectionCount) · \(currentSection.title)"
        }
        if completedSectionCount > 0 {
            return "단원 \(completedSectionCount)/\(totalSectionCount) 완료"
        }
        return "단원 0/\(totalSectionCount)"
    }

    nonisolated var nextSectionTitle: String? {
        nextSection?.title
    }

    nonisolated var dashboardHeadline: String {
        if let sectionProgressLabel {
            return "\(sectionProgressLabel) · \(percentComplete)%"
        }
        return "진도 \(currentPage)/\(max(totalPages, 1)) · \(percentComplete)%"
    }

    nonisolated var dashboardSubheadline: String? {
        guard totalSectionCount > 0 else { return nil }
        var parts: [String] = ["완료 \(completedSectionCount)개"]
        if let nextSectionTitle {
            parts.append("다음 \(nextSectionTitle)")
        }
        return parts.joined(separator: " · ")
    }
}

struct StudyMaterialImportSuggestion: Identifiable, Hashable {
    let id = UUID()
    var normalizedTitle: String
    var pdfTitle: String?
    var provider: StudyMaterialProvider
    var subject: StudySubject
    var confidence: Double
    var matchedSignals: [String]
    var totalPages: Int?
    var sourceQuery: String
    var matchedCatalogEntry: StudyMaterialCatalogEntry?

    var confidenceLabel: String {
        "\(Int((confidence * 100).rounded()))%"
    }

    func resolvedMetadata(title: String, provider: StudyMaterialProvider, subject: StudySubject) -> StudyMaterialMetadata? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }
        return StudyMaterialMetadata(
            catalogEntryID: matchedCatalogEntry?.id,
            canonicalTitle: trimmedTitle,
            provider: provider,
            subject: subject,
            recognitionConfidence: confidence,
            recognitionQuery: sourceQuery,
            matchedSignals: matchedSignals
        )
    }
}

struct StudyMaterialCatalogBundle: Codable {
    var version: Int
    var entries: [StudyMaterialCatalogEntry]
}

final class StudyMaterialCatalogStore {
    static let shared = StudyMaterialCatalogStore()

    let entries: [StudyMaterialCatalogEntry]

    init(bundle: Bundle = .main, entries: [StudyMaterialCatalogEntry]? = nil) {
        if let entries {
            self.entries = entries
        } else if let bundledEntries = Self.loadBundledEntries(from: bundle), !bundledEntries.isEmpty {
            self.entries = bundledEntries
        } else {
            self.entries = Self.defaultEntries
        }
    }

    func bestMatch(for query: String) -> StudyMaterialCatalogEntry? {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return nil }

        return entries
            .map { entry -> (StudyMaterialCatalogEntry, Int) in
                let candidates = [entry.canonicalTitle] + entry.aliases
                let score = candidates.reduce(0) { partial, candidate in
                    let normalizedCandidate = normalize(candidate)
                    if normalizedQuery.contains(normalizedCandidate) || normalizedCandidate.contains(normalizedQuery) {
                        return max(partial, normalizedCandidate.count)
                    }
                    return partial
                }
                return (entry, score)
            }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    if lhs.0.provider.displayOrder == rhs.0.provider.displayOrder {
                        return lhs.0.canonicalTitle.count > rhs.0.canonicalTitle.count
                    }
                    return lhs.0.provider.displayOrder < rhs.0.provider.displayOrder
                }
                return lhs.1 > rhs.1
            }
            .first?
            .0
    }

    var providers: [StudyMaterialProvider] {
        Array(Set(entries.map(\.provider)))
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    var subjects: [StudySubject] {
        Array(Set(entries.map(\.subject)))
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    private func normalize(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func loadBundledEntries(from bundle: Bundle) -> [StudyMaterialCatalogEntry]? {
        guard let url = bundle.url(forResource: "StudyMaterialCatalog", withExtension: "json") else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(StudyMaterialCatalogBundle.self, from: data)
            return decoded.entries
        } catch {
            return nil
        }
    }

    static let defaultEntries: [StudyMaterialCatalogEntry] = [
        StudyMaterialCatalogEntry(id: "sdij-math-core", canonicalTitle: "시대인재북스 수학", provider: .sdijBooks, subject: .math, aliases: ["시대인재북스 수학", "시대인재 수학", "sdij 수학"]),
        StudyMaterialCatalogEntry(id: "sdij-korean-core", canonicalTitle: "시대인재북스 국어", provider: .sdijBooks, subject: .korean, aliases: ["시대인재북스 국어", "시대인재 국어"]),
        StudyMaterialCatalogEntry(id: "sdij-english-core", canonicalTitle: "시대인재북스 영어", provider: .sdijBooks, subject: .english, aliases: ["시대인재북스 영어", "시대인재 영어"]),
        StudyMaterialCatalogEntry(id: "orbi-math-core", canonicalTitle: "오르비북스 수학", provider: .orbiBooks, subject: .math, aliases: ["오르비북스 수학", "orbi books 수학"]),
        StudyMaterialCatalogEntry(id: "ebs-math", canonicalTitle: "EBS 수학", provider: .ebs, subject: .math, aliases: ["수능특강 수학", "수능완성 수학", "ebs 수학"])
    ]
}

final class StudyMaterialRecognizer {
    private let catalogStore: StudyMaterialCatalogStore

    init(catalogStore: StudyMaterialCatalogStore = .shared) {
        self.catalogStore = catalogStore
    }

    func suggest(from sourceURL: URL) -> StudyMaterialImportSuggestion {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileTitle = sourceURL.deletingPathExtension().lastPathComponent
        let pdfTitle = readPDFTitle(from: sourceURL)
        let normalizedTitle = normalizedMaterialTitle(from: pdfTitle ?? fileTitle)
        let searchCorpus = [fileTitle, pdfTitle ?? "", normalizedTitle]
            .joined(separator: " ")
            .lowercased()
        let matchedCatalogEntry = catalogStore.bestMatch(for: searchCorpus)

        let provider = matchedCatalogEntry?.provider ?? guessProvider(in: searchCorpus)
        let subject = matchedCatalogEntry?.subject ?? guessSubject(in: searchCorpus)

        var confidence = 0.2
        var matchedSignals: [String] = []

        if let matchedCatalogEntry {
            confidence += 0.25
            matchedSignals.append("catalog:\(matchedCatalogEntry.canonicalTitle)")
        }

        if provider != .unspecified {
            confidence += 0.3
            matchedSignals.append("provider:\(provider.title)")
        }

        if subject != .unspecified {
            confidence += 0.3
            matchedSignals.append("subject:\(subject.title)")
        }

        if let pdfTitle, !pdfTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            confidence += 0.1
            matchedSignals.append("pdf-title")
        }

        if normalizedTitle != fileTitle {
            confidence += 0.1
            matchedSignals.append("normalized-title")
        }

        let pageCount = PDFDocument(url: sourceURL)?.pageCount

        return StudyMaterialImportSuggestion(
            normalizedTitle: normalizedTitle,
            pdfTitle: pdfTitle,
            provider: provider,
            subject: subject,
            confidence: min(confidence, 0.95),
            matchedSignals: matchedSignals,
            totalPages: pageCount,
            sourceQuery: fileTitle,
            matchedCatalogEntry: matchedCatalogEntry
        )
    }

    private func readPDFTitle(from sourceURL: URL) -> String? {
        guard let pdfDocument = PDFDocument(url: sourceURL) else { return nil }
        let attributes = pdfDocument.documentAttributes
        let rawTitle = attributes?[PDFDocumentAttribute.titleAttribute] as? String
        let trimmed = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func guessProvider(in corpus: String) -> StudyMaterialProvider {
        for provider in StudyMaterialProvider.allCases where provider != .unspecified && provider != .other {
            if provider.matchingTokens.contains(where: { corpus.contains($0.lowercased()) }) {
                if provider == .sdijBooks, corpus.contains("현강") {
                    continue
                }
                return provider
            }
        }

        if corpus.contains("시대인재") {
            return corpus.contains("현강") ? .sdijLecture : .sdijBooks
        }

        return .unspecified
    }

    private func guessSubject(in corpus: String) -> StudySubject {
        for subject in StudySubject.allCases where subject != .unspecified {
            if subject.matchingTokens.contains(where: { corpus.contains($0.lowercased()) }) {
                return subject
            }
        }
        return .unspecified
    }

    private func normalizedMaterialTitle(from rawTitle: String) -> String {
        rawTitle
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"[\[\]\(\)]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
