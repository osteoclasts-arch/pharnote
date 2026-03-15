import Foundation

nonisolated enum PastQuestionJSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([PastQuestionJSONValue])
    case object([String: PastQuestionJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: PastQuestionJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([PastQuestionJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value.rounded(.towardZero) == value ? String(Int(value)) : String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .array, .object, .null:
            return nil
        }
    }

    var stringArrayValue: [String] {
        guard case .array(let values) = self else { return [] }
        return values.compactMap(\.stringValue).filter { !$0.isEmpty }
    }

    var intValue: Int? {
        switch self {
        case .number(let value):
            return Int(value.rounded(.towardZero))
        case .string(let value):
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value):
            return value
        case .string(let value):
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        default:
            return nil
        }
    }
}

nonisolated struct PastQuestionMetadata: Codable, Hashable, Sendable {
    var values: [String: PastQuestionJSONValue]

    init(values: [String: PastQuestionJSONValue] = [:]) {
        self.values = values
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            values = [:]
        } else {
            values = try container.decode([String: PastQuestionJSONValue].self)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }

    subscript(key: String) -> PastQuestionJSONValue? {
        values[key]
    }

    func string(for key: String) -> String? {
        values[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    }

    func stringArray(for key: String) -> [String] {
        values[key]?.stringArrayValue ?? []
    }

    var examVariant: String? {
        string(for: "exam_variant")
    }

    var paperSection: String? {
        string(for: "paper_section")
    }

    var points: Int? {
        values["points"]?.intValue
    }

    var isCommon: Bool? {
        values["is_common"]?.boolValue
    }

    var keywords: [String] {
        stringArray(for: "keywords")
    }

    var unit: String? {
        string(for: "unit")
            ?? string(for: "chapter")
            ?? string(for: "topic")
    }
}

nonisolated struct PastQuestionRecord: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let subject: String
    let year: Int?
    let month: Int?
    let examType: String
    let questionNumber: Int
    let difficulty: String?
    let content: String
    let imageURLString: String?
    let answer: String?
    let solution: String?
    let normalizedExamVariant: String?
    let normalizedPaperSection: String?
    let normalizedPoints: Int?
    let normalizedHasImage: Bool?
    let metadata: PastQuestionMetadata

    enum CodingKeys: String, CodingKey {
        case id
        case subject
        case year
        case month
        case examType = "exam_type"
        case examTypeCamel = "examType"
        case questionNumber = "question_number"
        case questionNumberCamel = "questionNumber"
        case difficulty
        case content
        case imageURLString = "image_url"
        case imageURLStringCamel = "imageUrl"
        case answer
        case solution
        case normalizedExamVariant = "examVariant"
        case normalizedPaperSection = "paperSection"
        case normalizedPoints = "points"
        case normalizedHasImage = "hasImage"
        case metadata
    }

    init(
        id: UUID,
        subject: String,
        year: Int?,
        month: Int?,
        examType: String,
        questionNumber: Int,
        difficulty: String?,
        content: String,
        imageURLString: String?,
        answer: String?,
        solution: String?,
        normalizedExamVariant: String?,
        normalizedPaperSection: String?,
        normalizedPoints: Int?,
        normalizedHasImage: Bool?,
        metadata: PastQuestionMetadata
    ) {
        self.id = id
        self.subject = subject
        self.year = year
        self.month = month
        self.examType = examType
        self.questionNumber = questionNumber
        self.difficulty = difficulty
        self.content = content
        self.imageURLString = imageURLString
        self.answer = answer
        self.solution = solution
        self.normalizedExamVariant = normalizedExamVariant
        self.normalizedPaperSection = normalizedPaperSection
        self.normalizedPoints = normalizedPoints
        self.normalizedHasImage = normalizedHasImage
        self.metadata = metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        subject = try container.decode(String.self, forKey: .subject)
        year = try container.decodeIfPresent(Int.self, forKey: .year)
        month = try container.decodeIfPresent(Int.self, forKey: .month)
        examType = try container.decodeIfPresent(String.self, forKey: .examType)
            ?? container.decodeIfPresent(String.self, forKey: .examTypeCamel)
            ?? ""
        questionNumber = try container.decodeIfPresent(Int.self, forKey: .questionNumber)
            ?? container.decode(Int.self, forKey: .questionNumberCamel)
        difficulty = try container.decodeIfPresent(String.self, forKey: .difficulty)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        imageURLString = try container.decodeIfPresent(String.self, forKey: .imageURLString)
            ?? container.decodeIfPresent(String.self, forKey: .imageURLStringCamel)
        answer = try container.decodeIfPresent(String.self, forKey: .answer)
        solution = try container.decodeIfPresent(String.self, forKey: .solution)
        normalizedExamVariant = try container.decodeIfPresent(String.self, forKey: .normalizedExamVariant)
        normalizedPaperSection = try container.decodeIfPresent(String.self, forKey: .normalizedPaperSection)
        normalizedPoints = try container.decodeIfPresent(Int.self, forKey: .normalizedPoints)
        normalizedHasImage = try container.decodeIfPresent(Bool.self, forKey: .normalizedHasImage)
        metadata = try container.decodeIfPresent(PastQuestionMetadata.self, forKey: .metadata) ?? PastQuestionMetadata()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(subject, forKey: .subject)
        try container.encodeIfPresent(year, forKey: .year)
        try container.encodeIfPresent(month, forKey: .month)
        try container.encode(examType, forKey: .examType)
        try container.encode(questionNumber, forKey: .questionNumber)
        try container.encodeIfPresent(difficulty, forKey: .difficulty)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(imageURLString, forKey: .imageURLString)
        try container.encodeIfPresent(answer, forKey: .answer)
        try container.encodeIfPresent(solution, forKey: .solution)
        try container.encodeIfPresent(normalizedExamVariant, forKey: .normalizedExamVariant)
        try container.encodeIfPresent(normalizedPaperSection, forKey: .normalizedPaperSection)
        try container.encodeIfPresent(normalizedPoints, forKey: .normalizedPoints)
        try container.encodeIfPresent(normalizedHasImage, forKey: .normalizedHasImage)
        try container.encode(metadata, forKey: .metadata)
    }
}

