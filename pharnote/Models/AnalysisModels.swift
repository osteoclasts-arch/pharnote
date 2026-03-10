import CryptoKit
import Foundation

nonisolated struct AnalysisBundle: Codable, Identifiable, Hashable, Sendable {
    var bundleVersion: Int
    var bundleId: UUID
    var createdAt: Date
    var sourceApp: String
    var scope: AnalysisScope
    var document: AnalysisDocumentContext
    var page: AnalysisPageContext
    var content: AnalysisContentContext
    var behavior: AnalysisBehaviorContext
    var context: AnalysisExecutionContext
    var privacy: AnalysisPrivacyContext

    var id: UUID { bundleId }
}

nonisolated enum AnalysisScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case page
    case selection
    case session
    case documentSegment = "document-segment"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .page: return "현재 페이지"
        case .selection: return "선택 영역"
        case .session: return "최근 세션"
        case .documentSegment: return "인접 페이지"
        }
    }
    
    var shortDescription: String {
        switch self {
        case .page: return "현재 페이지 기준으로 분석합니다."
        case .selection: return "선택된 일부 영역만 분석합니다."
        case .session: return "최근 학습 흐름 전체를 묶습니다."
        case .documentSegment: return "현재 페이지와 인접 맥락을 함께 봅니다."
        }
    }
}

nonisolated enum AnalysisStudyIntent: String, Codable, CaseIterable, Identifiable, Sendable {
    case lecture
    case problemSolving = "problem_solving"
    case summary
    case review
    case examPrep = "exam_prep"
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lecture: return "강의 필기"
        case .problemSolving: return "문제 풀이"
        case .summary: return "개념 정리"
        case .review: return "복습"
        case .examPrep: return "시험 대비"
        case .unknown: return "미정"
        }
    }
}

nonisolated struct AnalysisDocumentContext: Codable, Hashable, Sendable {
    var documentId: UUID
    var documentType: PharDocument.DocumentType
    var title: String
    var subject: String?
    var collectionId: String?
    var sourceFingerprint: String?
}

nonisolated struct AnalysisPageContext: Codable, Hashable, Sendable {
    var pageId: UUID
    var pageIndex: Int
    var pageCount: Int
    var selectionRect: AnalysisRect?
    var template: String?
    var pageState: [String]
}

nonisolated struct AnalysisRect: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

nonisolated struct AnalysisContentContext: Codable, Hashable, Sendable {
    var previewImageRef: String?
    var drawingRef: String?
    var drawingStats: AnalysisDrawingStats
    var typedBlocks: [AnalysisTextBlock]
    var pdfTextBlocks: [AnalysisTextBlock]
    var ocrTextBlocks: [AnalysisTextBlock]
    var manualTags: [String]
    var bookmarks: [String]
}

nonisolated struct AnalysisDrawingStats: Codable, Hashable, Sendable {
    var strokeCount: Int
    var inkLengthEstimate: Double
    var eraseRatio: Double
    var highlightCoverage: Double
}

nonisolated struct AnalysisTextBlock: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var kind: String
    var text: String
    var pageIndex: Int

    init(kind: String, text: String, pageIndex: Int) {
        self.id = UUID()
        self.kind = kind
        self.text = text
        self.pageIndex = pageIndex
    }
}

nonisolated struct AnalysisBehaviorContext: Codable, Hashable, Sendable {
    var sessionId: UUID?
    var studyIntent: AnalysisStudyIntent
    var dwellMs: Int
    var foregroundEditsMs: Int
    var revisitCount: Int
    var toolUsage: [AnalysisToolUsage]
    var lassoActions: Int
    var copyActions: Int
    var pasteActions: Int
    var undoCount: Int
    var redoCount: Int
    var zoomEventCount: Int
    var navigationPath: [String]
}

nonisolated struct AnalysisToolUsage: Codable, Hashable, Sendable, Identifiable {
    var id: String { tool }
    var tool: String
    var count: Int
}

nonisolated struct AnalysisExecutionContext: Codable, Hashable, Sendable {
    var previousPageIds: [UUID]
    var nextPageIds: [UUID]
    var previousAnalysisIds: [UUID]
    var examDate: Date?
    var locale: String
    var timezone: String
}

nonisolated struct AnalysisPrivacyContext: Codable, Hashable, Sendable {
    var containsPdfText: Bool
    var containsHandwriting: Bool
    var userInitiated: Bool
}

nonisolated enum AnalysisRequestStatus: String, Codable, Hashable, Sendable {
    case queued
    case failed
    case completed
}

