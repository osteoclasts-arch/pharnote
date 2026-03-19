import CryptoKit
import Foundation
import PencilKit
import SwiftUI
import UIKit

nonisolated enum HighlightStructureMode: String, Codable, CaseIterable, Hashable, Sendable {
    case basic
    case structured

    var title: String {
        switch self {
        case .basic:
            return "기본"
        case .structured:
            return "구조화"
        }
    }

    var subtitle: String {
        switch self {
        case .basic:
            return "가볍게 표시"
        case .structured:
            return "역할 기반 구조"
        }
    }
}

nonisolated enum HighlightStructureRole: String, Codable, CaseIterable, Hashable, Sendable {
    case core
    case support
    case example
    case question

    var title: String {
        switch self {
        case .core:
            return "핵심"
        case .support:
            return "근거"
        case .example:
            return "예시"
        case .question:
            return "질문"
        }
    }

    var subtitle: String {
        switch self {
        case .core:
            return "중심 주장과 개념"
        case .support:
            return "설명과 근거"
        case .example:
            return "적용과 사례"
        case .question:
            return "헷갈리는 지점"
        }
    }

    var symbolName: String {
        switch self {
        case .core:
            return "star.fill"
        case .support:
            return "quote.bubble.fill"
        case .example:
            return "lightbulb.fill"
        case .question:
            return "questionmark.circle.fill"
        }
    }

    var defaultColorHex: String {
        switch self {
        case .core:
            return "#F2C94C"
        case .support:
            return "#4C7CF0"
        case .example:
            return "#31B67A"
        case .question:
            return "#E58DC1"
        }
    }

    var order: Int {
        switch self {
        case .core:
            return 0
        case .support:
            return 1
        case .example:
            return 2
        case .question:
            return 3
        }
    }

    var depth: Int {
        switch self {
        case .core:
            return 0
        case .support, .question:
            return 1
        case .example:
            return 2
        }
    }

    var parentRole: HighlightStructureRole? {
        switch self {
        case .core:
            return nil
        case .support:
            return .core
        case .example:
            return .support
        case .question:
            return .core
        }
    }
}

nonisolated struct HighlightStructureColorPreset: Codable, Hashable, Sendable {
    var role: HighlightStructureRole
    var colorHex: String
}

nonisolated struct HighlightStructureBounds: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(rect: CGRect) {
        self.x = Double(rect.origin.x)
        self.y = Double(rect.origin.y)
        self.width = Double(rect.size.width)
        self.height = Double(rect.size.height)
    }

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

nonisolated struct HighlightStructureItem: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var documentID: UUID
    var pageKey: String
    var pageLabel: String
    var mode: HighlightStructureMode
    var role: HighlightStructureRole
    var colorHex: String
    var strokeFingerprint: String
    var bounds: HighlightStructureBounds?
    var inferredText: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        documentID: UUID,
        pageKey: String,
        pageLabel: String,
        mode: HighlightStructureMode,
        role: HighlightStructureRole,
        colorHex: String,
        strokeFingerprint: String,
        bounds: HighlightStructureBounds? = nil,
        inferredText: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.documentID = documentID
        self.pageKey = pageKey
        self.pageLabel = pageLabel
        self.mode = mode
        self.role = role
        self.colorHex = colorHex
        self.strokeFingerprint = strokeFingerprint
        self.bounds = bounds
        self.inferredText = inferredText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated struct HighlightStructureRoleSummary: Identifiable, Codable, Hashable, Sendable {
    var role: HighlightStructureRole
    var count: Int
    var colorHex: String
    var depth: Int

    var id: String { role.rawValue }
}

nonisolated struct HighlightStructureOutlineEntry: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var role: HighlightStructureRole
    var title: String
    var subtitle: String
    var colorHex: String
    var depth: Int
    var count: Int
    var previewText: String?

    init(
        id: UUID = UUID(),
        role: HighlightStructureRole,
        title: String,
        subtitle: String,
        colorHex: String,
        depth: Int,
        count: Int,
        previewText: String? = nil
    ) {
        self.id = id
        self.role = role
        self.title = title
        self.subtitle = subtitle
        self.colorHex = colorHex
        self.depth = depth
        self.count = count
        self.previewText = previewText
    }
}

nonisolated struct HighlightStructureSnapshot: Codable, Hashable, Sendable {
    var pageKey: String
    var pageLabel: String
    var totalCount: Int
    var summaryLine: String
    var summaryBullets: [String]
    var roleSummaries: [HighlightStructureRoleSummary]
    var outlineEntries: [HighlightStructureOutlineEntry]
    var generatedAt: Date

    var isEmpty: Bool {
        totalCount == 0
    }
}

nonisolated enum HighlightColorCodec {
    static func hexString(from color: UIColor) -> String {
        let resolved = color.resolvedColor(with: UITraitCollection.current)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    static func uiColor(from hexString: String, fallback: UIColor = .systemYellow) -> UIColor {
        let trimmed = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        guard trimmed.count == 6, let rgb = UInt32(trimmed, radix: 16) else {
            return fallback
        }

        let red = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let green = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let blue = CGFloat(rgb & 0xFF) / 255.0
        return UIColor(red: red, green: green, blue: blue, alpha: 1.0)
    }
}

nonisolated enum HighlightStrokeFingerprint {
    static func make(from stroke: PKStroke) -> String {
        let inkType = String(describing: stroke.ink.inkType)
        let colorHex = HighlightColorCodec.hexString(from: stroke.ink.color)
        let bounds = stroke.renderBounds
        let boundsKey = String(
            format: "%.2f:%.2f:%.2f:%.2f",
            bounds.origin.x,
            bounds.origin.y,
            bounds.size.width,
            bounds.size.height
        )
        let controlPoints = stroke.path.map { point in
            String(
                format: "%.1f,%.1f,%.2f,%.2f",
                point.location.x,
                point.location.y,
                point.force,
                point.opacity
            )
        }
        let raw = [inkType, colorHex, boundsKey, "\(stroke.path.count)", controlPoints.joined(separator: "|")].joined(separator: "::")
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
