import Foundation

actor AnalysisPipelineEngine {
    func analyze(bundle: AnalysisBundle) async -> AnalysisResult {
        try? await Task.sleep(nanoseconds: 180_000_000)

        let features = normalize(bundle: bundle)
        let classification = classify(features: features, bundle: bundle)
        let scores = score(features: features, classification: classification, bundle: bundle)
        let concepts = makeConceptNodes(features: features, bundle: bundle, masteryScore: scores.masteryScore, confidenceScore: scores.confidenceScore)
        let evidence = makeEvidence(bundle: bundle, features: features, classification: classification, scores: scores)
        let misconceptions = makeMisconceptions(features: features, classification: classification, scores: scores)
        let reviewPlan = makeReviewPlan(features: features, classification: classification, scores: scores)
        let actions = makeRecommendedActions(classification: classification, concepts: concepts, reviewPlan: reviewPlan, scores: scores)
        let badges = makeBadges(classification: classification, scores: scores, reviewPlan: reviewPlan)

        return AnalysisResult(
            analysisId: UUID(),
            bundleId: bundle.bundleId,
            createdAt: Date(),
            documentId: bundle.document.documentId,
            pageId: bundle.page.pageId,
            summary: AnalysisResultSummary(
                headline: makeHeadline(classification: classification, scores: scores),
                body: makeBody(bundle: bundle, classification: classification, scores: scores, reviewPlan: reviewPlan),
                masteryScore: scores.masteryScore,
                confidenceScore: scores.confidenceScore
            ),
            classification: classification,
            conceptNodes: concepts,
            misconceptionCandidates: misconceptions,
            recommendedActions: actions,
            reviewPlan: reviewPlan,
            badges: badges,
            derivedSignals: AnalysisDerivedSignals(
                engagementScore: scores.engagementScore,
                struggleScore: scores.struggleScore,
                coverageScore: scores.coverageScore,
                isDensePage: features.isDensePage,
                hasMeaningfulInk: features.strokeCount > 0
            ),
            evidence: evidence,
            pipeline: AnalysisPipelineMetadata(
                engineVersion: "analysis-pipeline-v2",
                normalizedAt: Date(),
                featureVersion: 2
            )
        )
    }

    private func normalize(bundle: AnalysisBundle) -> NormalizedAnalysisFeatures {
        let sourceTexts = ([bundle.document.title] + bundle.content.pdfTextBlocks.map(\.text) + bundle.content.typedBlocks.map(\.text) + bundle.content.ocrTextBlocks.map(\.text) + bundle.content.manualTags)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let joinedText = sourceTexts.joined(separator: " ")
        let loweredText = joinedText.lowercased()

        let strokeCount = bundle.content.drawingStats.strokeCount
        let highlightCoverage = bundle.content.drawingStats.highlightCoverage
        let dwellMinutes = Double(bundle.behavior.dwellMs) / 60_000.0
        let editMinutes = Double(bundle.behavior.foregroundEditsMs) / 60_000.0
        let textLength = joinedText.count
        let formulaSignal = countOccurrences(in: joinedText, patterns: ["=", "+", "-", "×", "÷", "∫", "Σ", "sin", "cos", "log"])
        let problemSignal = countOccurrences(in: joinedText, patterns: ["문제", "문항", "정답", "해설", "풀이", "예제", "①", "②", "③", "④", "⑤"]) + formulaSignal
        let summarySignal = countOccurrences(in: joinedText, patterns: ["정리", "정의", "개념", "핵심", "요약", "공식", "포인트", "주의"])
        let memorizationSignal = countOccurrences(in: joinedText, patterns: ["암기", "외우", "키워드", "빈칸", "뜻", "용어"]) + countOccurrences(in: joinedText, patterns: [":", "-"])
        let lectureSignal = countOccurrences(in: joinedText, patterns: ["선생", "강의", "설명", "예시", "질문", "판서"])
        let reviewSignal = countOccurrences(in: joinedText, patterns: ["복습", "재확인", "다시", "오답", "체크", "헷갈"])

        let inferredSubject = inferSubject(
            from: bundle.document.subject ?? bundle.behavior.postSolveReview?.subject.title,
            text: loweredText
        )
        let inferredUnit = inferUnit(subject: inferredSubject, text: loweredText)
        let inferredConcepts = inferConcepts(subject: inferredSubject, text: loweredText, manualTags: bundle.content.manualTags)
        let reviewResponses = bundle.behavior.postSolveReview?.reviewPath ?? []
        let reviewAnsweredCount = reviewResponses.filter { $0.status != .notTried }.count
        let reviewFailedStepCount = reviewResponses.filter { $0.status == .failed }.count
        let reviewPartialStepCount = reviewResponses.filter { $0.status == .partial }.count
        let selfReportedConfidence = bundle.behavior.postSolveReview?.confidenceAfter.map {
            clamped(Double($0) / 100.0, min: 0, max: 1)
        }

        let engagementScore = normalized(
            dwellMinutes / 4.5
                + editMinutes / 3.0
                + Double(bundle.behavior.revisitCount) * 0.22
                + Double(strokeCount) / 70.0
        )
        let struggleScore = normalized(
            bundle.content.drawingStats.eraseRatio * 1.7
                + Double(bundle.behavior.undoCount + bundle.behavior.redoCount) / 12.0
                + Double(bundle.behavior.lassoActions) / 6.0
                + max(0, Double(problemSignal - summarySignal)) / 18.0
                + Double(reviewFailedStepCount) * 0.22
                + Double(reviewPartialStepCount) * 0.12
        )
        let coverageScore = normalized(
            Double(textLength) / 320.0
                + Double(strokeCount) / 90.0
                + highlightCoverage * 1.6
                + Double(min(bundle.content.pdfTextBlocks.count, 5)) / 5.0
                + Double(reviewAnsweredCount) / 8.0
        )

        return NormalizedAnalysisFeatures(
            strokeCount: strokeCount,
            highlightCoverage: highlightCoverage,
            dwellMinutes: dwellMinutes,
            editMinutes: editMinutes,
            textLength: textLength,
            problemSignal: problemSignal,
            summarySignal: summarySignal,
            memorizationSignal: memorizationSignal,
            lectureSignal: lectureSignal,
            reviewSignal: reviewSignal,
            engagementScore: engagementScore,
            struggleScore: struggleScore,
            coverageScore: coverageScore,
            inferredSubject: inferredSubject,
            inferredUnit: inferredUnit,
            inferredConcepts: inferredConcepts,
            isDensePage: strokeCount >= 28 || textLength >= 180 || bundle.content.pdfTextBlocks.count >= 2,
            hasPdfText: !bundle.content.pdfTextBlocks.isEmpty,
            hasManualTags: !bundle.content.manualTags.isEmpty,
            hasBookmarks: !bundle.content.bookmarks.isEmpty,
            hasStructuredReview: bundle.behavior.postSolveReview != nil,
            reviewAnsweredCount: reviewAnsweredCount,
            reviewFailedStepCount: reviewFailedStepCount,
            reviewPartialStepCount: reviewPartialStepCount,
            selfReportedConfidence: selfReportedConfidence,
            primaryStuckPoint: bundle.behavior.postSolveReview?.primaryStuckPoint,
            sourceText: joinedText
        )
    }

    private func classify(features: NormalizedAnalysisFeatures, bundle: AnalysisBundle) -> AnalysisClassification {
        var scores: [AnalysisDetectedStudyMode: Double] = [
            .conceptSummary: 0.15 + Double(features.summarySignal) * 0.18 + features.highlightCoverage * 0.6,
            .problemSolving: 0.15 + Double(features.problemSignal) * 0.16 + Double(bundle.behavior.undoCount + bundle.behavior.redoCount) * 0.04,
            .memorization: 0.1 + Double(features.memorizationSignal) * 0.22,
            .lectureNotes: 0.1 + Double(features.lectureSignal) * 0.18 + features.editMinutes * 0.08,
            .review: 0.1 + Double(features.reviewSignal) * 0.2 + Double(bundle.behavior.revisitCount) * 0.16
        ]

        switch bundle.behavior.studyIntent {
        case .summary:
            scores[.conceptSummary, default: 0] += 0.45
        case .problemSolving:
            scores[.problemSolving, default: 0] += 0.5
        case .lecture:
            scores[.lectureNotes, default: 0] += 0.45
        case .review:
            scores[.review, default: 0] += 0.45
        case .examPrep:
            scores[.problemSolving, default: 0] += 0.22
            scores[.review, default: 0] += 0.22
        case .unknown:
            break
        }

        if features.hasManualTags {
            scores[.conceptSummary, default: 0] += 0.12
        }
        if features.hasBookmarks {
            scores[.review, default: 0] += 0.08
        }

        let sorted = scores.sorted { lhs, rhs in lhs.value > rhs.value }
        let top = sorted.first
        let second = sorted.dropFirst().first
        let topMode = top?.key ?? .uncertain
        let confidenceGap = max((top?.value ?? 0) - (second?.value ?? 0), 0)

        let resolvedMode: AnalysisDetectedStudyMode
        if let top, let second, top.value > 0.75, second.value > 0.6, confidenceGap < 0.18 {
            resolvedMode = .mixed
        } else if (top?.value ?? 0) < 0.45 {
            resolvedMode = .uncertain
        } else {
            resolvedMode = topMode
        }

        let pageRole: AnalysisPageRole
        switch resolvedMode {
        case .conceptSummary:
            pageRole = features.reviewSignal >= 2 ? .correctionPage : .summaryPage
        case .problemSolving:
            pageRole = features.reviewSignal >= 2 ? .correctionPage : .problemPage
        case .memorization:
            pageRole = .flashcardPage
        case .lectureNotes:
            pageRole = .lecturePage
        case .review:
            pageRole = .referencePage
        case .mixed, .uncertain:
            pageRole = .mixedPage
        }

        return AnalysisClassification(
            studyMode: resolvedMode,
            pageRole: pageRole,
            subjectLabel: features.inferredSubject,
            unitLabel: features.inferredUnit,
            confidenceScore: clamped(0.42 + confidenceGap * 0.8 + (features.hasPdfText ? 0.08 : 0), min: 0.32, max: 0.94)
        )
    }

    private func score(
        features: NormalizedAnalysisFeatures,
        classification: AnalysisClassification,
        bundle: AnalysisBundle
    ) -> ScoredSignals {
        var masteryBase = 0.4 + (features.engagementScore * 0.24) + (features.coverageScore * 0.22) - (features.struggleScore * 0.2)
        var confidenceBase = 0.38 + (classification.confidenceScore * 0.42) + (features.coverageScore * 0.18) - (features.struggleScore * 0.12)

        switch classification.studyMode {
        case .conceptSummary:
            masteryBase += features.summarySignal >= 2 ? 0.08 : -0.03
        case .problemSolving:
            masteryBase += features.problemSignal >= 2 ? 0.04 : -0.06
            masteryBase -= Double(bundle.behavior.undoCount + bundle.behavior.redoCount) / 50.0
        case .memorization:
            confidenceBase -= 0.04
        case .lectureNotes:
            confidenceBase -= 0.02
        case .review:
            masteryBase += 0.03
        case .mixed:
            confidenceBase -= 0.05
        case .uncertain:
            confidenceBase -= 0.09
        }

        if features.hasManualTags {
            masteryBase += 0.04
        }
        if features.hasBookmarks {
            confidenceBase += 0.03
        }
        if features.hasStructuredReview {
            confidenceBase += 0.03
        }
        if let selfReportedConfidence = features.selfReportedConfidence {
            masteryBase += (selfReportedConfidence - 0.5) * 0.18
            confidenceBase += (selfReportedConfidence - 0.5) * 0.22
        }

        masteryBase -= Double(features.reviewFailedStepCount) / 18.0
        masteryBase -= Double(features.reviewPartialStepCount) / 28.0
        confidenceBase -= Double(features.reviewFailedStepCount) / 20.0

        let masteryScore = clamped(masteryBase, min: 0.24, max: 0.95)
        let confidenceScore = clamped(confidenceBase, min: 0.28, max: 0.96)

        return ScoredSignals(
            engagementScore: features.engagementScore,
            struggleScore: features.struggleScore,
            coverageScore: features.coverageScore,
            masteryScore: masteryScore,
            confidenceScore: confidenceScore
        )
    }

    private func makeConceptNodes(
        features: NormalizedAnalysisFeatures,
        bundle: AnalysisBundle,
        masteryScore: Double,
        confidenceScore: Double
    ) -> [AnalysisConceptNode] {
        let labels = Array(features.inferredConcepts.prefix(3))
        return labels.enumerated().map { index, label in
            AnalysisConceptNode(
                nodeId: "\(bundle.document.documentId.uuidString.lowercased()).concept.\(index)",
                label: label,
                masteryScore: clamped(masteryScore - Double(index) * 0.07, min: 0.2, max: 0.95),
                confidenceScore: clamped(confidenceScore - Double(index) * 0.05, min: 0.2, max: 0.96)
            )
        }
    }

    private func makeEvidence(
        bundle: AnalysisBundle,
        features: NormalizedAnalysisFeatures,
        classification: AnalysisClassification,
        scores: ScoredSignals
    ) -> [AnalysisEvidenceItem] {
        var items: [AnalysisEvidenceItem] = [
            AnalysisEvidenceItem(
                id: UUID(),
                title: "학습 유형 분류",
                detail: "페이지를 `\(classification.studyMode.title)` 흐름으로 읽었습니다. 이 분류는 현재 근거 기준 추정이며, 이후 수정될 수 있습니다.",
                strength: classification.confidenceScore
            ),
            AnalysisEvidenceItem(
                id: UUID(),
                title: "참여도 신호",
                detail: "머문 시간 \(String(format: "%.1f", features.dwellMinutes))분, 편집 시간 \(String(format: "%.1f", features.editMinutes))분, 필기 \(features.strokeCount)회가 기록됐습니다.",
                strength: scores.engagementScore
            ),
            AnalysisEvidenceItem(
                id: UUID(),
                title: "내용 커버리지",
                detail: "텍스트 길이 \(features.textLength)자, 형광펜 비율 \(percentage(features.highlightCoverage)), 커버리지 점수 \(percentage(scores.coverageScore))로 계산했습니다.",
                strength: scores.coverageScore
            )
        ]

        if let subject = classification.subjectLabel {
            items.append(
                AnalysisEvidenceItem(
                    id: UUID(),
                    title: "과목 인식",
                    detail: classification.unitLabel.map { "`\(subject)` · `\($0)` 맥락으로 해석했습니다." } ?? "`\(subject)` 과목 문맥으로 해석했습니다.",
                    strength: classification.confidenceScore
                )
            )
        }

        if let review = bundle.behavior.postSolveReview {
            var parts: [String] = []
            if let confidenceAfter = review.confidenceAfter {
                parts.append("직후 자신감 \(confidenceAfter)%")
            }
            if let firstApproach = review.firstApproach {
                parts.append("첫 접근 `\(humanizedReviewIdentifier(firstApproach))`")
            }
            if let primaryStuckPoint = review.primaryStuckPoint {
                parts.append("가장 막힌 단계 `\(readableReviewStepLabel(primaryStuckPoint))`")
            }
            if features.reviewFailedStepCount > 0 || features.reviewPartialStepCount > 0 {
                parts.append("review 경로에서 막힘 \(features.reviewFailedStepCount)개, 애매함 \(features.reviewPartialStepCount)개")
            }
            if let freeMemo = review.freeMemo?.trimmingCharacters(in: .whitespacesAndNewlines),
               !freeMemo.isEmpty {
                parts.append("메모 \(String(freeMemo.prefix(32)))")
            }

            items.append(
                AnalysisEvidenceItem(
                    id: UUID(),
                    title: "풀이 직후 자가 리뷰",
                    detail: parts.isEmpty
                        ? "풀이 직후 회고 입력이 함께 저장되었습니다."
                        : parts.joined(separator: ", ") + "를 함께 수집했습니다.",
                    strength: clamped(0.46 + Double(features.reviewAnsweredCount) * 0.08, min: 0.46, max: 0.9)
                )
            )
        }

        if scores.struggleScore > 0.42 {
            items.append(
                AnalysisEvidenceItem(
                    id: UUID(),
                    title: "마찰 신호",
                    detail: "undo/redo \(bundleUndoRedoLabel(scores: scores))와 수정 패턴 때문에 학습 마찰을 감지했습니다.",
                    strength: scores.struggleScore
                )
            )
        }

        return Array(items.sorted { $0.strength > $1.strength }.prefix(4))
    }

    private func makeMisconceptions(
        features: NormalizedAnalysisFeatures,
        classification: AnalysisClassification,
        scores: ScoredSignals
    ) -> [AnalysisMisconceptionCandidate] {
        var items: [AnalysisMisconceptionCandidate] = []

        if classification.studyMode == .problemSolving && scores.struggleScore > 0.48 {
            items.append(
                AnalysisMisconceptionCandidate(
                    id: UUID(),
                    label: "풀이 전개가 안정적으로 고정되지 않았을 가능성",
                    reason: "문제 풀이 패턴이 강한데 수정 마찰이 높아, 중간 단계에서 전략을 여러 번 바꾼 흔적이 있습니다.",
                    severity: clamped(scores.struggleScore, min: 0.34, max: 0.9)
                )
            )
        }

        if classification.studyMode == .conceptSummary && features.summarySignal < 2 {
            items.append(
                AnalysisMisconceptionCandidate(
                    id: UUID(),
                    label: "개념 정리 구조가 덜 선명할 가능성",
                    reason: "요약 의도에 비해 정의/정리/핵심 신호가 약합니다. 기준 문장과 예외 조건을 더 분리하는 편이 좋습니다.",
                    severity: 0.41
                )
            )
        }

        if classification.studyMode == .memorization && scores.coverageScore < 0.4 {
            items.append(
                AnalysisMisconceptionCandidate(
                    id: UUID(),
                    label: "암기 단서가 충분히 분리되지 않았을 가능성",
                    reason: "암기 세션으로 보이지만 cue/answer 구조가 약해 회상 단위가 흐릴 수 있습니다.",
                    severity: 0.38
                )
            )
        }

        return Array(items.prefix(2))
    }

    private func makeRecommendedActions(
        classification: AnalysisClassification,
        concepts: [AnalysisConceptNode],
        reviewPlan: AnalysisReviewPlan,
        scores: ScoredSignals
    ) -> [AnalysisRecommendedAction] {
        let focusConcept = concepts.first?.label ?? "핵심 개념"
        var actions: [AnalysisRecommendedAction] = []

        actions.append(
            AnalysisRecommendedAction(
                id: UUID(),
                title: reviewPlan.shouldReviewSoon ? "짧은 복습 큐로 다시 보내기" : "다음 학습 루프로 넘기기",
                detail: reviewPlan.shouldReviewSoon
                    ? "약 \(reviewPlan.recommendedHoursUntilReview)시간 내에 다시 열어 핵심 근거를 한 번 더 확인하세요."
                    : "현재 페이지는 다음 학습 루프로 넘겨도 됩니다. 필요 시 pharnode 대시보드에서 이어서 관리하세요.",
                style: .revisit
            )
        )

        switch classification.studyMode {
        case .problemSolving:
            actions.append(
                AnalysisRecommendedAction(
                    id: UUID(),
                    title: "\(focusConcept) 풀이 근거 2줄 보강",
                    detail: "정답만 남기지 말고 중간 전개 이유를 2줄만 보강해 두면 재학습 효율이 올라갑니다.",
                    style: .practice
                )
            )
        case .conceptSummary:
            actions.append(
                AnalysisRecommendedAction(
                    id: UUID(),
                    title: "\(focusConcept) 기준으로 정의/예외 분리",
                    detail: "핵심 문장, 예시, 주의 포인트를 분리하면 이후 복습과 검색 품질이 올라갑니다.",
                    style: .summarize
                )
            )
        case .memorization:
            actions.append(
                AnalysisRecommendedAction(
                    id: UUID(),
                    title: "암기 카드 단위로 쪼개기",
                    detail: "한 단원 전체를 외우기보다 회상 단위가 되는 질문/답 구조로 다시 나누세요.",
                    style: .summarize
                )
            )
        case .lectureNotes, .review, .mixed, .uncertain:
            actions.append(
                AnalysisRecommendedAction(
                    id: UUID(),
                    title: "\(focusConcept) 중심으로 다음 복습 기준 만들기",
                    detail: "다음에 이 페이지를 열었을 때 무엇을 확인할지 한 줄 기준을 남기세요.",
                    style: .revisit
                )
            )
        }

        if scores.struggleScore > 0.5 {
            actions.append(
                AnalysisRecommendedAction(
                    id: UUID(),
                    title: "pharnode에서 취약 지점 점검",
                    detail: "마찰이 높게 잡힌 페이지라 장기 대시보드에서 취약 단원 흐름과 같이 보는 편이 좋습니다.",
                    style: .inspectInPharnode
                )
            )
        }

        return actions
    }

    private func makeReviewPlan(
        features: NormalizedAnalysisFeatures,
        classification: AnalysisClassification,
        scores: ScoredSignals
    ) -> AnalysisReviewPlan {
        let shouldReviewSoon = scores.masteryScore < 0.68 || scores.struggleScore > 0.45 || classification.studyMode == .memorization
        let hours: Int
        if scores.masteryScore < 0.48 {
            hours = 6
        } else if shouldReviewSoon {
            hours = 18
        } else {
            hours = 48
        }

        let reason: String
        if classification.studyMode == .problemSolving && scores.struggleScore > 0.45 {
            reason = "풀이 전략이 완전히 굳지 않아 짧은 간격으로 다시 보는 편이 좋습니다."
        } else if classification.studyMode == .memorization {
            reason = "암기 세션은 짧은 지연 회상 루프로 다시 돌릴수록 유지율이 올라갑니다."
        } else if features.summarySignal >= 2 && scores.masteryScore >= 0.72 {
            reason = "핵심 구조는 잡혀 있어 다음 루프에서 재확인하면 충분합니다."
        } else {
            reason = "이해는 형성됐지만 아직 자동화된 수준은 아니라 빠른 재확인이 유리합니다."
        }

        return AnalysisReviewPlan(
            shouldReviewSoon: shouldReviewSoon,
            recommendedHoursUntilReview: hours,
            reviewReason: reason
        )
    }

    private func makeBadges(
        classification: AnalysisClassification,
        scores: ScoredSignals,
        reviewPlan: AnalysisReviewPlan
    ) -> [AnalysisBadge] {
        var badges = [AnalysisBadge(kind: .analyzed, title: "인사이트 생성됨")]

        if reviewPlan.shouldReviewSoon {
            badges.append(AnalysisBadge(kind: .reviewDue, title: "곧 다시 보기"))
        }
        if scores.masteryScore < 0.62 {
            badges.append(AnalysisBadge(kind: .needsPractice, title: "보강 필요"))
        } else if scores.masteryScore > 0.82 {
            badges.append(AnalysisBadge(kind: .wellUnderstood, title: "구조 안정적"))
        }
        if classification.confidenceScore < 0.58 || scores.confidenceScore < 0.56 {
            badges.append(AnalysisBadge(kind: .lowConfidence, title: "근거 더 필요"))
        }

        return badges
    }

    private func makeHeadline(classification: AnalysisClassification, scores: ScoredSignals) -> String {
        switch classification.studyMode {
        case .conceptSummary:
            if scores.masteryScore >= 0.78 {
                return "개념 정리 흐름이 비교적 안정적으로 잡힌 페이지입니다."
            }
            return "개념 정리 흔적은 충분하지만 한 번 더 정리 기준을 세우면 좋아지는 페이지입니다."
        case .problemSolving:
            if scores.struggleScore > 0.5 {
                return "문제 풀이 과정에서 잠깐 멈춘 지점이 보이는 페이지입니다."
            }
            return "문제 풀이 흐름은 보이지만 중간 근거를 조금 더 남기면 다시 보기 쉬워집니다."
        case .memorization:
            return "암기 흐름으로 보이며 회상 단위를 더 잘게 나누면 효율이 좋아질 수 있습니다."
        case .lectureNotes:
            return "강의 필기형 페이지로 보이며 핵심 문장을 한 번 더 추리면 다음 단계가 편해집니다."
        case .review:
            return "복습용 페이지로 보여 짧은 재확인 루프에 넣기 좋은 상태입니다."
        case .mixed:
            return "한 페이지 안에 여러 학습 목적이 섞여 있어 다음에 볼 때 기준을 나눠두는 편이 좋습니다."
        case .uncertain:
            return "학습 목적을 아직 단정하기 어려워 조금 더 근거를 모으는 편이 안전합니다."
        }
    }

    private func makeBody(
        bundle: AnalysisBundle,
        classification: AnalysisClassification,
        scores: ScoredSignals,
        reviewPlan: AnalysisReviewPlan
    ) -> String {
        let pageLabel = "p.\(bundle.page.pageIndex + 1)"
        let subjectLine = classification.subjectLabel.map { "과목은 `\($0)`" } ?? "과목은 아직 미확정"
        let unitLine = classification.unitLabel.map { "단원은 `\($0)`" } ?? "단원 힌트는 부족"
        let reviewLine: String
        if let review = bundle.behavior.postSolveReview {
            let stuckLine = review.primaryStuckPoint.map { "가장 막힌 단계는 `\(readableReviewStepLabel($0))`" } ?? "막힌 단계는 미선택"
            let confidenceLine = review.confidenceAfter.map { "직후 자신감은 \($0)%" } ?? "직후 자신감은 미기록"
            reviewLine = " 자가 리뷰 기준 \(confidenceLine)이며, \(stuckLine)로 남겼습니다."
        } else {
            reviewLine = ""
        }
        return "\(pageLabel) 기준으로 `\(classification.studyMode.title)` 흐름으로 읽었습니다. \(subjectLine), \(unitLine)입니다. 현재 이해 상태는 \(masteryDescriptor(scores.masteryScore)), 근거 상태는 \(confidenceDescriptor(scores.confidenceScore))으로 보이며, \(reviewPlan.reviewReason)\(reviewLine)"
    }

    private func inferSubject(from existing: String?, text: String) -> String? {
        if let existing, !existing.isEmpty {
            return existing
        }

        let subjectLexicon: [(String, [String])] = [
            ("수학", ["적분", "미분", "함수", "수열", "기하", "확률", "통계", "극한"]),
            ("국어", ["문학", "독서", "언어", "매체", "화법", "작문", "비문학"]),
            ("영어", ["독해", "구문", "영문법", "영단어", "빈칸", "순서"]),
            ("물리", ["역학", "전자기", "파동", "전류", "힘", "운동량"]),
            ("화학", ["몰", "산화", "환원", "평형", "반응속도", "화학식"]),
            ("생명과학", ["유전", "세포", "광합성", "호흡", "생태", "신경"]),
            ("지구과학", ["판구조", "대기", "천체", "해양", "암석", "지층"]),
            ("사탐", ["사회문화", "생활과윤리", "윤리", "한국지리", "세계지리", "정치와법", "경제"]),
            ("한국사", ["조선", "고려", "개항", "근대", "현대사"]) 
        ]

        return subjectLexicon
            .map { label, keywords in
                (label, keywords.reduce(0) { partial, keyword in partial + (text.contains(keyword) ? 1 : 0) })
            }
            .sorted { $0.1 > $1.1 }
            .first(where: { $0.1 > 0 })?
            .0
    }

    private func inferUnit(subject: String?, text: String) -> String? {
        let unitLexicon: [String: [String]] = [
            "수학": ["미분", "적분", "수열", "함수의 극한", "지수함수", "로그함수", "기하", "확률과 통계"],
            "국어": ["문학", "독서", "언어와 매체", "화법과 작문"],
            "영어": ["독해", "구문", "어휘", "영문법"],
            "물리": ["역학", "전자기", "파동", "열역학"],
            "화학": ["화학 결합", "몰", "평형", "산염기", "유기"],
            "생명과학": ["세포", "유전", "항상성", "생태계"],
            "지구과학": ["대기", "해양", "천체", "지질"],
            "사탐": ["사회문화", "생활과윤리", "윤리와사상", "한국지리", "세계지리", "정치와법", "경제"],
            "한국사": ["전근대사", "근현대사", "개항기"]
        ]

        guard let subject, let candidates = unitLexicon[subject] else { return nil }
        return candidates.first(where: { text.contains($0.lowercased()) || text.contains($0) })
    }

    private func inferConcepts(subject: String?, text: String, manualTags: [String]) -> [String] {
        if !manualTags.isEmpty {
            return orderedUnique(manualTags)
        }

        let subjectConcepts: [String: [String]] = [
            "수학": ["치환적분", "부분적분", "정적분", "미분계수", "극한", "수열", "확률", "경우의 수"],
            "국어": ["주제 파악", "선지 판단", "문학 개념", "비문학 구조"],
            "영어": ["구문 해석", "빈칸 추론", "순서 배열", "어휘 정리"],
            "물리": ["힘의 평형", "운동량 보존", "전자기 유도", "파동 간섭"],
            "화학": ["몰 계산", "평형 이동", "산화 환원", "반응 속도"],
            "생명과학": ["세포 호흡", "유전 추론", "항상성", "생태 상호작용"],
            "지구과학": ["판 구조론", "대기 순환", "천체 운동", "암석 순환"],
            "사탐": ["개념 비교", "자료 해석", "사례 적용"],
            "한국사": ["시대 구분", "정책 변화", "사료 해석"]
        ]

        var matches: [String] = []
        if let subject, let candidates = subjectConcepts[subject] {
            matches.append(contentsOf: candidates.filter { text.contains($0.lowercased()) || text.contains($0) })
        }

        if matches.isEmpty {
            matches.append(contentsOf: fallbackKeywords(from: text))
        }

        if matches.isEmpty {
            matches = [fallbackConcept(subject: subject)]
        }

        if matches.count == 1 {
            matches.append(secondaryConcept(subject: subject, hasPdfText: !text.isEmpty))
        }

        return Array(orderedUnique(matches).prefix(3))
    }

    private func fallbackKeywords(from text: String) -> [String] {
        let stopwords: Set<String> = ["the", "and", "for", "with", "this", "that", "문제", "풀이", "정리", "개념", "페이지", "이번", "현재", "다음"]
        let tokens = text
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
            .filter { $0.count >= 2 && !stopwords.contains($0.lowercased()) }
        return Array(orderedUnique(tokens).prefix(2)).map { "\($0) 개념" }
    }

    private func fallbackConcept(subject: String?) -> String {
        switch subject {
        case "수학": return "핵심 풀이 구조"
        case "국어": return "핵심 독해 포인트"
        case "영어": return "핵심 해석 포인트"
        case "물리", "화학", "생명과학", "지구과학": return "핵심 과학 개념"
        default: return "페이지 핵심 개념"
        }
    }

    private func secondaryConcept(subject: String?, hasPdfText: Bool) -> String {
        if hasPdfText {
            return "교재 문맥 이해"
        }
        switch subject {
        case "수학": return "자기 설명 흔적"
        case "국어", "영어": return "핵심 근거 표시"
        default: return "학습 흐름 정리"
        }
    }

    private func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            ordered.append(trimmed)
        }
        return ordered
    }

    private func countOccurrences(in text: String, patterns: [String]) -> Int {
        patterns.reduce(0) { partial, pattern in
            partial + (text.localizedCaseInsensitiveContains(pattern) ? 1 : 0)
        }
    }

    private func normalized(_ value: Double) -> Double {
        clamped(value, min: 0.0, max: 1.0)
    }

    private func clamped(_ value: Double, min minimum: Double, max maximum: Double) -> Double {
        Swift.max(minimum, Swift.min(maximum, value))
    }

    private func percentage(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func readableReviewStepLabel(_ identifier: String) -> String {
        switch identifier {
        case "condition_parse":
            return "조건 해석"
        case "strategy_choice":
            return "풀이 방향"
        case "execution":
            return "전개/풀이"
        case "verification":
            return "검산"
        default:
            return humanizedReviewIdentifier(identifier)
        }
    }

    private func humanizedReviewIdentifier(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func masteryDescriptor(_ score: Double) -> String {
        switch score {
        case 0.8...:
            return "안정적인 편"
        case 0.62...:
            return "무난한 편"
        case 0.45...:
            return "보강이 필요한 편"
        default:
            return "다시 확인이 필요한 편"
        }
    }

    private func confidenceDescriptor(_ score: Double) -> String {
        switch score {
        case 0.78...:
            return "충분한 편"
        case 0.58...:
            return "보통 수준"
        default:
            return "아직 제한적"
        }
    }

    private func bundleUndoRedoLabel(scores: ScoredSignals) -> String {
        "마찰 점수 \(percentage(scores.struggleScore))"
    }
}

private struct NormalizedAnalysisFeatures {
    var strokeCount: Int
    var highlightCoverage: Double
    var dwellMinutes: Double
    var editMinutes: Double
    var textLength: Int
    var problemSignal: Int
    var summarySignal: Int
    var memorizationSignal: Int
    var lectureSignal: Int
    var reviewSignal: Int
    var engagementScore: Double
    var struggleScore: Double
    var coverageScore: Double
    var inferredSubject: String?
    var inferredUnit: String?
    var inferredConcepts: [String]
    var isDensePage: Bool
    var hasPdfText: Bool
    var hasManualTags: Bool
    var hasBookmarks: Bool
    var hasStructuredReview: Bool
    var reviewAnsweredCount: Int
    var reviewFailedStepCount: Int
    var reviewPartialStepCount: Int
    var selfReportedConfidence: Double?
    var primaryStuckPoint: String?
    var sourceText: String
}

private struct ScoredSignals {
    var engagementScore: Double
    var struggleScore: Double
    var coverageScore: Double
    var masteryScore: Double
    var confidenceScore: Double
}