nonisolated struct AnalysisQueueEntry: Codable, Hashable, Identifiable, Sendable {
    var bundleId: UUID
    var createdAt: Date
    var documentId: UUID
    var documentTitle: String
    var documentType: PharDocument.DocumentType
    var pageLabel: String
    var studyIntent: AnalysisStudyIntent
    var scope: AnalysisScope
    var status: AnalysisRequestStatus
    var bundleFilePath: String
    var lastErrorMessage: String?

    var id: UUID { bundleId }
}

nonisolated struct AnalysisResult: Codable, Hashable, Identifiable, Sendable {
    var analysisId: UUID
    var bundleId: UUID
    var createdAt: Date
    var documentId: UUID
    var pageId: UUID
    var summary: AnalysisResultSummary
    var classification: AnalysisClassification?
    var conceptNodes: [AnalysisConceptNode]
    var misconceptionCandidates: [AnalysisMisconceptionCandidate]
    var recommendedActions: [AnalysisRecommendedAction]
    var reviewPlan: AnalysisReviewPlan
    var badges: [AnalysisBadge]
    var derivedSignals: AnalysisDerivedSignals
    var evidence: [AnalysisEvidenceItem]?
    var pipeline: AnalysisPipelineMetadata?

    var id: UUID { analysisId }
}

nonisolated struct AnalysisInspection: Identifiable, Hashable, Sendable {
    var entry: AnalysisQueueEntry
    var bundle: AnalysisBundle
    var result: AnalysisResult?
    var bundleJSON: String
    var resultJSON: String?

    var id: UUID { entry.bundleId }
}

nonisolated struct AnalysisResultSummary: Codable, Hashable, Sendable {
    var headline: String
    var body: String
    var masteryScore: Double
    var confidenceScore: Double
}

nonisolated struct AnalysisClassification: Codable, Hashable, Sendable {
    var studyMode: AnalysisDetectedStudyMode
    var pageRole: AnalysisPageRole
    var subjectLabel: String?
    var unitLabel: String?
    var confidenceScore: Double
}

nonisolated enum AnalysisDetectedStudyMode: String, Codable, Hashable, Sendable {
    case conceptSummary = "concept_summary"
    case problemSolving = "problem_solving"
    case memorization
    case lectureNotes = "lecture_notes"
    case review
    case mixed
    case uncertain

    var title: String {
        switch self {
        case .conceptSummary: return "개념 정리"
        case .problemSolving: return "문제 풀이"
        case .memorization: return "암기 세션"
        case .lectureNotes: return "강의 필기"
        case .review: return "복습"
        case .mixed: return "혼합 학습"
        case .uncertain: return "분류 미정"
        }
    }
}

nonisolated enum AnalysisPageRole: String, Codable, Hashable, Sendable {
    case summaryPage = "summary_page"
    case problemPage = "problem_page"
    case correctionPage = "correction_page"
    case lecturePage = "lecture_page"
    case flashcardPage = "flashcard_page"
    case referencePage = "reference_page"
    case mixedPage = "mixed_page"

    var title: String {
        switch self {
        case .summaryPage: return "요약 페이지"
        case .problemPage: return "문제 페이지"
        case .correctionPage: return "오답/교정 페이지"
        case .lecturePage: return "강의 필기 페이지"
        case .flashcardPage: return "암기 페이지"
        case .referencePage: return "참조 페이지"
        case .mixedPage: return "혼합 페이지"
        }
    }
}

nonisolated struct AnalysisEvidenceItem: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var detail: String
    var strength: Double
}

nonisolated struct AnalysisPipelineMetadata: Codable, Hashable, Sendable {
    var engineVersion: String
    var normalizedAt: Date
    var featureVersion: Int
}

nonisolated struct AnalysisConceptNode: Codable, Hashable, Identifiable, Sendable {
    var id: String { nodeId }
    var nodeId: String
    var label: String
    var masteryScore: Double
    var confidenceScore: Double
}

nonisolated struct AnalysisMisconceptionCandidate: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var label: String
    var reason: String
    var severity: Double
}

nonisolated struct AnalysisRecommendedAction: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var detail: String
    var style: AnalysisActionStyle
}

nonisolated enum AnalysisActionStyle: String, Codable, Hashable, Sendable {
    case revisit
    case practice
    case summarize
    case inspectInPharnode = "inspect_in_pharnode"
}

nonisolated struct AnalysisReviewPlan: Codable, Hashable, Sendable {
    var shouldReviewSoon: Bool
    var recommendedHoursUntilReview: Int
    var reviewReason: String
}

