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
                                viewModel.updateActiveTextSelectionRange(nil)
                            },
                            onSelectionChange: { range in
                                if viewModel.activeTextElementID == element.id {
                                    viewModel.updateActiveTextSelectionRange(range)
                                }
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
                        element: activeElement,
                        selectionRange: viewModel.activeTextElementSelectionRange,
                        onFontSize: { value in
                            viewModel.applyStyleToActiveTextElement(fontSize: value)
                        },
                        onFontWeight: { value in
                            viewModel.applyStyleToActiveTextElement(fontWeight: value)
                        },
                        onItalicToggle: {
                            let nextValue = !(activeElement.isItalic)
                            viewModel.applyStyleToActiveTextElement(isItalic: nextValue)
                        },
                        onFontName: { value in
                            viewModel.applyStyleToActiveTextElement(fontName: value)
                        },
                        onAlignment: { value in
                            viewModel.applyStyleToActiveTextElement(alignment: value)
                        },
                        onColorHex: { value in
                            viewModel.applyStyleToActiveTextElement(colorHex: value)
                        },
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
    let onSelectionChange: (NSRange?) -> Void
    
    @State private var dragOffset: CGSize = .zero
    @State private var isEditing: Bool = false
    
    var body: some View {
        RichTextTextView(
            element: $element,
            isActive: isActive,
            onActivate: {
                onTap()
                isEditing = true
            },
            onSelectionChange: onSelectionChange
        )
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? PharTheme.ColorToken.accentBlue : .clear, lineWidth: 2)
                .background(isActive ? Color.white.opacity(0.1) : .clear)
        )
        .frame(minWidth: 100)
            .offset(x: element.x + dragOffset.width, y: element.y + dragOffset.height)
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        guard !isEditing else { return }
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        guard !isEditing else { return }
                        element.x += value.translation.width
                        element.y += value.translation.height
                        dragOffset = .zero
                    }
            )
            .onChange(of: isActive) { _, active in
                if !active {
                    isEditing = false
                }
            }
    }
}
