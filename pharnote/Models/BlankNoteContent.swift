import Foundation
import SwiftUI
import UIKit

nonisolated enum BlankNotePaperSize: String, Codable, CaseIterable, Hashable, Sendable {
    case a5
    case b5
    case a4
    case b4
    case letter
    case wide

    var title: String {
        switch self {
        case .a5: return "A5"
        case .b5: return "B5"
        case .a4: return "A4"
        case .b4: return "B4"
        case .letter: return "Letter"
        case .wide: return "Wide"
        }
    }

    var subtitle: String {
        switch self {
        case .a5: return "148 × 210"
        case .b5: return "182 × 257"
        case .a4: return "210 × 297"
        case .b4: return "257 × 364"
        case .letter: return "216 × 279"
        case .wide: return "16:10"
        }
    }

    var aspectRatio: CGFloat {
        switch self {
        case .a5: return 210.0 / 148.0
        case .b5: return 257.0 / 182.0
        case .a4: return 297.0 / 210.0
        case .b4: return 364.0 / 257.0
        case .letter: return 279.0 / 216.0
        case .wide: return 1.25
        }
    }
}

nonisolated enum BlankNoteBackgroundStyle: String, Codable, CaseIterable, Hashable, Sendable {
    case plain
    case ruled
    case grid
    case dotGrid

    var title: String {
        switch self {
        case .plain: return "화이트"
        case .ruled: return "가로줄"
        case .grid: return "격자"
        case .dotGrid: return "도트"
        }
    }

    var subtitle: String {
        switch self {
        case .plain: return "무지"
        case .ruled: return "공책 줄"
        case .grid: return "수학/필기"
        case .dotGrid: return "미니멀"
        }
    }

    var surfaceColor: Color {
        switch self {
        case .plain: return Color(.sRGB, red: 0.996, green: 0.994, blue: 0.985, opacity: 1)
        case .ruled: return Color(.sRGB, red: 0.996, green: 0.993, blue: 0.982, opacity: 1)
        case .grid: return Color(.sRGB, red: 0.994, green: 0.992, blue: 0.984, opacity: 1)
        case .dotGrid: return Color(.sRGB, red: 0.994, green: 0.992, blue: 0.986, opacity: 1)
        }
    }

    var patternColor: Color {
        switch self {
        case .plain: return Color.clear
        case .ruled: return Color.black.opacity(0.065)
        case .grid: return Color.black.opacity(0.058)
        case .dotGrid: return Color.black.opacity(0.055)
        }
    }

    var patternOpacity: Double {
        switch self {
        case .plain: return 0
        case .ruled: return 1
        case .grid: return 1
        case .dotGrid: return 1
        }
    }
}

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
    var richTextData: Data?

    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case x
        case y
        case fontSize
        case fontWeight
        case isItalic
        case fontName
        case alignment
        case colorHex
        case richTextData
    }
    
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
        self.richTextData = nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        fontSize = try container.decode(Double.self, forKey: .fontSize)
        fontWeight = try container.decode(String.self, forKey: .fontWeight)
        isItalic = try container.decode(Bool.self, forKey: .isItalic)
        fontName = try container.decodeIfPresent(String.self, forKey: .fontName)
        alignment = try container.decode(String.self, forKey: .alignment)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        richTextData = try container.decodeIfPresent(Data.self, forKey: .richTextData)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(fontWeight, forKey: .fontWeight)
        try container.encode(isItalic, forKey: .isItalic)
        try container.encodeIfPresent(fontName, forKey: .fontName)
        try container.encode(alignment, forKey: .alignment)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encodeIfPresent(richTextData, forKey: .richTextData)
    }
}

extension PharTextElement {
    var plainText: String {
        text
    }

    func attributedString() -> NSAttributedString {
        if let richTextData,
           let stored = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: richTextData) {
            return stored
        }

