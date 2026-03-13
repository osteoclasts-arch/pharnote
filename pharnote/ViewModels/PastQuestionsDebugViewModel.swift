import Combine
import Foundation

@MainActor
final class PastQuestionsDebugViewModel: ObservableObject {
    @Published var apiBaseURLString: String
    @Published var baseURLString: String
    @Published var anonKey: String

    @Published var lookupSubject: String
    @Published var lookupYearText: String
    @Published var lookupMonthText: String
    @Published var lookupExamType: String
    @Published var lookupQuestionNumberText: String
    @Published var lookupExamVariant: String
    @Published var lookupRequireImage: Bool
    @Published var lookupRequirePointsText: String

    @Published var searchQuery: String
    @Published var searchSubjectHint: String
    @Published var searchTopKText: String

    @Published private(set) var lookupResponse: PastQuestionLookupResponse?
    @Published private(set) var searchResponse: PastQuestionSearchResponse?
    @Published private(set) var isRunningLookup = false
    @Published private(set) var isRunningSearch = false
    @Published var errorMessage: String?

    let configurationStore: PastQuestionsConfigurationStore

    private let service: PastQuestionsService

    convenience init() {
        self.init(configurationStore: .shared, service: .shared)
    }

    init(
        configurationStore: PastQuestionsConfigurationStore,
        service: PastQuestionsService
    ) {
        self.configurationStore = configurationStore
        self.service = service

        let configuration = configurationStore.configuration
        apiBaseURLString = configuration.apiBaseURLString
        baseURLString = configuration.baseURLString
        anonKey = configuration.anonKey

        lookupSubject = "수학"
        lookupYearText = "2026"
        lookupMonthText = "9"
        lookupExamType = "9월 모의평가"
        lookupQuestionNumberText = "22"
        lookupExamVariant = "공통"
        lookupRequireImage = true
        lookupRequirePointsText = "4"

        searchQuery = ""
        searchSubjectHint = "수학"
        searchTopKText = "6"
    }

    var configurationSourceLabel: String {
        configurationStore.configurationSourceLabel
    }

    var isLookupConfigured: Bool {
        configurationStore.configuration.hasLookupConfiguration
    }

    var isSearchConfigured: Bool {
        configurationStore.configuration.hasSearchConfiguration
    }

    var maskedAnonKey: String {
        let trimmed = configurationStore.configuration.sanitizedAnonKey
        guard trimmed.count > 12 else { return trimmed.isEmpty ? "-" : trimmed }
        let prefix = trimmed.prefix(6)
        let suffix = trimmed.suffix(4)
        return "\(prefix)…\(suffix)"
    }

    func loadValidationPreset() {
        lookupSubject = "수학"
        lookupYearText = "2026"
        lookupMonthText = "9"
        lookupExamType = "9월 모의평가"
        lookupQuestionNumberText = "22"
        lookupExamVariant = "공통"
        lookupRequireImage = true
        lookupRequirePointsText = "4"

        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            searchQuery = "함수 미분"
        }
        searchSubjectHint = "수학"
        searchTopKText = "6"
    }

    func refreshConfigurationFields() {
        configurationStore.reload()
        let configuration = configurationStore.configuration
        apiBaseURLString = configuration.apiBaseURLString
        baseURLString = configuration.baseURLString
        anonKey = configuration.anonKey
    }

    func saveConfiguration() {
        configurationStore.update(
            baseURLString: baseURLString,
            anonKey: anonKey,
            apiBaseURLString: apiBaseURLString
        )
        let configuration = configurationStore.configuration
        apiBaseURLString = configuration.apiBaseURLString
        baseURLString = configuration.baseURLString
        anonKey = configuration.anonKey
    }

    func runLookup() async {
        guard let year = Int(lookupYearText),
              let month = Int(lookupMonthText),
              let questionNumber = Int(lookupQuestionNumberText) else {
            errorMessage = PastQuestionsError.invalidLookupRequest.localizedDescription
            return
        }

        let trimmedPoints = lookupRequirePointsText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPoints.isEmpty, Int(trimmedPoints) == nil {
            errorMessage = "배점 조건은 숫자로 입력해 주세요."
            return
        }

        errorMessage = nil
        isRunningLookup = true
        defer { isRunningLookup = false }

        do {
            let response = try await service.lookup(
                PastQuestionLookupRequest(
                    subject: lookupSubject.trimmingCharacters(in: .whitespacesAndNewlines),
                    year: year,
                    month: month,
                    examType: lookupExamType.nilIfEmpty,
                    questionNumber: questionNumber,
                    examVariant: lookupExamVariant.nilIfEmpty,
                    requireImage: lookupRequireImage,
                    requirePaperSection: lookupExamVariant.trimmingCharacters(in: .whitespacesAndNewlines) == "공통" ? "공통" : nil,
                    requirePoints: Int(trimmedPoints)
                ),
                configuration: configurationStore.configuration
            )
            lookupResponse = response
            if response.status == .notFound {
                errorMessage = response.message
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func runSearch() async {
        let topK = max(Int(searchTopKText) ?? 6, 1)

        errorMessage = nil
        isRunningSearch = true
        defer { isRunningSearch = false }

        do {
            let response = try await service.search(
                PastQuestionSearchRequest(
                    query: searchQuery,
                    subjectHint: searchSubjectHint.nilIfEmpty,
                    topK: topK
                ),
                configuration: configurationStore.configuration
            )
            searchResponse = response
            if response.items.isEmpty {
                errorMessage = "검색 결과가 없습니다."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
