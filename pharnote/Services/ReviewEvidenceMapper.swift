import Foundation

struct ReviewEvidenceMapper {
    func derivedEvidence(for session: ReviewSession, schema: ReviewSchema) -> [DerivedReviewEvidence] {
        var evidence: [DerivedReviewEvidence] = []

        evidence.append(
            DerivedReviewEvidence(
                id: UUID(),
                subject: session.subject,
                evidenceType: "selection",
                nodeId: session.problemMatch?.canonicalProblemId,
                internalTag: session.problemMatch?.matchMethod.rawValue,
                confidence: session.problemMatch?.confidence ?? 0.5,
                sourceStepId: "selection",
                label: session.problemMatch?.displayTitle ?? session.subject.title,
                createdAt: session.updatedAt
            )
        )

        for answer in session.answers.sorted(by: { $0.createdAt < $1.createdAt }) {
            guard let step = schema.step(for: answer.stepId) else { continue }
            let selectedOptions = answer.selectedOptionIds.compactMap { optionId in
                step.options.first(where: { $0.id == optionId })
            }
            if selectedOptions.isEmpty {
                continue
            }

            for option in selectedOptions {
                evidence.append(
                    DerivedReviewEvidence(
                        id: UUID(),
                        subject: session.subject,
                        evidenceType: option.evidenceType,
                        nodeId: option.nodeId ?? option.internalTag,
                        internalTag: option.internalTag,
                        confidence: option.confidenceHint,
                        sourceStepId: answer.stepId,
                        label: option.title,
                        createdAt: answer.updatedAt
                    )
                )
            }
        }

        return evidence
    }

    func makePostSolveReview(from session: ReviewSession, schema: ReviewSchema) -> AnalysisPostSolveReview {
        let reviewPath = schema.steps.map { step in
            guard let answer = session.answers.last(where: { $0.stepId == step.id }),
                  let optionId = answer.selectedOptionIds.first,
                  let option = step.options.first(where: { $0.id == optionId }) else {
                return AnalysisReviewStepResponse(
                    stepId: step.id,
                    status: .notTried,
                    selectedOptionId: nil,
                    linkedStrokeId: nil,
                    calculatedDelayMs: nil
                )
            }

            let delayMs = Int(max(answer.createdAt.timeIntervalSince(session.startedAt), 0) * 1000)
            return AnalysisReviewStepResponse(
                stepId: step.id,
                status: option.analysisStatus,
                selectedOptionId: option.id,
                linkedStrokeId: option.nodeId ?? option.internalTag,
                calculatedDelayMs: delayMs
            )
        }

        var derivedNodeIds: [String] = []
        var derivedNodeLabels: [String] = []
        var derivedEvidenceTypes: [String] = []

        for answer in session.answers.sorted(by: { $0.createdAt < $1.createdAt }) {
            guard let step = schema.step(for: answer.stepId) else { continue }
            let selectedOptions = answer.selectedOptionIds.compactMap { optionId in
                step.options.first(where: { $0.id == optionId })
            }
            for option in selectedOptions {
                if let nodeId = option.nodeId ?? (!option.internalTag.isEmpty ? option.internalTag : nil),
                   !derivedNodeIds.contains(nodeId) {
                    derivedNodeIds.append(nodeId)
                }
                if !derivedNodeLabels.contains(option.title) {
                    derivedNodeLabels.append(option.title)
                }
                if !derivedEvidenceTypes.contains(option.evidenceType) {
                    derivedEvidenceTypes.append(option.evidenceType)
                }
            }
        }

        let primaryStuckPoint = reviewPath.first(where: { $0.status == .failed })?.stepId
            ?? reviewPath.first(where: { $0.status == .partial })?.stepId

        let firstApproach = session.answers.first?.selectedOptionIds.first
            ?? schema.steps.first?.options.first?.id

        return AnalysisPostSolveReview(
            subject: ReviewSchemaRegistry.analysisSubjectType(for: session.subject),
            confidenceAfter: Int((session.problemMatch?.confidence ?? 0.5) * 100),
            firstApproach: firstApproach,
            reviewPath: reviewPath,
            primaryStuckPoint: primaryStuckPoint,
            lassoSelectedPointIds: [session.selection.id.uuidString],
            derivedNodeIds: derivedNodeIds.isEmpty ? nil : derivedNodeIds,
            derivedNodeLabels: derivedNodeLabels.isEmpty ? nil : derivedNodeLabels,
            derivedEvidenceTypes: derivedEvidenceTypes.isEmpty ? nil : derivedEvidenceTypes,
            freeMemo: nil,
            analyzedAt: session.completedAt ?? session.updatedAt
        )
    }
}
