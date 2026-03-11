import SwiftUI
import UIKit

struct PDFDocumentEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var analysisCenter: AnalysisCenter
    @StateObject private var viewModel: PDFEditorViewModel
    @State private var isBottomPanelExpanded = false
    @State private var pageTransitionFlashOpacity: Double = 0
    @State private var isShowingAnalyzeSheet = false
    @State private var isShowingSectionEditor = false
    @State private var isShowingShareSheet = false
    @State private var workspaceChips: [WritingWorkspaceDocumentChip] = []

    init(document: PharDocument, initialPageKey: String? = nil) {
        _viewModel = StateObject(
            wrappedValue: PDFEditorViewModel(
                document: document,
                initialPageKey: initialPageKey
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            editorCanvas

            if isBottomPanelExpanded {
                workspacePanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(PharTheme.ColorToken.appBackground.ignoresSafeArea())
        .animation(PharTheme.AnimationToken.toolbarVisibility, value: isBottomPanelExpanded)
        .animation(PharTheme.AnimationToken.pageTransition, value: viewModel.currentPageIndex)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            viewModel.loadPDFIfNeeded()
            if workspaceChips.isEmpty {
                workspaceChips = WritingWorkspaceDocumentChip.makeChips(currentDocument: viewModel.document)
            }
        }
        .onDisappear {
            viewModel.closeDocument()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                viewModel.saveAllOverlayPagesImmediately()
            }
        }
        .onChange(of: viewModel.currentPageIndex) { _, _ in
            animatePageTransition()
        }
        .sheet(isPresented: $isShowingAnalyzeSheet) {
            PDFAnalyzePreviewSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isShowingSectionEditor) {
            PDFSectionMappingSheet(viewModel: viewModel)
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
        ZStack {
            WritingChromePalette.paper.ignoresSafeArea()

            RoundedRectangle(cornerRadius: PharTheme.CornerRadius.large, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white,
                            PharTheme.ColorToken.canvasBackground,
                            PharTheme.ColorToken.surfaceSecondary
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: PharTheme.CornerRadius.large, style: .continuous)
                        .stroke(PharTheme.ColorToken.border.opacity(0.35), lineWidth: 1)
                }
                .overlay(alignment: .topLeading) {
                    PDFCanvasDecor()
                }
                .padding(PharTheme.Spacing.medium)

            PDFKitView(viewModel: viewModel)
                .clipShape(RoundedRectangle(cornerRadius: PharTheme.CornerRadius.large, style: .continuous))
                .padding(PharTheme.Spacing.medium)

            RoundedRectangle(cornerRadius: PharTheme.CornerRadius.large, style: .continuous)
                .fill(PharTheme.ColorToken.accentBlue.opacity(pageTransitionFlashOpacity))
                .padding(PharTheme.Spacing.medium)
                .allowsHitTesting(false)

            VStack(spacing: 10) {
                WritingDocumentChipStrip(chips: workspaceChips)
                chromeToolbar
                if viewModel.selectedTool == .lasso {
                    chromeAnalyzeCallout
                }
                if viewModel.isEditingInkTool {
                    chromeInkPalette
                }
                if viewModel.selectedTool == .lasso {
                    chromeSelectionBar
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

    private var chromeToolbar: some View {
        WritingChromeCapsule {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    WritingChromeIconButton(systemName: "house", accentTint: true) {
                        viewModel.saveAllOverlayPagesImmediately()
                        dismiss()
                    }

                    WritingChromeIconButton(systemName: "plus.square", accentTint: true) {
                        isShowingSectionEditor = true
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
        WritingAnalyzeHintBubble(text: "분석 받고 싶은 문제를 태깅하세요!")
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

    private var chromeSelectionBar: some View {
        WritingChromeCapsule(fill: .white) {
            HStack(spacing: 10) {
                WritingAccentActionButton(
                    title: "분석하기",
                    systemName: "waveform.path.ecg.text",
                    isEnabled: viewModel.analysisSource != nil
                ) {
                    isShowingAnalyzeSheet = true
                }

                selectionPill("복사", systemName: "doc.on.doc", isEnabled: viewModel.canCopy) {
                    viewModel.copySelection()
                }
                selectionPill("잘라내기", systemName: "scissors", isEnabled: viewModel.canCut) {
                    viewModel.cutSelection()
                }
                selectionPill("붙여넣기", systemName: "doc.on.clipboard", isEnabled: viewModel.canPaste) {
                    viewModel.pasteSelection()
                }
                selectionPill("삭제", systemName: "trash", isEnabled: viewModel.canDelete) {
                    viewModel.deleteSelection()
                }
            }
        }
    }

    private func selectionPill(_ title: String, systemName: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(WritingChromePalette.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(WritingChromePalette.paper)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(WritingChromePalette.chipBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.38)
    }

    private func toolChromeButton(_ tool: PDFEditorViewModel.AnnotationTool, icon: String) -> some View {
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
            color: viewModel.swiftUIColorForColorID(colorID),
            isSelected: viewModel.selectedColorID == colorID
        ) {
            withAnimation(PharTheme.AnimationToken.toolbarVisibility) {
                viewModel.updateSelectedColor(colorID)
            }
        }
    }

    private var workspaceStatusHeader: some View {
        PharSurfaceCard(fill: PharTheme.ColorToken.surfacePrimary.opacity(0.94)) {
            HStack(alignment: .top, spacing: PharTheme.Spacing.medium) {
                VStack(alignment: .leading, spacing: PharTheme.Spacing.xxSmall) {
                    HStack(spacing: PharTheme.Spacing.xSmall) {
                        PharTagPill(
                            text: "페이지 \(viewModel.currentPageNumber)/\(max(viewModel.pageCount, 1))",
                            tint: PharTheme.ColorToken.accentBlue.opacity(0.12),
                            foreground: PharTheme.ColorToken.accentBlue
                        )
                        PharTagPill(
                            text: viewModel.currentPageHasUnsavedChanges ? "편집 중" : "저장됨",
                            tint: viewModel.currentPageHasUnsavedChanges
                                ? PharTheme.ColorToken.accentButter.opacity(0.24)
                                : PharTheme.ColorToken.accentMint.opacity(0.28),
                            foreground: PharTheme.ColorToken.inkPrimary
                        )
                        if viewModel.isCurrentPageBookmarked {
                            PharTagPill(
                                text: "북마크",
                                tint: PharTheme.ColorToken.accentPeach.opacity(0.24),
                                foreground: PharTheme.ColorToken.inkPrimary
                            )
                        }
                    }

                    Text(pdfStatusSummary)
                        .font(PharTypography.caption)
                        .foregroundStyle(PharTheme.ColorToken.subtleText)

                    if let sectionProgressHeadline = viewModel.sectionProgressHeadline {
                        Text(sectionProgressHeadline)
                            .font(PharTypography.captionStrong)
                            .foregroundStyle(PharTheme.ColorToken.accentBlue)
                            .lineLimit(1)
                    }

                    if let sectionProgressSubheadline = viewModel.sectionProgressSubheadline {
                        Text(sectionProgressSubheadline)
                            .font(PharTypography.caption)
                            .foregroundStyle(PharTheme.ColorToken.subtleText)
                            .lineLimit(1)
                    }

                    if let currentAnalysisResult {
                        AnalysisHeaderInsightBlock(result: currentAnalysisResult)
                            .padding(.top, PharTheme.Spacing.xSmall)
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: PharTheme.Spacing.xSmall) {
                    PharToolbarIconButton(
                        systemName: "list.bullet.indent",
                        accessibilityLabel: "단원 편집"
                    ) {
                        isShowingSectionEditor = true
                    }

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

    private var pdfStatusSummary: String {
        var parts: [String] = ["입력 모드 \(viewModel.inputModeLabel)"]

        if viewModel.currentPageOverlayStrokeCount > 0 {
            parts.append("필기 흔적 \(viewModel.currentPageOverlayStrokeCount)개")
        }
        if viewModel.currentPageSearchMatchCount > 0 {
            parts.append("검색 일치 \(viewModel.currentPageSearchMatchCount)개")
        }
        if viewModel.totalSectionCount > 0 {
            parts.append("단원 \(viewModel.completedSectionCount)/\(viewModel.totalSectionCount)")
        }

        return parts.joined(separator: " · ")
    }

    private var floatingToolDock: some View {
        VStack(spacing: PharTheme.Spacing.xSmall) {
            if viewModel.isEditingInkTool {
                inkControlsBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if viewModel.selectedTool == .lasso {
                selectionActionsBar
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
                .accessibilityLabel("입력 방식 전환")
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

    private var selectionActionsBar: some View {
        PharSurfaceCard(fill: PharTheme.ColorToken.surfacePrimary.opacity(0.92)) {
            HStack(spacing: PharTheme.Spacing.xSmall) {
                selectionActionButton(title: "복사", systemName: "doc.on.doc", isEnabled: viewModel.canCopy) {
                    viewModel.copySelection()
                }
                selectionActionButton(title: "잘라내기", systemName: "scissors", isEnabled: viewModel.canCut) {
                    viewModel.cutSelection()
                }
                selectionActionButton(title: "붙여넣기", systemName: "doc.on.clipboard", isEnabled: viewModel.canPaste) {
                    viewModel.pasteSelection()
                }
                selectionActionButton(title: "삭제", systemName: "trash", isEnabled: viewModel.canDelete, isDestructive: true) {
                    viewModel.deleteSelection()
                }

                Spacer(minLength: 0)

                Text("선택 후 드래그로 이동")
                    .font(PharTypography.caption)
                    .foregroundStyle(PharTheme.ColorToken.subtleText)
            }
        }
    }

    private var workspacePanel: some View {
        PharPanelContainer {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
                HStack(alignment: .top, spacing: PharTheme.Spacing.medium) {
                    VStack(alignment: .leading, spacing: PharTheme.Spacing.xxxSmall) {
                        Text("PDF Study Rail")
                            .font(PharTypography.captionStrong)
                            .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                        Text("페이지 이동, 텍스트 검색, 결과 탐색을 한 패널에서 유지합니다.")
                            .font(PharTypography.caption)
                            .foregroundStyle(PharTheme.ColorToken.subtleText)
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: PharTheme.Spacing.xSmall) {
                        PharTagPill(text: "\(viewModel.pageCount) pages", tint: PharTheme.ColorToken.surfaceSecondary)
                        if !viewModel.pdfTextSearchResults.isEmpty {
                            PharTagPill(
                                text: "\(viewModel.pdfTextSearchResults.count) hits",
                                tint: PharTheme.ColorToken.accentButter.opacity(0.22),
                                foreground: PharTheme.ColorToken.inkPrimary
                            )
                        }
                    }
                }

                workspacePanelSection {
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

                        Text("\(viewModel.currentPageNumber)/\(max(viewModel.pageCount, 1))")
                            .font(PharTypography.numberMono)
                            .frame(width: 72, alignment: .trailing)

                        TextField("페이지", text: $viewModel.pageJumpInput)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                            .frame(width: 84)

                        Button("이동") {
                            viewModel.goToInputPage()
                        }
                        .buttonStyle(PharSoftButtonStyle())

                        Spacer(minLength: 0)

                        Text(viewModel.inputModeLabel)
                            .font(PharTypography.captionStrong)
                            .foregroundStyle(PharTheme.ColorToken.subtleText)
                    }
                }

                workspacePanelSection {
                    VStack(spacing: PharTheme.Spacing.xSmall) {
                        HStack(spacing: PharTheme.Spacing.xSmall) {
                            TextField("PDF 텍스트 검색", text: $viewModel.pdfTextSearchQuery)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    viewModel.performPDFTextSearch()
                                }

                            Button("검색") {
                                viewModel.performPDFTextSearch()
                            }
                            .buttonStyle(PharPrimaryButtonStyle())

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
                                                    .frame(maxWidth: 196, alignment: .leading)
                                            }
                                            .padding(.horizontal, PharTheme.Spacing.small)
                                            .padding(.vertical, PharTheme.Spacing.xSmall)
                                            .background(
                                                RoundedRectangle(cornerRadius: PharTheme.CornerRadius.small, style: .continuous)
                                                    .fill(
                                                        viewModel.currentPDFTextSearchResultIndex == index
                                                        ? PharTheme.ColorToken.accentBlue.opacity(0.18)
                                                        : PharTheme.ColorToken.surfaceSecondary
                                                    )
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .hoverEffect(.highlight)
                                    }
                                }
                                .padding(.vertical, PharTheme.Spacing.xxxSmall)
                            }
                        }
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: PharTheme.Spacing.small) {
                        ForEach(0..<viewModel.pageCount, id: \.self) { index in
                            Button {
                                withAnimation(PharTheme.AnimationToken.pageTransition) {
                                    viewModel.goToPage(index: index)
                                }
                            } label: {
                                PDFPageThumbnailCell(
                                    image: viewModel.thumbnail(at: index),
                                    pageNumber: index + 1,
                                    isSelected: viewModel.currentPageIndex == index,
                                    isBookmarked: viewModel.isPageBookmarked(index),
                                    isDirty: viewModel.isPageDirty(index)
                                )
                            }
                            .buttonStyle(.plain)
                            .hoverEffect(.highlight)
                            .contextMenu {
                                Button {
                                    viewModel.goToPage(index: index)
                                    viewModel.toggleCurrentPageBookmark()
                                } label: {
                                    Label(
                                        viewModel.isPageBookmarked(index) ? "북마크 해제" : "북마크 추가",
                                        systemImage: viewModel.isPageBookmarked(index) ? "bookmark.slash" : "bookmark"
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, PharTheme.Spacing.xSmall)
                    .padding(.vertical, PharTheme.Spacing.xxxSmall)
                }
                .frame(height: 156)
            }
        }
        .frame(height: 358)
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

    private func toolButton(_ tool: PDFEditorViewModel.AnnotationTool, icon: String) -> some View {
        Button {
            withAnimation(PharTheme.AnimationToken.toolbarVisibility) {
                viewModel.selectTool(tool)
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: PharTheme.Icon.toolbar, weight: .semibold))
        }
        .buttonStyle(
            PharToolbarButtonStyle(
                isSelected: viewModel.selectedTool == tool,
                isDestructive: false
            )
        )
        .accessibilityLabel("\(tool.rawValue) 도구")
    }

    private func colorButton(colorID: Int) -> some View {
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
                            viewModel.selectedColorID == colorID ? PharTheme.ColorToken.inkPrimary : Color.clear,
                            lineWidth: 2
                        )
                }
                .scaleEffect(viewModel.selectedColorID == colorID ? 1.08 : 1.0)
                .frame(minWidth: PharTheme.HitArea.minimum, minHeight: PharTheme.HitArea.minimum)
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .disabled(!viewModel.isEditingInkTool)
        .animation(.easeInOut(duration: 0.16), value: viewModel.selectedColorID)
    }

    private func widthButton(_ width: Double) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.12)) {
                viewModel.selectStrokeWidth(width)
            }
        } label: {
            Circle()
                .fill(PharTheme.ColorToken.inkPrimary.opacity(0.86))
                .frame(width: strokeDotSize(for: width), height: strokeDotSize(for: width))
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(viewModel.strokeWidth == width ? PharTheme.ColorToken.accentBlue.opacity(0.18) : Color.clear)
                )
                .frame(minWidth: PharTheme.HitArea.minimum, minHeight: PharTheme.HitArea.minimum)
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
    }

    private func selectionActionButton(
        title: String,
        systemName: String,
        isEnabled: Bool,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
        }
        .buttonStyle(isDestructive ? PharSoftButtonStyle() : PharSoftButtonStyle())
        .disabled(!isEnabled)
        .foregroundStyle(isDestructive ? PharTheme.ColorToken.destructive : PharTheme.ColorToken.inkPrimary)
    }

    private func workspacePanelSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, PharTheme.Spacing.small)
            .padding(.vertical, PharTheme.Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                    .fill(PharTheme.ColorToken.surfacePrimary.opacity(0.88))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                    .stroke(PharTheme.ColorToken.border.opacity(0.36), lineWidth: 1)
            )
    }

    private func strokeDotSize(for width: Double) -> CGFloat {
        min(max(CGFloat(width) * 1.2, 4), 14)
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

private struct PDFAnalyzePreviewSheet: View {
    @ObservedObject var viewModel: PDFEditorViewModel
    @EnvironmentObject private var analysisCenter: AnalysisCenter
    @Environment(\.dismiss) private var dismiss
    @State private var selectedStudyIntent: AnalysisStudyIntent = .problemSolving
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
                            Text("현재 PDF 페이지의 필기 오버레이, 텍스트 문맥, 탐색 신호를 묶어 pharnode 분석 번들로 준비합니다.")
                                .font(PharTypography.body)
                                .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                        }
                    }

                    PharSurfaceCard {
                        VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
                            Text("Analyze setup")
                                .font(PharTypography.cardTitle)
                                .foregroundStyle(PharTheme.ColorToken.inkPrimary)

                            PDFPreviewRow(title: "범위", value: AnalysisScope.page.title)

                            Picker("학습 의도", selection: $selectedStudyIntent) {
                                ForEach([
                                    AnalysisStudyIntent.problemSolving,
                                    .review,
                                    .summary,
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
                                PDFPreviewRow(title: "대상 페이지", value: "\(preview.pageNumber) / \(preview.totalPages)")
                                PDFPreviewRow(title: "필기 스트로크", value: "\(preview.overlayStrokeCount)")
                                PDFPreviewRow(title: "북마크", value: preview.isBookmarked ? "예" : "아니오")
                                PDFPreviewRow(title: "저장 상태", value: preview.hasUnsavedChanges ? "로컬 변경 있음" : "저장 완료")
                                PDFPreviewRow(title: "텍스트 검색 일치", value: "\(preview.currentSearchMatches)")
                                PDFPreviewRow(title: "입력 모드", value: preview.inputModeLabel)
                                PDFPreviewRow(title: "체류 시간", value: "\(source.dwellMs / 1000)초")
                                PDFPreviewRow(title: "텍스트 블록", value: "\(source.pdfTextBlocks.count)")
                                PDFPreviewRow(title: "번들 자산", value: bundleAssetSummary(for: source))
                                PDFPreviewRow(title: "최근 수정", value: preview.updatedAt.formatted(date: .abbreviated, time: .shortened))
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
                            PDFPreviewRow(title: "대기 중", value: "\(analysisCenter.queuedCount)")
                            PDFPreviewRow(title: "완료됨", value: "\(analysisCenter.completedCount)")
                            if let entry = analysisCenter.lastQueuedEntry {
                                PDFPreviewRow(title: "최근 적재", value: "\(entry.documentTitle) · \(entry.pageLabel)")
                            }
                            if let latestBundle = analysisCenter.latestBundle {
                                PDFPreviewRow(title: "최근 bundle", value: String(latestBundle.bundleId.uuidString.prefix(8)) + "…")
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
                            Text("1. 현재 PDF 페이지 또는 선택 범위 결정")
                            Text("2. overlay drawing, preview image, page text context 수집")
                            Text("3. search hit / bookmark / dwell signal 병합")
                            Text("4. AnalysisBundle 생성 후 로컬 큐 적재")
                            Text("5. 이후 pharnode 파이프라인 처리")
                        }
                        .font(PharTypography.caption)
                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                    }

                    Button {
                        Task {
                            guard let source = viewModel.analysisSource else { return }
                            await analysisCenter.enqueuePDFPage(
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

    private func bundleAssetSummary(for source: PDFPageAnalysisSource) -> String {
        let preview = source.previewImageData == nil ? "preview 없음" : "preview 포함"
        let drawing = source.drawingData == nil ? "drawing 없음" : "drawing 포함"
        return "\(preview), \(drawing)"
    }

    private func loadOCRSummary(for source: PDFPageAnalysisSource) async {
        isLoadingOCRSummary = true
        ocrSummary = await analysisCenter.ocrPreview(for: source)
        isLoadingOCRSummary = false
    }
}

private struct PDFPreviewRow: View {
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

private struct PDFSectionMappingSheet: View {
    @ObservedObject var viewModel: PDFEditorViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [PDFEditorViewModel.SectionDraft] = []
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            List {
                Section("개요") {
                    LabeledContent("전체 페이지", value: "\(max(viewModel.pageCount, 1))")
                    LabeledContent("현재 페이지", value: "\(viewModel.currentPageNumber)")
                    LabeledContent("완료 단원", value: "\(viewModel.completedSectionCount)/\(viewModel.totalSectionCount)")
                    if let currentSectionTitle = viewModel.currentSectionTitle {
                        LabeledContent("현재 단원", value: currentSectionTitle)
                    }
                    if let nextSectionTitle = viewModel.nextSectionTitle {
                        LabeledContent("다음 단원", value: nextSectionTitle)
                    }
                }

                Section("단원 매핑") {
                    ForEach(Array(drafts.enumerated()), id: \.element.id) { index, draft in
                        VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
                            HStack {
                                Text("단원 \(index + 1)")
                                    .font(PharTypography.captionStrong)
                                    .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                                Spacer(minLength: 0)
                                if drafts.count > 1 {
                                    Button(role: .destructive) {
                                        drafts.removeAll { $0.id == draft.id }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                }
                            }

                            TextField(
                                "단원 제목",
                                text: Binding(
                                    get: { drafts[index].title },
                                    set: { drafts[index].title = $0 }
                                )
                            )
                            .textInputAutocapitalization(.never)

                            Stepper(
                                value: Binding(
                                    get: { drafts[index].startPage },
                                    set: { drafts[index].startPage = $0 }
                                ),
                                in: 1...max(viewModel.pageCount, 1)
                            ) {
                                Text("시작 페이지 \(drafts[index].startPage)")
                                    .font(PharTypography.bodyStrong)
                                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                            }

                            Text("적용 범위 \(resolvedEndPage(for: index))페이지까지")
                                .font(PharTypography.caption)
                                .foregroundStyle(PharTheme.ColorToken.subtleText)
                        }
                        .padding(.vertical, PharTheme.Spacing.xxxSmall)
                    }

                    Button {
                        drafts.append(viewModel.suggestedNewSectionDraft())
                    } label: {
                        Label("현재 페이지를 새 단원 시작으로 추가", systemImage: "plus")
                    }
                }

                Section("안내") {
                    Text("단원 제목과 시작 페이지만 수정하면 나머지 페이지 범위는 자동으로 이어 붙입니다. 겹치는 시작 페이지는 저장 시 자동 정규화됩니다.")
                        .font(PharTypography.caption)
                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                }
            }
            .navigationTitle("단원 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("저장")
                        }
                    }
                    .disabled(isSaving || drafts.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            drafts = viewModel.sectionDrafts
        }
    }

    private func resolvedEndPage(for index: Int) -> Int {
        let sortedDrafts = drafts.sorted { lhs, rhs in
            if lhs.startPage == rhs.startPage {
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            return lhs.startPage < rhs.startPage
        }
        guard let sortedIndex = sortedDrafts.firstIndex(where: { $0.id == drafts[index].id }) else {
            return max(viewModel.pageCount, 1)
        }
        let nextStart = sortedIndex + 1 < sortedDrafts.count ? sortedDrafts[sortedIndex + 1].startPage : max(viewModel.pageCount, 1) + 1
        return max(min(nextStart - 1, max(viewModel.pageCount, 1)), min(max(drafts[index].startPage, 1), max(viewModel.pageCount, 1)))
    }

    private func save() {
        isSaving = true
        Task {
            let saved = await viewModel.saveSectionDrafts(drafts)
            await MainActor.run {
                isSaving = false
                if saved {
                    dismiss()
                }
            }
        }
    }
}

private struct PDFCanvasDecor: View {
    var body: some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.xxSmall) {
            Capsule(style: .continuous)
                .fill(PharTheme.ColorToken.accentBlue.opacity(0.16))
                .frame(width: 92, height: 10)
            Capsule(style: .continuous)
                .fill(PharTheme.ColorToken.accentMint.opacity(0.16))
                .frame(width: 54, height: 6)
        }
        .padding(PharTheme.Spacing.large)
        .allowsHitTesting(false)
    }
}

private struct PDFPageThumbnailCell: View {
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
                    ProgressView()
                        .controlSize(.small)
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
