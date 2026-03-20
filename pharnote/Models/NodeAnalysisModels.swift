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

nonisolated struct NodeAnalysisReviewNodeChip: Identifiable, Hashable, Sendable {
    var nodeId: String
    var label: String
    var detail: String?

    var id: String { "\(nodeId)::\(label)" }
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

    nonisolated var reviewDiagnosis: NodeAnalysisReviewDiagnosis {
        synthesizeDiagnosis()
    }

    nonisolated var reviewNodeChips: [NodeAnalysisReviewNodeChip] {
        reviewNodeReferences().map { reference in
            NodeAnalysisReviewNodeChip(
                nodeId: reference.nodeId,
                label: reference.label,
                detail: reference.detail
            )
        }
    }

    nonisolated private func synthesizeDiagnosis() -> NodeAnalysisReviewDiagnosis {
        let references = reviewNodeReferences()
        let blockedNode = references.first?.displayLine ?? (reviewPromptSet.subject == .math ? "N-MATH-GEN" : "N-GEN-01")

        let summary: String
        if let firstReference = references.first {
            let extraCount = max(references.count - 1, 0)
            summary = extraCount > 0
                ? "복기에서 \(firstReference.displayLine) 외 \(extraCount)개 노드가 연결되었습니다."
                : "복기에서 \(firstReference.displayLine) 노드가 가장 먼저 잡혔습니다."
        } else {
            summary = review.primaryStuckPoint.map { "막힌 지점: \(reviewPromptSet.stepTitle(for: $0))" }
                ?? "\(reviewPromptSet.subject.title) 학습 흐름 분석 결과입니다."
        }

        return makeDiagnosis(
            categoryTitle: "\(reviewPromptSet.subject.title) 학습 진단",
            summary: summary,
            blockedNode: blockedNode,
            nextAction: references.isEmpty
                ? "복기 결과를 바탕으로 취약 지점을 보완하고 추천 문항으로 실력을 다지세요."
                : "PharNode에서 \(references.first?.displayLine ?? "복기 노드")를 다시 열어 같은 노드 흐름을 확인하세요."
        )
    }

    nonisolated private struct ReviewNodeReference: Hashable, Sendable {
        var nodeId: String
        var label: String
        var detail: String?

        var displayLine: String {
            "\(nodeId) · \(label)"
        }
    }

    nonisolated private func reviewNodeReferences() -> [ReviewNodeReference] {
        var references: [ReviewNodeReference] = []
        var seenNodeIds: Set<String> = []

        func append(option: AnalysisReviewOptionDefinition?, detail: String? = nil) {
            guard let option else { return }
            let nodeId = option.searchKeywords.first ?? option.id
            guard seenNodeIds.insert(nodeId).inserted else { return }
            references.append(
                ReviewNodeReference(
                    nodeId: nodeId,
                    label: option.title,
                    detail: detail
                )
            )
        }

        if let derivedNodeIds = review.derivedNodeIds,
           let derivedNodeLabels = review.derivedNodeLabels {
            for (index, nodeId) in derivedNodeIds.enumerated() {
                let label = derivedNodeLabels.indices.contains(index) ? derivedNodeLabels[index] : nodeId
                guard seenNodeIds.insert(nodeId).inserted else { continue }
                references.append(
                    ReviewNodeReference(
                        nodeId: nodeId,
                        label: label,
                        detail: review.derivedEvidenceTypes.flatMap { $0.indices.contains(index) ? $0[index] : nil }
                    )
                )
            }
        }

        if let firstID = review.firstApproach,
           let option = reviewPromptSet.optionDefinition(for: firstID) {
            append(option: option)
        }

        for response in review.reviewPath ?? [] {
            guard let selectedOptionID = response.selectedOptionId,
                  let option = reviewPromptSet.optionDefinition(for: selectedOptionID) else {
                continue
            }
            append(option: option, detail: response.linkedStrokeId)
        }

        if let primaryStuckPoint = review.primaryStuckPoint {
            append(option: AnalysisReviewOptionDefinition(id: primaryStuckPoint, title: reviewPromptSet.stepTitle(for: primaryStuckPoint)))
        }

        return references
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

        if let derivedNodeLabels = review.derivedNodeLabels {
            for label in derivedNodeLabels {
                appendTerms(from: AnalysisReviewOptionDefinition(id: label, title: label))
            }
        }

        if let derivedNodeIds = review.derivedNodeIds {
            for nodeId in derivedNodeIds {
                appendTerms(from: AnalysisReviewOptionDefinition(id: nodeId, title: nodeId))
            }
        }

        return Array(prioritizedTerms.prefix(6))
    }

    nonisolated private var selectedReviewTitles: [String] {
        reviewNodeReferences().map { $0.label }
    }

    nonisolated private var diagnosisWhyLine: String {
        let titles = selectedReviewTitles
        guard !titles.isEmpty else {
            return "복기 선택지가 아직 충분히 기록되지 않았습니다."
        }

        let joined = titles.prefix(3).map { "“\($0)”" }.joined(separator: " -> ")
        return "복기 경로에서 \(joined)을 선택했습니다."
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
}
