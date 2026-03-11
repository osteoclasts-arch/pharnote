import SwiftUI

struct BlankNoteEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var analysisCenter: AnalysisCenter
    @StateObject private var viewModel: BlankNoteEditorViewModel
    @State private var isBottomPanelExpanded = false
    @State private var pageTransitionFlashOpacity: Double = 0
    @State private var isShowingAnalyzeSheet = false
    @State private var isShowingShareSheet = false
    @State private var workspaceChips: [WritingWorkspaceDocumentChip] = []

    init(document: PharDocument, initialPageKey: String? = nil) {
        _viewModel = StateObject(
            wrappedValue: BlankNoteEditorViewModel(
                document: document,
                initialPageKey: initialPageKey
            )
        )
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
        .toolbar(.hidden, for: .navigationBar)
        .task {
            viewModel.loadInitialContentIfNeeded()
            if workspaceChips.isEmpty {
                workspaceChips = WritingWorkspaceDocumentChip.makeChips(currentDocument: viewModel.document)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                viewModel.saveImmediately()
            }
        }
        .onDisappear {
            viewModel.closeDocument()
        }
        .onChange(of: viewModel.currentPageID) { _, _ in
            animatePageTransition()
        }
        .sheet(isPresented: $isShowingAnalyzeSheet) {
            BlankNoteAnalyzePreviewSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isShowingShareSheet) {
            WritingDocumentShareSheet(items: WritingDocumentShareSource.activityItems(for: viewModel.document))
        }
        .alert("오류", isPresented: isErrorPresented) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var currentAnalysisResult: AnalysisResult? {
        guard let pageId = viewModel.currentAnalysisPageID else { return nil }
        return analysisCenter.result(for: viewModel.document.id, pageId: pageId)
    }

    private var editorCanvas: some View {
        GeometryReader { geometry in
            let pageWidth = min(772, max(640, geometry.size.width - 110))
            let pageHeight = pageWidth * 1.34

            ZStack(alignment: .top) {
                WritingChromePalette.paper.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 28) {
                        editorPage(width: pageWidth, height: pageHeight)

                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.white.opacity(0.78))
                            .frame(width: pageWidth, height: 170)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(Color.black.opacity(0.03), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.04), radius: 7, x: 0, y: 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 166)
                    .padding(.bottom, 120)
                }

                VStack(spacing: 10) {
                    WritingDocumentChipStrip(chips: workspaceChips)
                    chromeToolbar
                    if viewModel.selectedTool == .lasso {
                        chromeAnalyzeCallout
                    }
                    if viewModel.isEditingInkTool {
                        chromeInkPalette
                    }
                }
                .padding(.top, 18)
                .padding(.horizontal, 28)

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        WritingShareFAB {
                            isShowingShareSheet = true
                        }
                        .padding(.trailing, 28)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
    }

    private func editorPage(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(WritingChromePalette.canvas)
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)

            PencilCanvasView(viewModel: viewModel)
                .background(Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(PharTheme.ColorToken.accentBlue.opacity(pageTransitionFlashOpacity))
                .allowsHitTesting(false)
        }
        .frame(width: width, height: height)
    }

    private var chromeToolbar: some View {
        WritingChromeCapsule {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    WritingChromeIconButton(systemName: "house", accentTint: true) {
                        viewModel.saveImmediately()
                        dismiss()
                    }

                    WritingChromeIconButton(systemName: "plus.square", accentTint: true) {
                        viewModel.addPage()
                    }

                    WritingToolbarDivider()

                    toolChromeButton(.pen, icon: "pencil.tip")
                    toolChromeButton(.highlighter, icon: "highlighter")
                    toolChromeButton(.eraser, icon: "eraser")
                    toolChromeButton(.lasso, icon: "lasso")

                    WritingChromePlaceholderIcon(systemName: "paintbrush")
                    WritingChromePlaceholderIcon(systemName: "textformat")
                    WritingChromePlaceholderIcon(systemName: "message")
                    WritingChromePlaceholderIcon(systemName: "photo.badge.plus")
                    WritingChromePlaceholderIcon(systemName: "paperclip")
                    WritingChromePlaceholderIcon(systemName: "square.grid.2x2")

                    if viewModel.selectedTool == .lasso {
                        WritingChromeIconButton(
                            systemName: "waveform.path.ecg.text",
                            accentTint: true,
                            isSelected: true,
                            isEnabled: viewModel.analysisSource != nil
                        ) {
                            isShowingAnalyzeSheet = true
                        }
                    }

                    WritingChromeIconButton(
                        systemName: viewModel.isCurrentPageBookmarked ? "bookmark.fill" : "bookmark",
                        isSelected: viewModel.isCurrentPageBookmarked
                    ) {
                        viewModel.toggleCurrentPageBookmark()
                    }

                    WritingChromeIconButton(systemName: "arrow.uturn.backward", accentTint: true, isEnabled: viewModel.canUndo) {
                        viewModel.undo()
                    }

                    WritingChromeIconButton(systemName: "arrow.uturn.forward", accentTint: true, isEnabled: viewModel.canRedo) {
                        viewModel.redo()
                    }

                    WritingChromeIconButton(
                        systemName: "sidebar.right",
                        accentTint: true,
                        isSelected: isBottomPanelExpanded
                    ) {
                        withAnimation(PharTheme.AnimationToken.toolbarVisibility) {
                            isBottomPanelExpanded.toggle()
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var chromeAnalyzeCallout: some View {
        VStack(spacing: 10) {
            WritingAnalyzeHintBubble(text: "분석 받고 싶은 문제를 태깅하세요!")

            WritingAccentActionButton(
                title: "분석하기",
                systemName: "waveform.path.ecg.text",
                isEnabled: viewModel.analysisSource != nil
            ) {
                isShowingAnalyzeSheet = true
            }
        }
    }

    private var chromeInkPalette: some View {
        WritingChromeCapsule(fill: WritingChromePalette.paletteFill) {
            HStack(spacing: 10) {
                WritingStrokePresetButton(width: 2, isSelected: viewModel.strokeWidth == 2) {
                    viewModel.selectStrokeWidth(2)
                }
                WritingStrokePresetButton(width: 5, isSelected: viewModel.strokeWidth == 5) {
                    viewModel.selectStrokeWidth(5)
                }
                WritingStrokePresetButton(width: 9, isSelected: viewModel.strokeWidth == 9) {
                    viewModel.selectStrokeWidth(9)
                }

                WritingToolbarDivider()

                colorSwatchButton(3)
                colorSwatchButton(2)
                colorSwatchButton(0)
                colorSwatchButton(4)

                Button {
                    viewModel.updateSelectedColor(1)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(WritingChromePalette.chromeBorder)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.72))
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.2), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 508)
    }

    private func toolChromeButton(_ tool: BlankNoteEditorViewModel.AnnotationTool, icon: String) -> some View {
        WritingChromeIconButton(
            systemName: icon,
            isSelected: viewModel.selectedTool == tool
        ) {
            withAnimation(PharTheme.AnimationToken.toolbarVisibility) {
                viewModel.selectTool(tool)
            }
        }
    }

    private func colorSwatchButton(_ colorID: Int) -> some View {
        WritingColorSwatchButton(
            color: Color(uiColor: viewModel.uiColorForColorID(colorID)),
            isSelected: viewModel.selectedColorID == colorID
        ) {
            withAnimation(PharTheme.AnimationToken.toolbarVisibility) {
                viewModel.updateSelectedColor(colorID)
            }
        }
    }

    private var workspaceStatusHeader: some View {
        PharSurfaceCard(fill: PharTheme.ColorToken.surfacePrimary.opacity(0.92)) {
            HStack(alignment: .top, spacing: PharTheme.Spacing.medium) {
                VStack(alignment: .leading, spacing: PharTheme.Spacing.xxSmall) {
                    HStack(spacing: PharTheme.Spacing.xSmall) {
                        PharTagPill(text: "페이지 \(max(viewModel.currentPageNumber, 1))/\(max(viewModel.pages.count, 1))", tint: PharTheme.ColorToken.accentBlue.opacity(0.12), foreground: PharTheme.ColorToken.accentBlue)
                        PharTagPill(
                            text: viewModel.currentPageHasUnsavedChanges ? "편집 중" : "저장됨",
                            tint: viewModel.currentPageHasUnsavedChanges ? PharTheme.ColorToken.accentButter.opacity(0.24) : PharTheme.ColorToken.accentMint.opacity(0.28),
                            foreground: PharTheme.ColorToken.inkPrimary
                        )
                        if viewModel.isCurrentPageBookmarked {
                            PharTagPill(text: "북마크", tint: PharTheme.ColorToken.accentPeach.opacity(0.26))
                        }
                    }

                    Text("현재 페이지에 필기 흔적 \(viewModel.currentPageStrokeCount)개가 기록되어 있습니다.")
                        .font(PharTypography.caption)
                        .foregroundStyle(PharTheme.ColorToken.subtleText)

                    if let currentAnalysisResult {
                        AnalysisHeaderInsightBlock(result: currentAnalysisResult)
                            .padding(.top, PharTheme.Spacing.xSmall)
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: PharTheme.Spacing.xSmall) {
                    PharToolbarIconButton(
                        systemName: viewModel.isCurrentPageBookmarked ? "bookmark.fill" : "bookmark",
                        accessibilityLabel: viewModel.isCurrentPageBookmarked ? "북마크 해제" : "북마크 추가",
                        isSelected: viewModel.isCurrentPageBookmarked
                    ) {
                        viewModel.toggleCurrentPageBookmark()
                    }

                    Button {
                        isShowingAnalyzeSheet = true
                    } label: {
                        Label("분석", systemImage: "waveform.path.ecg.text")
                    }
                    .buttonStyle(PharPrimaryButtonStyle())
                }
            }
        }
    }

    private var floatingToolDock: some View {
        VStack(spacing: PharTheme.Spacing.xSmall) {
            if viewModel.isEditingInkTool {
                inkControlsBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            mainToolDock
        }
        .animation(PharTheme.AnimationToken.toolbarVisibility, value: viewModel.selectedTool)
    }

    private var mainToolDock: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PharTheme.Spacing.xSmall) {
                dockActionButton(systemName: "arrow.uturn.backward", label: "실행 취소", isEnabled: viewModel.canUndo) {
                    viewModel.undo()
                }
                dockActionButton(systemName: "arrow.uturn.forward", label: "다시 실행", isEnabled: viewModel.canRedo) {
                    viewModel.redo()
                }

                dockDivider

                toolButton(.pen, icon: "pencil.tip")
                toolButton(.highlighter, icon: "highlighter")
                toolButton(.eraser, icon: "eraser.fill")
                toolButton(.lasso, icon: "lasso")

                dockDivider

                Button {
                    viewModel.togglePencilOnlyInput()
                } label: {
                    Label(
                        viewModel.isPencilOnlyInputEnabled ? "Pencil" : "Touch",
                        systemImage: viewModel.isPencilOnlyInputEnabled ? "pencil.tip" : "hand.draw.fill"
                    )
                    .font(PharTypography.captionStrong)
                    .padding(.horizontal, PharTheme.Spacing.small)
                    .padding(.vertical, PharTheme.Spacing.xSmall)
                    .background(
                        Capsule(style: .continuous)
                            .fill(
                                viewModel.isPencilOnlyInputEnabled
                                ? PharTheme.ColorToken.accentBlue.opacity(0.16)
                                : PharTheme.ColorToken.surfaceSecondary
                            )
                    )
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)

                PharToolbarIconButton(
                    systemName: viewModel.isToolPickerVisible ? "scribble.variable" : "ellipsis.circle",
                    accessibilityLabel: viewModel.isToolPickerVisible ? "고급 툴 숨기기" : "고급 툴 보기",
                    isSelected: viewModel.isToolPickerVisible
                ) {
                    viewModel.toggleToolPicker()
                }
            }
            .padding(.horizontal, PharTheme.Spacing.small)
            .padding(.vertical, PharTheme.Spacing.small)
        }
        .background(
            Capsule(style: .continuous)
                .fill(PharTheme.ColorToken.toolbarFill)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(PharTheme.ColorToken.border.opacity(0.42), lineWidth: 1)
        )
        .shadow(color: PharTheme.ColorToken.overlayShadow, radius: 18, x: 0, y: 10)
    }

    private var inkControlsBar: some View {
        PharSurfaceCard(fill: PharTheme.ColorToken.surfacePrimary.opacity(0.92)) {
            HStack(spacing: PharTheme.Spacing.medium) {
                HStack(spacing: PharTheme.Spacing.xSmall) {
                    ForEach(viewModel.annotationColors) { color in
                        colorButton(colorID: color.id)
                    }
                }

                dockDivider

                HStack(spacing: PharTheme.Spacing.xxSmall) {
                    widthButton(2)
                    widthButton(5)
                    widthButton(9)
                    widthButton(14)
                }

                Spacer(minLength: 0)

                Text(viewModel.selectedTool.rawValue)
                    .font(PharTypography.captionStrong)
                    .foregroundStyle(PharTheme.ColorToken.subtleText)
            }
        }
    }

    private var thumbnailStrip: some View {
        PharPanelContainer {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
                HStack {
                    VStack(alignment: .leading, spacing: PharTheme.Spacing.xxxSmall) {
                        Text("Pages")
                            .font(PharTypography.captionStrong)
                            .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                        Text("현재, 인접 페이지를 우선 메모리에 두고 썸네일은 백그라운드에서 유지합니다.")
                            .font(PharTypography.caption)
                            .foregroundStyle(PharTheme.ColorToken.subtleText)
                    }
                    Spacer(minLength: 0)
                    PharTagPill(text: "\(viewModel.pages.count) pages", tint: PharTheme.ColorToken.surfaceSecondary)
                }

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
                                    isSelected: viewModel.currentPageID == page.id,
                                    isBookmarked: viewModel.isPageBookmarked(page.id),
                                    isDirty: viewModel.isPageDirty(page.id)
                                )
                            }
                            .buttonStyle(.plain)
                            .hoverEffect(.highlight)
                            .contextMenu {
                                Button {
                                    viewModel.selectPage(page.id)
                                    viewModel.toggleCurrentPageBookmark()
                                } label: {
                                    Label(viewModel.isPageBookmarked(page.id) ? "북마크 해제" : "북마크 추가", systemImage: viewModel.isPageBookmarked(page.id) ? "bookmark.slash" : "bookmark")
                                }

                                Button(role: .destructive) {
                                    viewModel.deletePage(page.id)
                                } label: {
                                    Label("페이지 삭제", systemImage: "trash")
                                }
                                .disabled(!viewModel.canDeletePage)
                            }
                        }
                    }
                    .padding(.horizontal, PharTheme.Spacing.xSmall)
                    .padding(.vertical, PharTheme.Spacing.xxxSmall)
                }
                .frame(height: 150)
            }
        }
    }

    private var dockDivider: some View {
        Rectangle()
            .fill(PharTheme.ColorToken.border.opacity(0.5))
            .frame(width: 1, height: 30)
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

    private func dockActionButton(
        systemName: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: PharTheme.Icon.toolbar, weight: .semibold))
        }
        .buttonStyle(PharToolbarButtonStyle(isSelected: false, isDestructive: false))
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    private func toolButton(_ tool: BlankNoteEditorViewModel.AnnotationTool, icon: String) -> some View {
        Button {
            withAnimation(PharTheme.AnimationToken.toolbarVisibility) {
                viewModel.selectTool(tool)
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(tool.rawValue)
                    .font(PharTypography.eyebrow)
            }
            .frame(minWidth: 58, minHeight: PharTheme.HitArea.comfortable)
            .foregroundStyle(viewModel.selectedTool == tool ? PharTheme.ColorToken.accentBlue : PharTheme.ColorToken.inkPrimary)
            .background(
                RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                    .fill(viewModel.selectedTool == tool ? PharTheme.ColorToken.accentBlue.opacity(0.14) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
    }

    private func colorButton(colorID: Int) -> some View {
        Button {
            withAnimation(PharTheme.AnimationToken.toolbarVisibility) {
                viewModel.updateSelectedColor(colorID)
            }
        } label: {
            Circle()
                .fill(Color(uiColor: viewModel.uiColorForColorID(colorID)))
                .frame(width: 24, height: 24)
                .overlay {
                    Circle()
                        .stroke(viewModel.selectedColorID == colorID ? PharTheme.ColorToken.inkPrimary : Color.clear, lineWidth: 2)
                }
                .scaleEffect(viewModel.selectedColorID == colorID ? 1.08 : 1.0)
                .frame(minWidth: PharTheme.HitArea.minimum, minHeight: PharTheme.HitArea.minimum)
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
    }

    private func widthButton(_ width: Double) -> some View {
        Button {
            withAnimation(PharTheme.AnimationToken.toolbarVisibility) {
                viewModel.selectStrokeWidth(width)
            }
        } label: {
            Circle()
                .fill(PharTheme.ColorToken.inkPrimary)
                .frame(width: width + 4, height: width + 4)
                .frame(minWidth: PharTheme.HitArea.minimum, minHeight: PharTheme.HitArea.minimum)
                .background(
                    Circle()
                        .fill(viewModel.strokeWidth == width ? PharTheme.ColorToken.accentBlue.opacity(0.14) : Color.clear)
                        .frame(width: PharTheme.HitArea.minimum - 4, height: PharTheme.HitArea.minimum - 4)
                )
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
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

private struct CanvasPaperDecor: View {
    var body: some View {
        VStack(spacing: 28) {
            ForEach(0..<12, id: \.self) { _ in
                Rectangle()
                    .fill(PharTheme.ColorToken.borderSoft.opacity(0.42))
                    .frame(height: 1)
            }
        }
        .padding(.horizontal, PharTheme.Spacing.large)
        .padding(.top, 90)
        .allowsHitTesting(false)
    }
}

private struct BlankNoteAnalyzePreviewSheet: View {
    @ObservedObject var viewModel: BlankNoteEditorViewModel
    @EnvironmentObject private var analysisCenter: AnalysisCenter
    @Environment(\.dismiss) private var dismiss
    @State private var selectedStudyIntent: AnalysisStudyIntent = .summary
    @State private var ocrSummary: OCRPreviewSummary?
    @State private var isLoadingOCRSummary = false

    private var currentResult: AnalysisResult? {
        guard let pageId = viewModel.currentAnalysisPageID else { return nil }
        return analysisCenter.result(for: viewModel.document.id, pageId: pageId)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PharTheme.Spacing.large) {
                    PharSurfaceCard(fill: PharTheme.GradientToken.accentWash) {
                        VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
                            Text("Analyze Preview")
                                .font(PharTypography.sectionTitle)
                                .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                            Text("현재 페이지의 필기, 썸네일, 학습 신호를 묶어 pharnode 파이프라인으로 넘길 준비를 합니다.")
                                .font(PharTypography.body)
                                .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                        }
                    }

                    PharSurfaceCard {
                        VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
                            Text("Analyze setup")
                                .font(PharTypography.cardTitle)
                                .foregroundStyle(PharTheme.ColorToken.inkPrimary)

                            PreviewRow(title: "범위", value: AnalysisScope.page.title)

                            Picker("학습 의도", selection: $selectedStudyIntent) {
                                ForEach([
                                    AnalysisStudyIntent.summary,
                                    .problemSolving,
                                    .review,
                                    .lecture,
                                    .examPrep
                                ]) { intent in
                                    Text(intent.title).tag(intent)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    if let preview = viewModel.analysisPreview, let source = viewModel.analysisSource {
                        PharSurfaceCard {
                            VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
                                PreviewRow(title: "대상 페이지", value: "\(preview.pageNumber) / \(max(viewModel.pages.count, 1))")
                                PreviewRow(title: "스트로크 수", value: "\(preview.strokeCount)")
                                PreviewRow(title: "북마크", value: preview.isBookmarked ? "예" : "아니오")
                                PreviewRow(title: "저장 상태", value: preview.hasUnsavedChanges ? "로컬 변경 있음" : "저장 완료")
                                PreviewRow(title: "최근 수정", value: preview.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                PreviewRow(title: "체류 시간", value: "\(source.dwellMs / 1000)초")
                                PreviewRow(title: "번들 자산", value: bundleAssetSummary(for: source))
                            }
                        }
                        OCRPreviewCard(summary: ocrSummary, isLoading: isLoadingOCRSummary)
                            .task(id: source.pageId) {
                                await loadOCRSummary(for: source)
                            }
                    }

                    PharSurfaceCard {
                        VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
                            Text("Queue status")
                                .font(PharTypography.cardTitle)
                                .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                            PreviewRow(title: "대기 중", value: "\(analysisCenter.queuedCount)")
                            PreviewRow(title: "완료됨", value: "\(analysisCenter.completedCount)")
                            if let entry = analysisCenter.lastQueuedEntry {
                                PreviewRow(title: "최근 적재", value: "\(entry.documentTitle) · \(entry.pageLabel)")
                            }
                            if let latestBundle = analysisCenter.latestBundle {
                                PreviewRow(title: "최근 bundle", value: String(latestBundle.bundleId.uuidString.prefix(8)) + "…")
                            }
                            if let errorMessage = analysisCenter.errorMessage {
                                Text(errorMessage)
                                    .font(PharTypography.caption)
                                    .foregroundStyle(PharTheme.ColorToken.destructive)
                            }
                        }
                    }

                    if let currentResult {
                        AnalysisResultDetailCard(result: currentResult)
                    }

                    PharSurfaceCard {
                        VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
                            Text("Planned pipeline")
                                .font(PharTypography.cardTitle)
                                .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                            Text("1. 현재 페이지 범위 선택")
                            Text("2. drawing, thumbnail, dwell signal 수집")
                            Text("3. AnalysisBundle 생성")
                            Text("4. 로컬 큐에 적재")
                            Text("5. 이후 pharnode 전송 / 결과 렌더링")
                        }
                        .font(PharTypography.caption)
                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                    }

                    Button {
                        Task {
                            guard let source = viewModel.analysisSource else { return }
                            await analysisCenter.enqueueBlankNote(
                                source: source,
                                scope: .page,
                                studyIntent: selectedStudyIntent
                            )
                        }
                    } label: {
                        HStack {
                            if analysisCenter.isEnqueuing {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(analysisCenter.isEnqueuing ? "적재 중..." : "분석 번들 큐에 적재")
                        }
                    }
                    .buttonStyle(PharPrimaryButtonStyle())
                    .disabled(analysisCenter.isEnqueuing || viewModel.analysisSource == nil)

                    Spacer(minLength: 0)
                }
                .padding(PharTheme.Spacing.large)
            }
            .navigationTitle("페이지 분석")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func bundleAssetSummary(for source: BlankNoteAnalysisSource) -> String {
        let preview = source.previewImageData == nil ? "preview 없음" : "preview 포함"
        let drawing = source.drawingData == nil ? "drawing 없음" : "drawing 포함"
        return "\(preview), \(drawing)"
    }

    private func loadOCRSummary(for source: BlankNoteAnalysisSource) async {
        isLoadingOCRSummary = true
        ocrSummary = await analysisCenter.ocrPreview(for: source)
        isLoadingOCRSummary = false
    }
}

private struct PreviewRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(PharTypography.captionStrong)
                .foregroundStyle(PharTheme.ColorToken.inkSecondary)
            Spacer(minLength: 0)
            Text(value)
                .font(PharTypography.bodyStrong)
                .foregroundStyle(PharTheme.ColorToken.inkPrimary)
        }
    }
}

struct OCRPreviewCard: View {
    let summary: OCRPreviewSummary?
    let isLoading: Bool

    var body: some View {
        PharSurfaceCard {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
                Text("OCR 미리보기")
                    .font(PharTypography.cardTitle)
                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)

                if isLoading {
                    HStack(spacing: PharTheme.Spacing.small) {
                        ProgressView()
                            .controlSize(.small)
                        Text("OCR 결과를 준비하는 중입니다.")
                            .font(PharTypography.caption)
                            .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                    }
                } else if let summary {
                    PreviewRow(title: "인식 블록", value: "\(summary.recognizedBlockCount)")
                    PreviewRow(title: "손글씨 블록", value: "\(summary.handwritingBlockCount)")
                    PreviewRow(title: "인식 문자 수", value: "\(summary.recognizedCharacterCount)")
                    PreviewRow(title: "수식 신호", value: summary.hasMathSignal ? "강함" : "약함")

                    if !summary.problemCandidates.isEmpty {
                        VStack(alignment: .leading, spacing: PharTheme.Spacing.xSmall) {
                            Text("문제 후보")
                                .font(PharTypography.captionStrong)
                                .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                            ForEach(summary.problemCandidates, id: \.self) { candidate in
                                Text(candidate)
                                    .font(PharTypography.caption)
                                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.top, PharTheme.Spacing.xSmall)
                    }

                    if !summary.topLines.isEmpty {
                        VStack(alignment: .leading, spacing: PharTheme.Spacing.xSmall) {
                            Text("대표 OCR 텍스트")
                                .font(PharTypography.captionStrong)
                                .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                            ForEach(summary.topLines, id: \.self) { line in
                                Text(line)
                                    .font(PharTypography.caption)
                                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.top, PharTheme.Spacing.xSmall)
                    }
                } else {
                    Text("아직 OCR 결과가 없습니다.")
                        .font(PharTypography.caption)
                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                }
            }
        }
    }
}

private struct PageThumbnailCell: View {
    let image: UIImage?
    let pageNumber: Int
    let isSelected: Bool
    let isBookmarked: Bool
    let isDirty: Bool

    var body: some View {
        VStack(spacing: PharTheme.Spacing.xSmall) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                    .fill(PharTheme.ColorToken.canvasBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                            .stroke(
                                isSelected ? PharTheme.ColorToken.accentBlue : PharTheme.ColorToken.border.opacity(0.4),
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

                HStack(spacing: 6) {
                    if isDirty {
                        Circle()
                            .fill(PharTheme.ColorToken.warning)
                            .frame(width: 8, height: 8)
                    }
                    if isBookmarked {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(PharTheme.ColorToken.accentBlue)
                    }
                }
                .padding(PharTheme.Spacing.xSmall)
            }
            .frame(width: 96, height: 122)
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .shadow(color: PharTheme.ColorToken.overlayShadow.opacity(isSelected ? 0.12 : 0.04), radius: isSelected ? 16 : 8, x: 0, y: isSelected ? 10 : 5)

            Text("\(pageNumber)")
                .font(PharTypography.captionStrong)
                .foregroundStyle(isSelected ? PharTheme.ColorToken.accentBlue : PharTheme.ColorToken.subtleText)
        }
        .padding(.vertical, PharTheme.Spacing.xxxSmall)
    }
}
