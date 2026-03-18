import SwiftUI

struct LiveTextEditingLayer: View {
    @ObservedObject var viewModel: BlankNoteEditorViewModel
    
    var body: some View {
        ZStack {
            ForEach($viewModel.pages) { $page in
                if page.id == viewModel.currentPageID {
                    ForEach($page.textElements) { $element in
                        TextElementView(
                            element: $element,
                            isActive: viewModel.activeTextElementID == element.id,
                            onTap: {
                                viewModel.activeTextElementID = element.id
                            },
                            onDelete: {
                                viewModel.deleteTextElement(id: element.id)
                            }
                        )
                    }
                }
            }
            
            if let activeID = viewModel.activeTextElementID,
               let activeElement = findActiveElement(activeID) {
                VStack {
                    Spacer()
                    FloatingTextToolbar(
                        element: Binding(
                            get: { activeElement },
                            set: { viewModel.updateTextElement($0) }
                        ),
                        onDelete: {
                            viewModel.deleteTextElement(id: activeID)
                        }
                    )
                    .padding(.bottom, 100)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
    
    private func findActiveElement(_ id: UUID) -> PharTextElement? {
        guard let pageID = viewModel.currentPageID,
              let page = viewModel.pages.first(where: { $0.id == pageID }) else { return nil }
        return page.textElements.first(where: { $0.id == id })
    }
}

struct TextElementView: View {
    @Binding var element: PharTextElement
    let isActive: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    
    @State private var dragOffset: CGSize = .zero
    @FocusState private var isFocused: Bool
    
    var body: some View {
        TextField("", text: $element.text, axis: .vertical)
            .font(.system(
                size: element.fontSize,
                weight: weightFromString(element.fontWeight),
                design: .rounded
            ))
            .italic(element.isItalic)
            .multilineTextAlignment(alignmentFromString(element.alignment))
            .foregroundStyle(Color(hex: element.colorHex) ?? .black)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? PharTheme.ColorToken.accentBlue : .clear, lineWidth: 2)
                    .background(isActive ? Color.white.opacity(0.1) : .clear)
            )
            .frame(minWidth: 100)
            .offset(x: element.x + dragOffset.width, y: element.y + dragOffset.height)
            .focused($isFocused)
            .onTapGesture {
                onTap()
                isFocused = true
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        element.x += value.translation.width
                        element.y += value.translation.height
                        dragOffset = .zero
                    }
            )
            .onChange(of: isActive) { active in
                if !active { isFocused = false }
            }
    }
    
    private func weightFromString(_ weight: String) -> Font.Weight {
        switch weight {
        case "bold": return .bold
        case "semibold": return .semibold
        case "medium": return .medium
        default: return .regular
        }
    }
    
    private func alignmentFromString(_ alignment: String) -> TextAlignment {
        switch alignment {
        case "center": return .center
        case "right": return .trailing
        default: return .leading
        }
    }
}
