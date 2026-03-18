import SwiftUI

struct FloatingTextToolbar: View {
    @Binding var element: PharTextElement
    var onDelete: () -> Void
    
    let fontSizes: [Double] = [12, 14, 16, 18, 20, 24, 28, 32, 40, 48]
    let weights = ["regular", "semibold", "bold"]
    let alignments = ["left", "center", "right"]
    
    var body: some View {
        WritingChromeCapsule {
            HStack(spacing: 4) {
                // Font Size
                Menu {
                    ForEach(fontSizes, id: \.self) { size in
                        Button("\(Int(size))pt") {
                            element.fontSize = size
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
                
                // Bold/Italic
                HStack(spacing: 2) {
                    WritingChromeIconButton(
                        systemName: "bold",
                        isSelected: element.fontWeight == "bold"
                    ) {
                        element.fontWeight = element.fontWeight == "bold" ? "regular" : "bold"
                    }
                    
                    WritingChromeIconButton(
                        systemName: "italic",
                        isSelected: element.isItalic
                    ) {
                        element.isItalic.toggle()
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
                            element.alignment = align
                        }
                    }
                }
                
                WritingToolbarDivider()
                
                // Color (Simplified)
                Circle()
                    .fill(Color(hex: element.colorHex) ?? .black)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                    .shadow(radius: 1)
                    .padding(.horizontal, 4)
                
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
