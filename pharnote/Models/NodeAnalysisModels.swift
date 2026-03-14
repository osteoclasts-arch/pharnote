import Foundation

nonisolated enum NodeAnalysisTab: String, CaseIterable, Identifiable, Sendable {
    case questionLookup = "question_lookup"
    case weaknessRecommendations = "weakness_recommendations"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .questionLookup:
            return "기출문제 검색하기"
        case .weaknessRecommendations:
            return "내 약점에 맞는 문제 추천 받기"
        }
    }
}

nonisolated enum NodeAnalysisLookupMode: String, CaseIterable, Identifiable, Sendable {
    case direct = "direct"
    case demo = "demo"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .direct:
            return "직접 조회"
        case .demo:
            return "테스트용 기출"
        }
    }
}

nonisolated enum NodeAnalysisSessionPhase: String, Hashable, Sendable {
    case idle
    case questionReady = "question_ready"
    case solving
    case confidenceSurvey = "confidence_survey"
    case review
    case completed
}

nonisolated enum NodeAnalysisConfidenceChoice: Int, CaseIterable, Identifiable, Sendable {
    case almostGuess = 15
    case unsure = 45
    case fairlySure = 75
    case almostCertain = 95

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .almostGuess:
            return "거의 찍음"
        case .unsure:
            return "반신반의"
        case .fairlySure:
            return "꽤 확신"
        case .almostCertain:
            return "거의 확실"
        }
    }

    var subtitle: String {
        switch self {
        case .almostGuess:
            return "근거보다 감으로 선택"
        case .unsure:
            return "맞을 수도 있지만 불안함"
        case .fairlySure:
            return "핵심 흐름은 맞다고 느낌"
        case .almostCertain:
            return "검산만 남았다고 느낌"
        }
    }
}

nonisolated enum NodeAnalysisReviewStage: Hashable, Sendable {
    case firstApproach
    case step(index: Int)
}

