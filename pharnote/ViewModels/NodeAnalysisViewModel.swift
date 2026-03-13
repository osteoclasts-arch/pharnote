import Combine
import Foundation

@MainActor
final class NodeAnalysisViewModel: ObservableObject {
    @Published var selectedTab: NodeAnalysisTab = .questionLookup

    @Published var lookupSubject: StudySubject = .math
    @Published var lookupYearText: String = ""
    @Published var lookupMonthText: String = "9"
    @Published var lookupQuestionNumberText: String = ""
    @Published var lookupVariant: NodeAnalysisExamVariantOption = .unspecified

    @Published private(set) var isLookingUp = false
    @Published private(set) var lookupResponse: PastQuestionLookupResponse?
    @Published private(set) var lookupErrorMessage: String?

    @Published private(set) var sessionPhase: NodeAnalysisSessionPhase = .idle
    @Published private(set) var elapsedSeconds = 0
    @Published var confidenceAfter: Double = 60

    @Published private(set) var reviewDraft: AnalysisPostSolveReviewDraft?
    @Published private(set) var reviewStage: NodeAnalysisReviewStage?

    @Published private(set) var weaknessRecords: [NodeAnalysisWeaknessRecord] = []
    @Published var selectedWeaknessRecordID: UUID?
    @Published private(set) var recommendationHits: [PastQuestionSearchHit] = []
    @Published private(set) var recommendationMessage: String?
    @Published private(set) var isLoadingRecommendations = false
    @Published private(set) var configuration: PastQuestionsConfiguration
    @Published private(set) var configurationSourceLabel: String

    private let configurationStore: PastQuestionsConfigurationStore
    private let questionsService: PastQuestionsService
    private let weaknessStore: NodeAnalysisStore
    private var solveTimer: Timer?
    private var solveStartedAt: Date?
    private var explicitlyMarkedStuckStepID: String?
    private var cancellables: Set<AnyCancellable> = []

    init(
        configurationStore: PastQuestionsConfigurationStore? = nil,
        questionsService: PastQuestionsService = .shared,
        weaknessStore: NodeAnalysisStore = NodeAnalysisStore()
    ) {
        let resolvedConfigurationStore = configurationStore ?? .shared
        self.configurationStore = resolvedConfigurationStore
        self.questionsService = questionsService
        self.weaknessStore = weaknessStore
        self.configuration = resolvedConfigurationStore.configuration
        self.configurationSourceLabel = resolvedConfigurationStore.configurationSourceLabel

        bindConfigurationStore()

        Task {
            await loadWeaknessRecords()
        }
    }

    deinit {
        solveTimer?.invalidate()
    }

    var currentQuestion: PastQuestionRecord? {
        lookupResponse?.match
    }

    var hasConfiguration: Bool {
        configuration.hasLookupConfiguration
    }

    var canLoadRecommendations: Bool {
        configuration.hasSearchConfiguration
    }

    var selectedWeaknessRecord: NodeAnalysisWeaknessRecord? {
        if let selectedWeaknessRecordID,
           let matched = weaknessRecords.first(where: { $0.id == selectedWeaknessRecordID }) {
            return matched
        }
        return weaknessRecords.first
    }

    var currentReviewPromptSet: AnalysisPostSolveReviewPromptSet? {
        reviewDraft?.promptSet
    }

    var currentReviewStepDefinition: AnalysisReviewStepDefinition? {
        guard case .step(let index) = reviewStage,
              let promptSet = currentReviewPromptSet,
              promptSet.stepDefinitions.indices.contains(index) else {
            return nil
        }
        return promptSet.stepDefinitions[index]
    }

    var reviewProgressLabel: String {
        guard let promptSet = currentReviewPromptSet,
              let reviewStage else {
            return ""
        }

        let total = promptSet.stepDefinitions.count + 1
        let current: Int

        switch reviewStage {
        case .firstApproach:
            current = 1
        case .step(let index):
            current = index + 2
        }

        return "\(current)/\(total)"
    }

    var isCurrentReviewSelectionValid: Bool {
        guard let reviewStage else { return false }

        switch reviewStage {
        case .firstApproach:
            return reviewDraft?.firstApproachID != nil
        case .step(let index):
            guard let promptSet = currentReviewPromptSet,
                  promptSet.stepDefinitions.indices.contains(index) else {
                return false
            }
            let step = promptSet.stepDefinitions[index]
            guard let reviewDraft else { return false }
            return reviewDraft.selectedOptionID(for: step.id) != nil
        }
    }

