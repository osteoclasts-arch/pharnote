import Foundation

actor HandwritingIndexingPipeline {
    private let store: HandwritingSearchStore
    private var workerTask: Task<Void, Never>?
    private var isRunning = false

    init(store: HandwritingSearchStore = HandwritingSearchStore()) {
        self.store = store
    }

    func startIfNeeded() {
        guard !isRunning else { return }
        isRunning = true

        workerTask = Task(priority: .utility) { [weak self] in
            while let self, !Task.isCancelled {
                await self.processOneJobIfNeeded()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        workerTask?.cancel()
        workerTask = nil
        isRunning = false
    }

    func enqueue(documentID: UUID, pageKey: String) async {
        do {
            var jobs = try store.loadJobs()
            let alreadyQueued = jobs.contains {
                $0.documentID == documentID && $0.pageKey == pageKey &&
                ($0.status == .queued || $0.status == .processing || $0.status == .pendingOCR)
            }
            guard !alreadyQueued else { return }

            let now = Date()
            let job = HandwritingIndexJob(
                id: UUID(),
                documentID: documentID,
                pageKey: pageKey,
                createdAt: now,
                updatedAt: now,
                status: .queued,
                note: "OCR connector not configured yet."
            )
            jobs.append(job)
            try store.saveJobs(jobs)
        } catch {
            // Search indexing bootstrap 단계에서는 파이프라인 실패를 사용자 플로우에 전파하지 않음.
        }
    }

    private func processOneJobIfNeeded() async {
        do {
            var jobs = try store.loadJobs()
            guard let nextIndex = jobs.firstIndex(where: { $0.status == .queued }) else { return }

            jobs[nextIndex].status = .processing
            jobs[nextIndex].updatedAt = Date()
            try store.saveJobs(jobs)

            // 단계 7: OCR 엔진 미연동 상태. 배경 작업 파이프라인/스토리지만 먼저 구성.
            jobs[nextIndex].status = .pendingOCR
            jobs[nextIndex].updatedAt = Date()
            jobs[nextIndex].note = "OCR engine integration is planned for a later stage."
            try store.saveJobs(jobs)
        } catch {
            // Retry 가능한 백그라운드 잡이므로 오류는 저장하지 않고 다음 주기 재시도.
        }
    }
}
