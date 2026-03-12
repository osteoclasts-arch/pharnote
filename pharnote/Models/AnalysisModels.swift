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

nonisolated struct OCRPreviewSummary: Hashable, Sendable {
    var recognizedBlockCount: Int
    var scannedPageBlockCount: Int
    var handwritingBlockCount: Int
    var recognizedCharacterCount: Int
    var topLines: [String]
    var problemCandidates: [String]
    var hasMathSignal: Bool
}

nonisolated enum AnalysisReviewSubjectType: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case math
    case korean
    case english
    case inquiry
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .math:
            return "수학"
        case .korean:
            return "국어"
        case .english:
            return "영어"
        case .inquiry:
            return "탐구"
        case .unknown:
            return "미지정"
        }
    }

    init(studySubject: StudySubject?) {
        switch studySubject {
        case .math?:
            self = .math
        case .korean?, .essay?:
            self = .korean
        case .english?:
            self = .english
        case .koreanHistory?, .socialInquiry?, .physics?, .chemistry?, .biology?, .earthScience?:
            self = .inquiry
        default:
            self = .unknown
        }
    }
}

nonisolated enum AnalysisReviewStepStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case clear
    case partial
    case failed
    case notTried = "not_tried"

    var title: String {
        switch self {
        case .clear:
            return "명확"
        case .partial:
            return "애매"
        case .failed:
            return "막힘"
        case .notTried:
            return "안 함"
        }
    }
}

nonisolated struct AnalysisReviewStepResponse: Codable, Hashable, Sendable, Identifiable {
    var stepId: String
    var status: AnalysisReviewStepStatus
    var selectedOptionId: String?

    var id: String { stepId }
}

nonisolated struct AnalysisPostSolveReview: Codable, Hashable, Sendable {
    var subject: AnalysisReviewSubjectType
    var confidenceAfter: Int?
    var firstApproach: String?
    var reviewPath: [AnalysisReviewStepResponse]?
    var primaryStuckPoint: String?
    var lassoSelectedPointIds: [String]?
    var freeMemo: String?
    var analyzedAt: Date
}

nonisolated struct AnalysisReviewOptionDefinition: Hashable, Sendable, Identifiable {
    var id: String
    var title: String
}

nonisolated struct AnalysisReviewStepDefinition: Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var options: [AnalysisReviewOptionDefinition]
}