    var currentReviewContextLine: String {
        guard let reviewStage,
              let reviewDraft,
              let promptSet = currentReviewPromptSet else {
            return "풀이 흐름을 처음부터 차근차근 복기합니다."
        }

        switch reviewStage {
        case .firstApproach:
            return "문제를 처음 보자마자 어떤 접근으로 시작했는지 먼저 고르세요."
        case .step(let index):
            let previousSignals = accumulatedReviewSignals(
                upTo: index,
                promptSet: promptSet,
                reviewDraft: reviewDraft
            )
            if previousSignals.isEmpty {
                return "이 단계에서 실제로 어떤 선택을 했는지 고르세요."
            }
            return "앞 단계에서 \(previousSignals.joined(separator: " -> ")) 흐름으로 갔다고 했어요. 그다음엔 무엇을 했나요?"
        }
    }

    func loadWeaknessRecords() async {
        do {
            let loaded = try await weaknessStore.loadWeaknessRecords()
            weaknessRecords = loaded
            if selectedWeaknessRecordID == nil {
                selectedWeaknessRecordID = loaded.first?.id
            }
        } catch {
            recommendationMessage = "약점 기록을 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }

    func refreshConfigurationFields() {
        configurationStore.reload()
        configuration = configurationStore.configuration
        configurationSourceLabel = configurationStore.configurationSourceLabel
    }

    func lookupQuestion() async {
        lookupErrorMessage = nil
        isLookingUp = true
        defer { isLookingUp = false }

        guard let year = Int(lookupYearText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let month = Int(lookupMonthText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let questionNumber = Int(lookupQuestionNumberText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            lookupResponse = nil
            sessionPhase = .idle
            lookupErrorMessage = PastQuestionsError.invalidLookupRequest.localizedDescription
            return
        }

        do {
            let response = try await questionsService.lookup(
                PastQuestionLookupRequest(
                    subject: lookupSubject.title,
                    year: year,
                    month: month,
                    examType: nil,
                    questionNumber: questionNumber,
                    examVariant: lookupVariant.requestValue,
                    requireImage: true,
                    requirePaperSection: lookupVariant == .common ? "공통" : nil,
                    requirePoints: nil
                ),
                configuration: configuration
            )

            lookupResponse = response

            if let match = response.match {
                applyLookupMatch(match)
            } else {
                resetSolveFlow()
                sessionPhase = .idle
                lookupErrorMessage = response.message ?? "조건에 맞는 기출 문항을 찾지 못했습니다."
            }
        } catch {
            lookupResponse = nil
            resetSolveFlow()
            sessionPhase = .idle
            lookupErrorMessage = error.localizedDescription
        }
    }

    private func bindConfigurationStore() {
        configurationStore.$configuration
            .sink { [weak self] configuration in
                guard let self else { return }
                self.configuration = configuration
                self.configurationSourceLabel = self.configurationStore.configurationSourceLabel
            }
            .store(in: &cancellables)
    }

    func startSolving() {
        guard currentQuestion != nil else { return }

        resetSolveFlow(keepLookup: true)
        sessionPhase = .solving
        solveStartedAt = Date()
        elapsedSeconds = 0

        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      let solveStartedAt = self.solveStartedAt else { return }
                self.elapsedSeconds = max(Int(Date().timeIntervalSince(solveStartedAt)), 0)
            }
        }
        solveTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopSolving() {
        guard sessionPhase == .solving else { return }
        solveTimer?.invalidate()
        solveTimer = nil

        if let solveStartedAt {
            elapsedSeconds = max(Int(Date().timeIntervalSince(solveStartedAt)), 0)
        }

        sessionPhase = .confidenceSurvey
    }

    func submitConfidenceSurvey() {
        guard let currentQuestion else { return }

        if reviewDraft == nil {
            reviewDraft = AnalysisPostSolveReviewDraft(subject: mappedStudySubject(from: currentQuestion.subject))
        }

        reviewDraft?.confidenceAfter = confidenceAfter
        reviewStage = .firstApproach
        sessionPhase = .review
    }

    func selectFirstApproach(_ optionID: String) {
        reviewDraft?.firstApproachID = optionID
    }

    func selectCurrentReviewOption(_ optionID: String) {
        guard let step = currentReviewStepDefinition else { return }
        mutateReviewDraft { draft in
            draft.setSelectedOptionID(optionID, for: step.id)
            if draft.stepStatus(for: step.id) == .notTried {
                draft.setStepStatus(.clear, for: step.id)
            }
        }
    }

    func setCurrentReviewStatus(_ status: AnalysisReviewStepStatus) {
        guard let step = currentReviewStepDefinition else { return }
        mutateReviewDraft { draft in
            draft.setStepStatus(status, for: step.id)
        }
    }

    func markCurrentStepAsStuck() {
        guard let step = currentReviewStepDefinition else { return }
        explicitlyMarkedStuckStepID = step.id
        mutateReviewDraft { draft in
            draft.primaryStuckPointID = step.id
            if draft.stepStatus(for: step.id) == .notTried || draft.stepStatus(for: step.id) == .clear {
                draft.setStepStatus(.failed, for: step.id)
            }
        }
    }

    func goToPreviousReviewStage() {
        guard let reviewStage else { return }
        switch reviewStage {
        case .firstApproach:
            sessionPhase = .confidenceSurvey
            self.reviewStage = nil
        case .step(let index):
            self.reviewStage = index == 0 ? .firstApproach : .step(index: index - 1)
        }
    }

    func goToNextReviewStage() async {
        guard let promptSet = currentReviewPromptSet,
              let reviewStage,
              isCurrentReviewSelectionValid else {
            return
        }

        switch reviewStage {
        case .firstApproach:
            self.reviewStage = .step(index: 0)
        case .step(let index):
            if index + 1 < promptSet.stepDefinitions.count {
                self.reviewStage = .step(index: index + 1)
            } else {
                await completeReviewFlow()
            }
        }
    }

    func refreshRecommendations() async {
        guard canLoadRecommendations else {
            recommendationHits = []
            recommendationMessage = PastQuestionsError.missingSearchConfiguration.localizedDescription
            return
        }

        guard let weakness = selectedWeaknessRecord else {
            recommendationHits = []
            recommendationMessage = "먼저 검색 탭에서 기출을 풀고 약점을 저장하세요."
            return
        }

        isLoadingRecommendations = true
        recommendationMessage = nil
        defer { isLoadingRecommendations = false }

        do {
            let queryCandidates = recommendationQueryCandidates(for: weakness)
            var matchedItems: [PastQuestionSearchHit] = []
            var matchedQuery: String?

            for query in queryCandidates {
                let response = try await questionsService.search(
                    PastQuestionSearchRequest(
                        query: query,
                        subjectHint: weakness.question.subject,
                        topK: 8
                    ),
                    configuration: configuration
                )

                let filteredItems = response.items.filter { $0.record.id != weakness.question.id }
                if !filteredItems.isEmpty {
                    matchedItems = filteredItems
                    matchedQuery = query
                    break
                }
            }

            recommendationHits = matchedItems

            if matchedItems.isEmpty {
                recommendationMessage = "저장된 약점을 기준으로 관련 기출을 찾지 못했습니다."
            } else {
                let weakPoint = weakness.stuckStepTitle
                let queryLabel = matchedQuery ?? "약점 키워드"
                recommendationMessage = "`\(weakPoint)`에서 막힌 기록을 바탕으로 `\(queryLabel)` 관련 기출을 추천합니다."
            }
        } catch {
            recommendationHits = []
            recommendationMessage = error.localizedDescription
        }
    }

    func ensureRecommendationsLoaded() async {
        if recommendationHits.isEmpty {
            await refreshRecommendations()
        }
    }

    func selectWeaknessRecord(_ recordID: UUID) async {
        selectedWeaknessRecordID = recordID
        recommendationHits = []
        await refreshRecommendations()
    }

    func useRecommendedQuestion(_ question: PastQuestionRecord) {
        lookupSubject = mappedStudySubject(from: question.subject) ?? .math
        lookupYearText = question.year.map(String.init) ?? ""
        lookupMonthText = question.month.map(String.init) ?? ""
        lookupQuestionNumberText = String(question.questionNumber)
        lookupVariant = mappedVariantOption(from: question.examVariant)
        lookupResponse = PastQuestionLookupResponse(
            status: .matched,
            match: question,
            candidates: [question],
            message: nil
        )
        applyLookupMatch(question)
        selectedTab = .questionLookup
    }

    private func completeReviewFlow() async {
        guard let currentQuestion,
              let reviewDraft else { return }

        let payload = reviewDraft.makePayload()
        let record = NodeAnalysisWeaknessRecord(
            id: UUID(),
            createdAt: Date(),
            question: currentQuestion,
            elapsedSeconds: elapsedSeconds,
            review: payload,
            wasExplicitlyMarked: explicitlyMarkedStuckStepID != nil
        )

        do {
            try await weaknessStore.saveWeaknessRecord(record)
            await loadWeaknessRecords()
            selectedWeaknessRecordID = record.id
            recommendationHits = []
            recommendationMessage = "약점 기록을 저장했습니다. 비슷한 문제를 바로 추천합니다."
            sessionPhase = .completed
            selectedTab = .weaknessRecommendations
            await refreshRecommendations()
        } catch {
            recommendationMessage = "약점 기록 저장 실패: \(error.localizedDescription)"
        }
    }

    private func applyLookupMatch(_ match: PastQuestionRecord) {
        resetSolveFlow(keepLookup: true)
        lookupErrorMessage = nil
        confidenceAfter = 60
        reviewDraft = AnalysisPostSolveReviewDraft(subject: mappedStudySubject(from: match.subject))
        sessionPhase = .questionReady
    }

    private func resetSolveFlow(keepLookup: Bool = false) {
        solveTimer?.invalidate()
        solveTimer = nil
        solveStartedAt = nil
        elapsedSeconds = 0
        confidenceAfter = 60
        reviewDraft = nil
        reviewStage = nil
        explicitlyMarkedStuckStepID = nil

        if !keepLookup {
            lookupResponse = nil
        }
    }

    private func mutateReviewDraft(_ mutation: (inout AnalysisPostSolveReviewDraft) -> Void) {
        guard var draft = reviewDraft else { return }
        mutation(&draft)
        reviewDraft = draft
    }

    private func accumulatedReviewSignals(
        upTo currentIndex: Int,
        promptSet: AnalysisPostSolveReviewPromptSet,
        reviewDraft: AnalysisPostSolveReviewDraft
    ) -> [String] {
        var signals: [String] = []

        if let firstApproachID = reviewDraft.firstApproachID,
           let firstApproach = promptSet.firstApproachOptions.first(where: { $0.id == firstApproachID }) {
            signals.append(firstApproach.title)
        }

        for index in 0..<currentIndex {
            guard promptSet.stepDefinitions.indices.contains(index) else { continue }
            let step = promptSet.stepDefinitions[index]
            guard let selectedID = reviewDraft.selectedOptionID(for: step.id),
                  let option = step.options.first(where: { $0.id == selectedID }) else {
                continue
            }
            signals.append(option.title)
        }

        return signals
    }

    private func recommendationQueryCandidates(for weakness: NodeAnalysisWeaknessRecord) -> [String] {
        let seeds = weakness.recommendationSeedTerms
        var candidates: [String] = []

        if let unit = weakness.unitLabel {
            let joinedWithKeywords = ([unit] + seeds.filter { $0 != unit }.prefix(2)).joined(separator: " ")
            if !joinedWithKeywords.isEmpty {
                candidates.append(joinedWithKeywords)
            }
            candidates.append(unit)
        }

        if !seeds.isEmpty {
            candidates.append(Array(seeds.prefix(3)).joined(separator: " "))
            candidates.append(Array(seeds.prefix(2)).joined(separator: " "))
        }

        if let fallback = weakness.question.contentPreview.nonEmpty,
           !fallback.isEmpty {
            candidates.append(String(fallback.prefix(36)))
        }

        var deduplicated: [String] = []
        var seen = Set<String>()
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2 else { continue }
            guard seen.insert(trimmed).inserted else { continue }
            deduplicated.append(trimmed)
        }

        return deduplicated
    }

    private func mappedStudySubject(from subjectLabel: String) -> StudySubject? {
        let normalized = subjectLabel.lowercased()

        if normalized.contains("수학") { return .math }
        if normalized.contains("국어") { return .korean }
        if normalized.contains("영어") { return .english }
        if normalized.contains("한국사") { return .koreanHistory }
        if normalized.contains("사탐") || normalized.contains("사회") { return .socialInquiry }
        if normalized.contains("물리") { return .physics }
        if normalized.contains("화학") { return .chemistry }
        if normalized.contains("생명") || normalized.contains("생물") { return .biology }
        if normalized.contains("지구") { return .earthScience }
        if normalized.contains("논술") { return .essay }

        return nil
    }

    private func mappedVariantOption(from variant: String?) -> NodeAnalysisExamVariantOption {
        switch variant?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case NodeAnalysisExamVariantOption.common.rawValue:
            return .common
        case NodeAnalysisExamVariantOption.ga.rawValue, "가":
            return .ga
        case NodeAnalysisExamVariantOption.na.rawValue, "나":
            return .na
        case NodeAnalysisExamVariantOption.integrated.rawValue:
            return .integrated
        default:
            return .unspecified
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
