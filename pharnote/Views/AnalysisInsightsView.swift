import SwiftUI

struct AnalysisHeaderInsightBlock: View {
    let result: AnalysisResult

    var body: some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.xSmall) {
            AnalysisBadgeRow(result: result, limit: 3)

            Text(result.summary.headline)
                .font(PharTypography.bodyStrong)
                .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                .lineLimit(2)

            HStack(spacing: PharTheme.Spacing.xSmall) {
                if let classification = result.classification {
                    AnalysisMetricPill(
                        title: "유형",
                        value: classification.studyMode.title,
                        tint: PharTheme.ColorToken.accentButter.opacity(0.22)
                    )
                }
                AnalysisMetricPill(
                    title: "이해 상태",
                    value: masteryLabel(result.summary.masteryScore),
                    tint: PharTheme.ColorToken.accentMint.opacity(0.26)
                )
                AnalysisMetricPill(
                    title: "근거 상태",
                    value: confidenceLabel(result.summary.confidenceScore),
                    tint: PharTheme.ColorToken.accentBlue.opacity(0.16)
                )
                if let firstConcept = result.conceptNodes.first {
                    AnalysisMetricPill(
                        title: "핵심",
                        value: firstConcept.label,
                        tint: PharTheme.ColorToken.accentButter.opacity(0.22)
                    )
                }
            }

            if let firstAction = result.recommendedActions.first {
                Text(firstAction.title)
                    .font(PharTypography.captionStrong)
                    .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                    .lineLimit(1)
            }
        }
    }
}

struct AnalysisResultDetailCard: View {
    let result: AnalysisResult

    var body: some View {
        PharSurfaceCard(fill: PharTheme.ColorToken.surfacePrimary.opacity(0.96)) {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                VStack(alignment: .leading, spacing: PharTheme.Spacing.xSmall) {
                    Text("페이지 인사이트")
                        .font(PharTypography.cardTitle)
                        .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                    Text(result.summary.headline)
                        .font(PharTypography.bodyStrong)
                        .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                    Text(result.summary.body)
                        .font(PharTypography.caption)
                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                }

                AnalysisBadgeRow(result: result, limit: 4)

                HStack(spacing: PharTheme.Spacing.xSmall) {
                    AnalysisMetricPill(
                        title: "이해 상태",
                        value: masteryLabel(result.summary.masteryScore),
                        tint: PharTheme.ColorToken.accentMint.opacity(0.26)
                    )
                    AnalysisMetricPill(
                        title: "근거 상태",
                        value: confidenceLabel(result.summary.confidenceScore),
                        tint: PharTheme.ColorToken.accentBlue.opacity(0.16)
                    )
                    AnalysisMetricPill(
                        title: "다음 권장",
                        value: result.reviewPlan.shouldReviewSoon ? "짧게 다시 보기" : "여유 있음",
                        tint: PharTheme.ColorToken.accentPeach.opacity(0.24)
                    )
                }

                if let classification = result.classification {
                    VStack(alignment: .leading, spacing: PharTheme.Spacing.xSmall) {
                        Text("인식된 맥락")
                            .font(PharTypography.captionStrong)
                            .foregroundStyle(PharTheme.ColorToken.inkSecondary)

                        FlexiblePillRow(items: detectedContextItems(for: classification)) { item in
                            AnalysisMetricPill(
                                title: item.title,
                                value: item.value,
                                tint: PharTheme.ColorToken.surfaceTertiary
                            )
                        }
                    }
                }

                if !result.conceptNodes.isEmpty {
                    VStack(alignment: .leading, spacing: PharTheme.Spacing.xSmall) {
                        Text("핵심 개념")
                            .font(PharTypography.captionStrong)
                            .foregroundStyle(PharTheme.ColorToken.inkSecondary)

                        FlowConceptRow(concepts: result.conceptNodes)
                    }
                }

                if !result.misconceptionCandidates.isEmpty {
                    VStack(alignment: .leading, spacing: PharTheme.Spacing.xSmall) {
                        Text("헷갈릴 수 있는 지점")
                            .font(PharTypography.captionStrong)
                            .foregroundStyle(PharTheme.ColorToken.inkSecondary)

                        ForEach(result.misconceptionCandidates) { item in
                            VStack(alignment: .leading, spacing: PharTheme.Spacing.xxxSmall) {
                                Text(item.label)
                                    .font(PharTypography.bodyStrong)
                                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                                Text(item.reason)
                                    .font(PharTypography.caption)
                                    .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                            }
                            .padding(PharTheme.Spacing.small)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                                    .fill(PharTheme.ColorToken.surfaceSecondary)
                            )
                        }
                    }
                }

                if let evidence = result.evidence, !evidence.isEmpty {
                    VStack(alignment: .leading, spacing: PharTheme.Spacing.xSmall) {
                        Text("분석 근거")
                            .font(PharTypography.captionStrong)
                            .foregroundStyle(PharTheme.ColorToken.inkSecondary)

                        ForEach(evidence) { item in
                            VStack(alignment: .leading, spacing: PharTheme.Spacing.xxxSmall) {
                                HStack(spacing: PharTheme.Spacing.xSmall) {
                                    Text(item.title)
                                        .font(PharTypography.bodyStrong)
                                        .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                                    Spacer(minLength: 0)
                                    Text(strengthLabel(item.strength))
                                        .font(PharTypography.captionStrong)
                                        .foregroundStyle(PharTheme.ColorToken.accentBlue)
                                }
                                Text(item.detail)
                                    .font(PharTypography.caption)
                                    .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                            }
                            .padding(PharTheme.Spacing.small)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                                    .fill(PharTheme.ColorToken.surfaceSecondary)
                            )
                        }
                    }
                }

