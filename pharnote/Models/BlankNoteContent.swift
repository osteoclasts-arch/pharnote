import Foundation

struct BlankNotePage: Identifiable, Codable, Hashable {
    let id: UUID
    let createdAt: Date
    var updatedAt: Date
}

struct BlankNoteContent: Codable {
    var version: Int
    var pages: [BlankNotePage]

    static func initial(now: Date = Date()) -> BlankNoteContent {
        BlankNoteContent(
            version: 2,
            pages: [
                BlankNotePage(id: UUID(), createdAt: now, updatedAt: now)
            ]
        )
    }
}
