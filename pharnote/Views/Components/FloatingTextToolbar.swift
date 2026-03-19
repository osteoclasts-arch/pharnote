import SwiftUI

struct FloatingTextToolbar: View {
    let element: PharTextElement
    let selectionRange: NSRange?
    let onFontSize: (Double) -> Void
    let onFontWeight: (String) -> Void
    let onItalicToggle: () -> Void
    let onFontName: (String?) -> Void
    let onAlignment: (String) -> Void
    let onColorHex: (String) -> Void
    var onDelete: () -> Void
    
    let fontSizes: [Double] = [12, 14, 16, 18, 20, 24, 28, 32, 40, 48]
    let fontFamilies: [(label: String, value: String?)] = [
        ("기본", nil),
        ("라운드", "rounded"),
        ("세리프", "serif"),
        ("고정폭", "monospaced")
    ]
    let alignments = ["left", "center", "right"]
    let colorOptions: [(label: String, value: String)] = [
        ("검정", "#000000"),
        ("파랑", "#2F6BFF"),
        ("초록", "#39B37C"),
        ("주황", "#F0B64C"),
        ("빨강", "#E45858")
    ]
    
    var body: some View {
        WritingChromeCapsule {
            HStack(spacing: 4) {
                // Font Size
                Menu {
                    ForEach(fontSizes, id: \.self) { size in
                        Button("\(Int(size))pt") {
                            onFontSize(size)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("\(Int(element.fontSize))")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                    }
                    .frame(width: 50, height: 32)
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(8)
                }

                WritingToolbarDivider()

                Menu {
                    ForEach(fontFamilies, id: \.label) { family in
                        Button {
                            onFontName(family.value)
                        } label: {
                            HStack {
                                Text(family.label)
                                if element.fontName == family.value {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(fontLabel(for: element.fontName))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                        Image(systemName: "font")
                            .font(.system(size: 10))
                    }
                    .frame(width: 62, height: 32)
                    .background(Color.black.opacity(0.05))
                    .cornerRadius(8)
                }
                
                WritingToolbarDivider()
                
                // Bold/Italic
                HStack(spacing: 2) {
                    WritingChromeIconButton(
                        systemName: "bold",
                        isSelected: element.fontWeight == "bold"
                    ) {
                        onFontWeight(element.fontWeight == "bold" ? "regular" : "bold")
                    }
                    
                    WritingChromeIconButton(
                        systemName: "italic",
                        isSelected: element.isItalic
                    ) {
                        onItalicToggle()
                    }
                }
                
                WritingToolbarDivider()
                
                // Alignment
                HStack(spacing: 2) {
                    ForEach(alignments, id: \.self) { align in
                        WritingChromeIconButton(
                            systemName: "text.align\(align)",
                            isSelected: element.alignment == align
                        ) {
                            onAlignment(align)
                        }
                    }
                }
                
                WritingToolbarDivider()
                
                // Color (Simplified)
                Menu {
                    ForEach(colorOptions, id: \.value) { option in
                        Button {
                            onColorHex(option.value)
                        } label: {
                            HStack {
                                Circle()
                                    .fill(Color(hex: option.value) ?? .black)
                                    .frame(width: 10, height: 10)
                                Text(option.label)
                            }
                        }
                    }
                } label: {
                    Circle()
                        .fill(Color(hex: element.colorHex) ?? .black)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        .shadow(radius: 1)
                        .padding(.horizontal, 4)
                }

                Text((selectionRange?.length ?? 0) > 0 ? "선택 \(selectionRange!.length)" : "전체")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(PharTheme.ColorToken.subtleText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.04), in: Capsule())
                
                WritingToolbarDivider()
                
                // Delete
                WritingChromeIconButton(systemName: "trash") {
                    onDelete()
                }
                .foregroundStyle(.red)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
    }

    private func fontLabel(for fontName: String?) -> String {
        switch fontName {
        case "rounded":
            return "R"
        case "serif":
            return "S"
        case "monospaced":
            return "M"
        default:
            return "Aa"
        }
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        self.init(
            red: Double((rgb & 0xFF0000) >> 16) / 255.0,
            green: Double((rgb & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgb & 0x0000FF) / 255.0
        )
    }
}
