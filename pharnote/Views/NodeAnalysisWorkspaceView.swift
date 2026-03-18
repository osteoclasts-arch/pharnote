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
                    detail: "정확한 기출 조회에는 TutorHub API base URL이 필요합니다. 제품 빌드에서는 번들 설정으로 자동 연결되고, DEBUG 빌드에서는 내부 기출 DB 패널에서만 수동 설정할 수 있습니다.",
                    accent: PharTheme.ColorToken.accentPeach
                )
            }

            lookupModePicker

            switch viewModel.lookupMode {
            case .direct:
                manualLookupCard
            case .demo:
                demoPresetCard
            }

            if let question = viewModel.currentQuestion {
                questionResultCard(for: question)
                solveFlowSection(for: question)
            }
        }
    }

    private var lookupModePicker: some View {
        Picker("기출 조회 방식", selection: $viewModel.lookupMode) {
            ForEach(NodeAnalysisLookupMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var manualLookupCard: some View {
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
    }

    private var demoPresetCard: some View {
        PharSurfaceCard(fill: PharTheme.ColorToken.surfacePrimary.opacity(0.96)) {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                HStack(alignment: .top, spacing: PharTheme.Spacing.medium) {
                    VStack(alignment: .leading, spacing: PharTheme.Spacing.xxSmall) {
                        Text("테스트용 기출")
                            .font(PharTypography.sectionTitle)
                            .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                        Text("2023·2024·2025 수능 수학 공통 22번을 바로 불러와 문항별 복기 UX를 데모할 수 있습니다.")
                            .font(PharTypography.caption)
                            .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                    }

                    Spacer(minLength: 0)

                    if viewModel.isLookingUp {
                        HStack(spacing: PharTheme.Spacing.xSmall) {
                            ProgressView()
                                .controlSize(.small)
                            Text("불러오는 중")
                                .font(PharTypography.captionStrong)
                                .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
                    ForEach(viewModel.demoPresets) { preset in
                        NodeAnalysisDemoPresetButton(
                            preset: preset,
                            isSelected: viewModel.selectedDemoPresetID == preset.id,
                            isLoading: viewModel.isLookingUp && viewModel.selectedDemoPresetID == preset.id
                        ) {
                            Task {
                                await viewModel.loadDemoPreset(preset)
                            }
                        }
                    }
                }

                if let lookupErrorMessage = viewModel.lookupErrorMessage {
                    Text(lookupErrorMessage)
                        .font(PharTypography.captionStrong)
                        .foregroundStyle(PharTheme.ColorToken.destructive)
                }
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
                            .disabled(viewModel.isLoadingRecommendations || !viewModel.canLoadRecommendations)
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

                    if let variant = question.examVariant {
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

                if let questionSourceMessage = viewModel.questionSourceMessage {
                    Text(questionSourceMessage)
                        .font(PharTypography.captionStrong)
                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                }

                HStack(spacing: PharTheme.Spacing.xSmall) {
                    if let activeDemoPreset = viewModel.activeDemoPreset {
                        PharTagPill(
                            text: "테스트용 기출 · \(activeDemoPreset.label)",
                            tint: PharTheme.ColorToken.accentPeach.opacity(0.22)
                        )
                    }
                    if let paperSection = question.paperSection {
                        PharTagPill(text: paperSection, tint: PharTheme.ColorToken.accentBlue.opacity(0.16))
                    }
                    if let points = question.points {
                        PharTagPill(text: "\(points)점", tint: PharTheme.ColorToken.accentPeach.opacity(0.18))
                    }
                    if let unit = question.metadata.unit {
                        PharTagPill(text: unit, tint: PharTheme.ColorToken.accentMint.opacity(0.24))
                    }
                    if let questionSourceLabel = viewModel.questionSourceLabel {
                        PharTagPill(text: questionSourceLabel, tint: PharTheme.ColorToken.surfaceTertiary)
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
                    Text(viewModel.activeDemoPreset == nil
                         ? "문제 이미지를 보고 실전처럼 풀이를 시작하세요. 버튼을 누르는 즉시 타이머가 작동합니다."
                         : "데모 모드에서는 실전처럼 타이머를 시작하거나, 바로 복기 흐름으로 들어가 문항별 사고 분기 UX를 확인할 수 있습니다.")
                        .font(PharTypography.body)
                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)

                    HStack(spacing: PharTheme.Spacing.small) {
                        Button(viewModel.activeDemoPreset == nil ? "문풀 시작" : "3분 실전 시작") {
                            viewModel.startSolving()
                        }
                        .buttonStyle(PharPrimaryButtonStyle())

                        if viewModel.canStartInstantReviewDemo {
                            Button("바로 복기 데모 시작") {
                                viewModel.startInstantReviewDemo()
                            }
                            .buttonStyle(PharSoftButtonStyle())
                        }
                    }
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

                    Text("이 문제를 풀고 답을 낼 때 얼마나 확신했나요?")
                        .font(PharTypography.bodyStrong)
                        .foregroundStyle(PharTheme.ColorToken.inkPrimary)

                    LazyVGrid(columns: reviewColumns, alignment: .leading, spacing: PharTheme.Spacing.small) {
                        ForEach(NodeAnalysisConfidenceChoice.allCases) { choice in
                            NodeAnalysisChoiceButton(
                                title: choice.title,
                                subtitle: choice.subtitle,
                                isSelected: viewModel.selectedConfidenceChoice == choice
                            ) {
                                viewModel.selectConfidenceChoice(choice)
                            }
                        }
                    }

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

                    Text(viewModel.activeDemoPreset == nil
                         ? (viewModel.canLoadRecommendations
                            ? "막힌 지점과 풀이 흐름을 저장했습니다. 추천 탭에서 비슷한 기출을 바로 이어서 풀 수 있습니다."
                            : "막힌 지점과 풀이 흐름을 저장했습니다. 추천 검색 설정이 없어도 현재 화면에서 복기 결과는 바로 확인할 수 있습니다.")
                         : (viewModel.canLoadRecommendations
                            ? "테스트용 기출 복기가 저장되었습니다. 같은 화면에서 데모 결과를 확인한 뒤 추천 문제로 자연스럽게 넘어갈 수 있습니다."
                            : "테스트용 기출 복기가 저장되었습니다. 현재 화면에서 진단 결과를 확인하고 바로 다른 테스트 문항으로 이어갈 수 있습니다."))
                        .font(PharTypography.body)
                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)

                    if let recommendationMessage = viewModel.recommendationMessage {
                        Text(recommendationMessage)
                            .font(PharTypography.captionStrong)
                            .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                    }

                    if let diagnosis = viewModel.selectedWeaknessRecord?.reviewDiagnosis {
                        diagnosisPanel(for: diagnosis)
                    }

                    if viewModel.shouldShowRecommendationCTA {
                        Button("추천 문제 보러 가기") {
                            viewModel.selectedTab = .weaknessRecommendations
                        }
                        .buttonStyle(PharPrimaryButtonStyle())
                    } else if viewModel.activeDemoPreset != nil {
                        Button("다른 테스트 문항 보기") {
                            viewModel.prepareForAnotherDemo()
                        }
                        .buttonStyle(PharPrimaryButtonStyle())
                    }
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

                diagnosisPanel(for: record.reviewDiagnosis)
            }
        }
    }

    private func diagnosisPanel(for diagnosis: NodeAnalysisReviewDiagnosis) -> some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
            HStack(spacing: PharTheme.Spacing.xSmall) {
                PharTagPill(
                    text: diagnosis.categoryTitle,
                    tint: PharTheme.ColorToken.accentBlue.opacity(0.16),
                    foreground: PharTheme.ColorToken.inkPrimary
                )
                PharTagPill(
                    text: "문항별 진단",
                    tint: PharTheme.ColorToken.accentPeach.opacity(0.18),
                    foreground: PharTheme.ColorToken.inkPrimary
                )
            }

            diagnosisLine(title: "핵심 진단", body: diagnosis.summary)
            diagnosisLine(title: "막힌 노드", body: diagnosis.blockedNode)
            diagnosisLine(title: "왜 그렇게 판단했는지", body: diagnosis.why)
            diagnosisLine(title: "다음에 점검할 것", body: diagnosis.nextAction)
        }
        .padding(PharTheme.Spacing.medium)
        .background(PharTheme.ColorToken.surfaceSecondary.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: PharTheme.CornerRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PharTheme.CornerRadius.large, style: .continuous)
                .stroke(PharTheme.ColorToken.borderSoft, lineWidth: 1)
        )
    }

    private func diagnosisLine(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.xxSmall) {
            Text(title)
                .font(PharTypography.captionStrong)
                .foregroundStyle(PharTheme.ColorToken.inkSecondary)
            Text(body)
                .font(PharTypography.body)
                .foregroundStyle(PharTheme.ColorToken.inkPrimary)
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
            return "다음 질문"
        case .step(let index):
            if index + 1 == promptSet.stepDefinitions.count {
                return viewModel.canLoadRecommendations ? "복기 저장하고 추천 받기" : "복기 저장하기"
            }
            return "다음 질문"
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
    var subtitle: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.xxSmall) {
                Text(title)
                    .font(PharTypography.bodyStrong)
                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                    .multilineTextAlignment(.leading)

                if let subtitle {
                    Text(subtitle)
                        .font(PharTypography.caption)
                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                        .multilineTextAlignment(.leading)
                }
            }
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

private struct NodeAnalysisDemoPresetButton: View {
    let preset: NodeAnalysisDemoQuestionPreset
    let isSelected: Bool
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
                HStack(alignment: .top, spacing: PharTheme.Spacing.small) {
                    VStack(alignment: .leading, spacing: PharTheme.Spacing.xxSmall) {
                        Text(preset.title)
                            .font(PharTypography.cardTitle)
                            .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                        Text(preset.subtitle)
                            .font(PharTypography.captionStrong)
                            .foregroundStyle(PharTheme.ColorToken.accentBlue)
                    }

                    Spacer(minLength: 0)

                    PharTagPill(
                        text: preset.label,
                        tint: PharTheme.ColorToken.accentButter.opacity(0.22),
                        foreground: PharTheme.ColorToken.inkPrimary
                    )
                }

                Text(preset.summary)
                    .font(PharTypography.caption)
                    .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                    .multilineTextAlignment(.leading)

                HStack(spacing: PharTheme.Spacing.small) {
                    PharTagPill(text: "\(preset.academicYear)학년도", tint: PharTheme.ColorToken.surfaceTertiary)
                    PharTagPill(text: "수능", tint: PharTheme.ColorToken.surfaceTertiary)
                    PharTagPill(text: "공통 22번", tint: PharTheme.ColorToken.surfaceTertiary)

                    Spacer(minLength: 0)

                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .padding(.horizontal, PharTheme.Spacing.medium)
            .padding(.vertical, PharTheme.Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: PharTheme.CornerRadius.large, style: .continuous)
                    .fill(isSelected ? PharTheme.ColorToken.accentBlue.opacity(0.10) : PharTheme.ColorToken.surfaceSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PharTheme.CornerRadius.large, style: .continuous)
                    .stroke(
                        isSelected ? PharTheme.ColorToken.accentBlue.opacity(0.34) : PharTheme.ColorToken.borderSoft,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