        return NSAttributedString(string: text, attributes: defaultTextAttributes())
    }

    mutating func storeAttributedString(_ attributedString: NSAttributedString) {
        text = attributedString.string
        richTextData = try? NSKeyedArchiver.archivedData(
            withRootObject: attributedString,
            requiringSecureCoding: false
        )
    }

    func makeUIFont(
        size: Double? = nil,
        weight: String? = nil,
        italic: Bool? = nil,
        fontName: String? = nil
    ) -> UIFont {
        let resolvedSize = CGFloat(size ?? fontSize)
        let resolvedWeight = Self.uiFontWeight(from: weight ?? fontWeight)
        let resolvedFontName = fontName ?? self.fontName

        let baseFont: UIFont
        if let customName = resolvedFontName,
           !customName.isEmpty,
           let customFont = UIFont(name: customName, size: resolvedSize) {
            baseFont = customFont
        } else {
            switch resolvedFontName {
            case "monospaced":
                baseFont = UIFont.monospacedSystemFont(ofSize: resolvedSize, weight: resolvedWeight)
            case "serif":
                let descriptor = UIFont.systemFont(ofSize: resolvedSize, weight: resolvedWeight).fontDescriptor
                baseFont = descriptor.withDesign(.serif)
                    .map { UIFont(descriptor: $0, size: resolvedSize) }
                    ?? UIFont.systemFont(ofSize: resolvedSize, weight: resolvedWeight)
            case "rounded":
                let descriptor = UIFont.systemFont(ofSize: resolvedSize, weight: resolvedWeight).fontDescriptor
                baseFont = descriptor.withDesign(.rounded)
                    .map { UIFont(descriptor: $0, size: resolvedSize) }
                    ?? UIFont.systemFont(ofSize: resolvedSize, weight: resolvedWeight)
            default:
                baseFont = UIFont.systemFont(ofSize: resolvedSize, weight: resolvedWeight)
            }
        }

        guard italic ?? isItalic else { return baseFont }
        let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitItalic)
        return descriptor.map { UIFont(descriptor: $0, size: resolvedSize) } ?? baseFont
    }

    func defaultTextAttributes() -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignmentFromString(alignment)
        paragraphStyle.lineBreakMode = .byWordWrapping
        return [
            .font: makeUIFont(),
            .foregroundColor: UIColor(Color(hex: colorHex) ?? .black),
            .paragraphStyle: paragraphStyle
        ]
    }

    func applyingBaseStyle(to attributedString: NSMutableAttributedString) {
        guard attributedString.length > 0 else { return }
        let wholeRange = NSRange(location: 0, length: attributedString.length)
        attributedString.addAttributes(defaultTextAttributes(), range: wholeRange)
    }

    private func alignmentFromString(_ alignment: String) -> NSTextAlignment {
        switch alignment {
        case "center":
            return .center
        case "right":
            return .right
        default:
            return .left
        }
    }

    private static func uiFontWeight(from rawValue: String) -> UIFont.Weight {
        switch rawValue {
        case "bold":
            return .bold
        case "semibold":
            return .semibold
        case "medium":
            return .medium
        case "light":
            return .light
        default:
            return .regular
        }
    }
}

struct BlankNotePage: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    var updatedAt: Date
    var textElements: [PharTextElement]
    var paperSize: BlankNotePaperSize
    var backgroundStyle: BlankNoteBackgroundStyle

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case textElements
        case paperSize
        case backgroundStyle
    }

    nonisolated init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        textElements: [PharTextElement] = [],
        paperSize: BlankNotePaperSize = .a4,
        backgroundStyle: BlankNoteBackgroundStyle = .plain
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.textElements = textElements
        self.paperSize = paperSize
        self.backgroundStyle = backgroundStyle
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        textElements = try container.decodeIfPresent([PharTextElement].self, forKey: .textElements) ?? []
        paperSize = try container.decodeIfPresent(BlankNotePaperSize.self, forKey: .paperSize) ?? .a4
        backgroundStyle = try container.decodeIfPresent(BlankNoteBackgroundStyle.self, forKey: .backgroundStyle) ?? .plain
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(textElements, forKey: .textElements)
        try container.encode(paperSize, forKey: .paperSize)
        try container.encode(backgroundStyle, forKey: .backgroundStyle)
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
            version: 5,
            pages: [
                BlankNotePage(id: UUID(), createdAt: now, updatedAt: now, textElements: [])
            ]
        )
    }
}
