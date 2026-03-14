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
    var linkedStrokeId: String?
    var calculatedDelayMs: Int?

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
    var searchKeywords: [String] = []
}

nonisolated struct AnalysisReviewStepVariant: Hashable, Sendable {
    var parentOptionIDs: [String]
    var title: String?
    var guidance: String?
    var options: [AnalysisReviewOptionDefinition]
}

nonisolated struct AnalysisReviewStepDefinition: Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var options: [AnalysisReviewOptionDefinition]
    var variants: [AnalysisReviewStepVariant] = []
}

nonisolated struct AnalysisResolvedReviewStepDefinition: Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var guidance: String?
    var options: [AnalysisReviewOptionDefinition]
}

nonisolated struct AnalysisPostSolveReviewPromptSet: Hashable, Sendable {
    var subject: AnalysisReviewSubjectType
    var firstApproachOptions: [AnalysisReviewOptionDefinition]
    var stepDefinitions: [AnalysisReviewStepDefinition]
    var overviewText: String?
    var firstApproachGuidance: String?
    var stepGuidanceByID: [String: String]

    init(
        subject: AnalysisReviewSubjectType,
        firstApproachOptions: [AnalysisReviewOptionDefinition],
        stepDefinitions: [AnalysisReviewStepDefinition],
        overviewText: String? = nil,
        firstApproachGuidance: String? = nil,
        stepGuidanceByID: [String: String] = [:]
    ) {
        self.subject = subject
        self.firstApproachOptions = firstApproachOptions
        self.stepDefinitions = stepDefinitions
        self.overviewText = overviewText
        self.firstApproachGuidance = firstApproachGuidance
        self.stepGuidanceByID = stepGuidanceByID
    }

    func stepTitle(for stepId: String) -> String {
        stepDefinitions.first(where: { $0.id == stepId })?.title ?? stepId.replacingOccurrences(of: "_", with: " ")
    }

    func guidance(for stepId: String) -> String? {
        stepGuidanceByID[stepId]
    }

    func resolvedStepDefinition(
        at index: Int,
        draft: AnalysisPostSolveReviewDraft?
    ) -> AnalysisResolvedReviewStepDefinition? {
        guard stepDefinitions.indices.contains(index) else { return nil }

        let step = stepDefinitions[index]
        let priorOptionID: String?

        if index == 0 {
            priorOptionID = draft?.firstApproachID
        } else {
            let previousStep = stepDefinitions[index - 1]
            priorOptionID = draft?.selectedOptionID(for: previousStep.id)
        }

        if let priorOptionID,
           let variant = step.variants.first(where: { $0.parentOptionIDs.contains(priorOptionID) }) {
            return AnalysisResolvedReviewStepDefinition(
                id: step.id,
                title: variant.title ?? step.title,
                guidance: variant.guidance ?? stepGuidanceByID[step.id],
                options: variant.options
            )
        }

        return AnalysisResolvedReviewStepDefinition(
            id: step.id,
            title: step.title,
            guidance: stepGuidanceByID[step.id],
            options: step.options
        )
    }

    func optionDefinition(for optionId: String) -> AnalysisReviewOptionDefinition? {
        if let firstApproach = firstApproachOptions.first(where: { $0.id == optionId }) {
            return firstApproach
        }

        for step in stepDefinitions {
            if let option = step.options.first(where: { $0.id == optionId }) {
                return option
            }
            for variant in step.variants {
                if let option = variant.options.first(where: { $0.id == optionId }) {
                    return option
                }
            }
        }

        return nil
    }

    static func promptSet(for studySubject: StudySubject?) -> AnalysisPostSolveReviewPromptSet {
        promptSet(for: AnalysisReviewSubjectType(studySubject: studySubject))
    }

    static func promptSet(for question: PastQuestionRecord?) -> AnalysisPostSolveReviewPromptSet {
        guard let question else {
            return promptSet(for: .unknown)
        }

        if let specialized = specializedPromptSet(for: question) {
            return specialized
        }

        return promptSet(for: reviewSubject(for: question.subject))
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

    private static func specializedPromptSet(for question: PastQuestionRecord) -> AnalysisPostSolveReviewPromptSet? {
        if isCSAT2023MathCommon22(question) {
            return csat2023MathCommon22PromptSet()
        }

        if isCSAT2024MathCommon22(question) {
            return csat2024MathCommon22PromptSet()
        }

        if isCSAT2025MathCommon22(question) {
            return csat2025MathCommon22PromptSet()
        }

        return nil
    }

    private static func csat2023MathCommon22PromptSet() -> AnalysisPostSolveReviewPromptSet {
        AnalysisPostSolveReviewPromptSet(
            subject: .math,
            firstApproachOptions: [
                option(
                    id: "csat23_q1_mvt",
                    title: "평균변화율과 미분계수를 연결해야겠다고 봤다",
                    keywords: ["평균값정리", "평균변화율", "미분계수"]
                ),
                option(
                    id: "csat23_q1_ambiguous",
                    title: "식을 정리해 보긴 했는데 어떤 개념을 써야 할지 애매했다",
                    keywords: ["식정리", "개념불명확", "평균변화율"]
                ),
                option(
                    id: "csat23_q1_find_g",
                    title: "g(x)의 식부터 직접 구하려고 했다",
                    keywords: ["g(x)", "보조함수", "직접구하기"]
                ),
                option(
                    id: "csat23_q1_other_condition",
                    title: "거의 감이 안 와서 다른 조건부터 보려 했다",
                    keywords: ["다른조건", "출발막힘", "구조파악실패"]
                )
            ],
            stepDefinitions: [
                AnalysisReviewStepDefinition(
                    id: "interpretation_branch",
                    title: "핵심 해석",
                    options: [],
                    variants: [
                        variant(
                            parentOptionIDs: ["csat23_q1_mvt"],
                            title: "그다음 실제로 어디까지 갔나요?",
                            guidance: "평균값정리 구조를 봤다면, 그 다음에 접선·g(1)·변곡점 중 어디까지 연결했는지 고르세요.",
                            options: [
                                option(id: "csat23_q2a_contact_x", title: "g(x)가 접선의 x좌표 같은 역할이라고 읽었다", keywords: ["접선의 x좌표", "g(x)의 역할", "접점"]),
                                option(id: "csat23_q2a_mvt_only", title: "평균값정리 느낌은 봤는데, 그걸 그래프/접선으로 못 옮겼다", keywords: ["평균값정리", "그래프해석실패", "접선전환실패"]),
                                option(id: "csat23_q2a_g1", title: "x→1 또는 g(1) 쪽 단서를 먼저 보려 했다", keywords: ["g(1)", "고정점", "x=1"]),
                                option(id: "csat23_q2a_stuck", title: "평균값정리라고 봤지만 그다음이 막혔다", keywords: ["평균값정리", "다음단계막힘"])
                            ]
                        ),
                        variant(
                            parentOptionIDs: ["csat23_q1_ambiguous", "csat23_q1_find_g", "csat23_q1_other_condition"],
                            title: "실제로 가장 크게 막힌 지점은 어디였나요?",
                            guidance: "식만 만졌거나 다른 조건으로 샜다면, 실제로 구조를 놓친 지점을 고르세요.",
                            options: [
                                option(id: "csat23_q2b_miss_g_role", title: "식은 만졌는데 g(x)의 의미를 못 잡았다", keywords: ["g(x)의 의미", "보조함수 역할", "구조실패"]),
                                option(id: "csat23_q2b_choose_f_or_g", title: "f와 g 중 무엇을 주인공으로 봐야 할지 헷갈렸다", keywords: ["f와 g", "주인공함수", "전략선택"]),
                                option(id: "csat23_q2b_no_graph", title: "조건은 읽었는데 그래프로 못 바꿨다", keywords: ["그래프번역실패", "접선", "변곡점"]),
                                option(id: "csat23_q2b_formula_only", title: "계산으로 밀면 될 줄 알았는데 정리가 안 됐다", keywords: ["계산밀기", "정리실패", "후반붕괴"])
                            ]
                        )
                    ]
                ),
                AnalysisReviewStepDefinition(
                    id: "final_breakdown",
                    title: "최종 정체",
                    options: [],
                    variants: [
                        variant(
                            parentOptionIDs: ["csat23_q2a_contact_x", "csat23_q2a_g1"],
                            title: "접선/평균값정리 해석 뒤에 실제로 무엇을 했나요?",
                            guidance: "접선의 의미나 g(1)까지 봤다면, 그 다음에 무엇을 먼저 잠그려 했는지 고르세요.",
                            options: [
                                option(id: "csat23_q3a_lock_g1", title: "g(1)이나 특정 접점의 위치를 먼저 확정하려 했다", keywords: ["g(1)", "접점위치", "고정정보"]),
                                option(id: "csat23_q3a_inflection", title: "변곡점 위치부터 잡으려 했다", keywords: ["변곡점", "삼차함수", "접선"]),
                                option(id: "csat23_q3a_no_numeric", title: "둘의 연결은 봤는데 수치화가 안 됐다", keywords: ["수치화실패", "연결실패", "접선해석"]),
                                option(id: "csat23_q3a_coefficients", title: "여기까진 갔는데 f(x) 계수로 못 넘겼다", keywords: ["계수결정", "일반형", "마무리실패"])
                            ]
                        ),
                        variant(
                            parentOptionIDs: [
                                "csat23_q2a_mvt_only",
                                "csat23_q2a_stuck",
                                "csat23_q2b_miss_g_role",
                                "csat23_q2b_choose_f_or_g",
                                "csat23_q2b_no_graph",
                                "csat23_q2b_formula_only"
                            ],
                            title: "결국 어떤 형태로 멈췄나요?",
                            guidance: "핵심 구조를 놓친 상태였다면, 마지막으로 어디에서 멈췄는지 고르세요.",
                            options: [
                                option(id: "csat23_q3b_mvt_name_only", title: "평균값정리라는 말은 떠올랐지만 쓸 줄 몰랐다", keywords: ["평균값정리", "이름만암", "적용실패"]),
                                option(id: "csat23_q3b_no_tangent", title: "접선/기울기 해석까지는 못 갔다", keywords: ["접선해석실패", "기울기해석실패"]),
                                option(id: "csat23_q3b_miss_g1", title: "g(1)의 의미를 놓쳤다", keywords: ["g(1)", "고정점누락"]),
                                option(id: "csat23_q3b_late_coefficients", title: "후반 계수 정리에서 꼬였다", keywords: ["계수정리", "후반붕괴", "일반형"])
                            ]
                        )
                    ]
                )
            ],
            overviewText: "2023 수능 수학 22번은 평균값정리 구조를 접선 의미로 바꾸고, g(1)과 변곡점 추론을 계수 결정으로 연결하는 문제입니다.",
            firstApproachGuidance: "(가) 조건을 처음 봤을 때 어떤 사고로 출발했는지 고르세요. 여기서 방향을 잘못 잡으면 뒤가 거의 다 무너집니다."
        )
    }

    private static func csat2024MathCommon22PromptSet() -> AnalysisPostSolveReviewPromptSet {
        AnalysisPostSolveReviewPromptSet(
            subject: .math,
            firstApproachOptions: [
                option(
                    id: "csat24_q1_box_constraint",
                    title: "박스의 정수 조건이 그래프를 강하게 제한한다고 봤다",
                    keywords: ["정수조건", "그래프제한", "x축배치"]
                ),
                option(
                    id: "csat24_q1_cubic_shape",
                    title: "일단 삼차함수 식/개형부터 잡으려 했다",
                    keywords: ["삼차함수", "개형", "일반형"]
                ),
                option(
                    id: "csat24_q1_derivative",
                    title: "도함수 부호 조건부터 해석했다",
                    keywords: ["도함수", "증가감소", "극값"]
                ),
                option(
                    id: "csat24_q1_no_entry",
                    title: "조건은 많았는데 어디부터 건드려야 할지 감이 없었다",
                    keywords: ["출발막힘", "조건과다", "전략부재"]
                )
            ],
            stepDefinitions: [
                AnalysisReviewStepDefinition(
                    id: "graph_constraint_branch",
                    title: "그래프 제약 해석",
                    options: [],
                    variants: [
                        variant(
                            parentOptionIDs: ["csat24_q1_box_constraint"],
                            title: "박스 조건을 어떻게 읽었나요?",
                            guidance: "정수 k 조건을 먼저 봤다면, 그걸 실근이나 x축 배치로 어떻게 번역했는지 고르세요.",
                            options: [
                                option(id: "csat24_q2a_sign_change_block", title: "두 점의 부호가 다르면 안 되니 x축 통과 방식이 제한된다고 봤다", keywords: ["부호조건", "x축통과", "그래프배치"]),
                                option(id: "csat24_q2a_root_layout", title: "실근의 개수나 배치를 좁히는 조건이라고 봤다", keywords: ["실근개수", "근배치", "그래프제약"]),
                                option(id: "csat24_q2a_unsure", title: "중요하다는 건 알았는데 정확히 뭘 의미하는지 모르겠었다", keywords: ["조건해석실패", "정수조건"]),
                                option(id: "csat24_q2a_formula_only", title: "식으로만 보다가 막혔다", keywords: ["식으로만해석", "그래프번역실패"])
                            ]
                        ),
                        variant(
                            parentOptionIDs: ["csat24_q1_cubic_shape", "csat24_q1_derivative", "csat24_q1_no_entry"],
                            title: "실제로 어디서 가장 크게 갈렸나요?",
                            guidance: "개형이나 도함수부터 들어갔다면, 실제로 어디에서 경로가 갈렸는지 고르세요.",
                            options: [
                                option(id: "csat24_q2b_shape_ok", title: "삼차함수의 증가/감소 개형은 잡았다", keywords: ["증가감소", "개형파악"]),
                                option(id: "csat24_q2b_no_axis", title: "개형은 그렸는데 x축과의 상대 위치를 못 정했다", keywords: ["x축위치", "교점배치", "개형"]),
                                option(id: "csat24_q2b_root_count_shaky", title: "실근이 1개인지 3개인지 판단이 흔들렸다", keywords: ["실근개수", "개수판단"]),
                                option(id: "csat24_q2b_no_box", title: "박스 조건을 마지막까지도 제대로 못 썼다", keywords: ["박스조건", "정수조건", "활용실패"])
                            ]
                        )
                    ]
                ),
                AnalysisReviewStepDefinition(
                    id: "final_breakdown",
                    title: "최종 정체",
                    options: [],
                    variants: [
                        variant(
                            parentOptionIDs: [
                                "csat24_q2a_sign_change_block",
                                "csat24_q2a_root_layout",
                                "csat24_q2a_unsure",
                                "csat24_q2a_formula_only"
                            ],
                            title: "x축 배치를 좁힐 때 실제로 어디까지 갔나요?",
                            guidance: "박스 조건을 그래프 배치로 번역했다면, 실제로 어디까지 압축했는지 고르세요.",
                            options: [
                                option(id: "csat24_q3a_rule_out_one_root", title: "실근이 하나인 경우는 배제해야 한다고 봤다", keywords: ["실근1개배제", "삼차함수", "x축배치"]),
                                option(id: "csat24_q3a_integer_gap", title: "정수 간격 사이에서 부호가 갈리면 안 된다고 봤다", keywords: ["정수간격", "부호갈림", "그래프제약"]),
                                option(id: "csat24_q3a_crossing_zone", title: "x축을 지나도 되는 위치와 지나면 안 되는 위치를 나눠 봤다", keywords: ["x축통과위치", "교점배치", "가능불가능"]),
                                option(id: "csat24_q3a_no_max_link", title: "여기까진 갔는데 최댓값 계산으로 못 넘겼다", keywords: ["최댓값", "f(1)", "마무리실패"])
                            ]
                        ),
                        variant(
                            parentOptionIDs: [
                                "csat24_q2b_shape_ok",
                                "csat24_q2b_no_axis",
                                "csat24_q2b_root_count_shaky",
                                "csat24_q2b_no_box"
                            ],
                            title: "가장 마지막에 막힌 건 무엇이었나요?",
                            guidance: "개형이나 도함수는 어느 정도 봤다면, 마지막으로 어디에서 흔들렸는지 고르세요.",
                            options: [
                                option(id: "csat24_q3b_no_intersection", title: "개형은 맞췄는데 교점 좌표 확정이 안 됐다", keywords: ["교점좌표", "x축위치", "개형"]),
                                option(id: "csat24_q3b_no_max", title: "교점 배치는 봤는데 f(1) 최대화가 안 됐다", keywords: ["f(1) 최대화", "목적식", "최적화"]),
                                option(id: "csat24_q3b_too_many_cases", title: "조건을 너무 많이 나눠서 계산이 터졌다", keywords: ["경우폭주", "분기과다", "계산폭주"]),
                                option(id: "csat24_q3b_no_final_check", title: "끝 검산이 불안해서 답을 못 정했다", keywords: ["검산불안", "마지막판단"])
                            ]
                        )
                    ]
                )
            ],
            overviewText: "2024 수능 수학 22번은 박스의 정수 조건을 x축 주변 그래프 배치 제한으로 번역하고, 삼차함수 개형과 교점 배치를 좁히는 문제가 핵심입니다.",
            firstApproachGuidance: "이 문항에서 처음 승부를 건 포인트를 고르세요. 박스 조건을 그래프 제한으로 봤는지가 가장 큰 갈림길입니다."
        )
    }

    private static func csat2025MathCommon22PromptSet() -> AnalysisPostSolveReviewPromptSet {
        AnalysisPostSolveReviewPromptSet(
            subject: .math,
            firstApproachOptions: [
                option(
                    id: "csat25_q1_forward",
                    title: "앞에서부터 점화식을 몇 번 써 보려 했다",
                    keywords: ["앞에서전개", "점화식", "계산밀기"]
                ),
                option(
                    id: "csat25_q1_a3_a5",
                    title: "a3와 a5의 관계를 먼저 잡으려 했다",
                    keywords: ["a3", "a5", "중간항", "절댓값"]
                ),
                option(
                    id: "csat25_q1_absolute",
                    title: "절댓값 조건부터 경우를 나누려 했다",
                    keywords: ["절댓값", "경우나누기", "부호분기"]
                ),
                option(
                    id: "csat25_q1_no_pivot",
                    title: "어디를 고정해야 할지 몰라 계산만 해봤다",
                    keywords: ["기준점부재", "계산만함", "점화식"]
                )
            ],
            stepDefinitions: [
                AnalysisReviewStepDefinition(
                    id: "sequence_pivot",
                    title: "기준점 선택",
                    options: [],
                    variants: [
                        variant(
                            parentOptionIDs: ["csat25_q1_a3_a5", "csat25_q1_absolute"],
                            title: "실제로 가장 먼저 잡은 핵심은 무엇이었나요?",
                            guidance: "중간항이나 절댓값을 먼저 본 경우, 정확히 어떤 기준점을 먼저 잠갔는지 고르세요.",
                            options: [
                                option(id: "csat25_q2a_abs_equal", title: "|a3|=|a5|를 먼저 봤다", keywords: ["|a3|=|a5|", "절댓값관계", "중간항"]),
                                option(id: "csat25_q2a_split_a3", title: "a3가 홀수/짝수/0일 수 있다는 걸 나눴다", keywords: ["a3", "홀수짝수", "0케이스"]),
                                option(id: "csat25_q2a_late_backtrack", title: "절댓값은 봤는데 역추적 발상은 늦게 나왔다", keywords: ["절댓값", "역추적지연"]),
                                option(id: "csat25_q2a_missing_case_fear", title: "경우를 나누긴 했는데 누락이 걱정됐다", keywords: ["경우누락", "절댓값분기", "불안"])
                            ]
                        ),
                        variant(
                            parentOptionIDs: ["csat25_q1_forward", "csat25_q1_no_pivot"],
                            title: "실제로 어디서 막혔나요?",
                            guidance: "앞에서부터 밀거나 기준점 없이 풀었다면, 실제로 무너진 지점을 고르세요.",
                            options: [
                                option(id: "csat25_q2b_too_many_terms", title: "앞에서 전개하다가 항이 너무 많아졌다", keywords: ["항이너무많음", "전개폭주", "계산량"]),
                                option(id: "csat25_q2b_no_a3_pivot", title: "a3를 기준으로 봐야 한다는 생각을 못 했다", keywords: ["a3 기준", "중간항기준", "전략실패"]),
                                option(id: "csat25_q2b_abs_sign_confused", title: "절댓값 때문에 부호 처리가 꼬였다", keywords: ["절댓값", "부호처리", "분기실패"]),
                                option(id: "csat25_q2b_zero_case", title: "0인 경우를 따로 봐야 하는지 몰랐다", keywords: ["0케이스", "절댓값", "누락"])
                            ]
                        )
                    ]
                ),
                AnalysisReviewStepDefinition(
                    id: "final_breakdown",
                    title: "최종 정체",
                    options: [],
                    variants: [
                        variant(
                            parentOptionIDs: [
                                "csat25_q2a_abs_equal",
                                "csat25_q2a_split_a3",
                                "csat25_q2a_late_backtrack",
                                "csat25_q2a_missing_case_fear"
                            ],
                            title: "경우를 나눌 때 실제로 어떤 수준까지 갔나요?",
                            guidance: "a3나 절댓값 분기를 기준으로 풀었다면, 후보를 어느 정도까지 통제했는지 고르세요.",
                            options: [
                                option(id: "csat25_q3a_many_candidates", title: "a3 후보값들을 꽤 다 뽑았다", keywords: ["a3후보", "후보생성", "역추적준비"]),
                                option(id: "csat25_q3a_zero_unsure", title: "홀수/짝수는 나눴는데 0 처리가 애매했다", keywords: ["0케이스", "홀수짝수", "누락위험"]),
                                option(id: "csat25_q3a_backtrack_error", title: "후보는 나왔는데 역추적에서 실수했다", keywords: ["역추적실수", "후보는있음"]),
                                option(id: "csat25_q3a_missing_case", title: "거의 다 했는데 일부 케이스를 빼먹었다", keywords: ["케이스누락", "마무리검산"])
                            ]
                        ),
                        variant(
                            parentOptionIDs: [
                                "csat25_q2b_too_many_terms",
                                "csat25_q2b_no_a3_pivot",
                                "csat25_q2b_abs_sign_confused",
                                "csat25_q2b_zero_case"
                            ],
                            title: "마지막에 가장 크게 흔들린 지점은?",
                            guidance: "기준점을 못 잡았거나 절댓값 분기에서 흔들렸다면, 마지막으로 어디에서 무너졌는지 고르세요.",
                            options: [
                                option(id: "csat25_q3b_no_candidates", title: "가능한 a3를 다 못 모았다", keywords: ["a3후보누락", "후보모으기실패"]),
                                option(id: "csat25_q3b_backtrack_confused", title: "a1로 되돌리는 역추적이 꼬였다", keywords: ["a1 역추적", "복원실패"]),
                                option(id: "csat25_q3b_no_final_check", title: "절댓값 합산 직전 검산을 못 했다", keywords: ["절댓값합산", "검산실패"]),
                                option(id: "csat25_q3b_gave_up", title: "케이스 수가 많아 보여서 중간에 포기했다", keywords: ["케이스과다", "중도포기"])
                            ]
                        )
                    ]
                )
            ],
            overviewText: "2025 수능 수학 22번은 앞에서 밀기보다 a3·a5 관계를 기준점으로 잡고, 절댓값 분기와 역추적으로 가능한 수열만 남기는 문제가 핵심입니다.",
            firstApproachGuidance: "이 문제를 처음 풀 때 어디를 기준점으로 잡았는지 고르세요. 앞에서 미는지, 중간항을 잠그는지가 가장 큰 갈림길입니다."
        )
    }

    private static func option(
        id: String,
        title: String,
        keywords: [String]
    ) -> AnalysisReviewOptionDefinition {
        AnalysisReviewOptionDefinition(id: id, title: title, searchKeywords: keywords)
    }

    private static func variant(
        parentOptionIDs: [String],
        title: String,
        guidance: String,
        options: [AnalysisReviewOptionDefinition]
    ) -> AnalysisReviewStepVariant {
        AnalysisReviewStepVariant(
            parentOptionIDs: parentOptionIDs,
            title: title,
            guidance: guidance,
            options: options
        )
    }

    private static func reviewSubject(for rawSubject: String) -> AnalysisReviewSubjectType {
        let normalized = rawSubject.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("수학") {
            return .math
        }
        if normalized.contains("영어") {
            return .english
        }
        if normalized.contains("국어") || normalized.contains("논술") {
            return .korean
        }
        if normalized.contains("한국사")
            || normalized.contains("사회")
            || normalized.contains("물리")
            || normalized.contains("화학")
            || normalized.contains("생명")
            || normalized.contains("지구") {
            return .inquiry
        }
        return .unknown
    }

    private static func isCSAT2023MathCommon22(_ question: PastQuestionRecord) -> Bool {
        let contentMatches = question.content.localizedCaseInsensitiveContains("평균변화율")
            && question.content.localizedCaseInsensitiveContains("g(")

        return isCSATMathCommon22(question, academicYear: 2023, contentMatches: contentMatches)
    }

    private static func isCSAT2024MathCommon22(_ question: PastQuestionRecord) -> Bool {
        let contentMatches = question.content.localizedCaseInsensitiveContains("정수")
            && (question.content.localizedCaseInsensitiveContains("도함수")
                || question.content.localizedCaseInsensitiveContains("미분"))

        return isCSATMathCommon22(question, academicYear: 2024, contentMatches: contentMatches)
    }

    private static func isCSAT2025MathCommon22(_ question: PastQuestionRecord) -> Bool {
        let contentMatches = question.content.localizedCaseInsensitiveContains("절댓값")
            && (question.content.localizedCaseInsensitiveContains("수열")
                || question.content.localizedCaseInsensitiveContains("a"))

        return isCSATMathCommon22(question, academicYear: 2025, contentMatches: contentMatches)
    }

    private static func isCSATMathCommon22(
        _ question: PastQuestionRecord,
        academicYear: Int,
        contentMatches: Bool
    ) -> Bool {
        guard reviewSubject(for: question.subject) == .math,
              question.questionNumber == 22 else {
            return false
        }

        let examMatches = question.examType.localizedCaseInsensitiveContains("수능")
        let yearMatches = question.year == academicYear
            || (question.year == academicYear - 1 && question.month == 11 && examMatches)
        let monthMatches = question.month == 11
        let commonMatches = question.examVariant == "공통"
            || question.metadata.isCommon == true
            || question.examVariant == nil

        return commonMatches && examMatches && ((yearMatches && monthMatches) || contentMatches)
    }
}

nonisolated struct AnalysisPostSolveReviewDraft: Hashable, Sendable {
    let promptSet: AnalysisPostSolveReviewPromptSet
    var confidenceAfter: Double
    var firstApproachID: String?
    var stepStatuses: [String: AnalysisReviewStepStatus]
    var stepOptionSelections: [String: String]
    var stepLinkedStrokeIds: [String: String]
    var stepCalculatedDelays: [String: Int]
    var primaryStuckPointID: String?
    var freeMemo: String

    init(subject: StudySubject?) {
        self.init(promptSet: AnalysisPostSolveReviewPromptSet.promptSet(for: subject))
    }

    init(question: PastQuestionRecord) {
        self.init(promptSet: AnalysisPostSolveReviewPromptSet.promptSet(for: question))
    }

    private init(promptSet: AnalysisPostSolveReviewPromptSet) {
        self.promptSet = promptSet
        self.confidenceAfter = 60
        self.firstApproachID = nil
        self.stepStatuses = Dictionary(
            uniqueKeysWithValues: promptSet.stepDefinitions.map { ($0.id, .notTried) }
        )
        self.stepOptionSelections = [:]
        self.stepLinkedStrokeIds = [:]
        self.stepCalculatedDelays = [:]
        self.primaryStuckPointID = nil
        self.freeMemo = ""
    }

    func stepStatus(for stepId: String) -> AnalysisReviewStepStatus {
        stepStatuses[stepId] ?? .notTried
    }

    mutating func setFirstApproachID(_ optionID: String?) {
        guard firstApproachID != optionID else { return }
        firstApproachID = optionID
        clearStepSelections(startingAt: 0)
        primaryStuckPointID = nil
    }

    mutating func setStepStatus(
        _ status: AnalysisReviewStepStatus,
        for stepId: String,
        stepIndex: Int? = nil
    ) {
        stepStatuses[stepId] = status
        if status == .notTried {
            stepOptionSelections.removeValue(forKey: stepId)
            stepLinkedStrokeIds.removeValue(forKey: stepId)
            stepCalculatedDelays.removeValue(forKey: stepId)
            if let stepIndex {
                clearStepSelections(startingAt: stepIndex + 1)
            }
            if primaryStuckPointID == stepId {
                primaryStuckPointID = nil
            }
        }
    }

    func selectedOptionID(for stepId: String) -> String? {
        stepOptionSelections[stepId]
    }

    mutating func setSelectedOptionID(
        _ optionID: String?,
        for stepId: String,
        stepIndex: Int? = nil
    ) {
        let previousOptionID = stepOptionSelections[stepId]
        if let optionID {
            stepOptionSelections[stepId] = optionID
        } else {
            stepOptionSelections.removeValue(forKey: stepId)
            stepLinkedStrokeIds.removeValue(forKey: stepId)
            stepCalculatedDelays.removeValue(forKey: stepId)
        }

        if previousOptionID != optionID, let stepIndex {
            clearStepSelections(startingAt: stepIndex + 1)
            primaryStuckPointID = nil
        }
    }

    func resolvedStepDefinition(at index: Int) -> AnalysisResolvedReviewStepDefinition? {
        promptSet.resolvedStepDefinition(at: index, draft: self)
    }

    var preferredStuckSteps: [AnalysisReviewStepDefinition] {
        let filtered = promptSet.stepDefinitions.filter {
            let status = stepStatus(for: $0.id)
            return status == .failed || status == .partial
        }
        return filtered.isEmpty ? promptSet.stepDefinitions : filtered
    }

    func makePayload(analyzedAt: Date = Date()) -> AnalysisPostSolveReview {
        let reviewPath = promptSet.stepDefinitions.map { step in
            AnalysisReviewStepResponse(
                stepId: step.id,
                status: stepStatus(for: step.id),
                selectedOptionId: selectedOptionID(for: step.id),
                linkedStrokeId: stepLinkedStrokeIds[step.id],
                calculatedDelayMs: stepCalculatedDelays[step.id]
            )
        }
        let trimmedMemo = freeMemo.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackStuck = reviewPath.first(where: { $0.status == .failed })?.stepId
            ?? reviewPath.first(where: { $0.status == .partial })?.stepId

        return AnalysisPostSolveReview(
            subject: promptSet.subject,
            confidenceAfter: Int(confidenceAfter.rounded()),
            firstApproach: firstApproachID,
            reviewPath: reviewPath,
            primaryStuckPoint: primaryStuckPointID ?? fallbackStuck,
            lassoSelectedPointIds: nil,
            freeMemo: trimmedMemo.isEmpty ? nil : trimmedMemo,
            analyzedAt: analyzedAt
        )
    }

    private mutating func clearStepSelections(startingAt startIndex: Int) {
        guard promptSet.stepDefinitions.indices.contains(startIndex) else { return }

        let clearedStepIDs = promptSet.stepDefinitions[startIndex...].map(\.id)
        for stepID in clearedStepIDs {
            stepStatuses[stepID] = .notTried
            stepOptionSelections.removeValue(forKey: stepID)
            stepLinkedStrokeIds.removeValue(forKey: stepID)
            stepCalculatedDelays.removeValue(forKey: stepID)
        }

        if let primaryStuckPointID,
           clearedStepIDs.contains(primaryStuckPointID) {
            self.primaryStuckPointID = nil
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
