import Foundation
import SwiftUI

struct PharTextElement: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var text: String
    var x: Double
    var y: Double
    var fontSize: Double
    var fontWeight: String // "regular", "bold", "semibold", "medium"
    var isItalic: Bool
    var fontName: String?
    var alignment: String // "left", "center", "right"
    var colorHex: String
    
    init(
        id: UUID = UUID(),
        text: String = "",
        x: Double = 100,
        y: Double = 100,
        fontSize: Double = 18,
        fontWeight: String = "regular",
        isItalic: Bool = false,
        fontName: String? = nil,
        alignment: String = "left",
        colorHex: String = "#000000"
    ) {
        self.id = id
        self.text = text
        self.x = x
        self.y = y
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.isItalic = isItalic
        self.fontName = fontName
        self.alignment = alignment
        self.colorHex = colorHex
    }
}

struct BlankNotePage: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    var updatedAt: Date
    var textElements: [PharTextElement]

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case textElements
    }

    nonisolated init(id: UUID, createdAt: Date, updatedAt: Date, textElements: [PharTextElement] = []) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.textElements = textElements
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        textElements = try container.decodeIfPresent([PharTextElement].self, forKey: .textElements) ?? []
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(textElements, forKey: .textElements)
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
            version: 3,
            pages: [
                BlankNotePage(id: UUID(), createdAt: now, updatedAt: now, textElements: [])
            ]
        )
    }
}
