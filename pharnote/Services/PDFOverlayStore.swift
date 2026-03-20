import Foundation
import SwiftUI
import UIKit

struct PDFTextAnnotation: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var pageId: UUID
    var pageIndex: Int
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var text: String
    var fontFamily: String?
    var fontSize: Double
    var fontWeight: String
    var fontStyle: String
    var textColor: String
    var textAlignment: String
    var createdAt: Date
    var updatedAt: Date
    var isSelected: Bool = false
    var isEditing: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, pageId, pageIndex, x, y, width, height, text, fontFamily, fontSize, fontWeight, fontStyle, textColor, textAlignment, createdAt, updatedAt
    }

    init(
        id: UUID = UUID(),
        pageId: UUID,
        pageIndex: Int,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        text: String = "",
        fontFamily: String? = nil,
        fontSize: Double = 20,
        fontWeight: String = "regular",
        fontStyle: String = "normal",
        textColor: String = "#000000",
        textAlignment: String = "left",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isSelected: Bool = false,
        isEditing: Bool = false
    ) {
        self.id = id
        self.pageId = pageId
        self.pageIndex = pageIndex
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.text = text
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.fontStyle = fontStyle
        self.textColor = textColor
        self.textAlignment = textAlignment
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isSelected = isSelected
        self.isEditing = isEditing
    }

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isEmpty: Bool {
        trimmedText.isEmpty
    }

    func resolvedFont() -> UIFont {
        let size = CGFloat(fontSize)
        let weight: UIFont.Weight
        switch fontWeight {
        case "bold":
            weight = .bold
        case "semibold":
            weight = .semibold
        case "medium":
            weight = .medium
        case "light":
            weight = .light
        default:
            weight = .regular
        }

        let baseFont: UIFont
        switch fontFamily {
        case "rounded":
            baseFont = UIFont.systemFont(ofSize: size, weight: weight).roundedFontFallback()
        case "serif":
            let descriptor = UIFont.systemFont(ofSize: size, weight: weight).fontDescriptor
            baseFont = descriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? UIFont.systemFont(ofSize: size, weight: weight)
        case "monospaced":
            baseFont = UIFont.monospacedSystemFont(ofSize: size, weight: weight)
        default:
            baseFont = UIFont.systemFont(ofSize: size, weight: weight)
        }

        if fontStyle == "italic" {
            let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitItalic)
            return descriptor.map { UIFont(descriptor: $0, size: size) } ?? baseFont
        }

        return baseFont
    }

    func paragraphAlignment() -> NSTextAlignment {
        switch textAlignment {
        case "center":
            return .center
        case "right":
            return .right
        default:
            return .left
        }
    }

    func textAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = paragraphAlignment()
        paragraph.lineBreakMode = .byWordWrapping
        return [
            .font: resolvedFont(),
            .foregroundColor: UIColor(Color(hex: textColor) ?? .black),
            .paragraphStyle: paragraph
        ]
    }
}

private extension UIFont {
    func roundedFontFallback() -> UIFont {
        let descriptor = fontDescriptor.withDesign(.rounded)
        return descriptor.map { UIFont(descriptor: $0, size: pointSize) } ?? self
    }
}

actor PDFOverlayStore {
    private let fileManager = FileManager.default
    private let overlaysDirectoryName = "PDFOverlayDrawings"

    func loadDrawingData(documentURL: URL, pageIndex: Int) -> Data? {
        let fileURL = drawingFileURL(documentURL: documentURL, pageIndex: pageIndex)
        return try? Data(contentsOf: fileURL)
    }

    func saveDrawingData(_ data: Data, documentURL: URL, pageIndex: Int) throws {
        let directoryURL = overlaysDirectoryURL(documentURL: documentURL)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = drawingFileURL(documentURL: documentURL, pageIndex: pageIndex)
        try data.write(to: fileURL, options: .atomic)
    }

    private func overlaysDirectoryURL(documentURL: URL) -> URL {
        documentURL.appendingPathComponent(overlaysDirectoryName, isDirectory: true)
    }

    private func drawingFileURL(documentURL: URL, pageIndex: Int) -> URL {
        overlaysDirectoryURL(documentURL: documentURL)
            .appendingPathComponent(String(format: "page-%04d.drawing", pageIndex), isDirectory: false)
    }
}

actor PDFTextAnnotationStore {
    private let fileManager = FileManager.default
    private let annotationsDirectoryName = "PDFTextAnnotations"

    private lazy var decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private lazy var encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    func loadAnnotations(documentURL: URL, pageIndex: Int) -> [PDFTextAnnotation] {
        let fileURL = annotationFileURL(documentURL: documentURL, pageIndex: pageIndex)
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        if let payload = try? decoder.decode(PDFTextAnnotationPagePayload.self, from: data) {
            return payload.annotations
        }
        return []
    }

    func saveAnnotations(_ annotations: [PDFTextAnnotation], documentURL: URL, pageIndex: Int) throws {
        let directoryURL = annotationsDirectoryURL(documentURL: documentURL)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let payload = PDFTextAnnotationPagePayload(pageIndex: pageIndex, annotations: annotations)
        let data = try encoder.encode(payload)
        try data.write(to: annotationFileURL(documentURL: documentURL, pageIndex: pageIndex), options: .atomic)
    }

    private func annotationsDirectoryURL(documentURL: URL) -> URL {
        documentURL.appendingPathComponent(annotationsDirectoryName, isDirectory: true)
    }

    private func annotationFileURL(documentURL: URL, pageIndex: Int) -> URL {
        annotationsDirectoryURL(documentURL: documentURL)
            .appendingPathComponent(String(format: "page-%04d.json", pageIndex), isDirectory: false)
    }

    private struct PDFTextAnnotationPagePayload: Codable {
        let pageIndex: Int
        let annotations: [PDFTextAnnotation]
    }
}
