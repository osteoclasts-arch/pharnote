import Combine
import Foundation

@MainActor
final class NodeAnalysisViewModel: ObservableObject {
    private static let demoLookupTimeoutNanoseconds: UInt64 = 1_500_000_000

    @Published var selectedTab: NodeAnalysisTab = .questionLookup
    @Published var lookupMode: NodeAnalysisLookupMode = .direct

    @Published var lookupSubject: StudySubject = .math
    @Published var lookupYearText: String = ""
    @Published var lookupMonthText: String = "9"
    @Published var lookupQuestionNumberText: String = ""
    @Published var lookupVariant: NodeAnalysisExamVariantOption = .unspecified
    @Published var selectedDemoPresetID: String = NodeAnalysisDemoQuestionPreset.demoCSAT22.first?.id ?? ""

    @Published private(set) var isLookingUp = false
    @Published private(set) var lookupResponse: PastQuestionLookupResponse?
    @Published private(set) var lookupErrorMessage: String?

    @Published private(set) var sessionPhase: NodeAnalysisSessionPhase = .idle
    @Published private(set) var elapsedSeconds = 0
    @Published var confidenceAfter: Double = Double(NodeAnalysisConfidenceChoice.unsure.rawValue)

    @Published private(set) var reviewDraft: AnalysisPostSolveReviewDraft?
    @Published private(set) var reviewStage: NodeAnalysisReviewStage?
    @Published var isBindingEvidence: Bool = false
    @Published private(set) var activeDemoPresetID: String?
    @Published private(set) var questionSourceLabel: String?
    @Published private(set) var questionSourceMessage: String?

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

    var demoPresets: [NodeAnalysisDemoQuestionPreset] {
        NodeAnalysisDemoQuestionPreset.demoCSAT22
    }

    var selectedDemoPreset: NodeAnalysisDemoQuestionPreset? {
        demoPresets.first(where: { $0.id == selectedDemoPresetID })
    }

    var activeDemoPreset: NodeAnalysisDemoQuestionPreset? {
        demoPresets.first(where: { $0.id == activeDemoPresetID })
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

    var currentReviewStepDefinition: AnalysisResolvedReviewStepDefinition? {
        guard case .step(let index) = reviewStage,
              let promptSet = currentReviewPromptSet else {
            return nil
        }
        return promptSet.resolvedStepDefinition(at: index, draft: reviewDraft)
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
            return promptSet.firstApproachGuidance
                ?? "문제를 처음 보자마자 어떤 접근으로 시작했는지 먼저 고르세요."
        case .step(let index):
            guard let step = promptSet.resolvedStepDefinition(at: index, draft: reviewDraft) else {
                return "이 단계에서 실제로 어떤 선택을 했는지 고르세요."
            }
            let stageGuidance = step.guidance
                ?? "이 단계에서 실제로 어떤 선택을 했는지 고르세요."
            let previousSignals = accumulatedReviewSignals(
                upTo: index,
                promptSet: promptSet,
                reviewDraft: reviewDraft
            )
            if previousSignals.isEmpty {
                return stageGuidance
            }
            return "앞 단계에서 \(previousSignals.joined(separator: " -> ")) 흐름으로 갔다고 했어요. \(stageGuidance)"
        }
    }

    var selectedConfidenceChoice: NodeAnalysisConfidenceChoice? {
        NodeAnalysisConfidenceChoice(rawValue: Int(confidenceAfter.rounded()))
    }

    var canStartInstantReviewDemo: Bool {
        activeDemoPreset != nil && currentQuestion != nil && sessionPhase == .questionReady
    }