nonisolated struct AnalysisPostSolveReviewPromptSet: Hashable, Sendable {
    var subject: AnalysisReviewSubjectType
    var firstApproachOptions: [AnalysisReviewOptionDefinition]
    var stepDefinitions: [AnalysisReviewStepDefinition]

    func stepTitle(for stepId: String) -> String {
        stepDefinitions.first(where: { $0.id == stepId })?.title ?? stepId.replacingOccurrences(of: "_", with: " ")
    }

    static func promptSet(for studySubject: StudySubject?) -> AnalysisPostSolveReviewPromptSet {
        promptSet(for: AnalysisReviewSubjectType(studySubject: studySubject))
    }

    static func promptSet(for subject: AnalysisReviewSubjectType) -> AnalysisPostSolveReviewPromptSet {
        let genericSteps = [
            AnalysisReviewStepDefinition(
                id: "condition_parse",
                title: "조건 해석",
                options: [
                    AnalysisReviewOptionDefinition(id: "generic_find_knowns", title: "주어진 조건 먼저 정리"),
                    AnalysisReviewOptionDefinition(id: "generic_define_target", title: "무엇을 구할지 먼저 고정"),
                    AnalysisReviewOptionDefinition(id: "generic_mark_keyword", title: "핵심 단서 표시"),
                    AnalysisReviewOptionDefinition(id: "generic_split_information", title: "정보를 단계별로 분리")
                ]
            ),
            AnalysisReviewStepDefinition(
                id: "strategy_choice",
                title: "풀이 방향",
                options: [
                    AnalysisReviewOptionDefinition(id: "generic_recall_rule", title: "관련 개념/규칙 떠올리기"),
                    AnalysisReviewOptionDefinition(id: "generic_choose_pattern", title: "대표 패턴 선택"),
                    AnalysisReviewOptionDefinition(id: "generic_try_simple_case", title: "쉬운 경우부터 시도"),
                    AnalysisReviewOptionDefinition(id: "generic_set_intermediate_goal", title: "중간 목표 먼저 세우기")
                ]
            ),
            AnalysisReviewStepDefinition(
                id: "execution",
                title: "전개/풀이",
                options: [
                    AnalysisReviewOptionDefinition(id: "generic_follow_order", title: "순서대로 전개"),
                    AnalysisReviewOptionDefinition(id: "generic_track_change", title: "변화 추적"),
                    AnalysisReviewOptionDefinition(id: "generic_compare_choices", title: "선택지/경우 비교"),
                    AnalysisReviewOptionDefinition(id: "generic_keep_basis", title: "근거를 옆에 남기기")
                ]
            ),
            AnalysisReviewStepDefinition(
                id: "verification",
                title: "검산/판단",
                options: [
                    AnalysisReviewOptionDefinition(id: "generic_recheck_condition", title: "조건과 다시 대조"),
                    AnalysisReviewOptionDefinition(id: "generic_check_final", title: "최종 답 모양 확인"),
                    AnalysisReviewOptionDefinition(id: "generic_find_counterexample", title: "반례/예외 확인"),
                    AnalysisReviewOptionDefinition(id: "generic_self_explain", title: "한 줄로 다시 설명")
                ]
            )
        ]

        switch subject {
        case .math:
            return AnalysisPostSolveReviewPromptSet(
                subject: .math,
                firstApproachOptions: [
                    AnalysisReviewOptionDefinition(id: "math_list_knowns", title: "조건과 미지수부터 정리"),
                    AnalysisReviewOptionDefinition(id: "math_recall_concept", title: "관련 공식/개념 먼저 떠올림"),
                    AnalysisReviewOptionDefinition(id: "math_find_pattern", title: "유형/패턴부터 찾음"),
                    AnalysisReviewOptionDefinition(id: "math_set_equation", title: "식 세우기부터 시도")
                ],
                stepDefinitions: [
                    AnalysisReviewStepDefinition(
                        id: "condition_parse",
                        title: "조건 해석",
                        options: [
                            AnalysisReviewOptionDefinition(id: "math_identify_given", title: "주어진 값/조건 구분"),
                            AnalysisReviewOptionDefinition(id: "math_define_target", title: "구할 대상을 고정"),
                            AnalysisReviewOptionDefinition(id: "math_pick_variable", title: "변수/기호 먼저 두기"),
                            AnalysisReviewOptionDefinition(id: "math_draw_relation", title: "관계식/도형 구조 먼저 보기")
                        ]
                    ),
                    AnalysisReviewStepDefinition(
                        id: "strategy_choice",
                        title: "풀이 방향",
                        options: [
                            AnalysisReviewOptionDefinition(id: "math_recall_formula", title: "관련 공식 회상"),
                            AnalysisReviewOptionDefinition(id: "math_try_substitution", title: "치환/변형 시도"),
                            AnalysisReviewOptionDefinition(id: "math_case_split", title: "경우 나누기 선택"),
                            AnalysisReviewOptionDefinition(id: "math_transform_expression", title: "식을 정리해 흐름 만들기")
                        ]
                    ),
                    AnalysisReviewStepDefinition(
                        id: "execution",
                        title: "전개/계산",
                        options: [
                            AnalysisReviewOptionDefinition(id: "math_keep_equation_consistent", title: "등식 흐름 유지"),
                            AnalysisReviewOptionDefinition(id: "math_follow_sign_change", title: "부호/계수 변화 추적"),
                            AnalysisReviewOptionDefinition(id: "math_manage_case_flow", title: "경우별 흐름 정리"),
                            AnalysisReviewOptionDefinition(id: "math_track_definition_use", title: "정의 적용 위치 확인")
                        ]
                    ),
                    AnalysisReviewStepDefinition(
                        id: "verification",
                        title: "검산",
                        options: [
                            AnalysisReviewOptionDefinition(id: "math_check_domain", title: "정의역/조건 재확인"),
                            AnalysisReviewOptionDefinition(id: "math_recheck_final_expression", title: "최종 식 다시 보기"),
                            AnalysisReviewOptionDefinition(id: "math_compare_with_condition", title: "초기 조건과 대조"),
                            AnalysisReviewOptionDefinition(id: "math_substitute_simple_case", title: "쉬운 값 대입 검산")
                        ]
                    )
                ]
            )
        case .korean:
            return AnalysisPostSolveReviewPromptSet(
                subject: .korean,
                firstApproachOptions: [
                    AnalysisReviewOptionDefinition(id: "korean_find_prompt_keyword", title: "발문 키워드부터 확인"),
                    AnalysisReviewOptionDefinition(id: "korean_scan_evidence", title: "근거 문장부터 찾음"),
                    AnalysisReviewOptionDefinition(id: "korean_classify_passage", title: "글의 유형/구조 먼저 판단"),
                    AnalysisReviewOptionDefinition(id: "korean_compare_choices_early", title: "선지부터 비교")
                ],
                stepDefinitions: [
                    AnalysisReviewStepDefinition(
                        id: "condition_parse",
                        title: "문항 해석",
                        options: [
                            AnalysisReviewOptionDefinition(id: "korean_grasp_prompt", title: "무엇을 묻는지 파악"),
                            AnalysisReviewOptionDefinition(id: "korean_mark_clue_sentence", title: "핵심 문장 표시"),
                            AnalysisReviewOptionDefinition(id: "korean_identify_passage_role", title: "문단 역할 구분"),
                            AnalysisReviewOptionDefinition(id: "korean_define_choice_task", title: "선지 판단 기준 고정")
                        ]
                    ),
                    AnalysisReviewStepDefinition(
                        id: "strategy_choice",
                        title: "접근 방향",
                        options: [
                            AnalysisReviewOptionDefinition(id: "korean_summarize_paragraph", title: "문단별 핵심 정리"),
                            AnalysisReviewOptionDefinition(id: "korean_compare_choices", title: "선지 대조"),
                            AnalysisReviewOptionDefinition(id: "korean_track_core_claim", title: "중심 주장 추적"),
                            AnalysisReviewOptionDefinition(id: "korean_locate_evidence", title: "근거 위치 먼저 고정")
                        ]
                    ),
                    AnalysisReviewStepDefinition(
                        id: "execution",
                        title: "판단/소거",
                        options: [
                            AnalysisReviewOptionDefinition(id: "korean_eliminate_wrong_choice", title: "오답 선지 소거"),
                            AnalysisReviewOptionDefinition(id: "korean_match_evidence", title: "근거와 선지 연결"),
                            AnalysisReviewOptionDefinition(id: "korean_follow_structure", title: "구조 흐름 따라가기"),
                            AnalysisReviewOptionDefinition(id: "korean_check_expression", title: "표현/어조 확인")
                        ]
                    ),
                    AnalysisReviewStepDefinition(
                        id: "verification",
                        title: "최종 확인",
                        options: [
                            AnalysisReviewOptionDefinition(id: "korean_recheck_keyword", title: "발문 핵심어 재확인"),
                            AnalysisReviewOptionDefinition(id: "korean_verify_choice_basis", title: "선택 근거 다시 보기"),
                            AnalysisReviewOptionDefinition(id: "korean_review_counterexample", title: "반대 근거 점검"),
                            AnalysisReviewOptionDefinition(id: "korean_confirm_scope", title: "범위/대상 확인")
                        ]
                    )
                ]
            )
        case .english:
            return AnalysisPostSolveReviewPromptSet(
                subject: .english,
                firstApproachOptions: [
                    AnalysisReviewOptionDefinition(id: "english_parse_sentence", title: "문장 구조부터 파악"),
                    AnalysisReviewOptionDefinition(id: "english_find_clue", title: "단서 문장부터 찾음"),
                    AnalysisReviewOptionDefinition(id: "english_compare_choices", title: "선지 먼저 비교"),
                    AnalysisReviewOptionDefinition(id: "english_identify_structure", title: "글 전개 구조 먼저 판단")
                ],
                stepDefinitions: [
                    AnalysisReviewStepDefinition(
                        id: "condition_parse",
                        title: "문장/발문 해석",
                        options: [
                            AnalysisReviewOptionDefinition(id: "english_identify_task", title: "발문 요구 파악"),
                            AnalysisReviewOptionDefinition(id: "english_split_sentence", title: "문장 성분 나누기"),
                            AnalysisReviewOptionDefinition(id: "english_mark_connector", title: "접속/전환어 표시"),
                            AnalysisReviewOptionDefinition(id: "english_pick_keyword", title: "핵심 단어 고정")
                        ]
                    ),
                    AnalysisReviewStepDefinition(
                        id: "strategy_choice",
                        title: "접근 방향",
                        options: [
                            AnalysisReviewOptionDefinition(id: "english_clue_first", title: "근거 문장 우선"),
                            AnalysisReviewOptionDefinition(id: "english_structure_first", title: "글 구조 우선"),
                            AnalysisReviewOptionDefinition(id: "english_vocab_guess", title: "어휘/문맥 추론"),
                            AnalysisReviewOptionDefinition(id: "english_choice_compare", title: "선지 비교 시작")
                        ]
                    ),
                    AnalysisReviewStepDefinition(
                        id: "execution",
                        title: "해석/판단",
                        options: [
                            AnalysisReviewOptionDefinition(id: "english_match_evidence", title: "근거와 답 연결"),
                            AnalysisReviewOptionDefinition(id: "english_remove_false_choice", title: "오답 선지 제거"),
                            AnalysisReviewOptionDefinition(id: "english_track_reference", title: "대명사/지시어 추적"),
                            AnalysisReviewOptionDefinition(id: "english_keep_tense_logic", title: "시제/논리 유지")
                        ]
                    ),
                    AnalysisReviewStepDefinition(
                        id: "verification",
                        title: "최종 확인",
                        options: [
                            AnalysisReviewOptionDefinition(id: "english_recheck_prompt", title: "발문 재확인"),
                            AnalysisReviewOptionDefinition(id: "english_recheck_clue", title: "근거 문장 다시 보기"),
                            AnalysisReviewOptionDefinition(id: "english_check_choice_scope", title: "선지 범위 점검"),
                            AnalysisReviewOptionDefinition(id: "english_self_translate", title: "핵심 문장 다시 해석")
                        ]
                    )
                ]
            )
        case .inquiry:
            return AnalysisPostSolveReviewPromptSet(
                subject: .inquiry,
                firstApproachOptions: [
                    AnalysisReviewOptionDefinition(id: "inquiry_identify_principle", title: "관련 원리부터 떠올림"),
                    AnalysisReviewOptionDefinition(id: "inquiry_read_graph", title: "표/그래프부터 읽음"),
                    AnalysisReviewOptionDefinition(id: "inquiry_sort_conditions", title: "조건부터 분류"),
                    AnalysisReviewOptionDefinition(id: "inquiry_recall_formula", title: "식/법칙 먼저 점검")
                ],
                stepDefinitions: [
                    AnalysisReviewStepDefinition(
                        id: "condition_parse",
                        title: "자료/조건 해석",
                        options: [
                            AnalysisReviewOptionDefinition(id: "inquiry_identify_variable", title: "변수/축 먼저 읽기"),
                            AnalysisReviewOptionDefinition(id: "inquiry_mark_experiment", title: "실험 조건 구분"),
                            AnalysisReviewOptionDefinition(id: "inquiry_sort_units", title: "단위/기호 확인"),
                            AnalysisReviewOptionDefinition(id: "inquiry_pick_question_core", title: "핵심 질문 고정")
                        ]
                    ),
                    AnalysisReviewStepDefinition(
                        id: "strategy_choice",
                        title: "해석 방향",
                        options: [
                            AnalysisReviewOptionDefinition(id: "inquiry_link_principle", title: "원리와 연결"),
                            AnalysisReviewOptionDefinition(id: "inquiry_compare_cases", title: "조건별 비교"),
                            AnalysisReviewOptionDefinition(id: "inquiry_extract_trend", title: "증감 경향 파악"),
                            AnalysisReviewOptionDefinition(id: "inquiry_eliminate_noise", title: "불필요 정보 제거")
                        ]
                    ),
                    AnalysisReviewStepDefinition(
                        id: "execution",
                        title: "추론/계산",
                        options: [
                            AnalysisReviewOptionDefinition(id: "inquiry_apply_rule", title: "법칙 적용"),
                            AnalysisReviewOptionDefinition(id: "inquiry_follow_graph", title: "그래프 흐름 추적"),
                            AnalysisReviewOptionDefinition(id: "inquiry_manage_case_flow", title: "조건별 추론 정리"),
                            AnalysisReviewOptionDefinition(id: "inquiry_track_exception", title: "예외 상황 확인")
                        ]
                    ),
                    AnalysisReviewStepDefinition(
                        id: "verification",
                        title: "최종 판단",
                        options: [
                            AnalysisReviewOptionDefinition(id: "inquiry_recheck_condition", title: "조건 다시 대조"),
                            AnalysisReviewOptionDefinition(id: "inquiry_recheck_unit", title: "단위/방향 검산"),
                            AnalysisReviewOptionDefinition(id: "inquiry_check_graph_reason", title: "자료 근거 재확인"),
                            AnalysisReviewOptionDefinition(id: "inquiry_compare_with_fact", title: "사실과 다시 비교")
                        ]
                    )
                ]
            )
        case .unknown:
            return AnalysisPostSolveReviewPromptSet(
                subject: .unknown,
                firstApproachOptions: [
                    AnalysisReviewOptionDefinition(id: "generic_scan_prompt", title: "문제를 끝까지 읽음"),
                    AnalysisReviewOptionDefinition(id: "generic_find_knowns", title: "주어진 정보 정리"),
                    AnalysisReviewOptionDefinition(id: "generic_recall_rule", title: "관련 개념 떠올림"),
                    AnalysisReviewOptionDefinition(id: "generic_try_pattern", title: "익숙한 패턴부터 시도")
                ],
                stepDefinitions: genericSteps
            )
        }
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
    var postSolveReview: AnalysisPostSolveReview?
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
    var postSolveReview: AnalysisPostSolveReview?
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
    var postSolveReview: AnalysisPostSolveReview?
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
