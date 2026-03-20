import SwiftUI

struct ProblemReviewPanel: View {
    @ObservedObject var viewModel: PDFEditorViewModel

    var body: some View {
        let session = viewModel.problemReviewSession
        let recognition = viewModel.problemRecognitionResult
        let selection = viewModel.problemSelection
        let schema = currentSchema(for: session, recognition: recognition, selection: selection)

        PharSurfaceCard(
            fill: PharTheme.ColorToken.surfacePrimary.opacity(0.96),
            stroke: PharTheme.ColorToken.border.opacity(0.55),
            shadow: PharTheme.ShadowToken.lifted
        ) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                    headerRow(session: session, schema: schema)

                    if let message = viewModel.problemReviewMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !message.isEmpty {
                        Text(message)
                            .font(PharTypography.caption)
                            .foregroundStyle(PharTheme.ColorToken.subtleText)
                    }

                    if let session {
                        activeSessionBody(session: session, schema: schema)
                    } else {
                        recognitionBody(recognition: recognition, selection: selection, schema: schema)
                    }
                }
            }
        }
    }

    private func headerRow(session: ReviewSession?, schema: ReviewSchema) -> some View {
        HStack(alignment: .top, spacing: PharTheme.Spacing.small) {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.xxxSmall) {
                Text(schema.title)
                    .font(PharTypography.bodyStrong)
                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)

                Text(headerSubtitle(session: session))
                    .font(PharTypography.caption)
                    .foregroundStyle(PharTheme.ColorToken.subtleText)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: PharTheme.Spacing.xSmall) {
                autosaveIndicator

                HStack(spacing: PharTheme.Spacing.xxSmall) {
                    if session != nil {
                        Button {
                            viewModel.isProblemReviewPanelVisible = false
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 13, weight: .bold))
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(PharTheme.ColorToken.surfaceSecondary)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("복기 패널 접기")
                    }

                    Button {
                        if session == nil {
                            viewModel.clearProblemSelection()
                        } else {
                            viewModel.isProblemReviewPanelVisible = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(PharTheme.ColorToken.surfaceSecondary)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(session == nil ? "선택 취소" : "복기 패널 닫기")
                }
            }
        }
    }

    private func headerSubtitle(session: ReviewSession?) -> String {
        if let session {
            if session.status == .completed {
                return "복기가 저장되었습니다."
            }
            return "선택한 문제에 바로 붙는 inline 복기"
        }
        return "선택한 문제를 인식하고 복기를 시작합니다."
    }

    @ViewBuilder
    private var autosaveIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(autosaveColor)
                .frame(width: 8, height: 8)
            Text(autosaveText)
                .font(PharTypography.captionStrong)
                .foregroundStyle(PharTheme.ColorToken.subtleText)
        }
        .padding(.horizontal, PharTheme.Spacing.small)
        .padding(.vertical, PharTheme.Spacing.xSmall)
        .background(
            Capsule(style: .continuous)
                .fill(PharTheme.ColorToken.surfaceSecondary)
        )
    }

    private var autosaveColor: Color {
        switch viewModel.problemReviewAutosaveStatus {
        case .idle:
            return PharTheme.ColorToken.border
        case .saving:
            return PharTheme.ColorToken.accentBlue
        case .saved:
            return PharTheme.ColorToken.accentMint
        case .retryNeeded:
            return PharTheme.ColorToken.accentPeach
        }
    }

    private var autosaveText: String {
        switch viewModel.problemReviewAutosaveStatus {
        case .idle:
            return "대기"
        case .saving:
            return "저장 중"
        case .saved:
            return "저장됨"
        case .retryNeeded:
            return "재시도 필요"
        }
    }

    @ViewBuilder
    private func recognitionBody(
        recognition: ProblemRecognitionResult?,
        selection: ProblemSelection?,
        schema: ReviewSchema
    ) -> some View {
        if let recognition, recognition.status == .matching {
            matchingCard
        } else if let session = viewModel.problemReviewSession {
            activeSessionBody(session: session, schema: schema)
        } else if let recognition, recognition.status == .ambiguous, !recognition.candidates.isEmpty {
            ambiguousRecognitionBody(recognition: recognition, selection: selection, schema: schema)
        } else if let recognition, let match = recognition.bestMatch {
            recognizedCard(match: match, selection: selection, schema: schema)
        } else {
            fallbackCard(schema: schema)
        }
    }

    private var matchingCard: some View {
        PharSurfaceCard(
            fill: PharTheme.ColorToken.surfaceSecondary.opacity(0.75),
            stroke: PharTheme.ColorToken.borderSoft
        ) {
            HStack(spacing: PharTheme.Spacing.small) {
                ProgressView()
                    .tint(PharTheme.ColorToken.accentBlue)
                VStack(alignment: .leading, spacing: PharTheme.Spacing.xxxSmall) {
                    Text("문제를 찾는 중")
                        .font(PharTypography.bodyStrong)
                    Text("선택 영역을 기준으로 문제를 비교하고 있습니다.")
                        .font(PharTypography.caption)
                        .foregroundStyle(PharTheme.ColorToken.subtleText)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func ambiguousRecognitionBody(
        recognition: ProblemRecognitionResult,
        selection: ProblemSelection?,
        schema: ReviewSchema
    ) -> some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
            recognizedCardHeader(
                title: recognition.bestMatch?.displayTitle ?? "후보가 여러 개입니다",
                subtitle: "가장 가까운 문제부터 선택하세요.",
                statusText: "애매함"
            )

            VStack(spacing: PharTheme.Spacing.xSmall) {
                ForEach(recognition.candidates.prefix(3)) { candidate in
                    candidateButton(candidate: candidate)
                }
            }

            actionRow(
                startTitle: "기본 복기",
                startAction: {
                    viewModel.startProblemReview(using: recognition.bestMatch)
                },
                secondaryTitle: "다시 선택",
                secondaryAction: {
                    viewModel.clearProblemSelection()
                }
            )
        }
    }

    private func recognizedCard(
        match: ProblemMatch,
        selection: ProblemSelection?,
        schema: ReviewSchema
    ) -> some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
            recognizedCardHeader(
                title: match.displayTitle,
                subtitle: trimmed(selection?.recognitionText)
                    ?? "선택한 문제를 인식했습니다.",
                statusText: "인식됨"
            )

            actionRow(
                startTitle: "복기 시작",
                startAction: {
                    viewModel.startProblemReview(using: match)
                },
                secondaryTitle: "매칭 변경",
                secondaryAction: {
                    viewModel.changeProblemMatch()
                }
            )
        }
    }

    private func fallbackCard(schema: ReviewSchema) -> some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
            recognizedCardHeader(
                title: schema.title,
                subtitle: "자동 인식이 어려우면 기본 복기로 바로 들어갈 수 있습니다.",
                statusText: "대기"
            )

            actionRow(
                startTitle: "기본 복기",
                startAction: {
                    viewModel.startProblemReview(using: nil)
                },
                secondaryTitle: "다시 선택",
                secondaryAction: {
                    viewModel.clearProblemSelection()
                }
            )
        }
    }

    private func recognizedCardHeader(title: String, subtitle: String, statusText: String) -> some View {
        PharSurfaceCard(
            fill: PharTheme.ColorToken.surfaceSecondary.opacity(0.72),
            stroke: PharTheme.ColorToken.borderSoft
        ) {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.xSmall) {
                HStack(alignment: .center, spacing: PharTheme.Spacing.xSmall) {
                    PharTagPill(text: statusText, tint: PharTheme.ColorToken.accentBlue.opacity(0.16))
                    Spacer(minLength: 0)
                }

                Text(title)
                    .font(PharTypography.bodyStrong)
                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                    .lineLimit(2)

                Text(subtitle)
                    .font(PharTypography.caption)
                    .foregroundStyle(PharTheme.ColorToken.subtleText)
                    .lineLimit(3)
            }
        }
    }

    private func actionRow(
        startTitle: String,
        startAction: @escaping () -> Void,
        secondaryTitle: String,
        secondaryAction: @escaping () -> Void
    ) -> some View {
        VStack(spacing: PharTheme.Spacing.xSmall) {
            Button(action: startAction) {
                HStack {
                    Image(systemName: "play.fill")
                    Text(startTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PharPrimaryButtonStyle())

            Button(action: secondaryAction) {
                Text(secondaryTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PharSoftButtonStyle())
        }
    }

    @ViewBuilder
    private func activeSessionBody(session: ReviewSession, schema: ReviewSchema) -> some View {
        let stepIndex = min(session.answers.count, max(schema.steps.count - 1, 0))
        let progress = schema.steps.isEmpty ? 0.0 : Double(min(session.answers.count, schema.steps.count)) / Double(schema.steps.count)

        if session.status == .completed || session.answers.count >= schema.steps.count {
            completedBody(session: session, schema: schema)
        } else if let step = schema.steps[safe: stepIndex] {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                progressBlock(progress: progress, completedCount: session.answers.count, totalCount: schema.steps.count)
                stepCard(step: step, isBackEnabled: !session.answers.isEmpty)
            }
        } else {
            fallbackProgressBlock(progress: progress)
        }
    }

    private func progressBlock(progress: Double, completedCount: Int, totalCount: Int) -> some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.xSmall) {
            HStack {
                Text("진행")
                    .font(PharTypography.captionStrong)
                    .foregroundStyle(PharTheme.ColorToken.subtleText)
                Spacer(minLength: 0)
                Text("\(completedCount)/\(totalCount)")
                    .font(PharTypography.captionStrong.monospacedDigit())
                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)
            }

            ProgressView(value: progress)
                .tint(PharTheme.ColorToken.accentBlue)
        }
    }

    private func fallbackProgressBlock(progress: Double) -> some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
            ProgressView(value: progress)
                .tint(PharTheme.ColorToken.accentBlue)
            Text("복기 단계가 준비되지 않았습니다.")
                .font(PharTypography.caption)
                .foregroundStyle(PharTheme.ColorToken.subtleText)
        }
    }

    private func stepCard(step: ReviewSchemaStep, isBackEnabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.xxxSmall) {
                Text(step.title)
                    .font(PharTypography.bodyStrong)
                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)

                Text(step.prompt)
                    .font(PharTypography.caption)
                    .foregroundStyle(PharTheme.ColorToken.subtleText)
            }

            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 140), spacing: PharTheme.Spacing.xSmall, alignment: .top)
                ],
                spacing: PharTheme.Spacing.xSmall
            ) {
                ForEach(step.options) { option in
                    stepOptionButton(step: step, option: option)
                }
            }

            HStack(spacing: PharTheme.Spacing.xSmall) {
                Button {
                    viewModel.goBackInProblemReview()
                } label: {
                    Label("이전", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PharSoftButtonStyle())
                .disabled(!isBackEnabled)

                Button {
                    viewModel.abandonCurrentProblemReview()
                } label: {
                    Label("중단", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PharSoftButtonStyle())
                .foregroundStyle(PharTheme.ColorToken.subtleText)
            }
        }
    }

    private func stepOptionButton(step: ReviewSchemaStep, option: ReviewSchemaOption) -> some View {
        Button {
            viewModel.updateProblemReviewAnswer(
                stepId: step.id,
                selectedOptionIds: [option.id],
                freeText: nil
            )
        } label: {
            HStack(alignment: .top, spacing: PharTheme.Spacing.xSmall) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.title)
                        .font(PharTypography.bodyStrong)
                        .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(option.internalTag)
                        .font(PharTypography.captionStrong)
                        .foregroundStyle(PharTheme.ColorToken.subtleText)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(PharTheme.ColorToken.subtleText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PharTheme.Spacing.small)
            .padding(.vertical, PharTheme.Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                    .fill(PharTheme.ColorToken.surfaceSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                    .stroke(PharTheme.ColorToken.borderSoft, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func candidateButton(candidate: ProblemMatchCandidate) -> some View {
        Button {
            viewModel.startProblemReview(using: candidate.asMatch())
        } label: {
            HStack(alignment: .top, spacing: PharTheme.Spacing.xSmall) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.displayTitle)
                        .font(PharTypography.bodyStrong)
                        .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                        .multilineTextAlignment(.leading)
                    Text(trimmed(candidate.reason) ?? candidate.sessionType)
                        .font(PharTypography.caption)
                        .foregroundStyle(PharTheme.ColorToken.subtleText)
                }

                Spacer(minLength: 0)

                Text("\(Int(candidate.confidence * 100))%")
                    .font(PharTypography.captionStrong.monospacedDigit())
                    .foregroundStyle(PharTheme.ColorToken.accentBlue)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PharTheme.Spacing.small)
            .padding(.vertical, PharTheme.Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                    .fill(PharTheme.ColorToken.surfaceSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                    .stroke(PharTheme.ColorToken.borderSoft, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func completedBody(session: ReviewSession, schema: ReviewSchema) -> some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
            recognizedCardHeader(
                title: session.problemMatch?.displayTitle ?? schema.title,
                subtitle: "\(session.answers.count) responses saved",
                statusText: "완료"
            )

            HStack(spacing: PharTheme.Spacing.xSmall) {
                PharTagPill(text: session.subject.title, tint: PharTheme.ColorToken.accentBlue.opacity(0.14))
                PharTagPill(text: "저장됨", tint: PharTheme.ColorToken.accentMint.opacity(0.18))
                if let completedAt = session.completedAt {
                    PharTagPill(
                        text: completedAt.formatted(date: .omitted, time: .shortened),
                        tint: PharTheme.ColorToken.surfaceTertiary
                    )
                }
            }

            Text("이 문제의 복기 결과는 분석/마스터리 추적에 재사용됩니다.")
                .font(PharTypography.caption)
                .foregroundStyle(PharTheme.ColorToken.subtleText)

            Button {
                viewModel.clearProblemSelection()
            } label: {
                Label("닫기", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PharPrimaryButtonStyle())
        }
    }

    private func currentSchema(
        for session: ReviewSession?,
        recognition: ProblemRecognitionResult?,
        selection: ProblemSelection?
    ) -> ReviewSchema {
        if let session {
            return viewModel.problemReviewSchema ?? ReviewSchemaRegistry.schema(for: session.subject)
        }

        let subject = recognition?.bestMatch?.subject
            ?? selection?.recognizedMatch?.subject
            ?? viewModel.document.studyMaterial?.subject
            ?? .unspecified
        return ReviewSchemaRegistry.schema(for: subject)
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