nonisolated struct NodeAnalysisDemoQuestionPreset: Hashable, Identifiable, Sendable {
    let id: String
    let academicYear: Int
    let label: String
    let subtitle: String
    let summary: String
    let subject: StudySubject
    let month: Int
    let questionNumber: Int
    let examVariant: NodeAnalysisExamVariantOption
    let examType: String

    var title: String {
        "\(academicYear) 수능 수학 공통 22번"
    }

    var lookupYears: [Int] {
        var years = [academicYear]
        if academicYear > 1 {
            years.append(academicYear - 1)
        }
        return years
    }

    var fallbackRecord: PastQuestionRecord {
        switch id {
        case "csat_2023_common_22":
            return PastQuestionRecord(
                id: UUID(uuidString: "11111111-1111-4111-8111-111111111111") ?? UUID(),
                subject: subject.title,
                year: academicYear,
                month: month,
                examType: examType,
                questionNumber: questionNumber,
                difficulty: "4점",
                content: "데모용 축약 문항. 최고차항 계수가 1인 삼차함수 f와 연속함수 g가 있다. x>1에서 평균변화율이 어떤 점의 미분계수와 같아지는 구조 [f(x)-f(1)]/(x-1)=f'(g(x)) 와 g(x)>=5/2 조건이 주어지고, 추가 조건을 통해 g(1), 접점, 변곡점의 위치를 연결하여 값을 구하는 문제다.",
                imageURLString: nil,
                answer: nil,
                solution: "평균변화율을 접선 의미로 바꾸고, g(1)과 변곡점 정보를 먼저 잠근 뒤 계수 결정으로 연결하는 흐름을 데모한다.",
                normalizedExamVariant: examVariant.requestValue,
                normalizedPaperSection: "공통",
                normalizedPoints: 4,
                normalizedHasImage: false,
                metadata: PastQuestionMetadata(values: [
                    "is_common": .bool(true),
                    "paper_section": .string("공통"),
                    "points": .number(4),
                    "unit": .string("미분법"),
                    "chapter": .string("도함수와 평균값정리"),
                    "keywords": .array([
                        .string("평균값정리"),
                        .string("평균변화율"),
                        .string("접선"),
                        .string("변곡점"),
                        .string("삼차함수"),
                        .string("합성함수")
                    ])
                ])
            )
        case "csat_2024_common_22":
            return PastQuestionRecord(
                id: UUID(uuidString: "22222222-2222-4222-8222-222222222222") ?? UUID(),
                subject: subject.title,
                year: academicYear,
                month: month,
                examType: examType,
                questionNumber: questionNumber,
                difficulty: "4점",
                content: "데모용 축약 문항. 최고차항 계수가 1인 삼차함수 f(x)에 대해 도함수 부호 조건과 함께, 모든 정수 k에 대해 특정 정수 간격 양끝에서 부호가 갈리는 상황이 없다는 박스 조건이 주어진다. 이 제약을 x축 주변 그래프 배치 제한으로 읽어 실근 배치와 f(1)의 최댓값을 결정하는 문제다.",
                imageURLString: nil,
                answer: nil,
                solution: "정수 조건을 계산식이 아니라 x축 통과 가능 위치 제한으로 읽고, 삼차함수 개형과 교점 배치를 좁히는 흐름을 데모한다.",
                normalizedExamVariant: examVariant.requestValue,
                normalizedPaperSection: "공통",
                normalizedPoints: 4,
                normalizedHasImage: false,
                metadata: PastQuestionMetadata(values: [
                    "is_common": .bool(true),
                    "paper_section": .string("공통"),
                    "points": .number(4),
                    "unit": .string("미분법"),
                    "chapter": .string("도함수와 함수의 그래프"),
                    "keywords": .array([
                        .string("삼차함수"),
                        .string("도함수"),
                        .string("정수 조건"),
                        .string("부호 변화"),
                        .string("x축 배치"),
                        .string("최댓값")
                    ])
                ])
            )
        default:
            return PastQuestionRecord(
                id: UUID(uuidString: "33333333-3333-4333-8333-333333333333") ?? UUID(),
                subject: subject.title,
                year: academicYear,
                month: month,
                examType: examType,
                questionNumber: questionNumber,
                difficulty: "4점",
                content: "데모용 축약 문항. 수열 {a_n}이 점화식과 절댓값 조건을 만족한다. |a3|=|a5| 관계와 추가 제약을 이용해 a3의 가능한 값을 좁히고, 부호·짝홀·0 케이스를 나눈 뒤 역추적으로 |a1|의 가능한 값을 복원해야 하는 문제다.",
                imageURLString: nil,
                answer: nil,
                solution: "앞에서 전개하지 않고 중간항과 절댓값 관계를 기준점으로 잡아 분기와 역추적을 통제하는 흐름을 데모한다.",
                normalizedExamVariant: examVariant.requestValue,
                normalizedPaperSection: "공통",
                normalizedPoints: 4,
                normalizedHasImage: false,
                metadata: PastQuestionMetadata(values: [
                    "is_common": .bool(true),
                    "paper_section": .string("공통"),
                    "points": .number(4),
                    "unit": .string("수열"),
                    "chapter": .string("점화식"),
                    "keywords": .array([
                        .string("수열"),
                        .string("점화식"),
                        .string("절댓값"),
                        .string("역추적"),
                        .string("a3"),
                        .string("a5")
                    ])
                ])
            )
        }
    }

    static let demoCSAT22: [NodeAnalysisDemoQuestionPreset] = [
        NodeAnalysisDemoQuestionPreset(
            id: "csat_2023_common_22",
            academicYear: 2023,
            label: "개념-해석형",
            subtitle: "평균값정리 -> 접선 -> 변곡점",
            summary: "평균변화율을 접선 의미로 바꾸고 g(1), 변곡점, 계수 결정으로 이어지는지 복기합니다.",
            subject: .math,
            month: 11,
            questionNumber: 22,
            examVariant: .common,
            examType: "수능"
        ),
        NodeAnalysisDemoQuestionPreset(
            id: "csat_2024_common_22",
            academicYear: 2024,
            label: "개형-배치형",
            subtitle: "정수 조건 -> x축 배치 제한",
            summary: "박스의 정수 조건을 그래프 배치 제한으로 읽고 삼차함수 교점 위치를 좁히는지 복기합니다.",
            subject: .math,
            month: 11,
            questionNumber: 22,
            examVariant: .common,
            examType: "수능"
        ),
        NodeAnalysisDemoQuestionPreset(
            id: "csat_2025_common_22",
            academicYear: 2025,
            label: "수열-역추적형",
            subtitle: "a3 기준 -> 절댓값 분기 -> 역추적",
            summary: "복잡한 점화식을 앞에서 밀지 않고 중간항과 절댓값 관계로 잠근 뒤 역추적하는지 복기합니다.",
            subject: .math,
            month: 11,
            questionNumber: 22,
            examVariant: .common,
            examType: "수능"
        )
    ]
}

