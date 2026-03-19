import Foundation
import PencilKit

struct HighlightStructureEngine {
    func captureItem(
        documentID: UUID,
        pageKey: String,
        pageLabel: String,
        mode: HighlightStructureMode,
        role: HighlightStructureRole,
        colorHex: String,
        stroke: PKStroke,
        referenceText: String? = nil
    ) -> HighlightStructureItem {
        let inferredText = referenceText
            .flatMap { Self.bestPreview(from: $0) }
            ?? role.subtitle

        return HighlightStructureItem(
            documentID: documentID,
            pageKey: pageKey,
            pageLabel: pageLabel,
            mode: mode,
            role: role,
            colorHex: colorHex,
            strokeFingerprint: HighlightStrokeFingerprint.make(from: stroke),
            bounds: HighlightStructureBounds(rect: stroke.renderBounds),
            inferredText: inferredText,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func syncItems(
        currentItems: [HighlightStructureItem],
        drawing: PKDrawing
    ) -> [HighlightStructureItem] {
        let currentFingerprints = Set(drawing.strokes.map { HighlightStrokeFingerprint.make(from: $0) })
        let filtered = currentItems.filter { currentFingerprints.contains($0.strokeFingerprint) }
        return filtered.sorted(by: sortItems(_:_:))
    }

    func buildSnapshot(
        pageKey: String,
        pageLabel: String,
        items: [HighlightStructureItem],
        referenceText: String?,
        generatedAt: Date = Date()
    ) -> HighlightStructureSnapshot {
        let grouped = Dictionary(grouping: items) { $0.role }
        let roleSummaries = HighlightStructureRole.allCases.map { role in
            let count = grouped[role]?.count ?? 0
            return HighlightStructureRoleSummary(
                role: role,
                count: count,
                colorHex: grouped[role]?.first?.colorHex ?? role.defaultColorHex,
                depth: role.depth
            )
        }

        let outlineEntries = roleSummaries.compactMap { summary -> HighlightStructureOutlineEntry? in
            guard summary.count > 0 else { return nil }
            return HighlightStructureOutlineEntry(
                role: summary.role,
                title: summary.role.title,
                subtitle: "\(summary.count)개 · \(summary.role.subtitle)",
                colorHex: summary.colorHex,
                depth: summary.depth,
                count: summary.count,
                previewText: grouped[summary.role]?.first?.inferredText
            )
        }

        let summaryBullets = Self.summaryBullets(
            referenceText: referenceText,
            items: items,
            pageLabel: pageLabel
        )

        let summaryLine: String
        if items.isEmpty {
            summaryLine = "아직 구조화된 하이라이트가 없습니다. 역할을 지정하면 자동 아웃라인이 만들어집니다."
        } else if let firstBullet = summaryBullets.first {
            summaryLine = "\(pageLabel) 구조 요약: \(firstBullet)"
        } else {
            summaryLine = "\(pageLabel)에서 \(items.count)개의 구조화 하이라이트를 묶었습니다."
        }

        return HighlightStructureSnapshot(
            pageKey: pageKey,
            pageLabel: pageLabel,
            totalCount: items.count,
            summaryLine: summaryLine,
            summaryBullets: summaryBullets,
            roleSummaries: roleSummaries,
            outlineEntries: outlineEntries,
            generatedAt: generatedAt
        )
    }

    static func summaryBullets(referenceText: String?, items: [HighlightStructureItem], pageLabel: String) -> [String] {
        let normalizedReference: [String]
        if let referenceText {
            var lines: [String] = referenceText
                .replacingOccurrences(of: "\r", with: "\n")
                .split(whereSeparator: { $0.isNewline })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { String($0) }
            if lines.count > 4 {
                lines.removeSubrange(4..<lines.count)
            }
            normalizedReference = lines
        } else {
            normalizedReference = []
        }

        if !normalizedReference.isEmpty {
            return Array(normalizedReference.prefix(3))
        }

        guard !items.isEmpty else {
            return []
        }

        let grouped = Dictionary(grouping: items) { $0.role }
        return HighlightStructureRole.allCases.compactMap { role in
            guard let count = grouped[role]?.count, count > 0 else { return nil }
            return "\(role.title) \(count)개"
        }
    }

    static func bestPreview(from text: String, maxLength: Int = 28) -> String? {
        let normalized = text
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let first = normalized.first else { return nil }
        if first.count <= maxLength {
            return first
        }
        return String(first.prefix(maxLength)) + "..."
    }

    private func sortItems(_ lhs: HighlightStructureItem, _ rhs: HighlightStructureItem) -> Bool {
        if lhs.role.order != rhs.role.order {
            return lhs.role.order < rhs.role.order
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
