import Foundation
import Combine

@MainActor
final class SearchInfrastructure: ObservableObject {
    static let shared = SearchInfrastructure()

    private let handwritingPipeline: HandwritingIndexingPipeline
    private let handwritingStore: HandwritingSearchStore

    init(
        handwritingPipeline: HandwritingIndexingPipeline = HandwritingIndexingPipeline(),
        handwritingStore: HandwritingSearchStore = HandwritingSearchStore()
    ) {
        self.handwritingPipeline = handwritingPipeline
        self.handwritingStore = handwritingStore
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

    func searchHandwriting(query: String, limit: Int = 20) async -> [HandwritingSearchHit] {
        (try? await handwritingStore.search(query: query, limit: limit)) ?? []
    }
}