    var shouldShowRecommendationCTA: Bool {
        canLoadRecommendations
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
        guard let year = Int(lookupYearText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let month = Int(lookupMonthText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let questionNumber = Int(lookupQuestionNumberText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            lookupResponse = nil
            sessionPhase = .idle
            lookupErrorMessage = PastQuestionsError.invalidLookupRequest.localizedDescription
            return
        }

        lookupMode = .direct

        let request = PastQuestionLookupRequest(
            subject: lookupSubject.title,
            year: year,
            month: month,
            examType: nil,
            questionNumber: questionNumber,
            examVariant: lookupVariant.requestValue,
            requireImage: true,
            requirePaperSection: lookupVariant == .common ? "공통" : nil,
            requirePoints: nil
        )

        await performLookup(with: [request], demoPresetID: nil)
    }

    func loadSelectedDemoPreset() async {
        guard let preset = selectedDemoPreset else { return }
        await loadDemoPreset(preset)
    }

    func loadDemoPreset(_ preset: NodeAnalysisDemoQuestionPreset) async {
        lookupMode = .demo
        selectedDemoPresetID = preset.id
        lookupSubject = preset.subject
        lookupYearText = String(preset.academicYear)
        lookupMonthText = String(preset.month)
        lookupQuestionNumberText = String(preset.questionNumber)
        lookupVariant = preset.examVariant

        let requests = preset.lookupYears.map { year in
            PastQuestionLookupRequest(
                subject: preset.subject.title,
                year: year,
                month: preset.month,
                examType: preset.examType,
                questionNumber: preset.questionNumber,
                examVariant: preset.examVariant.requestValue,
                requireImage: true,
                requirePaperSection: "공통",
                requirePoints: nil
            )
        }

        await performLookup(with: requests, demoPresetID: preset.id)
    }

    func prepareForAnotherDemo() {
        lookupMode = .demo
        lookupErrorMessage = nil
        questionSourceLabel = nil
        questionSourceMessage = nil
        resetSolveFlow()
        sessionPhase = .idle
    }

    func selectConfidenceChoice(_ choice: NodeAnalysisConfidenceChoice) {
        confidenceAfter = Double(choice.rawValue)
    }

    func startInstantReviewDemo() {
        guard currentQuestion != nil else { return }
        solveTimer?.invalidate()
        solveTimer = nil
        solveStartedAt = nil
        elapsedSeconds = 0
        sessionPhase = .confidenceSurvey
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
            reviewDraft = AnalysisPostSolveReviewDraft(question: currentQuestion)
        }

        reviewDraft?.confidenceAfter = confidenceAfter
        reviewStage = .firstApproach
        sessionPhase = .review
    }

    func selectFirstApproach(_ optionID: String) {
        mutateReviewDraft { draft in
            draft.setFirstApproachID(optionID)
        }
    }

    func selectCurrentReviewOption(_ optionID: String) {
        guard let step = currentReviewStepDefinition,
              case .step(let stepIndex) = reviewStage else { return }
        mutateReviewDraft { draft in
            draft.setSelectedOptionID(optionID, for: step.id, stepIndex: stepIndex)
            if draft.stepStatus(for: step.id) == .notTried {
                draft.setStepStatus(.clear, for: step.id, stepIndex: stepIndex)
            }
        }
    }

    func setCurrentReviewStatus(_ status: AnalysisReviewStepStatus) {
        guard let step = currentReviewStepDefinition,
              case .step(let stepIndex) = reviewStage else { return }
        mutateReviewDraft { draft in
            draft.setStepStatus(status, for: step.id, stepIndex: stepIndex)
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

    func startEvidenceBinding() {
        isBindingEvidence = true
    }

    func cancelEvidenceBinding() {
        isBindingEvidence = false
    }

    func bindEvidence(strokeId: String, timestampMs: Int) {
        guard let step = currentReviewStepDefinition else {
            isBindingEvidence = false
            return
        }
        
        mutateReviewDraft { draft in
            draft.stepLinkedStrokeIds[step.id] = strokeId
            draft.stepCalculatedDelays[step.id] = timestampMs
        }
        
        isBindingEvidence = false
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
        activeDemoPresetID = nil
        lookupMode = .direct
        lookupResponse = PastQuestionLookupResponse(
            status: .matched,
            match: question,
            candidates: [question],
            message: nil
        )
        applyLookupMatch(question, demoPresetID: nil)
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
            recommendationMessage = canLoadRecommendations
                ? "약점 기록을 저장했습니다. 같은 화면에서 결과를 확인한 뒤 추천 문제로 넘어갈 수 있습니다."
                : "약점 기록을 저장했습니다. 같은 화면에서 진단 결과를 확인하고 다음 데모 문항으로 이어갈 수 있습니다."
            sessionPhase = .completed
            if canLoadRecommendations {
                await refreshRecommendations()
            }
        } catch {
            recommendationMessage = "약점 기록 저장 실패: \(error.localizedDescription)"
        }
    }

    private func applyLookupMatch(
        _ match: PastQuestionRecord,
        demoPresetID: String? = nil,
        sourceLabel: String? = nil,
        sourceMessage: String? = nil
    ) {
        resetSolveFlow(keepLookup: true)
        lookupErrorMessage = nil
        activeDemoPresetID = demoPresetID
        questionSourceLabel = sourceLabel
        questionSourceMessage = sourceMessage
        confidenceAfter = Double(NodeAnalysisConfidenceChoice.unsure.rawValue)
        reviewDraft = AnalysisPostSolveReviewDraft(question: match)
        sessionPhase = .questionReady
    }

    private func resetSolveFlow(keepLookup: Bool = false) {
        solveTimer?.invalidate()
        solveTimer = nil
        solveStartedAt = nil
        elapsedSeconds = 0
        confidenceAfter = Double(NodeAnalysisConfidenceChoice.unsure.rawValue)
        reviewDraft = nil
        reviewStage = nil
        explicitlyMarkedStuckStepID = nil

        if !keepLookup {
            lookupResponse = nil
            activeDemoPresetID = nil
            questionSourceLabel = nil
            questionSourceMessage = nil
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
                  let option = promptSet.optionDefinition(for: selectedID) else {
                continue
            }
            signals.append(option.title)
        }

        return signals
    }

    private func recommendationQueryCandidates(for weakness: NodeAnalysisWeaknessRecord) -> [String] {
        let seeds = weakness.recommendationSeedTerms
        var candidates: [String] = []
        let reviewNodeSeeds = Array(
            Set(
                (weakness.review.derivedNodeLabels ?? []) +
                (weakness.review.derivedNodeIds ?? [])
            )
        )
        .sorted()
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

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

        if !reviewNodeSeeds.isEmpty {
            candidates.append(Array(reviewNodeSeeds.prefix(3)).joined(separator: " "))
            candidates.append(Array(reviewNodeSeeds.prefix(2)).joined(separator: " "))
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

    private func performLookup(
        with requests: [PastQuestionLookupRequest],
        demoPresetID: String?
    ) async {
        lookupErrorMessage = nil
        questionSourceLabel = nil
        questionSourceMessage = nil
        isLookingUp = true
        defer { isLookingUp = false }

        var lastResponse: PastQuestionLookupResponse?

        do {
            for request in requests {
                let response = try await lookupResponse(for: request, demoPresetID: demoPresetID)
                lastResponse = response

                if let match = response.match {
                    lookupResponse = response
                    let sourceLabel = configuration.hasLookupAPIConfiguration ? "TutorGPT API" : "기출 DB 검색"
                    applyLookupMatch(
                        match,
                        demoPresetID: demoPresetID,
                        sourceLabel: sourceLabel,
                        sourceMessage: demoPresetID == nil ? nil : "\(sourceLabel)으로 문제를 불러왔습니다."
                    )
                    return
                }
            }

            if let demoFallback = demoPresetID.flatMap({ demoPreset(for: $0) }) {
                applyDemoFallback(demoFallback, response: lastResponse)
                return
            }

            lookupResponse = lastResponse
            activeDemoPresetID = nil
            resetSolveFlow(keepLookup: true)
            sessionPhase = .idle
            lookupErrorMessage = lastResponse?.message ?? "조건에 맞는 기출 문항을 찾지 못했습니다."
        } catch {
            if let demoFallback = demoPresetID.flatMap({ demoPreset(for: $0) }) {
                applyDemoFallback(demoFallback, response: nil, error: error)
                return
            }

            lookupResponse = nil
            activeDemoPresetID = nil
            resetSolveFlow()
            sessionPhase = .idle
            lookupErrorMessage = error.localizedDescription
        }
    }

    private func lookupResponse(
        for request: PastQuestionLookupRequest,
        demoPresetID: String?
    ) async throws -> PastQuestionLookupResponse {
        guard demoPresetID != nil else {
            return try await questionsService.lookup(request, configuration: configuration)
        }

        let questionsService = self.questionsService
        let configuration = self.configuration

        return try await withThrowingTaskGroup(of: PastQuestionLookupResponse.self) { group in
            group.addTask {
                try await questionsService.lookup(request, configuration: configuration)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: Self.demoLookupTimeoutNanoseconds)
                throw PastQuestionsError.requestFailed("데모 조회가 지연되었습니다.")
            }

            defer { group.cancelAll() }

            guard let firstResult = try await group.next() else {
                throw PastQuestionsError.invalidResponse
            }

            return firstResult
        }
    }

    private func demoPreset(for id: String) -> NodeAnalysisDemoQuestionPreset? {
        demoPresets.first(where: { $0.id == id })
    }

    private func applyDemoFallback(
        _ preset: NodeAnalysisDemoQuestionPreset,
        response: PastQuestionLookupResponse?,
        error: Error? = nil
    ) {
        let fallbackRecord = preset.fallbackRecord
        let fallbackResponse = PastQuestionLookupResponse(
            status: .matched,
            match: fallbackRecord,
            candidates: [fallbackRecord],
            message: nil
        )
        lookupResponse = fallbackResponse
        applyLookupMatch(
            fallbackRecord,
            demoPresetID: preset.id,
            sourceLabel: "앱 내 데모 캐시",
            sourceMessage: error == nil && response?.message == nil
                ? "실시간 API가 아직 준비되지 않아 앱에 저장된 데모 문항으로 이어서 진행합니다."
                : "실시간 API 응답이 불안정해 앱에 저장된 데모 문항으로 자동 전환했습니다."
        )
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
