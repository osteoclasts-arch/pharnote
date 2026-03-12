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

nonisolated enum NodeAnalysisSessionPhase: String, Hashable, Sendable {
    case idle
    case questionReady = "question_ready"
    case solving
    case confidenceSurvey = "confidence_survey"
    case review
    case completed
}

nonisolated enum NodeAnalysisReviewStage: Hashable, Sendable {
    case firstApproach
    case step(index: Int)
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

extension NodeAnalysisWeaknessRecord {
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
        question.metadata.examVariant
    }

    nonisolated var unitLabel: String? {
        question.metadata.unit
    }

    nonisolated var stuckStepTitle: String {
        guard let stepId = review.primaryStuckPoint else {
            return "막힌 단계 미지정"
        }
        return AnalysisPostSolveReviewPromptSet.promptSet(for: review.subject).stepTitle(for: stepId)
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

    nonisolated var recommendationSeedTerms: [String] {
        var seeds: [String] = []

        if let unitLabel {
            seeds.append(unitLabel)
        }

        seeds.append(contentsOf: question.metadata.keywords.prefix(3))

        let contentTerms = question.content
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }
            .filter { !$0.allSatisfy(\.isNumber) }

        for token in contentTerms where !seeds.contains(token) {
            seeds.append(token)
            if seeds.count >= 6 {
                break
            }
        }

        return seeds
    }
}
