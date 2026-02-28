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
    static let rootDirectoryName = "SearchIndexes"
    static let metadataDirectoryName = "Metadata"
    static let payloadDirectoryName = "Payloads"
    static let handwritingPayloadDirectoryName = "Handwriting"

    static let jobsFileName = "handwriting_jobs.json"
    static let recordsFileName = "handwriting_records.json"
}
