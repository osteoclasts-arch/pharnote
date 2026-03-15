import Foundation

actor HandwritingIndexingPipeline {
    private let store: HandwritingSearchStore
    private let ocrService: DocumentOCRService
    private var workerTask: Task<Void, Never>?
    private var isRunning = false

    init(
        store: HandwritingSearchStore = HandwritingSearchStore(),
        ocrService: DocumentOCRService = DocumentOCRService()
    ) {
        self.store = store
        self.ocrService = ocrService
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
            var jobs = try await store.loadJobs()
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
                note: "OCR queued."
            )
            jobs.append(job)
            try await store.saveJobs(jobs)
        } catch {
            // Search indexing bootstrap 단계에서는 파이프라인 실패를 사용자 플로우에 전파하지 않음.
        }
    }

    private func processOneJobIfNeeded() async {
        do {
            var jobs = try await store.loadJobs()
            guard let nextIndex = jobs.firstIndex(where: { $0.status == .queued }) else { return }

            jobs[nextIndex].status = .processing
            jobs[nextIndex].updatedAt = Date()
            try await store.saveJobs(jobs)

            let documents = try await LibraryStore().loadIndex()
            guard let document = documents.first(where: { $0.id == jobs[nextIndex].documentID }) else {
                jobs[nextIndex].status = .failed
                jobs[nextIndex].updatedAt = Date()
                jobs[nextIndex].note = "Document not found."
                try await store.saveJobs(jobs)
                return
            }

            guard let recognizedText = await ocrService.recognizeIndexedText(document: document, pageKey: jobs[nextIndex].pageKey),
                  !recognizedText.isEmpty else {
                jobs[nextIndex].status = .failed
                jobs[nextIndex].updatedAt = Date()
                jobs[nextIndex].note = "No OCR text detected."
                try await store.saveJobs(jobs)
                return
            }

            let payloadPath = try await store.saveHandwritingTextPayload(recognizedText, job: jobs[nextIndex])
            var records = try await store.loadRecords()
            records.removeAll {
                $0.documentID == jobs[nextIndex].documentID && $0.pageKey == jobs[nextIndex].pageKey
            }
            records.append(
                HandwritingIndexRecord(
                    id: UUID(),
                    documentID: jobs[nextIndex].documentID,
                    pageKey: jobs[nextIndex].pageKey,
                    indexedAt: Date(),
                    textPayloadPath: payloadPath,
                    engineVersion: DocumentOCRService.engineVersion
                )
            )
            try await store.saveRecords(records)

            jobs[nextIndex].status = .completed
            jobs[nextIndex].updatedAt = Date()
            jobs[nextIndex].note = "OCR indexed."
            try await store.saveJobs(jobs)
        } catch {
            do {
                var jobs = try await store.loadJobs()
                if let index = jobs.firstIndex(where: { $0.status == .processing }) {
                    jobs[index].status = .failed
                    jobs[index].updatedAt = Date()
                    jobs[index].note = error.localizedDescription
                    try await store.saveJobs(jobs)
                }
            } catch {
                // Indexing failure is persisted on best effort only.
            }
        }
    }
}