nonisolated enum NodeAnalysisExamVariantOption: String, CaseIterable, Identifiable, Sendable {
    case unspecified = ""
    case common = "공통"
    case ga = "가형"
    case na = "나형"
    case integrated = "통합"

    var id: String { rawValue.isEmpty ? "unspecified" : rawValue }

    var title: String {
        switch self {
        case .unspecified:
            return "형 선택 안 함"
        case .common:
            return "공통"
        case .ga:
            return "가형"
        case .na:
            return "나형"
        case .integrated:
            return "통합"
        }
    }

    var requestValue: String? {
        rawValue.isEmpty ? nil : rawValue
    }
}

nonisolated struct NodeAnalysisWeaknessRecord: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var createdAt: Date
    var question: PastQuestionRecord
    var elapsedSeconds: Int
    var review: AnalysisPostSolveReview
    var wasExplicitlyMarked: Bool
}

nonisolated struct NodeAnalysisReviewDiagnosis: Hashable, Sendable {
    var categoryTitle: String
    var summary: String
    var blockedNode: String
    var why: String
    var nextAction: String
    var delayWarning: String? = nil
}

extension NodeAnalysisWeaknessRecord {
    nonisolated private var reviewPromptSet: AnalysisPostSolveReviewPromptSet {
        AnalysisPostSolveReviewPromptSet.promptSet(for: question)
    }

    nonisolated var titleLine: String {
        var parts: [String] = []
        if let year = question.year {
            parts.append("\(year)학년도")
        }
        if let month = question.month {
            parts.append("\(month)월")
        }
        parts.append(question.subject)
        parts.append("\(question.questionNumber)번")
        return parts.joined(separator: " ")
    }

    nonisolated var examVariantLabel: String? {
        question.examVariant
    }

    nonisolated var unitLabel: String? {
        question.metadata.unit
    }

    nonisolated var stuckStepTitle: String {
        guard let stepId = review.primaryStuckPoint else {
            return "막힌 단계 미지정"
        }
        return reviewPromptSet.stepTitle(for: stepId)
    }

    nonisolated var confidenceSummary: String {
        guard let confidenceAfter = review.confidenceAfter else {
            return "확신도 미기록"
        }
        return "확신도 \(confidenceAfter)"
    }

    nonisolated var elapsedLabel: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    nonisolated var reviewDiagnosis: NodeAnalysisReviewDiagnosis? {
        let optionIDs = selectedReviewOptionIDs
        guard !optionIDs.isEmpty else { return nil }

        if optionIDs.contains(where: { $0.hasPrefix("csat23_") }) {
            return diagnosisForCSAT2023()
        }

        if optionIDs.contains(where: { $0.hasPrefix("csat24_") }) {
            return diagnosisForCSAT2024()
        }

        if optionIDs.contains(where: { $0.hasPrefix("csat25_") }) {
            return diagnosisForCSAT2025()
        }

        return nil
    }

