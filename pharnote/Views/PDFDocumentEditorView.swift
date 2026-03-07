import SwiftUI
import UIKit

struct PDFDocumentEditorView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: PDFEditorViewModel
    @State private var isBottomPanelExpanded = true
    @State private var pageTransitionFlashOpacity: Double = 0

    init(document: PharDocument) {
        _viewModel = StateObject(wrappedValue: PDFEditorViewModel(document: document))
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                PDFKitView(viewModel: viewModel)
                    .background(Color(.secondarySystemBackground))

                RoundedRectangle(cornerRadius: PharTheme.CornerRadius.large, style: .continuous)
                    .fill(Color.accentColor.opacity(pageTransitionFlashOpacity))
                    .padding(PharTheme.Spacing.medium)
                    .allowsHitTesting(false)
            }

            if isBottomPanelExpanded {
                controlsAndThumbnails
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(PharTheme.ColorToken.appBackground.ignoresSafeArea())
        .animation(PharTheme.AnimationToken.toolbarVisibility, value: isBottomPanelExpanded)
        .animation(PharTheme.AnimationToken.pageTransition, value: viewModel.currentPageIndex)
        .navigationTitle(viewModel.document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
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
            viewModel.loadPDFIfNeeded()
        }
        .onDisappear {
            viewModel.stopTasks()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                viewModel.saveAllOverlayPagesImmediately()
            }
        }
        .onChange(of: viewModel.currentPageIndex) { _, _ in
            animatePageTransition()
        }
        .alert("오류", isPresented: isErrorPresented) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var controlsAndThumbnails: some View {
        PharPanelContainer {
            VStack(spacing: PharTheme.Spacing.xSmall) {
                toolControls
                pdfTextSearchControls

                HStack(spacing: PharTheme.Spacing.xSmall) {
                    PharToolbarIconButton(
                        systemName: "chevron.left",
                        accessibilityLabel: "이전 페이지",
                        isEnabled: viewModel.canGoPrevious
                    ) {
                        viewModel.goToPreviousPage()
                    }

                    PharToolbarIconButton(
                        systemName: "chevron.right",
                        accessibilityLabel: "다음 페이지",
                        isEnabled: viewModel.canGoNext
                    ) {
                        viewModel.goToNextPage()
                    }

                    Text("\(max(viewModel.currentPageIndex + 1, 1))/\(max(viewModel.pageCount, 1))")
                        .font(PharTypography.numberMono)
                        .frame(width: 72, alignment: .trailing)

                    TextField("페이지", text: $viewModel.pageJumpInput)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .frame(width: 80)

                    Button("이동") {
                        viewModel.goToInputPage()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .hoverEffect(.highlight)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, PharTheme.Spacing.small)
                .padding(.top, PharTheme.Spacing.xxSmall)

                if viewModel.selectedTool == .lasso {
                    HStack(spacing: PharTheme.Spacing.xSmall) {
                        Button {
                            viewModel.copySelection()
                        } label: {
                            Label("복사", systemImage: "doc.on.doc")
                        }
                        .disabled(!viewModel.canCopy)

                        Button {
                            viewModel.cutSelection()
                        } label: {
                            Label("잘라내기", systemImage: "scissors")
                        }
                        .disabled(!viewModel.canCut)

                        Button {
                            viewModel.pasteSelection()
                        } label: {
                            Label("붙여넣기", systemImage: "doc.on.clipboard")
                        }
                        .disabled(!viewModel.canPaste)

                        Button(role: .destructive) {
                            viewModel.deleteSelection()
                        } label: {
                            Label("삭제", systemImage: "trash")
                        }
                        .disabled(!viewModel.canDelete)

                        Text("선택 후 드래그로 이동")
                            .font(PharTypography.caption)
                            .foregroundStyle(PharTheme.ColorToken.subtleText)

                        Spacer(minLength: 0)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .padding(.horizontal, PharTheme.Spacing.small)
                    .transition(.opacity)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: PharTheme.Spacing.xSmall) {
                        ForEach(0..<viewModel.pageCount, id: \.self) { index in
                            Button {
                                withAnimation(PharTheme.AnimationToken.pageTransition) {
                                    viewModel.goToPage(index: index)
                                }
                            } label: {
                                PDFPageThumbnailCell(
                                    image: viewModel.thumbnail(at: index),
                                    pageNumber: index + 1,
                                    isSelected: viewModel.currentPageIndex == index
                                )
                            }
                            .buttonStyle(.plain)
                            .hoverEffect(.highlight)
                        }
                    }
                    .padding(.horizontal, PharTheme.Spacing.small)
                    .padding(.bottom, PharTheme.Spacing.xxSmall)
                }
            }
        }
        .frame(height: 372)
    }

    private var pdfTextSearchControls: some View {
        VStack(spacing: PharTheme.Spacing.xxSmall) {
            HStack(spacing: PharTheme.Spacing.xSmall) {
                TextField("PDF 텍스트 검색", text: $viewModel.pdfTextSearchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        viewModel.performPDFTextSearch()
                    }

                Button("검색") {
                    viewModel.performPDFTextSearch()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .hoverEffect(.highlight)

                PharToolbarIconButton(
                    systemName: "xmark.circle",
                    accessibilityLabel: "검색 초기화",
                    isEnabled: !(viewModel.pdfTextSearchQuery.isEmpty && viewModel.pdfTextSearchResults.isEmpty)
                ) {
                    viewModel.clearPDFTextSearch()
                }

                PharToolbarIconButton(
                    systemName: "chevron.up",
                    accessibilityLabel: "이전 검색 결과",
                    isEnabled: viewModel.canGoToPreviousPDFTextResult
                ) {
                    viewModel.goToPreviousPDFTextResult()
                }

                PharToolbarIconButton(
                    systemName: "chevron.down",
                    accessibilityLabel: "다음 검색 결과",
                    isEnabled: viewModel.canGoToNextPDFTextResult
                ) {
                    viewModel.goToNextPDFTextResult()
                }

                Text("\(viewModel.currentPDFTextSearchResultIndex.map { $0 + 1 } ?? 0)/\(viewModel.pdfTextSearchResults.count)")
                    .font(PharTypography.captionStrong.monospacedDigit())
                    .frame(width: 64, alignment: .trailing)
            }
            .padding(.horizontal, PharTheme.Spacing.small)

            if !viewModel.pdfTextSearchResults.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PharTheme.Spacing.xSmall) {
                        ForEach(Array(viewModel.pdfTextSearchResults.enumerated()), id: \.element.id) { index, result in
                            Button {
                                viewModel.goToPDFTextSearchResult(at: index)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("p.\(result.pageIndex + 1)")
                                        .font(PharTypography.captionStrong)
                                    Text(result.snippet)
                                        .font(PharTypography.caption)
                                        .lineLimit(1)
                                        .frame(maxWidth: 180, alignment: .leading)
                                }
                                .padding(.horizontal, PharTheme.Spacing.small)
                                .padding(.vertical, PharTheme.Spacing.xSmall)
                                .background(
                                    RoundedRectangle(cornerRadius: PharTheme.CornerRadius.small, style: .continuous)
                                        .fill(
                                            viewModel.currentPDFTextSearchResultIndex == index
                                            ? Color.accentColor.opacity(0.2)
                                            : PharTheme.ColorToken.toolbarFill.opacity(0.7)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .hoverEffect(.highlight)
                        }
                    }
                    .padding(.horizontal, PharTheme.Spacing.small)
                }
                .transition(.opacity)
            }
        }
    }

    private var toolControls: some View {
        VStack(spacing: PharTheme.Spacing.xSmall) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PharTheme.Spacing.xSmall) {
                    paletteActionButton(
                        systemName: "arrow.uturn.backward",
                        label: "실행 취소",
                        isEnabled: viewModel.canUndo
                    ) {
                        viewModel.undo()
                    }

                    paletteActionButton(
                        systemName: "arrow.uturn.forward",
                        label: "다시 실행",
                        isEnabled: viewModel.canRedo
                    ) {
                        viewModel.redo()
                    }

                    paletteDivider

                    paletteToolButton(.pen, icon: "pencil.tip")
                    paletteToolButton(.highlighter, icon: "highlighter")
                    paletteToolButton(.eraser, icon: "eraser.fill")
                    paletteToolButton(.lasso, icon: "lasso")

                    paletteDivider

                    HStack(spacing: 6) {
                        ForEach(viewModel.annotationColors) { color in
                            paletteColorButton(colorID: color.id)
                        }
                    }

                    paletteDivider

                    HStack(spacing: 6) {
                        strokePresetButton(2)
                        strokePresetButton(5)
                        strokePresetButton(9)
                        strokePresetButton(14)
                    }
                    .disabled(!viewModel.isEditingInkTool)

                    paletteDivider

                    Button {
                        withAnimation(PharTheme.AnimationToken.toolbarVisibility) {
                            viewModel.togglePencilOnlyInput()
                        }
                    } label: {
                        Label(
                            viewModel.isPencilOnlyInputEnabled ? "Pencil" : "Touch",
                            systemImage: viewModel.isPencilOnlyInputEnabled ? "pencil.tip" : "hand.draw.fill"
                        )
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    viewModel.isPencilOnlyInputEnabled
                                    ? Color.accentColor.opacity(0.2)
                                    : PharTheme.ColorToken.toolbarFill.opacity(0.6)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                    .accessibilityLabel("입력 방식 전환")
                }
                .padding(.horizontal, PharTheme.Spacing.xSmall)
                .padding(.vertical, PharTheme.Spacing.xSmall)
            }
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(PharTheme.ColorToken.border.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)

            if viewModel.isEditingInkTool {
                HStack(spacing: PharTheme.Spacing.xSmall) {
                    Text("굵기")
                        .font(PharTypography.captionStrong)
                        .foregroundStyle(PharTheme.ColorToken.subtleText)

                    Slider(value: $viewModel.strokeWidth, in: 1...20, step: 1)
                        .frame(maxWidth: 220)

                    Text("\(Int(viewModel.strokeWidth))")
                        .font(PharTypography.captionStrong.monospacedDigit())
                        .frame(width: 32, alignment: .trailing)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, PharTheme.Spacing.small)
                .padding(.vertical, PharTheme.Spacing.xSmall)
                .background(
                    RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                        .fill(PharTheme.ColorToken.toolbarFill.opacity(0.5))
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, PharTheme.Spacing.small)
        .padding(.top, PharTheme.Spacing.xxSmall)
        .animation(.easeInOut(duration: 0.2), value: viewModel.selectedTool)
    }

    private var paletteDivider: some View {
        Rectangle()
            .fill(PharTheme.ColorToken.border.opacity(0.45))
            .frame(width: 1, height: 30)
    }

    private func paletteActionButton(
        systemName: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
        }
        .buttonStyle(PharToolbarButtonStyle(isSelected: false, isDestructive: false))
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    private func paletteToolButton(
        _ tool: PDFEditorViewModel.AnnotationTool,
        icon: String
    ) -> some View {
        Button {
            withAnimation(PharTheme.AnimationToken.toolbarVisibility) {
                viewModel.selectedTool = tool
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .frame(
                    minWidth: PharTheme.HitArea.minimum,
                    minHeight: PharTheme.HitArea.minimum
                )
                .foregroundStyle(
                    viewModel.selectedTool == tool
                    ? Color.accentColor
                    : Color.primary
                )
                .background(
                    RoundedRectangle(cornerRadius: PharTheme.CornerRadius.small, style: .continuous)
                        .fill(
                            viewModel.selectedTool == tool
                            ? Color.accentColor.opacity(0.18)
                            : Color.clear
                        )
                )
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .accessibilityLabel("\(tool.rawValue) 도구")
    }

    private func paletteColorButton(colorID: Int) -> some View {
        Button {
            withAnimation(PharTheme.AnimationToken.toolbarVisibility) {
                viewModel.updateSelectedColor(colorID)
            }
        } label: {
            Circle()
                .fill(viewModel.swiftUIColorForColorID(colorID))
                .frame(width: 24, height: 24)
                .overlay {
                    Circle()
                        .stroke(
                            viewModel.selectedColorID == colorID ? Color.primary : Color.clear,
                            lineWidth: 2
                        )
                }
                .scaleEffect(viewModel.selectedColorID == colorID ? 1.08 : 1.0)
                .frame(
                    minWidth: PharTheme.HitArea.minimum,
                    minHeight: PharTheme.HitArea.minimum
                )
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .disabled(!viewModel.isEditingInkTool)
        .animation(.easeInOut(duration: 0.16), value: viewModel.selectedColorID)
    }

    private func strokePresetButton(_ width: Double) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.12)) {
                viewModel.strokeWidth = width
            }
        } label: {
            Circle()
                .fill(Color.primary.opacity(0.86))
                .frame(width: strokeDotSize(for: width), height: strokeDotSize(for: width))
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(viewModel.strokeWidth == width ? Color.accentColor.opacity(0.18) : Color.clear)
                )
                .frame(
                    minWidth: PharTheme.HitArea.minimum,
                    minHeight: PharTheme.HitArea.minimum
                )
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
    }

    private func strokeDotSize(for width: Double) -> CGFloat {
        min(max(CGFloat(width) * 1.2, 4), 14)
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
        pageTransitionFlashOpacity = 0.08
        withAnimation(PharTheme.AnimationToken.pageTransition) {
            pageTransitionFlashOpacity = 0
        }
    }
}

