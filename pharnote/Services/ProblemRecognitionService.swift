import Foundation
import PDFKit

struct ProblemRecognitionContext: Sendable {
    var document: PharDocument
    var selection: ProblemSelection
    var pageTextBlocks: [AnalysisTextBlock]
    var hint: ProblemRecognitionHint?
    var pastQuestionsConfiguration: PastQuestionsConfiguration?
}

actor ProblemRecognitionService {
    private let documentOCRService: DocumentOCRService
    private let pastQuestionsService: PastQuestionsService

    private let highConfidenceThreshold = 0.84
    private let mediumConfidenceThreshold = 0.62

    init(
        documentOCRService: DocumentOCRService = DocumentOCRService(),
        pastQuestionsService: PastQuestionsService = .shared
    ) {
        self.documentOCRService = documentOCRService
        self.pastQuestionsService = pastQuestionsService
    }

    func recognize(_ context: ProblemRecognitionContext) async -> ProblemRecognitionResult {
        let selectionText = await documentOCRService.recognizePDFSelectionText(
            document: context.document,
            pageIndex: context.selection.pageIndex,
            normalizedRect: CGRect(
                x: context.selection.boundingBox.x,
                y: context.selection.boundingBox.y,
                width: context.selection.boundingBox.width,
                height: context.selection.boundingBox.height
            )
        )

        let pageText = textSnippet(from: context.pageTextBlocks)
        let recognitionText = joinedNonEmpty([selectionText, pageText])

        if let directMatch = directMatch(from: context, recognitionText: recognitionText) {
            return ProblemRecognitionResult(
                selectionId: context.selection.id,
                bestMatch: directMatch,
                candidates: [],
                confidence: directMatch.confidence,
                status: .matched,
                recognitionText: recognitionText,
                reason: "direct_metadata"
            )
        }

        guard let configuration = context.pastQuestionsConfiguration,
              configuration.hasSearchConfiguration else {
            return ProblemRecognitionResult(
                selectionId: context.selection.id,
                bestMatch: nil,
                candidates: [],
                confidence: 0,
                status: .failed,
                recognitionText: recognitionText,
                reason: "search_unavailable"
            )
        }

        let query = buildSearchQuery(
            document: context.document,
            selectionText: selectionText,
            pageText: pageText
        )

        do {
            let response = try await pastQuestionsService.search(
                PastQuestionSearchRequest(query: query, subjectHint: context.document.studyMaterial?.subject.title, topK: 6),
                configuration: configuration
            )

            let candidates = convertCandidates(from: response.items)
            guard let bestCandidate = candidates.first else {
                return ProblemRecognitionResult(
                    selectionId: context.selection.id,
                    bestMatch: nil,
                    candidates: [],
                    confidence: 0,
                    status: .failed,
                    recognitionText: recognitionText,
                    reason: "no_candidates"
                )
            }

            let confidence = normalizedConfidence(for: bestCandidate, topCandidate: candidates.first, secondCandidate: candidates.dropFirst().first)
            let bestMatch = convertToMatch(bestCandidate, alternatives: Array(candidates.dropFirst(1).prefix(3)))

            let status: ProblemSelectionRecognitionStatus
            if confidence >= highConfidenceThreshold {
                status = .matched
            } else if confidence >= mediumConfidenceThreshold {
                status = .ambiguous
            } else {
                status = .failed
            }

            return ProblemRecognitionResult(
                selectionId: context.selection.id,
                bestMatch: status == .failed ? nil : bestMatch,
                candidates: candidates,
                confidence: confidence,
                status: status,
                recognitionText: recognitionText,
                reason: status == .matched ? "fuzzy_match" : "candidate_pool"
            )
        } catch {
            return ProblemRecognitionResult(
                selectionId: context.selection.id,
                bestMatch: nil,
                candidates: [],
                confidence: 0,
                status: .failed,
                recognitionText: recognitionText,
                reason: error.localizedDescription
            )
        }
    }

    private func directMatch(from context: ProblemRecognitionContext, recognitionText: String?) -> ProblemMatch? {
        guard let hint = context.hint else { return nil }

        if let canonicalProblemId = trimmedNonEmpty(hint.canonicalProblemId) {
            let subject = hint.subject ?? context.document.studyMaterial?.subject ?? .unspecified
            let year = hint.year ?? currentYearFallback()
            return ProblemMatch(
                examId: trimmedNonEmpty(hint.examId) ?? context.document.studyMaterial?.catalogEntryID ?? context.document.id.uuidString,
                subject: subject,
                year: year,
                sessionType: trimmedNonEmpty(hint.sessionType) ?? context.document.studyMaterial?.canonicalTitle ?? "exam",
                problemNumber: hint.problemNumber ?? max(context.selection.pageIndex + 1, 1),
                canonicalProblemId: canonicalProblemId,
                confidence: min(max(hint.confidence ?? 0.98, 0), 0.99),
                matchMethod: .directMetadata,
                displayTitle: displayTitle(
                    year: year == 0 ? currentYearFallback() : year,
                    subject: subject,
                    problemNumber: hint.problemNumber ?? max(context.selection.pageIndex + 1, 1)
                ),
                recognitionText: recognitionText,
                candidateAlternatives: nil
            )
        }

        return nil
    }

    private func convertCandidates(from hits: [PastQuestionSearchHit]) -> [ProblemMatchCandidate] {
        hits.map { hit in
            let record = hit.record
            return ProblemMatchCandidate(
                examId: trimmedNonEmpty(record.examType) ?? record.id.uuidString,
                subject: subject(from: record.subject),
                year: record.year ?? 0,
                sessionType: trimmedNonEmpty(record.examType) ?? "exam",
                problemNumber: record.questionNumber,
                canonicalProblemId: record.id.uuidString,
                confidence: confidence(for: hit.score),
                matchMethod: .fuzzySearch,
                displayTitle: displayTitle(
                    year: record.year ?? currentYearFallback(),
                    subject: subject(from: record.subject),
                    problemNumber: record.questionNumber
                ),
                reason: trimmedNonEmpty(hit.snippet)
            )
        }
    }

    private func convertToMatch(_ candidate: ProblemMatchCandidate, alternatives: [ProblemMatchCandidate]) -> ProblemMatch {
        ProblemMatch(
            examId: candidate.examId,
            subject: candidate.subject,
            year: candidate.year,
            sessionType: candidate.sessionType,
            problemNumber: candidate.problemNumber,
            canonicalProblemId: candidate.canonicalProblemId,
            confidence: candidate.confidence,
            matchMethod: candidate.matchMethod,
            displayTitle: candidate.displayTitle,
            recognitionText: candidate.reason,
            candidateAlternatives: alternatives.isEmpty ? nil : alternatives
        )
    }

    private func normalizedConfidence(for candidate: ProblemMatchCandidate, topCandidate: ProblemMatchCandidate?, secondCandidate: ProblemMatchCandidate?) -> Double {
        let scoreBoost = min(max(candidate.confidence, 0.0), 0.98)
        guard let topCandidate else { return scoreBoost }

        let gap = max(topCandidate.confidence - (secondCandidate?.confidence ?? 0.0), 0)
        let gapBoost = min(gap * 0.35, 0.09)
        return min(0.98, scoreBoost + gapBoost)
    }

    private func confidence(for score: Int) -> Double {
        min(0.98, max(0.35, 0.38 + Double(score) / 180.0))
    }

    private func textSnippet(from blocks: [AnalysisTextBlock]) -> String? {
        return joinedNonEmpty(blocks.map(\.text))
    }

    private func buildSearchQuery(
        document: PharDocument,
        selectionText: String?,
        pageText: String?
    ) -> String {
        [
            document.title,
            document.studyMaterial?.canonicalTitle,
            document.studySubjectTitle,
            trimmedNonEmpty(selectionText),
            trimmedNonEmpty(pageText)
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\t", with: " ")
        .split(whereSeparator: \.isNewline)
        .map { line in
            line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func displayTitle(year: Int, subject: StudySubject, problemNumber: Int) -> String {
        "\(year) \(subject.title) Q\(problemNumber)"
    }

    private func subject(from raw: String) -> StudySubject {
        let normalized = raw.lowercased().replacingOccurrences(of: " ", with: "")
        if normalized.contains("국어") {
            return .korean
        }
        if normalized.contains("수학") {
            return .math
        }
        if normalized.contains("영어") {
            return .english
        }
        if normalized.contains("한국사") {
            return .koreanHistory
        }
        if normalized.contains("물리") {
            return .physics
        }
        if normalized.contains("화학") {
            return .chemistry
        }
        if normalized.contains("생명") || normalized.contains("생물") {
            return .biology
        }
        if normalized.contains("지구과학") {
            return .earthScience
        }
        if normalized.contains("사탐") || normalized.contains("사회") {
            return .socialInquiry
        }
        return .unspecified
    }

    private func currentYearFallback() -> Int {
        Calendar.current.component(.year, from: Date())
    }

    private func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func joinedNonEmpty(_ values: [String?]) -> String? {
        let pieces = values.compactMap { trimmedNonEmpty($0) }
        return pieces.isEmpty ? nil : pieces.joined(separator: "\n")
    }
}
