import Foundation

struct PharDocument: Identifiable, Codable, Hashable {
    enum DocumentType: String, Codable, CaseIterable {
        case blankNote
        case pdf
    }

    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var type: DocumentType
    var path: String
}
