import CryptoKit
import Foundation

nonisolated struct ProblemSelectionPoint: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
}

nonisolated struct ProblemSelectionBoundingBox: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    nonisolated var isValid: Bool {
        width > 0.01 && height > 0.01
    }
}

nonisolated enum ProblemSelectionType: String, Codable, CaseIterable, Hashable, Sendable {
    case wholeProblem
    case candidateProblem
    case refinement
}

nonisolated enum ProblemSelectionRecognitionStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case idle
    case matching
    case matched
    case ambiguous
    case failed
}

nonisolated struct ProblemSelection: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var documentId: UUID
    var pageId: UUID
    var pageIndex: Int
    var selectionType: ProblemSelectionType
    var polygon: [ProblemSelectionPoint]
    var boundingBox: ProblemSelectionBoundingBox
    var createdAt: Date
    var updatedAt: Date
    var recognitionStatus: ProblemSelectionRecognitionStatus
    var recognitionText: String?
    var pageTextFingerprint: String?
    var recognizedMatch: ProblemMatch?

    nonisolated var selectionSignature: String {
        let points = polygon
            .map { String(format: "%.4f,%.4f", $0.x, $0.y) }
            .joined(separator: "|")
        let box = String(
            format: "%.4f,%.4f,%.4f,%.4f",
            boundingBox.x,
            boundingBox.y,
            boundingBox.width,
            boundingBox.height
        )
        return sha256Hex(
            [
                documentId.uuidString.lowercased(),
                pageId.uuidString.lowercased(),
                String(pageIndex),
                selectionType.rawValue,
                box,
                points
            ].joined(separator: "::")
        )
    }

    nonisolated var resumeKey: String {
        [documentId.uuidString.lowercased(), pageId.uuidString.lowercased(), selectionSignature]
            .joined(separator: "::")
    }

    nonisolated var isLargeEnough: Bool {
        boundingBox.width >= 0.04 && boundingBox.height >= 0.04
    }

    private nonisolated func sha256Hex(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

nonisolated enum ProblemMatchMethod: String, Codable, CaseIterable, Hashable, Sendable {
    case directMetadata
    case ocrText
    case subjectQuestionNumber
    case fuzzySearch
    case manualChoice
}

nonisolated struct ProblemMatchCandidate: Codable, Hashable, Identifiable, Sendable {
    var id: String { canonicalProblemId }
    var examId: String
    var subject: StudySubject
    var year: Int
    var sessionType: String
    var problemNumber: Int
    var canonicalProblemId: String
    var confidence: Double
    var matchMethod: ProblemMatchMethod
    var displayTitle: String
    var reason: String?

    nonisolated func asMatch() -> ProblemMatch {
        ProblemMatch(
            examId: examId,
            subject: subject,
            year: year,
            sessionType: sessionType,
            problemNumber: problemNumber,
            canonicalProblemId: canonicalProblemId,
            confidence: confidence,
            matchMethod: matchMethod,
            displayTitle: displayTitle,
            recognitionText: reason,
            candidateAlternatives: nil
        )
    }
}

nonisolated struct ProblemMatch: Codable, Hashable, Identifiable, Sendable {
    var id: String { canonicalProblemId }
    var examId: String
    var subject: StudySubject
    var year: Int
    var sessionType: String
    var problemNumber: Int
    var canonicalProblemId: String
    var confidence: Double
    var matchMethod: ProblemMatchMethod
    var displayTitle: String
    var recognitionText: String?
    var candidateAlternatives: [ProblemMatchCandidate]?
}

nonisolated struct ProblemRecognitionHint: Codable, Hashable, Sendable {
    var examId: String?
    var canonicalProblemId: String?
    var year: Int?
    var sessionType: String?
    var problemNumber: Int?
    var subject: StudySubject?
    var confidence: Double?
}

nonisolated struct ProblemRecognitionResult: Codable, Hashable, Sendable {
    var selectionId: UUID
    var bestMatch: ProblemMatch?
    var candidates: [ProblemMatchCandidate]
    var confidence: Double
    var status: ProblemSelectionRecognitionStatus
    var recognitionText: String?
    var reason: String?
}

nonisolated enum ReviewSessionStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case draft
    case inProgress = "in_progress"
    case completed
    case abandoned
}