#Preview("PDFEditor") {
    NavigationStack {
        PDFDocumentEditorView(document: PreviewDocumentFactory.pdfDocument())
    }
}

private enum PreviewDocumentFactory {
    static func pdfDocument() -> PharDocument {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent("PDFPreview.pharnote", isDirectory: true)
        let pdfURL = baseURL.appendingPathComponent("Original.pdf", isDirectory: false)
        ensurePreviewPDFExists(at: pdfURL)
        return PharDocument(
            id: UUID(),
            title: "미리보기 PDF",
            createdAt: Date(),
            updatedAt: Date(),
            type: .pdf,
            path: baseURL.path
        )
    }

    private static func ensurePreviewPDFExists(at url: URL) {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) { return }
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        let data = renderer.pdfData { context in
            context.beginPage()
            let text = "Preview PDF"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 32, weight: .semibold),
                .foregroundColor: UIColor.darkGray
            ]
            let textRect = CGRect(x: 40, y: 40, width: 515, height: 100)
            text.draw(in: textRect, withAttributes: attributes)
        }
        try? data.write(to: url, options: .atomic)
    }
}

private struct PDFPageThumbnailCell: View {
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
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(width: 86, height: 112)

            Text("\(pageNumber)")
                .font(PharTypography.captionStrong)
                .foregroundStyle(isSelected ? Color.accentColor : PharTheme.ColorToken.subtleText)
        }
    }
}