extension PastQuestionRecord {
    nonisolated var imageURL: URL? {
        guard let imageURLString,
              let url = URL(string: imageURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
              !imageURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return url
    }

    nonisolated var llmImageInputURLString: String? {
        imageURL?.absoluteString
    }

    nonisolated var examVariant: String? {
        normalizedExamVariant?.nonEmpty ?? metadata.examVariant
    }

    nonisolated var paperSection: String? {
        normalizedPaperSection?.nonEmpty ?? metadata.paperSection
    }

    nonisolated var points: Int? {
        normalizedPoints ?? metadata.points
    }

    nonisolated var hasImage: Bool {
        normalizedHasImage ?? (imageURL != nil)
    }

    nonisolated var contentPreview: String {
        let cleaned = content.compactWhitespace()
        return String(cleaned.prefix(220))
    }

    nonisolated var answerPreview: String? {
        answer?.compactWhitespace().nonEmpty
    }
}

nonisolated struct PastQuestionLookupRequest: Codable, Hashable, Sendable {
    var subject: String
    var year: Int
    var month: Int
    var examType: String?
    var questionNumber: Int
    var examVariant: String?
    var requireImage: Bool
    var requirePaperSection: String?
    var requirePoints: Int?
}

nonisolated enum PastQuestionLookupStatus: String, Codable, Hashable, Sendable {
    case matched
    case notFound = "not_found"
}

nonisolated struct PastQuestionLookupResponse: Hashable, Sendable {
    var status: PastQuestionLookupStatus
    var match: PastQuestionRecord?
    var candidates: [PastQuestionRecord]
    var message: String?
}

nonisolated struct PastQuestionSearchRequest: Hashable, Sendable {
    var query: String
    var subjectHint: String?
    var topK: Int
}

nonisolated struct PastQuestionSearchHit: Identifiable, Hashable, Sendable {
    var id: UUID { record.id }
    var record: PastQuestionRecord
    var snippet: String
    var matchedTokens: [String]
    var score: Int
}

nonisolated struct PastQuestionSearchResponse: Hashable, Sendable {
    var query: String
    var subjectHint: String?
    var totalCandidates: Int
    var items: [PastQuestionSearchHit]
}

private extension String {
    nonisolated var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated func compactWhitespace() -> String {
        replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .split(whereSeparator: \.isNewline)
            .map { line in
                line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
