import SwiftUI

struct NodeAnalysisWorkspaceView: View {
    @StateObject private var viewModel = NodeAnalysisViewModel()

    private let subjectOptions: [StudySubject] = [
        .korean,
        .math,
        .english,
        .koreanHistory,
        .socialInquiry,
        .physics,
        .chemistry,
        .biology,
        .earthScience
    ]

    private let monthOptions = [3, 6, 9, 11]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.large) {
                headerCard
                tabPicker

                switch viewModel.selectedTab {
                case .questionLookup:
                    questionLookupContent
                case .weaknessRecommendations:
                    weaknessRecommendationsContent
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 36)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(PharTheme.GradientToken.appBackdrop.ignoresSafeArea())
        .task(id: viewModel.selectedTab) {
            if viewModel.selectedTab == .weaknessRecommendations {
                await viewModel.ensureRecommendationsLoaded()
            }
        }
        .onAppear {
            viewModel.refreshConfigurationFields()
        }
    }

    private var headerCard: some View {
        PharSurfaceCard(fill: PharTheme.GradientToken.accentWash) {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                Text("노드 분석")
                    .font(PharTypography.heroDisplay)
                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)

                Text("기출 이미지를 바로 불러와 실전처럼 풀고, 확신도와 사고과정 복기를 통해 어디서 막혔는지 추적합니다.")
                    .font(PharTypography.heroSubtitle)
                    .foregroundStyle(PharTheme.ColorToken.inkSecondary)

                HStack(spacing: PharTheme.Spacing.xSmall) {
                    NodeAnalysisMetricCard(
                        title: "저장된 약점",
                        value: "\(viewModel.weaknessRecords.count)",
                        tint: PharTheme.ColorToken.accentBlue.opacity(0.14)
                    )
                    NodeAnalysisMetricCard(
                        title: "추천 후보",
                        value: "\(viewModel.recommendationHits.count)",
                        tint: PharTheme.ColorToken.accentMint.opacity(0.22)
                    )
                    NodeAnalysisMetricCard(
                        title: "연결",
                        value: viewModel.hasConfiguration ? viewModel.configurationSourceLabel : "미설정",
                        tint: PharTheme.ColorToken.accentButter.opacity(0.24)
                    )
                }
            }
        }
    }

    private var tabPicker: some View {
        Picker("노드 분석 탭", selection: $viewModel.selectedTab) {
            ForEach(NodeAnalysisTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    private var questionLookupContent: some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.large) {
            if !viewModel.hasConfiguration {
                NodeAnalysisInfoCard(
                    title: "기출 검색 준비 중",
                    detail: "앱의 기출 DB 설정이 아직 반영되지 않았습니다. 제품 빌드에서는 번들 설정으로 자동 연결되고, DEBUG 빌드에서는 내부 기출 DB 패널에서만 수동 설정할 수 있습니다.",
                    accent: PharTheme.ColorToken.accentPeach
                )
            }

            PharSurfaceCard {
                VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                    Text("기출문제 검색")
                        .font(PharTypography.sectionTitle)
                        .foregroundStyle(PharTheme.ColorToken.inkPrimary)

                    HStack(spacing: PharTheme.Spacing.medium) {
                        Picker("과목", selection: $viewModel.lookupSubject) {
                            ForEach(subjectOptions) { subject in
                                Text(subject.title).tag(subject)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("월", selection: monthBinding) {
                            ForEach(monthOptions, id: \.self) { month in
                                Text("\(month)월").tag(month)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("형", selection: $viewModel.lookupVariant) {
                            ForEach(NodeAnalysisExamVariantOption.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    HStack(spacing: PharTheme.Spacing.medium) {
                        NodeAnalysisNumericField(title: "시행년도", text: $viewModel.lookupYearText, placeholder: "2026")
                        NodeAnalysisNumericField(title: "문항 번호", text: $viewModel.lookupQuestionNumberText, placeholder: "22")
                    }

                    Button {
                        Task {
                            await viewModel.lookupQuestion()
                        }
                    } label: {
                        HStack(spacing: PharTheme.Spacing.xSmall) {
                            if viewModel.isLookingUp {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(viewModel.isLookingUp ? "조회 중..." : "기출 이미지 불러오기")
                        }
                    }
                    .buttonStyle(PharPrimaryButtonStyle())
                    .disabled(viewModel.isLookingUp || !viewModel.hasConfiguration)

                    if let lookupErrorMessage = viewModel.lookupErrorMessage {
                        Text(lookupErrorMessage)
                            .font(PharTypography.captionStrong)
                            .foregroundStyle(PharTheme.ColorToken.destructive)
                    }
                }
            }

            if let question = viewModel.currentQuestion {
                questionResultCard(for: question)
                solveFlowSection(for: question)
            }
        }
    }

    private var weaknessRecommendationsContent: some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.large) {
            if viewModel.weaknessRecords.isEmpty {
                PharSurfaceCard {
                    ContentUnavailableView(
                        "저장된 약점이 없습니다",
                        systemImage: "brain.head.profile",
                        description: Text("기출을 한 번 풀고 복기에서 막힌 지점을 표시하면 여기서 비슷한 문제를 추천합니다.")
                    )
                }
            } else {
                weaknessSelectionSection

                if let selectedWeakness = viewModel.selectedWeaknessRecord {
                    weaknessSummaryCard(for: selectedWeakness)
                }

                PharSurfaceCard {
                    VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                        HStack {
                            VStack(alignment: .leading, spacing: PharTheme.Spacing.xxSmall) {
                                Text("약점 기반 추천")
                                    .font(PharTypography.sectionTitle)
                                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                                Text("저장된 막힘 지점과 단원 키워드를 기준으로 비슷한 기출을 다시 찾습니다.")
                                    .font(PharTypography.caption)
                                    .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                            }

                            Spacer(minLength: 0)

                            Button("추천 새로고침") {
                                Task {
                                    await viewModel.refreshRecommendations()
                                }
                            }
                            .buttonStyle(PharSoftButtonStyle())
                            .disabled(viewModel.isLoadingRecommendations)
                        }

                        if let recommendationMessage = viewModel.recommendationMessage {
                            Text(recommendationMessage)
                                .font(PharTypography.captionStrong)
                                .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                        }

                        if viewModel.isLoadingRecommendations {
                            HStack(spacing: PharTheme.Spacing.small) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("추천 문제를 찾는 중입니다.")
                                    .font(PharTypography.caption)
                                    .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                            }
                        } else if viewModel.recommendationHits.isEmpty {
                            Text("아직 불러온 추천 문제가 없습니다.")
                                .font(PharTypography.caption)
                                .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                        } else {
                            VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                                ForEach(viewModel.recommendationHits) { hit in
                                    recommendationCard(for: hit)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var weaknessSelectionSection: some View {
        PharSurfaceCard {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                Text("기준 약점 선택")
                    .font(PharTypography.cardTitle)
                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PharTheme.Spacing.small) {
                        ForEach(viewModel.weaknessRecords.prefix(8)) { record in
                            Button {
                                Task {
                                    await viewModel.selectWeaknessRecord(record.id)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: PharTheme.Spacing.xxSmall) {
                                    Text(record.titleLine)
                                        .font(PharTypography.captionStrong)
                                        .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                                        .lineLimit(1)
                                    Text(record.stuckStepTitle)
                                        .font(PharTypography.caption)
                                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, PharTheme.Spacing.small)
                                .padding(.vertical, PharTheme.Spacing.small)
                                .background(
                                    RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                                        .fill(viewModel.selectedWeaknessRecordID == record.id
                                              ? PharTheme.ColorToken.accentBlue.opacity(0.14)
                                              : PharTheme.ColorToken.surfaceSecondary)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                                        .stroke(
                                            viewModel.selectedWeaknessRecordID == record.id
                                            ? PharTheme.ColorToken.accentBlue.opacity(0.34)
                                            : PharTheme.ColorToken.borderSoft,
                                            lineWidth: 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func questionResultCard(for question: PastQuestionRecord) -> some View {
        PharSurfaceCard {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                HStack(alignment: .top, spacing: PharTheme.Spacing.medium) {
                    VStack(alignment: .leading, spacing: PharTheme.Spacing.xxSmall) {
                        Text(questionHeaderLine(for: question))
                            .font(PharTypography.sectionTitle)
                            .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                        Text(question.examType)
                            .font(PharTypography.captionStrong)
                            .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                    }

                    Spacer(minLength: 0)

                    if let variant = question.metadata.examVariant {
                        PharTagPill(
                            text: variant,
                            tint: PharTheme.ColorToken.accentButter.opacity(0.22),
                            foreground: PharTheme.ColorToken.inkPrimary
                        )
                    }
                }

                if let imageURL = question.imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 280)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous))
                        case .failure:
                            RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                                .fill(PharTheme.ColorToken.surfaceSecondary)
                                .frame(height: 220)
                                .overlay {
                                    Text("이미지를 불러오지 못했습니다.")
                                        .font(PharTypography.caption)
                                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                                }
                        @unknown default:
                            EmptyView()
                        }
                    }
                }

                Text(question.contentPreview)
                    .font(PharTypography.body)
                    .foregroundStyle(PharTheme.ColorToken.inkSecondary)

                HStack(spacing: PharTheme.Spacing.xSmall) {
                    if let unit = question.metadata.unit {
                        PharTagPill(text: unit, tint: PharTheme.ColorToken.accentMint.opacity(0.24))
                    }
                    if let answer = question.answerPreview {
                        PharTagPill(text: "정답 \(answer)", tint: PharTheme.ColorToken.surfaceTertiary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func solveFlowSection(for question: PastQuestionRecord) -> some View {
        switch viewModel.sessionPhase {
        case .idle:
            EmptyView()
        case .questionReady:
            PharSurfaceCard {
                VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                    Text("문풀 시작")
                        .font(PharTypography.sectionTitle)
                        .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                    Text("문제 이미지를 보고 실전처럼 풀이를 시작하세요. 버튼을 누르는 즉시 타이머가 작동합니다.")
                        .font(PharTypography.body)
                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)

                    Button("문풀 시작") {
                        viewModel.startSolving()
                    }
                    .buttonStyle(PharPrimaryButtonStyle())
                }
            }
        case .solving:
            PharSurfaceCard {
                VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                    Text("문풀 진행 중")
                        .font(PharTypography.sectionTitle)
                        .foregroundStyle(PharTheme.ColorToken.inkPrimary)

                    Text(timeString(from: viewModel.elapsedSeconds))
                        .font(.system(size: 42, weight: .bold, design: .monospaced))
                        .foregroundStyle(PharTheme.ColorToken.accentBlue)

                    Text("풀이가 끝나는 시점에 종료 버튼을 누르면 확신도 설문과 사고과정 복기가 바로 이어집니다.")
                        .font(PharTypography.caption)
                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)

                    Button("타이머 종료하고 복기하기") {
                        viewModel.stopSolving()
                    }
                    .buttonStyle(PharPrimaryButtonStyle())
                }
            }
        case .confidenceSurvey:
            PharSurfaceCard {
                VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                    Text("풀이 확신도")
                        .font(PharTypography.sectionTitle)
                        .foregroundStyle(PharTheme.ColorToken.inkPrimary)

                    HStack {
                        Text("지금 답에 얼마나 확신이 있나요?")
                            .font(PharTypography.bodyStrong)
                            .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                        Spacer(minLength: 0)
                        Text("\(Int(viewModel.confidenceAfter.rounded()))")
                            .font(PharTypography.numberMono)
                            .foregroundStyle(PharTheme.ColorToken.accentBlue)
                    }

                    Slider(value: $viewModel.confidenceAfter, in: 0...100, step: 1)

                    HStack {
                        Text("완전 감")
                        Spacer(minLength: 0)
                        Text("거의 확신")
                    }
                    .font(PharTypography.caption)
                    .foregroundStyle(PharTheme.ColorToken.inkSecondary)

                    Button("사고과정 복기 시작") {
                        viewModel.submitConfidenceSurvey()
                    }
                    .buttonStyle(PharPrimaryButtonStyle())
                }
            }
        case .review:
            reviewCard(for: question)
        case .completed:
            PharSurfaceCard {
                VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                    Text("약점 기록 저장 완료")
                        .font(PharTypography.sectionTitle)
                        .foregroundStyle(PharTheme.ColorToken.inkPrimary)

                    Text("막힌 지점과 풀이 흐름을 저장했습니다. 추천 탭에서 비슷한 기출을 바로 이어서 풀 수 있습니다.")
                        .font(PharTypography.body)
                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)

                    Button("추천 문제 보러 가기") {
                        viewModel.selectedTab = .weaknessRecommendations
                    }
                    .buttonStyle(PharPrimaryButtonStyle())
                }
            }
        }
    }

    private func reviewCard(for question: PastQuestionRecord) -> some View {
        PharSurfaceCard {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                HStack {
                    VStack(alignment: .leading, spacing: PharTheme.Spacing.xxSmall) {
                        Text("사고과정 복기")
                            .font(PharTypography.sectionTitle)
                            .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                        Text(viewModel.reviewProgressLabel)
                            .font(PharTypography.captionStrong)
                            .foregroundStyle(PharTheme.ColorToken.accentBlue)
                    }
                    Spacer(minLength: 0)
                    Text(timeString(from: viewModel.elapsedSeconds))
                        .font(PharTypography.numberMono)
                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                }

                Text(viewModel.currentReviewContextLine)
                    .font(PharTypography.body)
                    .foregroundStyle(PharTheme.ColorToken.inkSecondary)

                if case .firstApproach = viewModel.reviewStage {
                    if let promptSet = viewModel.currentReviewPromptSet {
                        LazyVGrid(columns: reviewColumns, alignment: .leading, spacing: PharTheme.Spacing.small) {
                            ForEach(promptSet.firstApproachOptions) { option in
                                NodeAnalysisChoiceButton(
                                    title: option.title,
                                    isSelected: viewModel.reviewDraft?.firstApproachID == option.id
                                ) {
                                    viewModel.selectFirstApproach(option.id)
                                }
                            }
                        }
                    }
                } else if let step = viewModel.currentReviewStepDefinition {
                    VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
                        Text(step.title)
                            .font(PharTypography.cardTitle)
                            .foregroundStyle(PharTheme.ColorToken.inkPrimary)

                        Picker("단계 상태", selection: currentReviewStatusBinding) {
                            Text("명확").tag(AnalysisReviewStepStatus.clear)
                            Text("애매").tag(AnalysisReviewStepStatus.partial)
                            Text("막힘").tag(AnalysisReviewStepStatus.failed)
                        }
                        .pickerStyle(.segmented)

                        LazyVGrid(columns: reviewColumns, alignment: .leading, spacing: PharTheme.Spacing.small) {
                            ForEach(step.options) { option in
                                NodeAnalysisChoiceButton(
                                    title: option.title,
                                    isSelected: viewModel.reviewDraft?.selectedOptionID(for: step.id) == option.id
                                ) {
                                    viewModel.selectCurrentReviewOption(option.id)
                                }
                            }
                        }

                        if let primaryStuckPoint = viewModel.reviewDraft?.primaryStuckPointID,
                           primaryStuckPoint == step.id {
                            PharTagPill(
                                text: "현재 막힌 지점으로 저장됨",
                                tint: PharTheme.ColorToken.accentPeach.opacity(0.24),
                                foreground: PharTheme.ColorToken.inkPrimary
                            )
                        }

                        if let status = viewModel.reviewDraft?.stepStatus(for: step.id),
                           status == .partial || status == .failed {
                            Button("막힌 지점으로 표시") {
                                viewModel.markCurrentStepAsStuck()
                            }
                            .buttonStyle(PharSoftButtonStyle())
                        }
                    }
                }

                HStack(spacing: PharTheme.Spacing.small) {
                    Button("이전") {
                        viewModel.goToPreviousReviewStage()
                    }
                    .buttonStyle(PharSoftButtonStyle())

                    Button(nextButtonTitle) {
                        Task {
                            await viewModel.goToNextReviewStage()
                        }
                    }
                    .buttonStyle(PharPrimaryButtonStyle())
                    .disabled(!viewModel.isCurrentReviewSelectionValid)
                }
            }
        }
    }

    private func weaknessSummaryCard(for record: NodeAnalysisWeaknessRecord) -> some View {
        PharSurfaceCard {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                HStack(alignment: .top, spacing: PharTheme.Spacing.medium) {
                    VStack(alignment: .leading, spacing: PharTheme.Spacing.xxSmall) {
                        Text(record.titleLine)
                            .font(PharTypography.sectionTitle)
                            .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                        Text(record.stuckStepTitle)
                            .font(PharTypography.bodyStrong)
                            .foregroundStyle(PharTheme.ColorToken.accentBlue)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: PharTheme.Spacing.xxSmall) {
                        Text(record.elapsedLabel)
                            .font(PharTypography.numberMono)
                            .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                        Text(record.confidenceSummary)
                            .font(PharTypography.caption)
                            .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                    }
                }

                HStack(spacing: PharTheme.Spacing.xSmall) {
                    if let unitLabel = record.unitLabel {
                        PharTagPill(text: unitLabel, tint: PharTheme.ColorToken.accentMint.opacity(0.24))
                    }
                    if let examVariantLabel = record.examVariantLabel {
                        PharTagPill(text: examVariantLabel, tint: PharTheme.ColorToken.accentButter.opacity(0.24))
                    }
                    PharTagPill(
                        text: record.wasExplicitlyMarked ? "직접 표시한 약점" : "자동 추론 약점",
                        tint: PharTheme.ColorToken.surfaceTertiary
                    )
                }

                Text(record.question.contentPreview)
                    .font(PharTypography.body)
                    .foregroundStyle(PharTheme.ColorToken.inkSecondary)
            }
        }
    }

    private func recommendationCard(for hit: PastQuestionSearchHit) -> some View {
        PharSurfaceCard(fill: PharTheme.ColorToken.surfacePrimary.opacity(0.94)) {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                HStack(alignment: .top, spacing: PharTheme.Spacing.medium) {
                    VStack(alignment: .leading, spacing: PharTheme.Spacing.xxSmall) {
                        Text(questionHeaderLine(for: hit.record))
                            .font(PharTypography.cardTitle)
                            .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                        Text(hit.snippet)
                            .font(PharTypography.caption)
                            .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                            .lineLimit(3)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: PharTheme.Spacing.xxSmall) {
                        Text("score \(hit.score)")
                            .font(PharTypography.captionStrong)
                            .foregroundStyle(PharTheme.ColorToken.accentBlue)
                        if let difficulty = hit.record.difficulty {
                            Text(difficulty)
                                .font(PharTypography.caption)
                                .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                        }
                    }
                }

                if let imageURL = hit.record.imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 180)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous))
                        case .failure:
                            RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                                .fill(PharTheme.ColorToken.surfaceSecondary)
                                .frame(height: 160)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }

                HStack(spacing: PharTheme.Spacing.small) {
                    Button("이 문제로 이어서 풀기") {
                        viewModel.useRecommendedQuestion(hit.record)
                    }
                    .buttonStyle(PharPrimaryButtonStyle())

                    if let unit = hit.record.metadata.unit {
                        PharTagPill(text: unit, tint: PharTheme.ColorToken.surfaceTertiary)
                    }
                }
            }
        }
    }

    private var currentReviewStatusBinding: Binding<AnalysisReviewStepStatus> {
        Binding(
            get: {
                guard let step = viewModel.currentReviewStepDefinition else { return .clear }
                return viewModel.reviewDraft?.stepStatus(for: step.id) ?? .clear
            },
            set: { newValue in
                viewModel.setCurrentReviewStatus(newValue)
            }
        )
    }

    private var monthBinding: Binding<Int> {
        Binding(
            get: { Int(viewModel.lookupMonthText) ?? monthOptions[2] },
            set: { viewModel.lookupMonthText = String($0) }
        )
    }

    private var nextButtonTitle: String {
        guard let promptSet = viewModel.currentReviewPromptSet,
              let reviewStage = viewModel.reviewStage else {
            return "다음"
        }

        switch reviewStage {
        case .firstApproach:
            return "조건 해석으로 이동"
        case .step(let index):
            return index + 1 == promptSet.stepDefinitions.count ? "복기 저장하고 추천 받기" : "다음 단계"
        }
    }

    private var reviewColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: PharTheme.Spacing.small),
            GridItem(.flexible(), spacing: PharTheme.Spacing.small)
        ]
    }

    private func questionHeaderLine(for question: PastQuestionRecord) -> String {
        let year = question.year.map { "\($0)학년도" } ?? "연도 미상"
        let month = question.month.map { "\($0)월" } ?? "월 미상"
        return "\(year) \(month) \(question.subject) \(question.questionNumber)번"
    }

    private func timeString(from seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct NodeAnalysisMetricCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.xxSmall) {
            Text(title)
                .font(PharTypography.captionStrong)
                .foregroundStyle(PharTheme.ColorToken.inkSecondary)
            Text(value)
                .font(PharTypography.bodyStrong)
                .foregroundStyle(PharTheme.ColorToken.inkPrimary)
        }
        .padding(.horizontal, PharTheme.Spacing.small)
        .padding(.vertical, PharTheme.Spacing.small)
        .background(
            RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                .fill(tint)
        )
    }
}

