import Combine
import Foundation

nonisolated struct PastQuestionsConfiguration: Hashable, Sendable {
    var baseURLString: String
    var anonKey: String
    var apiBaseURLString: String

    var isComplete: Bool {
        hasLookupConfiguration
    }

    var sanitizedBaseURLString: String {
        baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var sanitizedAnonKey: String {
        anonKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var sanitizedAPIBaseURLString: String {
        apiBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasSearchConfiguration: Bool {
        baseURLString.trimmedNonEmpty != nil && anonKey.trimmedNonEmpty != nil
    }

    var hasLookupAPIConfiguration: Bool {
        apiBaseURLString.trimmedNonEmpty != nil
    }

    var hasLookupConfiguration: Bool {
        hasLookupAPIConfiguration || hasSearchConfiguration
    }
}

@MainActor
final class PastQuestionsConfigurationStore: ObservableObject {
    static let shared = PastQuestionsConfigurationStore()

    static let envURLKey = "PAST_QUESTIONS_SUPABASE_URL"
    static let envAnonKey = "PAST_QUESTIONS_SUPABASE_ANON_KEY"
    static let envAPIBaseURLKey = "PAST_QUESTIONS_API_BASE_URL"
    static let infoURLKey = "PAST_QUESTIONS_SUPABASE_URL"
    static let infoAnonKey = "PAST_QUESTIONS_SUPABASE_ANON_KEY"
    static let infoAPIBaseURLKey = "PAST_QUESTIONS_API_BASE_URL"
    private static let storedURLUserDefaultsKey = "past_questions.supabase_url"
    private static let storedAnonUserDefaultsKey = "past_questions.supabase_anon_key"
    private static let storedAPIBaseURLUserDefaultsKey = "past_questions.api_base_url"

    @Published private(set) var configuration: PastQuestionsConfiguration

    private let userDefaults: UserDefaults
    private let environment: [String: String]
    private let infoDictionary: [String: Any]

    init(
        userDefaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) {
        self.userDefaults = userDefaults
        self.environment = environment
        self.infoDictionary = infoDictionary
        self.configuration = Self.loadConfiguration(
            userDefaults: userDefaults,
            environment: environment,
            infoDictionary: infoDictionary,
            storedURLKey: Self.storedURLUserDefaultsKey,
            storedAnonKey: Self.storedAnonUserDefaultsKey
        )
    }

    var configurationSourceLabel: String {
        let envURL = environment[Self.envURLKey]?.trimmedNonEmpty
        let envAnonKey = environment[Self.envAnonKey]?.trimmedNonEmpty
        let envAPIBaseURL = environment[Self.envAPIBaseURLKey]?.trimmedNonEmpty
        if envURL != nil || envAnonKey != nil || envAPIBaseURL != nil {
            return "환경변수"
        }
        let bundleURL = Self.infoString(forKey: Self.infoURLKey, in: infoDictionary)
        let bundleAnonKey = Self.infoString(forKey: Self.infoAnonKey, in: infoDictionary)
        let bundleAPIBaseURL = Self.infoString(forKey: Self.infoAPIBaseURLKey, in: infoDictionary)
        if bundleURL != nil || bundleAnonKey != nil || bundleAPIBaseURL != nil {
            return "앱 번들"
        }
        if configuration.hasLookupConfiguration || configuration.hasSearchConfiguration {
            return "앱 저장값"
        }
        return "미설정"
    }

    func update(baseURLString: String, anonKey: String, apiBaseURLString: String) {
        let normalized = PastQuestionsConfiguration(
            baseURLString: normalizedURLString(baseURLString),
            anonKey: anonKey.trimmingCharacters(in: .whitespacesAndNewlines),
            apiBaseURLString: normalizedURLString(apiBaseURLString)
        )

        if let baseURL = normalized.baseURLString.trimmedNonEmpty {
            userDefaults.set(baseURL, forKey: Self.storedURLUserDefaultsKey)
        } else {
            userDefaults.removeObject(forKey: Self.storedURLUserDefaultsKey)
        }

        if let anonKey = normalized.anonKey.trimmedNonEmpty {
            userDefaults.set(anonKey, forKey: Self.storedAnonUserDefaultsKey)
        } else {
            userDefaults.removeObject(forKey: Self.storedAnonUserDefaultsKey)
        }

        if let apiBaseURL = normalized.apiBaseURLString.trimmedNonEmpty {
            userDefaults.set(apiBaseURL, forKey: Self.storedAPIBaseURLUserDefaultsKey)
        } else {
            userDefaults.removeObject(forKey: Self.storedAPIBaseURLUserDefaultsKey)
        }

        configuration = Self.loadConfiguration(
            userDefaults: userDefaults,
            environment: environment,
            infoDictionary: infoDictionary,
            storedURLKey: Self.storedURLUserDefaultsKey,
            storedAnonKey: Self.storedAnonUserDefaultsKey
        )
    }

    func reload() {
        configuration = Self.loadConfiguration(
            userDefaults: userDefaults,
            environment: environment,
            infoDictionary: infoDictionary,
            storedURLKey: Self.storedURLUserDefaultsKey,
            storedAnonKey: Self.storedAnonUserDefaultsKey
        )
    }

    private func normalizedURLString(_ candidate: String) -> String {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let normalized = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        if normalized.hasPrefix("http://") || normalized.hasPrefix("https://") {
            return normalized
        }
        return "https://\(normalized)"
    }

    private static func loadConfiguration(
        userDefaults: UserDefaults,
        environment: [String: String],
        infoDictionary: [String: Any],
        storedURLKey: String,
        storedAnonKey: String
    ) -> PastQuestionsConfiguration {
        let envURL = environment[envURLKey]?.trimmedNonEmpty
        let envAnonKey = environment[envAnonKey]?.trimmedNonEmpty
        let envAPIBaseURL = environment[envAPIBaseURLKey]?.trimmedNonEmpty
        let bundleURL = infoString(forKey: infoURLKey, in: infoDictionary)
        let bundleAnonKey = infoString(forKey: infoAnonKey, in: infoDictionary)
        let bundleAPIBaseURL = infoString(forKey: infoAPIBaseURLKey, in: infoDictionary)
        let storedURL = userDefaults.string(forKey: storedURLKey)?.trimmedNonEmpty
        let storedAnonKey = userDefaults.string(forKey: storedAnonKey)?.trimmedNonEmpty
        let storedAPIBaseURL = userDefaults.string(forKey: storedAPIBaseURLUserDefaultsKey)?.trimmedNonEmpty

        return PastQuestionsConfiguration(
            baseURLString: envURL ?? bundleURL ?? storedURL ?? "",
            anonKey: envAnonKey ?? bundleAnonKey ?? storedAnonKey ?? "",
            apiBaseURLString: envAPIBaseURL ?? bundleAPIBaseURL ?? storedAPIBaseURL ?? ""
        )
    }

    private static func infoString(forKey key: String, in dictionary: [String: Any]) -> String? {
        guard let rawValue = dictionary[key] as? String else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.contains("$(") else { return nil }
        return trimmed
    }
}

enum PastQuestionsError: LocalizedError {
    case missingConfiguration
    case missingLookupConfiguration
    case missingSearchConfiguration
    case invalidBaseURL
    case invalidAPIBaseURL
    case invalidLookupRequest
    case invalidSearchQuery
    case requestFailed(String)
    case invalidResponse
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "기출 DB 연결 정보가 없습니다."
        case .missingLookupConfiguration:
            return "기출 exact lookup 연결 정보가 없습니다. PAST_QUESTIONS_API_BASE_URL을 설정하거나 기존 Supabase 설정을 확인하세요."
        case .missingSearchConfiguration:
            return "기출 search 연결 정보가 없습니다. PAST_QUESTIONS_SUPABASE_URL과 PAST_QUESTIONS_SUPABASE_ANON_KEY를 설정하세요."
        case .invalidBaseURL:
            return "기출 DB Supabase URL 형식이 올바르지 않습니다."
        case .invalidAPIBaseURL:
            return "TutorHub API URL 형식이 올바르지 않습니다."
        case .invalidLookupRequest:
            return "과목, 연도, 월, 문항 번호를 모두 확인해 주세요."
        case .invalidSearchQuery:
            return "검색어를 2글자 이상 입력해 주세요."
        case .requestFailed(let message):
            return "기출 DB 조회 실패: \(message)"
        case .invalidResponse:
            return "기출 DB 응답 형식이 올바르지 않습니다."
        case .decodingFailed:
            return "기출 DB 응답을 해석하지 못했습니다."
        }
    }
}

private struct PastQuestionLookupAPIResponse: Decodable {
    let ok: Bool
    let match: PastQuestionRecord?
    let candidates: [PastQuestionRecord]
    let reason: String?

    private enum CodingKeys: String, CodingKey {
        case ok
        case match
        case candidates
        case reason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        match = try container.decodeIfPresent(PastQuestionRecord.self, forKey: .match)
        candidates = try container.decodeIfPresent([PastQuestionRecord].self, forKey: .candidates) ?? []
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
    }
}

actor PastQuestionsService {
    static let shared = PastQuestionsService()

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let selectFields = "id,subject,year,month,exam_type,question_number,difficulty,content,image_url,answer,solution,metadata"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func lookup(
        _ request: PastQuestionLookupRequest,
        configuration: PastQuestionsConfiguration
    ) async throws -> PastQuestionLookupResponse {
        guard request.year > 0, request.month > 0, request.questionNumber > 0 else {
            throw PastQuestionsError.invalidLookupRequest
        }

        if configuration.hasLookupAPIConfiguration {
            return try await lookupViaTutorHubAPI(request, configuration: configuration)
        }
        if configuration.hasSearchConfiguration {
            return try await lookupViaSupabaseFallback(request, configuration: configuration)
        }
        throw PastQuestionsError.missingLookupConfiguration
    }

    func search(
        _ request: PastQuestionSearchRequest,
        configuration: PastQuestionsConfiguration
    ) async throws -> PastQuestionSearchResponse {
        guard configuration.hasSearchConfiguration else {
            throw PastQuestionsError.missingSearchConfiguration
        }

        let trimmedQuery = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.count >= 2 else {
            throw PastQuestionsError.invalidSearchQuery
        }

        let normalizedSubjectHint = request.subjectHint?.trimmingCharacters(in: .whitespacesAndNewlines).trimmedNonEmpty
        let fetchLimit = min(max(request.topK * 90, 240), 900)

        let queryItems = [
            URLQueryItem(name: "select", value: selectFields),
            URLQueryItem(name: "content", value: "not.is.null"),
            URLQueryItem(name: "limit", value: "\(fetchLimit)"),
            URLQueryItem(name: "order", value: "year.desc.nullslast,month.desc.nullslast,question_number.asc")
        ]

        let rows = try await fetchRows(queryItems: queryItems, configuration: configuration)
        let queryTokens = tokenize(trimmedQuery)
        let queryNgrams = characterNgrams(trimmedQuery)

        let hits = rows
            .map { row -> PastQuestionSearchHit? in
                let scoring = scoreSearchCandidate(
                    row: row,
                    query: trimmedQuery,
                    queryTokens: queryTokens,
                    queryNgrams: queryNgrams,
                    subjectHint: normalizedSubjectHint
                )

                guard scoring.score > 0 else { return nil }

                return PastQuestionSearchHit(
                    record: row,
                    snippet: buildSnippet(for: row, queryTokens: queryTokens),
                    matchedTokens: scoring.matchedTokens,
                    score: scoring.score
                )
            }
            .compactMap { $0 }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                if ($0.record.year ?? 0) != ($1.record.year ?? 0) { return ($0.record.year ?? 0) > ($1.record.year ?? 0) }
                if ($0.record.month ?? 0) != ($1.record.month ?? 0) { return ($0.record.month ?? 0) > ($1.record.month ?? 0) }
                return $0.record.questionNumber < $1.record.questionNumber
            }

        return PastQuestionSearchResponse(
            query: trimmedQuery,
            subjectHint: normalizedSubjectHint,
            totalCandidates: rows.count,
            items: Array(hits.prefix(max(request.topK, 1)))
        )
    }

    private func lookupViaTutorHubAPI(
        _ request: PastQuestionLookupRequest,
        configuration: PastQuestionsConfiguration
    ) async throws -> PastQuestionLookupResponse {
        let endpoint = try makeLookupAPIURL(configuration: configuration)
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 30
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PastQuestionsError.invalidResponse
        }

        let decoded: PastQuestionLookupAPIResponse
        do {
            decoded = try decoder.decode(PastQuestionLookupAPIResponse.self, from: data)
        } catch {
            if (200 ... 299).contains(httpResponse.statusCode) {
                throw PastQuestionsError.decodingFailed
            }
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw PastQuestionsError.requestFailed(message?.trimmedNonEmpty ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))
        }

        if httpResponse.statusCode == 404 {
            return PastQuestionLookupResponse(
                status: .notFound,
                match: nil,
                candidates: decoded.candidates,
                message: lookupFailureMessage(reason: decoded.reason)
            )
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw PastQuestionsError.requestFailed(
                lookupFailureMessage(reason: decoded.reason) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }

        guard decoded.ok, let match = decoded.match else {
            return PastQuestionLookupResponse(
                status: .notFound,
                match: nil,
                candidates: decoded.candidates,
                message: lookupFailureMessage(reason: decoded.reason)
            )
        }

        return PastQuestionLookupResponse(
            status: .matched,
            match: match,
            candidates: [match] + decoded.candidates,
            message: nil
        )
    }

    private func lookupViaSupabaseFallback(
        _ request: PastQuestionLookupRequest,
        configuration: PastQuestionsConfiguration
    ) async throws -> PastQuestionLookupResponse {
        let yearCandidates = inferredYearCandidates(year: request.year, month: request.month)
        let queryItems = [
            URLQueryItem(name: "select", value: selectFields),
            URLQueryItem(name: "question_number", value: "eq.\(request.questionNumber)"),
            URLQueryItem(name: "month", value: "eq.\(request.month)"),
            URLQueryItem(name: "year", value: yearCandidates.count == 1 ? "eq.\(yearCandidates[0])" : "in.(\(yearCandidates.map(String.init).joined(separator: ",")))"),
            URLQueryItem(name: "limit", value: "60"),
            URLQueryItem(name: "order", value: "year.desc.nullslast,month.desc.nullslast")
        ]

        let rows = try await fetchRows(queryItems: queryItems, configuration: configuration)
        let subjectFiltered = filteredLookupRows(rows, request: request)
        let candidatePool = subjectFiltered.isEmpty ? rows : subjectFiltered
        let requirementFiltered = candidatePool.filter { row in
            rowSatisfiesLookupRequirements(row, request: request)
        }
        let filteredCandidates = requirementFiltered.isEmpty ? [] : requirementFiltered
        let requestedVariant = normalizedRequestedVariant(for: request)
        let exactVariantExists = requestedVariant.map { variant in
            filteredCandidates.contains { row in normalizedVariant(for: row) == variant && !isLegacyIntegratedRow(row) }
        } ?? false

        let ranked = filteredCandidates.sorted {
            isLookupCandidate($0, rankedAheadOf: $1, request: request, exactVariantExists: exactVariantExists)
        }

        guard let match = ranked.first else {
            return PastQuestionLookupResponse(
                status: .notFound,
                match: nil,
                candidates: Array(candidatePool.prefix(6)),
                message: "조건에 맞는 기출 문항을 찾지 못했습니다."
            )
        }

        return PastQuestionLookupResponse(
            status: .matched,
            match: match,
            candidates: ranked,
            message: nil
        )
    }

    private func makeLookupAPIURL(configuration: PastQuestionsConfiguration) throws -> URL {
        guard configuration.hasLookupAPIConfiguration,
              let baseURL = URL(string: configuration.sanitizedAPIBaseURLString) else {
            throw PastQuestionsError.invalidAPIBaseURL
        }

        if baseURL.path.hasSuffix("/api") {
            return baseURL.appending(path: "pharnode/item/lookup")
        }
        return baseURL.appending(path: "api/pharnode/item/lookup")
    }

    private func lookupFailureMessage(reason: String?) -> String? {
        switch reason?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case nil, "":
            return "조건에 맞는 기출 문항을 찾지 못했습니다."
        case "no_match_after_requirement_filter":
            return "이미지/공통 여부/배점 조건을 만족하는 기출 문항을 찾지 못했습니다."
        case "no_candidates":
            return "해당 회차와 문항 번호에 맞는 기출 후보가 없습니다."
        case "invalid_request":
            return "기출 조회 요청 형식이 올바르지 않습니다."
        default:
            return reason
        }
    }

    private func fetchRows(
        queryItems: [URLQueryItem],
        configuration: PastQuestionsConfiguration
    ) async throws -> [PastQuestionRecord] {
        guard let baseURL = URL(string: configuration.sanitizedBaseURLString) else {
            throw PastQuestionsError.invalidBaseURL
        }

        var components = URLComponents(url: baseURL.appending(path: "rest/v1/past_questions"), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw PastQuestionsError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.sanitizedAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(configuration.sanitizedAnonKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PastQuestionsError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw PastQuestionsError.requestFailed(message?.trimmedNonEmpty ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))
        }

        do {
            return try decoder.decode([PastQuestionRecord].self, from: data)
        } catch {
            throw PastQuestionsError.decodingFailed
        }
    }

    private func filteredLookupRows(_ rows: [PastQuestionRecord], request: PastQuestionLookupRequest) -> [PastQuestionRecord] {
        let requestedSubjectRoot = subjectRoot(for: request.subject)
        guard let requestedSubjectRoot else { return rows }
        return rows.filter { subjectRoot(for: $0.subject) == requestedSubjectRoot }
    }

    private func inferredYearCandidates(year: Int, month: Int) -> [Int] {
        guard [6, 9, 10, 11].contains(month) else { return [year] }
        var results: [Int] = []
        for candidate in [year, year - 1, year + 1] where !results.contains(candidate) {
            results.append(candidate)
        }
        return results
    }

    private func normalizedRequestedVariant(for request: PastQuestionLookupRequest) -> String? {
        if let explicitVariant = request.examVariant?.trimmedNonEmpty {
            return normalizedVariant(raw: explicitVariant, questionNumber: request.questionNumber)
        }

        let normalizedSubject = normalizedCompact(request.subject)
        if normalizedSubject.contains("공통")
            || normalizedSubject.contains("가형")
            || normalizedSubject.contains("나형")
            || normalizedSubject.contains("미적분")
            || normalizedSubject.contains("기하")
            || normalizedSubject.contains("확률과통계")
            || normalizedSubject.contains("확통")
            || normalizedSubject.contains("통합") {
            return normalizedVariant(raw: request.subject, questionNumber: request.questionNumber)
        }

        return nil
    }

    private func normalizedVariant(for row: PastQuestionRecord) -> String? {
        normalizedVariant(raw: rawVariant(for: row), questionNumber: row.questionNumber)
    }

    private func rawVariant(for row: PastQuestionRecord) -> String? {
        if let metadataVariant = row.metadata.examVariant?.trimmedNonEmpty {
            return metadataVariant
        }

        let normalizedSubject = normalizedCompact(row.subject)
        if normalizedSubject.contains("수학(공통)") || normalizedSubject.contains("수학공통") || normalizedSubject == "공통" {
            return "공통"
        }
        if normalizedSubject.contains("가형") || normalizedSubject.hasSuffix("가") {
            return "가형"
        }
        if normalizedSubject.contains("나형") || normalizedSubject.hasSuffix("나") {
            return "나형"
        }
        if normalizedSubject.contains("미적분") {
            return "미적분"
        }
        if normalizedSubject.contains("기하") {
            return "기하"
        }
        if normalizedSubject.contains("확률과통계") || normalizedSubject.contains("확통") {
            return "확률과통계"
        }
        if normalizedSubject == "수학" || normalizedSubject.contains("통합") {
            return "통합"
        }
        return nil
    }

    private func normalizedVariant(raw: String?, questionNumber: Int) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).trimmedNonEmpty else { return nil }
        let normalized = normalizedCompact(raw)

        if normalized == "수학(공통)" || normalized == "수학공통" || normalized == "공통" || normalized == "common" {
            return "공통"
        }
        if normalized == "가" || normalized == "가형" || normalized == "ga" {
            return "가형"
        }
        if normalized == "나" || normalized == "나형" || normalized == "na" {
            return "나형"
        }
        if normalized == "통합" || normalized == "integrated" {
            if (1 ... 22).contains(questionNumber) {
                return "공통"
            }
            return "통합"
        }
        if normalized == "수학" || normalized == "math" {
            return nil
        }
        if normalized.contains("미적분") {
            return "미적분"
        }
        if normalized.contains("기하") {
            return "기하"
        }
        if normalized.contains("확률과통계") || normalized.contains("확통") {
            return "확률과통계"
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func inferredPaperSection(for row: PastQuestionRecord) -> String? {
        if let explicit = row.paperSection?.trimmedNonEmpty {
            return explicit
        }

        switch normalizedVariant(for: row) {
        case "공통":
            return "공통"
        case "미적분", "기하", "확률과통계":
            return "선택"
        case "통합":
            if (1 ... 22).contains(row.questionNumber) {
                return "공통"
            }
            if (23 ... 30).contains(row.questionNumber) {
                return "선택"
            }
            return nil
        default:
            return nil
        }
    }

    private func inferredPoints(for row: PastQuestionRecord) -> Int? {
        if let explicit = row.points {
            return explicit
        }

        guard let difficulty = row.difficulty?.trimmingCharacters(in: .whitespacesAndNewlines).trimmedNonEmpty else {
            return nil
        }

        if difficulty.contains("4점") { return 4 }
        if difficulty.contains("3점") { return 3 }
        if difficulty.contains("2점") { return 2 }
        if difficulty.contains("5점") { return 5 }
        return nil
    }

    private func rowSatisfiesLookupRequirements(
        _ row: PastQuestionRecord,
        request: PastQuestionLookupRequest
    ) -> Bool {
        if let examType = request.examType?.trimmedNonEmpty {
            let normalizedRequestedExamType = normalizedCompact(examType)
            let normalizedRowExamType = normalizedCompact(row.examType)
            if normalizedRequestedExamType != normalizedRowExamType {
                return false
            }
        }

        if request.requireImage, !row.hasImage {
            return false
        }

        if let requiredPaperSection = request.requirePaperSection?.trimmedNonEmpty,
           inferredPaperSection(for: row) != requiredPaperSection {
            return false
        }

        if let requiredPoints = request.requirePoints,
           inferredPoints(for: row) != requiredPoints {
            return false
        }

        return true
    }

    private func isLegacyIntegratedRow(_ row: PastQuestionRecord) -> Bool {
        let raw = rawVariant(for: row)
        let normalized = normalizedCompact(raw ?? "")
        if normalized == "통합" || normalized == "integrated" {
            return true
        }

        let subject = normalizedCompact(row.subject)
        return subject == "수학" || subject == "수학통합"
    }

    private func lookupSortTuple(
        for row: PastQuestionRecord,
        request: PastQuestionLookupRequest,
        exactVariantExists: Bool
    ) -> (Int, Int, Int, Int, Int, Int, Int, Int) {
        let requestedVariant = normalizedRequestedVariant(for: request)
        let rowVariant = normalizedVariant(for: row)
        let rowYear = row.year ?? 0
        let rowMonth = row.month ?? 0
        let variantMatch = requestedVariant != nil && rowVariant == requestedVariant ? 1 : 0
        let hasImage = row.imageURL != nil ? 1 : 0
        let hasAnswer = row.answer?.trimmedNonEmpty != nil ? 1 : 0
        let hasSolution = row.solution?.trimmedNonEmpty != nil ? 1 : 0
        let legacyPenalty = exactVariantExists && isLegacyIntegratedRow(row) && variantMatch == 0 ? -1 : 0
        let score = lookupScore(for: row, request: request, exactVariantExists: exactVariantExists)

        return (
            score,
            variantMatch,
            hasImage,
            hasAnswer,
            hasSolution,
            rowYear,
            rowMonth,
            legacyPenalty
        )
    }

    private func isLookupCandidate(
        _ lhs: PastQuestionRecord,
        rankedAheadOf rhs: PastQuestionRecord,
        request: PastQuestionLookupRequest,
        exactVariantExists: Bool
    ) -> Bool {
        let left = lookupSortTuple(for: lhs, request: request, exactVariantExists: exactVariantExists)
        let right = lookupSortTuple(for: rhs, request: request, exactVariantExists: exactVariantExists)

        if left.0 != right.0 { return left.0 > right.0 }
        if left.1 != right.1 { return left.1 > right.1 }
        if left.2 != right.2 { return left.2 > right.2 }
        if left.3 != right.3 { return left.3 > right.3 }
        if left.4 != right.4 { return left.4 > right.4 }
        if left.5 != right.5 { return left.5 > right.5 }
        if left.6 != right.6 { return left.6 > right.6 }
        return left.7 > right.7
    }

    private func lookupScore(
        for row: PastQuestionRecord,
        request: PastQuestionLookupRequest,
        exactVariantExists: Bool
    ) -> Int {
        var score = 0

        if row.questionNumber == request.questionNumber {
            score += 240
        }

        if row.year == request.year {
            score += 120
        } else if inferredYearCandidates(year: request.year, month: request.month).contains(row.year ?? -1) {
            score += 48
        }

        if row.month == request.month {
            score += 40
        }

        if let requestSubject = subjectRoot(for: request.subject),
           let rowSubject = subjectRoot(for: row.subject) {
            if requestSubject == rowSubject {
                score += 60
            } else {
                score -= 120
            }
        }

        let requestedVariant = normalizedRequestedVariant(for: request)
        let rowVariant = normalizedVariant(for: row)
        if let requestedVariant {
            if rowVariant == requestedVariant {
                score += 180
            } else if requestedVariant == "공통" && isLegacyIntegratedRow(row) {
                score += exactVariantExists ? 18 : 72
            } else if exactVariantExists {
                score -= 90
            } else {
                score -= 16
            }
        }

        if row.imageURL != nil {
            score += 20
        }
        if row.answer?.trimmedNonEmpty != nil {
            score += 14
        }
        if row.solution?.trimmedNonEmpty != nil {
            score += 6
        }
        if exactVariantExists && isLegacyIntegratedRow(row) && rowVariant != requestedVariant {
            score -= 36
        }

        return score
    }

    private func subjectRoot(for raw: String) -> String? {
        let normalized = normalizedCompact(raw)
        guard !normalized.isEmpty else { return nil }

        if normalized.contains("수학") || normalized.contains("공통") || normalized.contains("가형") || normalized.contains("나형") || normalized.contains("미적분") || normalized.contains("기하") || normalized.contains("확률과통계") || normalized.contains("확통") || normalized.contains("통합") {
            return "수학"
        }
        if normalized.contains("국어") {
            return "국어"
        }
        if normalized.contains("영어") {
            return "영어"
        }
        if normalized.contains("물리") {
            return "물리"
        }
        if normalized.contains("화학") {
            return "화학"
        }
        if normalized.contains("생명") || normalized.contains("생물") {
            return "생명과학"
        }
        if normalized.contains("지구과학") {
            return "지구과학"
        }
        if normalized.contains("한국사") {
            return "한국사"
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).trimmedNonEmpty
    }

    private func normalizedCompact(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .replacingOccurrences(of: "\n", with: "")
    }

    private func searchCorpus(for row: PastQuestionRecord) -> String {
        [
            row.subject,
            row.examType,
            row.content,
            row.answer ?? "",
            row.solution ?? "",
            row.metadata.keywords.joined(separator: " "),
            row.metadata.unit ?? ""
        ]
        .joined(separator: "\n")
        .compactWhitespace()
    }

    private func scoreSearchCandidate(
        row: PastQuestionRecord,
        query: String,
        queryTokens: [String],
        queryNgrams: [String],
        subjectHint: String?
    ) -> (score: Int, matchedTokens: [String]) {
        let corpus = searchCorpus(for: row)
        let normalizedCorpus = corpus.lowercased()
        guard !normalizedCorpus.isEmpty else {
            return (0, [])
        }

        var score = 0
        var matchedTokens: [String] = []

        for token in queryTokens {
            guard normalizedCorpus.contains(token) else { continue }
            matchedTokens.append(token)
            score += token.count >= 4 ? 7 : 5
        }

        let queryHead = query.lowercased().prefix(42)
        if !queryHead.isEmpty, normalizedCorpus.contains(queryHead) {
            score += 18
        }

        let corpusNgrams = characterNgrams(corpus)
        score += Int((jaccardSimilarity(queryNgrams, corpusNgrams) * 44).rounded())

        if let subjectHint, !subjectHint.isEmpty {
            let subjectRootHint = subjectRoot(for: subjectHint)
            if subjectRootHint == subjectRoot(for: row.subject) {
                score += 12
            }
        }

        if row.imageURL != nil {
            score += 2
        }
        if row.answer?.trimmedNonEmpty != nil {
            score += 2
        }
        if row.solution?.trimmedNonEmpty != nil {
            score += 1
        }

        return (score, Array(matchedTokens.prefix(12)))
    }

    private func buildSnippet(for row: PastQuestionRecord, queryTokens: [String]) -> String {
        let source = row.content.compactWhitespace().trimmedNonEmpty
            ?? row.solution?.compactWhitespace().trimmedNonEmpty
            ?? row.answer?.compactWhitespace().trimmedNonEmpty
            ?? ""

        guard !source.isEmpty else { return "" }

        let lowered = source.lowercased()
        var hitIndex = -1
        for token in queryTokens {
            let index = lowered.range(of: token)?.lowerBound
            guard let index else { continue }
            let offset = lowered.distance(from: lowered.startIndex, to: index)
            if hitIndex < 0 || offset < hitIndex {
                hitIndex = offset
            }
        }

        if hitIndex < 0 {
            return String(source.prefix(220))
        }

        let start = max(0, hitIndex - 70)
        let end = min(source.count, hitIndex + 170)
        let lower = source.index(source.startIndex, offsetBy: start)
        let upper = source.index(source.startIndex, offsetBy: end)
        let prefix = start > 0 ? "..." : ""
        let suffix = end < source.count ? "..." : ""
        return "\(prefix)\(source[lower ..< upper])\(suffix)"
    }

    private let koreanStopWords: Set<String> = [
        "그리고", "하지만", "그러나", "또는", "정말", "이번", "관련", "대한", "위해", "에서", "까지",
        "하는", "하면", "해줘", "알려줘", "질문", "답변", "문제", "문항", "수능", "자료", "내용", "정답",
        "보기", "다음", "아래", "중에서", "것은", "있는", "없는", "이다", "한다", "해설", "풀이"
    ]

    private func tokenize(_ value: String) -> [String] {
        var seen: Set<String> = []
        let tokens = value
            .lowercased()
            .split { character in
                !(character.isWholeNumber || character.isLetter)
            }
            .map(String.init)
            .filter { $0.count >= 2 }
            .filter { !koreanStopWords.contains($0) }
            .filter { seen.insert($0).inserted }

        return Array(tokens.prefix(24))
    }

    private func characterNgrams(_ value: String, n: Int = 2) -> [String] {
        let normalized = value.lowercased().replacingOccurrences(of: " ", with: "")
        guard normalized.count >= n else { return [] }

        let characters = Array(normalized)
        guard characters.count >= n else { return [] }

        return (0 ... characters.count - n).map { offset in
            String(characters[offset ..< offset + n])
        }
    }

    private func jaccardSimilarity(_ lhs: [String], _ rhs: [String]) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let lhsSet = Set(lhs)
        let rhsSet = Set(rhs)
        let intersection = lhsSet.intersection(rhsSet).count
        let union = lhsSet.union(rhsSet).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }
}

private extension String {
    nonisolated var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated func compactWhitespace() -> String {
        replacingOccurrences(of: "\r\n", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map { line in
                line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
