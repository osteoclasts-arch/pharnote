import Foundation

enum HandwritingIndexJobStatus: String, Codable {
    case queued
    case processing
    case pendingOCR
    case failed
    case completed
}

struct HandwritingIndexJob: Identifiable, Codable {
    let id: UUID
    let documentID: UUID
    let pageKey: String
    let createdAt: Date
    var updatedAt: Date
    var status: HandwritingIndexJobStatus
    var note: String?
}

struct HandwritingIndexRecord: Identifiable, Codable {
    let id: UUID
    let documentID: UUID
    let pageKey: String
    let indexedAt: Date
    let textPayloadPath: String
    let engineVersion: String
}

struct SearchIndexStorageLayout {
    nonisolated static let rootDirectoryName = "SearchIndexes"
    nonisolated static let metadataDirectoryName = "Metadata"
    nonisolated static let payloadDirectoryName = "Payloads"
    nonisolated static let handwritingPayloadDirectoryName = "Handwriting"

    nonisolated static let jobsFileName = "handwriting_jobs.json"
    nonisolated static let recordsFileName = "handwriting_records.json"
}