private struct NodeAnalysisNumericField: View {
    let title: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.xxSmall) {
            Text(title)
                .font(PharTypography.captionStrong)
                .foregroundStyle(PharTheme.ColorToken.inkSecondary)

            TextField(placeholder, text: $text)
                .keyboardType(.numberPad)
                .font(PharTypography.bodyStrong)
                .foregroundStyle(PharTheme.ColorToken.inkPrimary)
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
    }
}

private struct NodeAnalysisInfoCard: View {
    let title: String
    let detail: String
    let accent: Color

    var body: some View {
        PharSurfaceCard(fill: accent.opacity(0.12), stroke: accent.opacity(0.22)) {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.xSmall) {
                Text(title)
                    .font(PharTypography.cardTitle)
                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                Text(detail)
                    .font(PharTypography.caption)
                    .foregroundStyle(PharTheme.ColorToken.inkSecondary)
            }
        }
    }
}

private struct NodeAnalysisChoiceButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(PharTypography.bodyStrong)
                .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .padding(.horizontal, PharTheme.Spacing.small)
                .padding(.vertical, PharTheme.Spacing.small)
                .background(
                    RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                        .fill(isSelected ? PharTheme.ColorToken.accentBlue.opacity(0.14) : PharTheme.ColorToken.surfaceSecondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                        .stroke(
                            isSelected ? PharTheme.ColorToken.accentBlue.opacity(0.34) : PharTheme.ColorToken.borderSoft,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }
}
