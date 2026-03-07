import SwiftUI

struct BlankNoteEditorView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: BlankNoteEditorViewModel
    @State private var isBottomPanelExpanded = true
    @State private var pageTransitionFlashOpacity: Double = 0

    init(document: PharDocument) {
        _viewModel = StateObject(wrappedValue: BlankNoteEditorViewModel(document: document))
    }

    var body: some View {
        VStack(spacing: 0) {
            editorCanvas

            if isBottomPanelExpanded {
                thumbnailStrip
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(PharTheme.ColorToken.appBackground.ignoresSafeArea())
        .animation(PharTheme.AnimationToken.toolbarVisibility, value: isBottomPanelExpanded)
        .animation(PharTheme.AnimationToken.pageTransition, value: viewModel.currentPageID)
        .navigationTitle(viewModel.document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                PharToolbarIconButton(
                    systemName: "arrow.uturn.backward",
                    accessibilityLabel: "실행 취소",
                    isEnabled: viewModel.canUndo
                ) {
                    viewModel.undo()
                }
                PharToolbarIconButton(
                    systemName: "arrow.uturn.forward",
                    accessibilityLabel: "다시 실행",
                    isEnabled: viewModel.canRedo
                ) {
                    viewModel.redo()
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                PharToolbarIconButton(
                    systemName: "plus.square.on.square",
                    accessibilityLabel: "페이지 추가"
                ) {
                    viewModel.addPage()
                }

                PharToolbarIconButton(
                    systemName: "trash",
                    accessibilityLabel: "현재 페이지 삭제",
                    isEnabled: viewModel.canDeletePage,
                    isDestructive: true
                ) {
                    viewModel.deleteCurrentPage()
                }

                PharToolbarIconButton(
                    systemName: viewModel.isToolPickerVisible ? "applepencil.and.scribble" : "applepencil",
                    accessibilityLabel: viewModel.isToolPickerVisible ? "툴 피커 숨기기" : "툴 피커 보이기",
                    isSelected: viewModel.isToolPickerVisible
                ) {
                    viewModel.toggleToolPicker()
                }

                PharToolbarIconButton(
                    systemName: isBottomPanelExpanded ? "rectangle.bottomthird.inset.filled" : "rectangle.bottomthird.inset",
                    accessibilityLabel: isBottomPanelExpanded ? "하단 패널 접기" : "하단 패널 펼치기",
                    isSelected: isBottomPanelExpanded
                ) {
                    withAnimation(PharTheme.AnimationToken.toolbarVisibility) {
                        isBottomPanelExpanded.toggle()
                    }
                }
            }
        }
        .task {
            viewModel.loadInitialContentIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                viewModel.saveImmediately()
            }
        }
        .onDisappear {
            viewModel.saveImmediately()
        }
        .onChange(of: viewModel.currentPageID) { _, _ in
            animatePageTransition()
        }
        .alert("오류", isPresented: isErrorPresented) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var editorCanvas: some View {
        ZStack {
            PharTheme.ColorToken.canvasBackground.ignoresSafeArea()

            PencilCanvasView(viewModel: viewModel)
                .background(PharTheme.ColorToken.canvasBackground)
                .clipShape(RoundedRectangle(cornerRadius: PharTheme.CornerRadius.large, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: PharTheme.CornerRadius.large, style: .continuous)
                        .stroke(PharTheme.ColorToken.border.opacity(0.35), lineWidth: 1)
                }
                .padding(PharTheme.Spacing.medium)

            RoundedRectangle(cornerRadius: PharTheme.CornerRadius.large, style: .continuous)
                .fill(Color.accentColor.opacity(pageTransitionFlashOpacity))
                .padding(PharTheme.Spacing.medium)
                .allowsHitTesting(false)
        }
    }

    private var thumbnailStrip: some View {
        PharPanelContainer {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PharTheme.Spacing.small) {
                    ForEach(viewModel.pages) { page in
                        Button {
                            withAnimation(PharTheme.AnimationToken.pageTransition) {
                                viewModel.selectPage(page.id)
                            }
                        } label: {
                            PageThumbnailCell(
                                image: viewModel.thumbnail(for: page.id),
                                pageNumber: viewModel.pageNumber(for: page.id),
                                isSelected: viewModel.currentPageID == page.id
                            )
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.highlight)
                        .contextMenu {
                            Button(role: .destructive) {
                                viewModel.deletePage(page.id)
                            } label: {
                                Label("페이지 삭제", systemImage: "trash")
                            }
                            .disabled(!viewModel.canDeletePage)
                        }
                    }
                }
                .padding(.horizontal, PharTheme.Spacing.medium)
                .padding(.vertical, PharTheme.Spacing.xSmall)
            }
            .frame(height: 146)
        }
    }

    private var isErrorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.errorMessage = nil
                }
            }
        )
    }

    private func animatePageTransition() {
        pageTransitionFlashOpacity = 0.09
        withAnimation(PharTheme.AnimationToken.pageTransition) {
            pageTransitionFlashOpacity = 0
        }
    }
}

#Preview("BlankNoteEditor") {
    NavigationStack {
        BlankNoteEditorView(document: PreviewDocumentFactory.blankNoteDocument())
    }
}

private enum PreviewDocumentFactory {
    static func blankNoteDocument() -> PharDocument {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BlankNotePreview.pharnote", isDirectory: true)
        return PharDocument(
            id: UUID(),
            title: "미리보기 노트",
            createdAt: Date(),
            updatedAt: Date(),
            type: .blankNote,
            path: url.path
        )
    }
}

private struct PageThumbnailCell: View {
    let image: UIImage?
    let pageNumber: Int
    let isSelected: Bool

    var body: some View {
        VStack(spacing: PharTheme.Spacing.xSmall) {
            ZStack {
                RoundedRectangle(cornerRadius: PharTheme.CornerRadius.small, style: .continuous)
                    .fill(PharTheme.ColorToken.canvasBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: PharTheme.CornerRadius.small, style: .continuous)
                            .stroke(
                                isSelected ? Color.accentColor : PharTheme.ColorToken.border.opacity(0.4),
                                lineWidth: isSelected ? 2 : 1
                            )
                    }

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(PharTheme.Spacing.xSmall)
                } else {
                    Image(systemName: "doc.text.image")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 92, height: 120)

            Text("\(pageNumber)")
                .font(PharTypography.captionStrong)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .padding(.vertical, PharTheme.Spacing.xxSmall)
    }
}