nonisolated enum ReviewAutosaveStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case idle
    case saving
    case saved
    case retryNeeded = "retry_needed"
}

nonisolated struct ReviewAnswer: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var stepId: String
    var selectedOptionIds: [String]
    var freeText: String?
    var createdAt: Date
    var updatedAt: Date
}

nonisolated struct DerivedReviewEvidence: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var subject: StudySubject
    var evidenceType: String
    var nodeId: String?
    var internalTag: String?
    var confidence: Double
    var sourceStepId: String
    var label: String
    var createdAt: Date
}

nonisolated struct ReviewSchemaOption: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var internalTag: String
    var analysisStatus: AnalysisReviewStepStatus
    var evidenceType: String
    var confidenceHint: Double
    var nodeId: String?
}

nonisolated struct ReviewSchemaStep: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var prompt: String
    var options: [ReviewSchemaOption]
    var allowsFreeText: Bool
    var supportsMultipleSelection: Bool
}

nonisolated struct ReviewSchema: Codable, Hashable, Sendable {
    var subject: StudySubject
    var version: Int
    var title: String
    var steps: [ReviewSchemaStep]

    func step(for id: String) -> ReviewSchemaStep? {
        steps.first(where: { $0.id == id })
    }

    func option(for stepId: String, optionId: String) -> ReviewSchemaOption? {
        step(for: stepId)?.options.first(where: { $0.id == optionId })
    }
}

nonisolated struct ReviewSession: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var userId: String?
    var documentId: UUID
    var pageId: UUID
    var pageIndex: Int
    var selectionId: UUID
    var selection: ProblemSelection
    var canonicalProblemId: String?
    var problemMatch: ProblemMatch?
    var subject: StudySubject
    var status: ReviewSessionStatus
    var startedAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var schemaVersion: Int
    var answers: [ReviewAnswer]
    var derivedTags: [DerivedReviewEvidence]
    var autosaveVersion: Int
    var lastAutosavedAt: Date?
    var lastAutosaveErrorMessage: String?

    nonisolated var resumeKey: String {
        let problemKey = trimmed(canonicalProblemId)
            ?? trimmed(problemMatch?.canonicalProblemId)
            ?? selection.selectionSignature
        return [
            documentId.uuidString.lowercased(),
            pageId.uuidString.lowercased(),
            problemKey
        ].joined(separator: "::")
    }

    nonisolated var displayTitle: String {
        if let problemMatch {
            return problemMatch.displayTitle
        }
        return "\(subject.title) 복기"
    }

    nonisolated var isCompleted: Bool {
        status == .completed
    }

    private nonisolated func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

nonisolated struct ReviewSessionStorePayload: Codable, Sendable {
    var sessions: [ReviewSession]
}