    nonisolated var recommendationSeedTerms: [String] {
        var seeds: [String] = []

        func append(_ term: String?) {
            guard let term else { return }
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2 else { return }
            guard !seeds.contains(trimmed) else { return }
            seeds.append(trimmed)
        }

        if let unitLabel {
            append(unitLabel)
        }

        for term in reviewSignalTerms {
            append(term)
        }

        for term in question.metadata.keywords.prefix(3) {
            append(term)
        }

        let contentTerms = question.content
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }
            .filter { !$0.allSatisfy(\.isNumber) }

        for token in contentTerms where !seeds.contains(token) {
            append(token)
            if seeds.count >= 6 {
                break
            }
        }

        return seeds
    }

    nonisolated private var reviewSignalTerms: [String] {
        var prioritizedTerms: [String] = []

        func appendTerms(from option: AnalysisReviewOptionDefinition?) {
            guard let option else { return }

            let candidates = option.searchKeywords.isEmpty
                ? [option.title]
                : option.searchKeywords + [option.title]

            for candidate in candidates {
                let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count >= 2 else { continue }
                guard !prioritizedTerms.contains(trimmed) else { continue }
                prioritizedTerms.append(trimmed)
            }
        }

        if let firstApproachID = review.firstApproach {
            appendTerms(from: reviewPromptSet.optionDefinition(for: firstApproachID))
        }

        let responses = review.reviewPath ?? []
        let prioritizedStatuses: [AnalysisReviewStepStatus] = [.failed, .partial, .clear, .notTried]

        for status in prioritizedStatuses {
            for response in responses where response.status == status {
                guard let selectedOptionID = response.selectedOptionId else { continue }
                appendTerms(from: reviewPromptSet.optionDefinition(for: selectedOptionID))
            }
        }

        appendTerms(from: review.primaryStuckPoint.map {
            AnalysisReviewOptionDefinition(id: $0, title: reviewPromptSet.stepTitle(for: $0))
        })

        return Array(prioritizedTerms.prefix(6))
    }

    nonisolated private var selectedReviewOptionIDs: [String] {
        var orderedIDs: [String] = []

        func append(_ optionID: String?) {
            guard let optionID else { return }
            guard !orderedIDs.contains(optionID) else { return }
            orderedIDs.append(optionID)
        }

        append(review.firstApproach)
        for response in review.reviewPath ?? [] {
            append(response.selectedOptionId)
        }

        return orderedIDs
    }

    nonisolated private var selectedReviewTitles: [String] {
        selectedReviewOptionIDs.compactMap { reviewPromptSet.optionDefinition(for: $0)?.title }
    }

    nonisolated private var diagnosisWhyLine: String {
        let titles = selectedReviewTitles
        guard !titles.isEmpty else {
            return "복기 선택지가 아직 충분히 기록되지 않았습니다."
        }

        let joined = titles.prefix(3).map { "“\($0)”" }.joined(separator: " -> ")
        return "복기 경로에서 \(joined)을 선택했습니다."
    }

    nonisolated private func selectedOptionID(for stepID: String) -> String? {
        review.reviewPath?.first(where: { $0.stepId == stepID })?.selectedOptionId
    }

    nonisolated private func makeDiagnosis(
        categoryTitle: String,
        summary: String,
        blockedNode: String,
        nextAction: String
    ) -> NodeAnalysisReviewDiagnosis {
        var delayWarning: String? = nil
        if let maxDelay = review.reviewPath?.compactMap({ $0.calculatedDelayMs }).max() {
            if maxDelay > 60000 {
                let minutes = maxDelay / 60000
                let seconds = (maxDelay % 60000) / 1000
                delayWarning = "⚠️ 특정 단계에서 \(minutes)분 \(seconds)초 이상 정체되었습니다. 초기 발상 속도를 높이는 연습이 필요합니다."
            } else if maxDelay > 0 {
                let seconds = maxDelay / 1000
                delayWarning = "✅ 인지 지연 체크됨: 최고 지연 \(seconds)초. 빠른 발상 속도입니다."
            }
        }

        return NodeAnalysisReviewDiagnosis(
            categoryTitle: categoryTitle,
            summary: summary,
            blockedNode: blockedNode,
            why: diagnosisWhyLine,
            nextAction: nextAction,
            delayWarning: delayWarning
        )
    }

    nonisolated private func matches(_ optionID: String?, in candidates: [String]) -> Bool {
        guard let optionID else { return false }
        return candidates.contains(optionID)
    }

    nonisolated private func diagnosisForCSAT2023() -> NodeAnalysisReviewDiagnosis {
        let firstApproach = review.firstApproach
        let secondStep = selectedOptionID(for: "interpretation_branch")
        let finalStep = selectedOptionID(for: "final_breakdown")

        if matches(finalStep, in: ["csat23_q3a_coefficients", "csat23_q3b_late_coefficients"]) {
            return makeDiagnosis(
                categoryTitle: "개념-해석형 진단",
                summary: "핵심 구조는 읽었지만, 마지막 일반형 정리와 계수 결정으로 닫는 과정이 흔들렸습니다.",
                blockedNode: "N-END-01 · 개형/접점 정보가 확보되면 -> 일반형에 필요한 최소 계수만 남기고 바로 대입한다",
                nextAction: "삼차함수 일반형을 세운 뒤 조건 2~3개로 닫는 후반부를 따로 연습하세요."
            )
        }

        if firstApproach == "csat23_q1_find_g"
            || matches(secondStep, in: ["csat23_q2b_choose_f_or_g", "csat23_q2b_formula_only"]) {
            return makeDiagnosis(
                categoryTitle: "개념-해석형 진단",
                summary: "보조함수 g(x)를 직접 구하는 쪽으로 들어가면서, 이 문항의 실제 주인공인 접점 구조를 놓쳤습니다.",
                blockedNode: "N-REP-01 · 보조함수 g(x)가 등장하면 -> 식을 직접 구하려 들기보다 원래 구조에서의 역할을 먼저 본다",
                nextAction: "보조함수 문제를 보면 먼저 '이 함수가 직접 대상인지, 다른 구조를 가리키는 장치인지'부터 판별하세요."
            )
        }

        if matches(
            secondStep,
            in: [
                "csat23_q2a_mvt_only",
                "csat23_q2a_stuck",
                "csat23_q2b_miss_g_role",
                "csat23_q2b_no_graph",
                "csat23_q3b_mvt_name_only",
                "csat23_q3b_no_tangent",
                "csat23_q3b_miss_g1"
            ]
        ) || matches(finalStep, in: ["csat23_q3b_mvt_name_only", "csat23_q3b_no_tangent", "csat23_q3b_miss_g1"]) {
            return makeDiagnosis(
                categoryTitle: "개념-해석형 진단",
                summary: "평균값정리라는 이름은 떠올렸지만, 그걸 접선·기울기·g(1) 의미로 바꾸는 데서 끊겼습니다.",
                blockedNode: "N-MVT-01 · 평균변화율 = 미분계수 꼴이 보이면 -> 식 변형보다 먼저 어떤 점의 접선인가를 해석한다",
                nextAction: "식 정리 전에 두 점-접선-중간점 스케치를 먼저 그리는 루틴을 고정하세요."
            )
        }

        return makeDiagnosis(
            categoryTitle: "개념-해석형 진단",
            summary: "평균값정리 구조와 접점 의미까지는 잡았지만, 고정 정보와 변곡점 추론을 수치화하는 연결이 충분히 단단하지 않았습니다.",
            blockedNode: "N-MVT-01 · 특정 입력값(x=1)이 반복되면 -> 그 점에서 얻는 고정 정보(g(1))를 먼저 잠근다",
            nextAction: "평균값정리 해석 뒤 바로 g(1) 같은 고정 정보 -> 변곡점/계수 결정으로 연결하는 연습이 필요합니다."
        )
    }

    nonisolated private func diagnosisForCSAT2024() -> NodeAnalysisReviewDiagnosis {
        let secondStep = selectedOptionID(for: "graph_constraint_branch")
        let finalStep = selectedOptionID(for: "final_breakdown")

        if finalStep == "csat24_q3b_too_many_cases" {
            return makeDiagnosis(
                categoryTitle: "개형-배치형 진단",
                summary: "초반 추론으로 경우를 줄여야 하는 문제인데, 분기를 너무 많이 열어 계산량이 폭주했습니다.",
                blockedNode: "N-CUBIC-01 · 조건이 복잡해 보여도 -> 먼저 개형, 다음 x축 배치, 마지막 수치화 순으로 단계 고정한다",
                nextAction: "개형 문제에서는 처음 30초 안에 경우를 늘리지 말고, x축 배치부터 삭제하는 습관을 들이세요."
            )
        }

        if matches(secondStep, in: ["csat24_q2a_unsure", "csat24_q2a_formula_only", "csat24_q2b_no_box"]) {
            return makeDiagnosis(
                categoryTitle: "개형-배치형 진단",
                summary: "박스의 정수 조건을 계산 조건으로만 보고, x축 주변 그래프 배치 제한으로 바꾸지 못했습니다.",
                blockedNode: "N-CUBIC-02 · 정수 k가 들어간 부호 조건이면 -> 식 계산보다 먼저 정수 간격 양끝의 부호 비교 상황으로 번역한다",
                nextAction: "모든 정수 k 조건이 보이면 숫자 대입보다 그래프 배치 번역부터 시작하세요."
            )
        }

        if matches(
            secondStep,
            in: [
                "csat24_q2a_root_layout",
                "csat24_q2b_no_axis",
                "csat24_q2b_root_count_shaky",
                "csat24_q3b_no_intersection"
            ]
        ) || finalStep == "csat24_q3b_no_intersection" {
            return makeDiagnosis(
                categoryTitle: "개형-배치형 진단",
                summary: "삼차함수 개형은 어느 정도 봤지만, x축과의 실제 배치를 잠그지 못해 실근 위치 추론이 흔들렸습니다.",
                blockedNode: "N-CUBIC-02 · 삼차함수에서 부호 조건이 주어지면 -> 실근 개수만 보지 말고 x축과의 상대 위치를 정수 간격 기준으로 본다",
                nextAction: "실근 개수 판단과 교점 위치 추론을 분리해서 연습하고, 정수 간격별 통과 가능 위치를 먼저 지우세요."
            )
        }

        let blockedNode: String
        if matches(finalStep, in: ["csat24_q3a_no_max_link", "csat24_q3b_no_max", "csat24_q3b_no_final_check"]) {
            blockedNode = "N-END-01 · 삼차함수 개형이 좁혀지면 -> 교점 배치와 목적식 값을 바로 연결한다"
        } else {
            blockedNode = "N-CUBIC-02 · 정수 간격 양끝의 부호 조건이 주어지면 -> x축 통과 가능 위치를 먼저 배제한다"
        }

        return makeDiagnosis(
            categoryTitle: "개형-배치형 진단",
            summary: "박스 조건을 그래프 배치 제한으로 읽는 출발은 맞았습니다. 다만 마지막 목적식 최대화나 종료 검산에서 속도가 떨어졌습니다.",
            blockedNode: blockedNode,
            nextAction: "교점 배치를 좁힌 뒤에는 바로 f(1) 같은 목적식과 연결하고, 마지막 10초는 검산만 따로 쓰세요."
        )
    }

    nonisolated private func diagnosisForCSAT2025() -> NodeAnalysisReviewDiagnosis {
        let firstApproach = review.firstApproach
        let secondStep = selectedOptionID(for: "sequence_pivot")
        let finalStep = selectedOptionID(for: "final_breakdown")

        if matches(finalStep, in: ["csat25_q3a_backtrack_error", "csat25_q3b_backtrack_confused"]) {
            return makeDiagnosis(
                categoryTitle: "수열-역추적형 진단",
                summary: "중간항 후보까지는 모았지만, a1으로 되돌리는 역추적 통제가 흔들렸습니다.",
                blockedNode: "N-SEQ-03 · 중간항 후보가 정해졌다면 -> 역추적으로 원래 항을 복원한다",
                nextAction: "후보마다 같은 순서로 역추적 표를 쓰는 루틴을 만들어 복원 과정을 고정하세요."
            )
        }

        if matches(finalStep, in: ["csat25_q3a_missing_case", "csat25_q3b_no_final_check"]) {
            return makeDiagnosis(
                categoryTitle: "수열-역추적형 진단",
                summary: "핵심 구조는 잡았지만, 마지막 합산 직전 누락·중복 검산이 약했습니다.",
                blockedNode: "N-END-01 · 케이스형 합산 문제는 -> 마지막에 누락·중복·종료조건 검산을 분리해서 한 번 더 한다",
                nextAction: "후보 나열이 끝나면 합산 전 10초를 따로 써서 0 케이스와 중복 계산을 다시 확인하세요."
            )
        }

        if matches(
            secondStep,
            in: [
                "csat25_q2b_abs_sign_confused",
                "csat25_q2b_zero_case",
                "csat25_q3a_zero_unsure"
            ]
        ) || finalStep == "csat25_q3a_zero_unsure" {
            return makeDiagnosis(
                categoryTitle: "수열-역추적형 진단",
                summary: "절댓값 관계는 봤지만, 부호·짝홀·0 케이스를 완전하게 분리하지 못했습니다.",
                blockedNode: "N-SEQ-02 · 절댓값 등식으로 후보가 생기면 -> 부호·짝홀·0을 분리해서 경우를 완전하게 나눈다",
                nextAction: "절댓값 수열 문제에서는 부호, 짝홀, 0 체크리스트를 고정해서 누락을 막으세요."
            )
        }

        if matches(firstApproach, in: ["csat25_q1_forward", "csat25_q1_no_pivot"])
            || matches(secondStep, in: ["csat25_q2b_too_many_terms", "csat25_q2b_no_a3_pivot"])
            || matches(finalStep, in: ["csat25_q3b_no_candidates", "csat25_q3b_gave_up"]) {
            return makeDiagnosis(
                categoryTitle: "수열-역추적형 진단",
                summary: "앞에서부터 전개하다가 계산량에 끌려가, a3 기준으로 잠그는 역추적 구조를 놓쳤습니다.",
                blockedNode: "N-SEQ-01 · 점화식이 복잡할수록 -> 처음부터 밀지 말고 반복되는 중간항 관계를 먼저 찾는다",
                nextAction: "점화식 문항은 전개 전에 기준점이 될 중간항을 먼저 정하고 시작하세요."
            )
        }

        return makeDiagnosis(
            categoryTitle: "수열-역추적형 진단",
            summary: "중간항과 절댓값 관계를 기준점으로 잡는 출발은 맞았습니다. 이제 후보 생성 뒤 검산 루틴만 더 짧게 만들면 됩니다.",
            blockedNode: "N-SEQ-03 · 절댓값 조건으로 후보를 얻었으면 -> 역추적으로 원래 항을 복원한다",
            nextAction: "a3 후보를 좁힌 뒤에는 각 후보를 같은 순서로 역추적하고, 마지막에 0 케이스만 별도로 재확인하세요."
        )
    }
}