nonisolated enum AnalysisReviewTaskStatus: String, Codable, Hashable, CaseIterable, Sendable {
    case pending
    case completed
    case dismissed

    var title: String {
        switch self {
        case .pending: return "대기"
        case .completed: return "완료"
        case .dismissed: return "제외"
        }
    }
}

nonisolated enum AnalysisReviewTaskKind: String, Codable, Hashable, CaseIterable, Sendable {
    case revisitPage = "revisit_page"
    case practiceConcept = "practice_concept"
    case restructureNotes = "restructure_notes"

    var title: String {
        switch self {
        case .revisitPage: return "페이지 재확인"
        case .practiceConcept: return "개념 연습"
        case .restructureNotes: return "노트 재구성"
        }
    }
}

nonisolated struct AnalysisReviewTask: Codable, Hashable, Identifiable, Sendable {
    var taskId: UUID
    var createdAt: Date
    var updatedAt: Date
    var dueAt: Date
    var status: AnalysisReviewTaskStatus
    var kind: AnalysisReviewTaskKind
    var analysisId: UUID
    var bundleId: UUID
    var documentId: UUID
    var pageId: UUID
    var documentTitle: String
    var pageLabel: String
    var title: String
    var detail: String
    var subjectLabel: String?
    var unitLabel: String?
    var conceptLabel: String?

    var id: UUID { taskId }

    var isDueSoon: Bool {
        status == .pending && dueAt <= Date().addingTimeInterval(60 * 60 * 12)
    }
}

nonisolated struct AnalysisBadge: Codable, Hashable, Identifiable, Sendable {
    var id: String { kind.rawValue + ":" + title }
    var kind: AnalysisBadgeKind
    var title: String
}

nonisolated enum AnalysisBadgeKind: String, Codable, Hashable, Sendable {
    case analyzed
    case reviewDue = "review_due"
    case lowConfidence = "low_confidence"
    case needsPractice = "needs_practice"
    case wellUnderstood = "well_understood"
}

nonisolated struct AnalysisDerivedSignals: Codable, Hashable, Sendable {
    var engagementScore: Double
    var struggleScore: Double
    var coverageScore: Double
    var isDensePage: Bool
    var hasMeaningfulInk: Bool
}

nonisolated struct BlankNoteAnalysisSource: Sendable {
    var document: PharDocument
    var pageId: UUID
    var pageIndex: Int
    var pageCount: Int
    var previousPageIds: [UUID]
    var nextPageIds: [UUID]
    var pageState: [String]
    var previewImageData: Data?
    var drawingData: Data?
    var drawingStats: AnalysisDrawingStats
    var manualTags: [String]
    var bookmarks: [String]
    var sessionId: UUID
    var dwellMs: Int
    var foregroundEditsMs: Int
    var revisitCount: Int
    var toolUsage: [AnalysisToolUsage]
    var lassoActions: Int
    var copyActions: Int
    var pasteActions: Int
    var undoCount: Int
    var redoCount: Int
    var navigationPath: [String]
}

nonisolated struct PDFPageAnalysisSource: Sendable {
    var document: PharDocument
    var pageId: UUID
    var pageIndex: Int
    var pageCount: Int
    var previousPageIds: [UUID]
    var nextPageIds: [UUID]
    var pageState: [String]
    var previewImageData: Data?
    var drawingData: Data?
    var drawingStats: AnalysisDrawingStats
    var pdfTextBlocks: [AnalysisTextBlock]
    var manualTags: [String]
    var bookmarks: [String]
    var sessionId: UUID
    var dwellMs: Int
    var foregroundEditsMs: Int
    var revisitCount: Int
    var toolUsage: [AnalysisToolUsage]
    var lassoActions: Int
    var copyActions: Int
    var pasteActions: Int
    var undoCount: Int
    var redoCount: Int
    var zoomEventCount: Int
    var navigationPath: [String]
    var sourceFingerprint: String?
}

nonisolated enum AnalysisBundleAssetName {
    static let previewImage = "preview.png"
    static let drawingData = "drawing.data"
}

extension UUID {
    nonisolated static func stableAnalysisPageID(namespace: UUID, pageIndex: Int) -> UUID {
        let input = "\(namespace.uuidString.lowercased())::page::\(pageIndex)"
        let digest = SHA256.hash(data: Data(input.utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    nonisolated static func stableAnalysisTaskID(namespace: UUID, key: String) -> UUID {
        let input = "\(namespace.uuidString.lowercased())::task::\(key.lowercased())"
        let digest = SHA256.hash(data: Data(input.utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