nonisolated struct ReviewSchemaRegistry {
    static let schemaVersion = 1

    static func schema(for subject: StudySubject) -> ReviewSchema {
        switch subject {
        case .korean:
            return koreanSchema()
        case .math:
            return mathSchema()
        default:
            return fallbackSchema(subject: subject)
        }
    }

    static func analysisSubjectType(for subject: StudySubject) -> AnalysisReviewSubjectType {
        switch subject {
        case .math:
            return .math
        case .korean, .essay:
            return .korean
        case .english:
            return .english
        case .koreanHistory, .socialInquiry, .physics, .chemistry, .biology, .earthScience:
            return .inquiry
        case .unspecified:
            return .unknown
        }
    }

    static func displayTitle(for subject: StudySubject) -> String {
        switch subject {
        case .korean:
            return "국어 복기"
        case .math:
            return "수학 복기"
        default:
            return "\(subject.title) 복기"
        }
    }

    private static func koreanSchema() -> ReviewSchema {
        ReviewSchema(
            subject: .korean,
            version: schemaVersion,
            title: "국어 복기",
            steps: [
                ReviewSchemaStep(
                    id: "stuck_point",
                    title: "어디서 가장 막혔나요?",
                    prompt: "가장 이해가 끊긴 지점을 눌러주세요.",
                    options: [
                        ReviewSchemaOption(id: "korean_passage", title: "지문 전체", internalTag: "ST-01", analysisStatus: .failed, evidenceType: "passage", confidenceHint: 0.72, nodeId: "ST-01"),
                        ReviewSchemaOption(id: "korean_paragraph", title: "특정 문단", internalTag: "ST-01", analysisStatus: .failed, evidenceType: "paragraph", confidenceHint: 0.75, nodeId: "ST-01"),
                        ReviewSchemaOption(id: "korean_bogi", title: "보기", internalTag: "AP-03", analysisStatus: .partial, evidenceType: "choice-context", confidenceHint: 0.8, nodeId: "AP-03"),
                        ReviewSchemaOption(id: "korean_choice_compare", title: "선지 비교", internalTag: "CV-01", analysisStatus: .partial, evidenceType: "choice-compare", confidenceHint: 0.76, nodeId: "CV-01"),
                        ReviewSchemaOption(id: "korean_vague", title: "전체적으로 애매", internalTag: "KI-01", analysisStatus: .partial, evidenceType: "global-comprehension", confidenceHint: 0.64, nodeId: "KI-01"),
                        ReviewSchemaOption(id: "korean_time", title: "시간 부족", internalTag: "TIME-01", analysisStatus: .partial, evidenceType: "timing", confidenceHint: 0.6, nodeId: "TIME-01")
                    ],
                    allowsFreeText: false,
                    supportsMultipleSelection: false
                ),
                ReviewSchemaStep(
                    id: "why_hard",
                    title: "왜 그 부분이 어려웠나요?",
                    prompt: "학생 입장에서 가장 가까운 이유를 골라주세요.",
                    options: [
                        ReviewSchemaOption(id: "korean_sentence_meaning", title: "문장 자체가 어려움", internalTag: "ST-01", analysisStatus: .failed, evidenceType: "sentence-meaning", confidenceHint: 0.7, nodeId: "ST-01"),
                        ReviewSchemaOption(id: "korean_flow", title: "흐름이 안 보임", internalTag: "ST-02", analysisStatus: .failed, evidenceType: "flow", confidenceHint: 0.7, nodeId: "ST-02"),
                        ReviewSchemaOption(id: "korean_key_point", title: "핵심이 안 잡힘", internalTag: "KI-01", analysisStatus: .failed, evidenceType: "key-point", confidenceHint: 0.66, nodeId: "KI-01"),
                        ReviewSchemaOption(id: "korean_position", title: "입장이 헷갈림", internalTag: "ST-02", analysisStatus: .partial, evidenceType: "speaker-position", confidenceHint: 0.68, nodeId: "ST-02"),
                        ReviewSchemaOption(id: "korean_apply_bogi", title: "연결이 안 됨", internalTag: "AP-03", analysisStatus: .partial, evidenceType: "application", confidenceHint: 0.7, nodeId: "AP-03"),
                        ReviewSchemaOption(id: "korean_similar", title: "선지에 적용이 안 됨", internalTag: "CV-05", analysisStatus: .partial, evidenceType: "choice-application", confidenceHint: 0.73, nodeId: "CV-05")
                    ],
                    allowsFreeText: false,
                    supportsMultipleSelection: false
                ),
                ReviewSchemaStep(
                    id: "cause_miss",
                    title: "무엇 때문에 결국 틀렸나요?",
                    prompt: "가장 직접적인 원인을 골라주세요.",
                    options: [
                        ReviewSchemaOption(id: "korean_passage_understanding", title: "지문 이해 부족", internalTag: "ST-01", analysisStatus: .failed, evidenceType: "understanding", confidenceHint: 0.72, nodeId: "ST-01"),
                        ReviewSchemaOption(id: "korean_key_failure", title: "핵심 파악 실패", internalTag: "KI-01", analysisStatus: .failed, evidenceType: "key-point", confidenceHint: 0.7, nodeId: "KI-01"),
                        ReviewSchemaOption(id: "korean_apply_failure", title: "보기 적용 실패", internalTag: "AP-03", analysisStatus: .failed, evidenceType: "application", confidenceHint: 0.78, nodeId: "AP-03"),
                        ReviewSchemaOption(id: "korean_choice_confusion", title: "선지 헷갈림", internalTag: "CV-01", analysisStatus: .partial, evidenceType: "choice-judgment", confidenceHint: 0.74, nodeId: "CV-01"),
                        ReviewSchemaOption(id: "korean_overclaim", title: "과장된 선지에 속음", internalTag: "CV-01", analysisStatus: .partial, evidenceType: "overclaim", confidenceHint: 0.82, nodeId: "CV-01"),
                        ReviewSchemaOption(id: "korean_no_basis", title: "근거 없이 선택", internalTag: "CV-05", analysisStatus: .failed, evidenceType: "evidence-gap", confidenceHint: 0.8, nodeId: "CV-05"),
                        ReviewSchemaOption(id: "korean_time_pressure", title: "시간 부족", internalTag: "TIME-01", analysisStatus: .partial, evidenceType: "timing", confidenceHint: 0.6, nodeId: "TIME-01")
                    ],
                    allowsFreeText: false,
                    supportsMultipleSelection: false
                )
            ]
        )
    }

    private static func mathSchema() -> ReviewSchema {
        ReviewSchema(
            subject: .math,
            version: schemaVersion,
            title: "수학 복기",
            steps: [
                ReviewSchemaStep(
                    id: "stuck_point",
                    title: "어디서 가장 막혔나요?",
                    prompt: "가장 먼저 멈춘 지점을 눌러주세요.",
                    options: [
                        ReviewSchemaOption(id: "math_condition", title: "조건 이해", internalTag: "MATH-COND-01", analysisStatus: .failed, evidenceType: "condition", confidenceHint: 0.78, nodeId: "MATH-COND-01"),
                        ReviewSchemaOption(id: "math_setup", title: "풀이 세팅", internalTag: "MATH-APP-01", analysisStatus: .partial, evidenceType: "setup", confidenceHint: 0.75, nodeId: "MATH-APP-01"),
                        ReviewSchemaOption(id: "math_transform", title: "식 변형", internalTag: "MATH-EXEC-01", analysisStatus: .failed, evidenceType: "transformation", confidenceHint: 0.8, nodeId: "MATH-EXEC-01"),
                        ReviewSchemaOption(id: "math_graph", title: "그래프/그림 해석", internalTag: "MATH-COND-02", analysisStatus: .partial, evidenceType: "visual", confidenceHint: 0.73, nodeId: "MATH-COND-02"),
                        ReviewSchemaOption(id: "math_choice", title: "선지 비교", internalTag: "MATH-JUDGE-01", analysisStatus: .partial, evidenceType: "choice-compare", confidenceHint: 0.7, nodeId: "MATH-JUDGE-01"),
                        ReviewSchemaOption(id: "math_time", title: "시간 부족", internalTag: "TIME-01", analysisStatus: .partial, evidenceType: "timing", confidenceHint: 0.58, nodeId: "TIME-01")
                    ],
                    allowsFreeText: false,
                    supportsMultipleSelection: false
                ),
                ReviewSchemaStep(
                    id: "what_missed",
                    title: "무엇을 놓쳤나요?",
                    prompt: "학생 입장에서 가장 직접적인 누락을 골라주세요.",
                    options: [
                        ReviewSchemaOption(id: "math_missed_condition", title: "중요한 조건을 놓침", internalTag: "MATH-COND-01", analysisStatus: .failed, evidenceType: "condition", confidenceHint: 0.8, nodeId: "MATH-COND-01"),
                        ReviewSchemaOption(id: "math_saw_but_not_action", title: "조건은 봤지만 어떻게 할지 몰랐음", internalTag: "MATH-DOCTRINE-01", analysisStatus: .partial, evidenceType: "doctrine", confidenceHint: 0.76, nodeId: "MATH-DOCTRINE-01"),
                        ReviewSchemaOption(id: "math_connect_conditions", title: "조건들을 연결 못함", internalTag: "MATH-COND-02", analysisStatus: .failed, evidenceType: "connection", confidenceHint: 0.74, nodeId: "MATH-COND-02"),
                        ReviewSchemaOption(id: "math_knew_method", title: "방법은 알았지만 못 풀었음", internalTag: "MATH-EXEC-01", analysisStatus: .failed, evidenceType: "execution", confidenceHint: 0.78, nodeId: "MATH-EXEC-01"),
                        ReviewSchemaOption(id: "math_calc_mistake", title: "계산/정리 실수", internalTag: "MATH-EXEC-02", analysisStatus: .partial, evidenceType: "calculation", confidenceHint: 0.68, nodeId: "MATH-EXEC-02"),
                        ReviewSchemaOption(id: "math_switch_late", title: "방향을 너무 늦게 바꿈", internalTag: "MATH-JUDGE-01", analysisStatus: .partial, evidenceType: "judgment", confidenceHint: 0.66, nodeId: "MATH-JUDGE-01")
                    ],
                    allowsFreeText: false,
                    supportsMultipleSelection: false
                ),
                ReviewSchemaStep(
                    id: "best_explains",
                    title: "무엇이 가장 잘 설명하나요?",
                    prompt: "이번 오답/막힘을 가장 잘 설명하는 원인을 골라주세요.",
                    options: [
                        ReviewSchemaOption(id: "math_condition_issue", title: "조건 감지 실패", internalTag: "MATH-COND-01", analysisStatus: .failed, evidenceType: "condition", confidenceHint: 0.8, nodeId: "MATH-COND-01"),
                        ReviewSchemaOption(id: "math_doctrine_issue", title: "도식/도구 회상 실패", internalTag: "MATH-DOCTRINE-01", analysisStatus: .partial, evidenceType: "doctrine", confidenceHint: 0.74, nodeId: "MATH-DOCTRINE-01"),
                        ReviewSchemaOption(id: "math_approach_issue", title: "풀이 방향 선택 실패", internalTag: "MATH-APP-01", analysisStatus: .partial, evidenceType: "approach", confidenceHint: 0.76, nodeId: "MATH-APP-01"),
                        ReviewSchemaOption(id: "math_execution_issue", title: "전개/계산 문제", internalTag: "MATH-EXEC-01", analysisStatus: .failed, evidenceType: "execution", confidenceHint: 0.8, nodeId: "MATH-EXEC-01"),
                        ReviewSchemaOption(id: "math_choice_issue", title: "선지 판단 문제", internalTag: "MATH-JUDGE-01", analysisStatus: .partial, evidenceType: "choice-judgment", confidenceHint: 0.7, nodeId: "MATH-JUDGE-01"),
                        ReviewSchemaOption(id: "math_time_issue", title: "시간 부족", internalTag: "TIME-01", analysisStatus: .partial, evidenceType: "timing", confidenceHint: 0.6, nodeId: "TIME-01")
                    ],
                    allowsFreeText: false,
                    supportsMultipleSelection: false
                )
            ]
        )
    }

    private static func fallbackSchema(subject: StudySubject) -> ReviewSchema {
        ReviewSchema(
            subject: subject,
            version: schemaVersion,
            title: "\(subject.title) 복기",
            steps: [
                ReviewSchemaStep(
                    id: "stuck_point",
                    title: "어디서 막혔나요?",
                    prompt: "가장 먼저 멈춘 지점을 골라주세요.",
                    options: [
                        ReviewSchemaOption(id: "fallback_reading", title: "읽는 단계", internalTag: "GEN-READ-01", analysisStatus: .failed, evidenceType: "reading", confidenceHint: 0.7, nodeId: "GEN-READ-01"),
                        ReviewSchemaOption(id: "fallback_setup", title: "시작/세팅 단계", internalTag: "GEN-SETUP-01", analysisStatus: .partial, evidenceType: "setup", confidenceHint: 0.7, nodeId: "GEN-SETUP-01"),
                        ReviewSchemaOption(id: "fallback_execution", title: "전개 단계", internalTag: "GEN-EXEC-01", analysisStatus: .failed, evidenceType: "execution", confidenceHint: 0.7, nodeId: "GEN-EXEC-01"),
                        ReviewSchemaOption(id: "fallback_choice", title: "선지/판단 단계", internalTag: "GEN-JUDGE-01", analysisStatus: .partial, evidenceType: "judgment", confidenceHint: 0.7, nodeId: "GEN-JUDGE-01")
                    ],
                    allowsFreeText: false,
                    supportsMultipleSelection: false
                ),
                ReviewSchemaStep(
                    id: "what_missed",
                    title: "무엇을 놓쳤나요?",
                    prompt: "가장 직접적인 누락을 골라주세요.",
                    options: [
                        ReviewSchemaOption(id: "fallback_condition", title: "조건/정보", internalTag: "GEN-COND-01", analysisStatus: .failed, evidenceType: "condition", confidenceHint: 0.7, nodeId: "GEN-COND-01"),
                        ReviewSchemaOption(id: "fallback_rule", title: "규칙/개념", internalTag: "GEN-DOCTRINE-01", analysisStatus: .partial, evidenceType: "doctrine", confidenceHint: 0.7, nodeId: "GEN-DOCTRINE-01"),
                        ReviewSchemaOption(id: "fallback_execution", title: "실행/계산", internalTag: "GEN-EXEC-01", analysisStatus: .failed, evidenceType: "execution", confidenceHint: 0.7, nodeId: "GEN-EXEC-01"),
                        ReviewSchemaOption(id: "fallback_judgment", title: "판단/선택", internalTag: "GEN-JUDGE-01", analysisStatus: .partial, evidenceType: "judgment", confidenceHint: 0.7, nodeId: "GEN-JUDGE-01")
                    ],
                    allowsFreeText: false,
                    supportsMultipleSelection: false
                ),
                ReviewSchemaStep(
                    id: "cause",
                    title: "무엇이 가장 잘 설명하나요?",
                    prompt: "이번 막힘을 가장 잘 설명하는 원인을 골라주세요.",
                    options: [
                        ReviewSchemaOption(id: "fallback_condition_issue", title: "조건 이해 문제", internalTag: "GEN-COND-01", analysisStatus: .failed, evidenceType: "condition", confidenceHint: 0.7, nodeId: "GEN-COND-01"),
                        ReviewSchemaOption(id: "fallback_doctrine_issue", title: "개념/규칙 회상 문제", internalTag: "GEN-DOCTRINE-01", analysisStatus: .partial, evidenceType: "doctrine", confidenceHint: 0.7, nodeId: "GEN-DOCTRINE-01"),
                        ReviewSchemaOption(id: "fallback_application_issue", title: "적용 문제", internalTag: "GEN-APP-01", analysisStatus: .partial, evidenceType: "application", confidenceHint: 0.7, nodeId: "GEN-APP-01"),
                        ReviewSchemaOption(id: "fallback_time_issue", title: "시간 부족", internalTag: "TIME-01", analysisStatus: .partial, evidenceType: "timing", confidenceHint: 0.6, nodeId: "TIME-01")
                    ],
                    allowsFreeText: false,
                    supportsMultipleSelection: false
                )
            ]
        )
    }
}

extension StudySubject {
    nonisolated var reviewSchemaSubject: StudySubject {
        switch self {
        case .essay:
            return .korean
        default:
            return self
        }
    }
}
