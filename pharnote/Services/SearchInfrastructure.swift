import Foundation
import Combine

@MainActor
final class SearchInfrastructure: ObservableObject {
    private let handwritingPipeline: HandwritingIndexingPipeline

    init(handwritingPipeline: HandwritingIndexingPipeline = HandwritingIndexingPipeline()) {
        self.handwritingPipeline = handwritingPipeline
    }

    func start() {
        Task {
            await handwritingPipeline.startIfNeeded()
        }
    }

    func stop() {
        Task {
            await handwritingPipeline.stop()
        }
    }

    func enqueueHandwritingIndexJob(documentID: UUID, pageKey: String) {
        Task {
            await handwritingPipeline.enqueue(documentID: documentID, pageKey: pageKey)
        }
    }
}
