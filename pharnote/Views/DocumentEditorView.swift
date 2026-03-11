import SwiftUI
import UIKit

struct DocumentEditorLaunchTarget: Hashable {
    let document: PharDocument
    let initialPageKey: String?
}

struct DocumentEditorView: View {
    let document: PharDocument
    let initialPageKey: String?

    init(document: PharDocument, initialPageKey: String? = nil) {
        self.document = document
        self.initialPageKey = initialPageKey
    }

    var body: some View {
        switch document.type {
        case .blankNote:
            BlankNoteEditorView(document: document, initialPageKey: initialPageKey)
        case .pdf:
            PDFDocumentEditorView(document: document, initialPageKey: initialPageKey)
        }
    }
}

struct WritingWorkspaceDocumentChip: Identifiable, Hashable {
    let id: UUID
    let title: String
    let isCurrent: Bool

    static func makeChips(currentDocument: PharDocument, limit: Int = 4) -> [WritingWorkspaceDocumentChip] {
        let recentDocuments = (try? LibraryStore().loadIndex())
            .map { documents in
                documents.sorted { lhs, rhs in
                    if lhs.updatedAt == rhs.updatedAt {
                        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                    }
                    return lhs.updatedAt > rhs.updatedAt
                }
            } ?? []

        var chips: [WritingWorkspaceDocumentChip] = [
            WritingWorkspaceDocumentChip(
                id: currentDocument.id,
                title: currentDocument.title,
                isCurrent: true
            )
        ]

        for document in recentDocuments where document.id != currentDocument.id {
            chips.append(
                WritingWorkspaceDocumentChip(
                    id: document.id,
                    title: document.title,
                    isCurrent: false
                )
            )

            if chips.count == limit {
                break
            }
        }

        return chips
    }
}

enum WritingChromePalette {
    static let accent = Color(.sRGB, red: 1.0, green: 0.439, blue: 0.0, opacity: 1.0)
    static let ink = Color(.sRGB, red: 0.117, green: 0.156, blue: 0.262, opacity: 1.0)
    static let paper = Color(.sRGB, red: 0.965, green: 0.963, blue: 0.938, opacity: 1.0)
    static let chip = Color(.sRGB, red: 0.928, green: 0.923, blue: 0.847, opacity: 1.0)
    static let chipBorder = Color(.sRGB, red: 0.741, green: 0.733, blue: 0.651, opacity: 1.0)
    static let chromeBorder = Color(.sRGB, red: 0.58, green: 0.565, blue: 0.506, opacity: 1.0)
    static let paletteFill = Color(.sRGB, red: 0.932, green: 0.914, blue: 0.742, opacity: 1.0)
    static let canvas = Color(.sRGB, red: 0.973, green: 0.973, blue: 0.973, opacity: 1.0)
    static let hintFill = Color(.sRGB, red: 0.952, green: 0.698, blue: 0.467, opacity: 1.0)
    static let hintText = Color(.sRGB, red: 0.678, green: 0.384, blue: 0.125, opacity: 1.0)
    static let shadow = Color.black.opacity(0.12)
}

struct WritingChromeCapsule<Content: View>: View {
    let fill: Color
    let content: Content

    init(fill: Color = .white, @ViewBuilder content: () -> Content) {
        self.fill = fill
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(WritingChromePalette.chromeBorder, lineWidth: 1.2)
            )
    }
}

struct WritingDocumentChipStrip: View {
    let chips: [WritingWorkspaceDocumentChip]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    HStack(spacing: 10) {
                        Text(chip.title)
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundStyle(chip.isCurrent ? Color.white : WritingChromePalette.ink.opacity(0.62))
                            .lineLimit(1)

                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(chip.isCurrent ? Color.white : WritingChromePalette.ink.opacity(0.4))
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 40)
                    .background(
                        Capsule(style: .continuous)
                            .fill(chip.isCurrent ? WritingChromePalette.accent : WritingChromePalette.chip)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(chip.isCurrent ? WritingChromePalette.accent : WritingChromePalette.chipBorder, lineWidth: 1.2)
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }
}

struct WritingChromeIconButton: View {
    let systemName: String
    var accentTint: Bool = false
    var isSelected: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(foregroundColor)
                .frame(width: 36, height: 36)
                .background(
                    Group {
                        if isSelected {
                            Circle()
                                .fill(WritingChromePalette.accent)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
    }

    private var foregroundColor: Color {
        if isSelected {
            return .white
        }
        return accentTint ? WritingChromePalette.accent : WritingChromePalette.ink
    }
}

struct WritingChromePlaceholderIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(WritingChromePalette.ink)
            .frame(width: 36, height: 36)
            .opacity(0.9)
    }
}

struct WritingToolbarDivider: View {
    var body: some View {
        Rectangle()
            .fill(WritingChromePalette.chromeBorder.opacity(0.8))
            .frame(width: 1, height: 28)
    }
}

struct WritingStrokePresetButton: View {
    let width: CGFloat
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(Color.black.opacity(0.12))
                }

                WritingStrokePresetSample(width: width)
                    .foregroundStyle(WritingChromePalette.ink)
            }
            .frame(width: 48, height: 32)
        }
        .buttonStyle(.plain)
    }
}

private struct WritingStrokePresetSample: View {
    let width: CGFloat

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: size.width * 0.15, y: size.height * 0.68))
            path.addCurve(
                to: CGPoint(x: size.width * 0.48, y: size.height * 0.28),
                control1: CGPoint(x: size.width * 0.24, y: size.height * 0.18),
                control2: CGPoint(x: size.width * 0.34, y: size.height * 0.82)
            )
            path.addCurve(
                to: CGPoint(x: size.width * 0.85, y: size.height * 0.62),
                control1: CGPoint(x: size.width * 0.61, y: size.height * 0.06),
                control2: CGPoint(x: size.width * 0.71, y: size.height * 0.9)
            )
            context.stroke(path, with: .color(.primary), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
    }
}

struct WritingColorSwatchButton: View {
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 32, height: 32)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(isSelected ? 0.55 : 0.18), lineWidth: isSelected ? 2.5 : 1.2)
                )
                .background(
                    Circle()
                        .fill(Color.white.opacity(isSelected ? 0.35 : 0))
                        .frame(width: 40, height: 40)
                )
        }
        .buttonStyle(.plain)
    }
}

struct WritingShareFAB: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 74, height: 74)
                .background(
                    Circle()
                        .fill(WritingChromePalette.accent)
                )
                .shadow(color: WritingChromePalette.shadow, radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }
}

struct WritingAnalyzeHintBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(WritingChromePalette.hintText)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(WritingChromePalette.hintFill.opacity(0.9))
            )
    }
}

struct WritingAccentActionButton: View {
    let title: String
    let systemName: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.241, green: 0.147, blue: 0.049))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(WritingChromePalette.hintFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: WritingChromePalette.shadow.opacity(0.8), radius: 6, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
    }
}

struct WritingDocumentShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

enum WritingDocumentShareSource {
    static func activityItems(for document: PharDocument) -> [Any] {
        let packageURL = URL(fileURLWithPath: document.path, isDirectory: true)
        if document.type == .pdf {
            let preferredPDFURL = packageURL.appendingPathComponent("Original.pdf", isDirectory: false)
            if FileManager.default.fileExists(atPath: preferredPDFURL.path) {
                return [preferredPDFURL]
            }
        }
        return [packageURL]
    }
}
