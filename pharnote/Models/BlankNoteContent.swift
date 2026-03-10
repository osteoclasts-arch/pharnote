import Foundation

struct BlankNotePage: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
    }

    nonisolated init(id: UUID, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

struct BlankNoteContent: Codable, Sendable {
    var version: Int
    var pages: [BlankNotePage]

    enum CodingKeys: String, CodingKey {
        case version
        case pages
    }

    nonisolated init(version: Int, pages: [BlankNotePage]) {
        self.version = version
        self.pages = pages
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        pages = try container.decode([BlankNotePage].self, forKey: .pages)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(pages, forKey: .pages)
    }

    nonisolated static func initial(now: Date = Date()) -> BlankNoteContent {
        BlankNoteContent(
            version: 2,
            pages: [
                BlankNotePage(id: UUID(), createdAt: now, updatedAt: now)
            ]
        )
    }
}