                if !result.recommendedActions.isEmpty {
                    VStack(alignment: .leading, spacing: PharTheme.Spacing.xSmall) {
                        Text("추천 다음 행동")
                            .font(PharTypography.captionStrong)
                            .foregroundStyle(PharTheme.ColorToken.inkSecondary)

                        ForEach(result.recommendedActions) { action in
                            HStack(alignment: .top, spacing: PharTheme.Spacing.small) {
                                Image(systemName: icon(for: action.style))
                                    .foregroundStyle(PharTheme.ColorToken.accentBlue)
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: PharTheme.Spacing.xxxSmall) {
                                    Text(action.title)
                                        .font(PharTypography.bodyStrong)
                                        .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                                    Text(action.detail)
                                        .font(PharTypography.caption)
                                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func icon(for style: AnalysisActionStyle) -> String {
        switch style {
        case .revisit:
            return "arrow.clockwise.circle.fill"
        case .practice:
            return "pencil.and.outline"
        case .summarize:
            return "text.badge.star"
        case .inspectInPharnode:
            return "waveform.path.ecg.text"
        }
    }

    private func detectedContextItems(for classification: AnalysisClassification) -> [DetectedContextItem] {
        var items: [DetectedContextItem] = [
            DetectedContextItem(title: "학습 유형", value: classification.studyMode.title),
            DetectedContextItem(title: "페이지", value: classification.pageRole.title)
        ]

        if let subjectLabel = classification.subjectLabel {
            items.append(DetectedContextItem(title: "과목", value: subjectLabel))
        }
        if let unitLabel = classification.unitLabel {
            items.append(DetectedContextItem(title: "단원", value: unitLabel))
        }

        return items
    }
}

struct AnalysisBadgeRow: View {
    let result: AnalysisResult
    var limit: Int

    var body: some View {
        FlexiblePillRow(items: Array(result.badges.prefix(limit))) { badge in
            PharTagPill(
                text: badge.title,
                tint: badgeTint(for: badge.kind),
                foreground: badgeForeground(for: badge.kind)
            )
        }
    }

    private func badgeTint(for kind: AnalysisBadgeKind) -> Color {
        switch kind {
        case .analyzed:
            return PharTheme.ColorToken.accentBlue.opacity(0.14)
        case .reviewDue:
            return PharTheme.ColorToken.accentPeach.opacity(0.24)
        case .lowConfidence:
            return PharTheme.ColorToken.surfaceTertiary
        case .needsPractice:
            return PharTheme.ColorToken.accentButter.opacity(0.22)
        case .wellUnderstood:
            return PharTheme.ColorToken.accentMint.opacity(0.28)
        }
    }

    private func badgeForeground(for kind: AnalysisBadgeKind) -> Color {
        switch kind {
        case .analyzed, .lowConfidence, .needsPractice, .wellUnderstood, .reviewDue:
            return PharTheme.ColorToken.inkPrimary
        }
    }
}

func masteryLabel(_ score: Double) -> String {
    switch score {
    case 0.8...:
        return "안정적"
    case 0.62...:
        return "무난함"
    case 0.45...:
        return "보강 필요"
    default:
        return "다시 확인"
    }
}

func confidenceLabel(_ score: Double) -> String {
    switch score {
    case 0.78...:
        return "근거 충분"
    case 0.58...:
        return "보통"
    default:
        return "추가 근거 필요"
    }
}

func strengthLabel(_ score: Double) -> String {
    switch score {
    case 0.75...:
        return "강함"
    case 0.5...:
        return "보통"
    default:
        return "약함"
    }
}

private struct DetectedContextItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
}

struct AnalysisMetricPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: PharTheme.Spacing.xxxSmall) {
            Text(title)
                .font(PharTypography.eyebrow)
                .foregroundStyle(PharTheme.ColorToken.inkSecondary)
            Text(value)
                .font(PharTypography.captionStrong)
                .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, PharTheme.Spacing.small)
        .padding(.vertical, PharTheme.Spacing.xxSmall)
        .background(
            Capsule(style: .continuous)
                .fill(tint)
        )
    }
}

private struct FlowConceptRow: View {
    let concepts: [AnalysisConceptNode]

    var body: some View {
        FlexiblePillRow(items: concepts) { concept in
            AnalysisMetricPill(
                title: strengthLabel(concept.masteryScore),
                value: concept.label,
                tint: PharTheme.ColorToken.surfaceTertiary
            )
        }
    }
}

private struct FlexiblePillRow<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            HStack(spacing: PharTheme.Spacing.xSmall) {
                ForEach(items) { item in
                    content(item)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: PharTheme.Spacing.xSmall) {
                ForEach(items) { item in
                    content(item)
                }
            }
        }
    }
}
