import SwiftUI
import AVKit
import Combine

struct BlankNoteEditorView: View {
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var analysisCenter: AnalysisCenter
    @EnvironmentObject private var libraryViewModel: LibraryViewModel
    @StateObject private var viewModel: BlankNoteEditorViewModel
    @StateObject private var audioController: DocumentAudioController
    @StateObject private var workspaceController:
    DocumentWorkspaceController
    @StateObject private var lectureSync = LectureSyncService.shared
    @State private var player = AVPlayer()
    @State private var isBottomPanelExpanded = false
    @State private var pageTransitionFlashOpacity: Double = 0
    @State private var isShowingAnalyzeSheet = false
    @State private var isShowingShareSheet = false
    @State private var isShowingTextComposer = false
    @State private var isShowingPhotoPicker = false
    @State private var isShowingFilePicker = false
    @State private var isShowingPageStyleSheet = false
    @State private var documentBeingRenamed: PharDocument?
    @State private var imageEditorContext: WritingImageEditorContext?
    @State private var editingStrokePresetIndex: Int?
    @State private var isManagedTransition = false
    @State private var activePaletteTool: BlankNoteEditorViewModel.AnnotationTool? = nil
    @State private var isShowingEraserModePicker = false
    @State private var isShowingPageRail = false
    @State private var pageZoomScale: CGFloat = 1.0
    @GestureState private var pageMagnificationDelta: CGFloat = 1.0

    private let minPageZoomScale: CGFloat = 0.75
    private let maxPageZoomScale: CGFloat = 2.5

    init(document: PharDocument, initialPageKey: String? = nil) {
        let editorViewModel = BlankNoteEditorViewModel(
            document: document,
            initialPageKey: initialPageKey
        )
        _viewModel = StateObject(
            wrappedValue: editorViewModel
        )
        _audioController = StateObject(
            wrappedValue: DocumentAudioController(
                document: document,
                anchorProvider: {
                    DocumentAudioController.Anchor(
                        pageKey: editorViewModel.currentPageID?.uuidString.lowercased(),
                        pageLabel: "페이지 \(max(editorViewModel.currentPageNumber, 1))"
                    )
                }
            )
        )
        _workspaceController = StateObject(
            wrappedValue: DocumentWorkspaceController(
                document: document,
                anchorProvider: {
                    DocumentWorkspaceController.Anchor(
                        pageKey: editorViewModel.currentPageID?.uuidString.lowercased(),
                        pageLabel: editorViewModel.currentPageNumber > 0 ? "페이지 \(editorViewModel.currentPageNumber)" : nil
                    )
                }
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("BlankNoteInsertCapturedImage"))) { note in
            if let image = note.object as? UIImage, let data = image.pngData() {
                workspaceController.importImageData(data, suggestedFileName: "captured_board.png", preferredPlacement: nil)
            }
        }
        .task {
            viewModel.loadInitialContentIfNeeded()
            audioController.loadRecordingsIfNeeded()
            workspaceController.loadIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                viewModel.saveImmediately()
                audioController.handleBackgroundTransition()
            }
        }
        .onDisappear {
            audioController.tearDown()
            guard !isManagedTransition else { return }
            Task {
                await viewModel.closeDocument()
                libraryViewModel.loadDocuments()
            }
        }
        .onChange(of: viewModel.currentPageID) { _, _ in
            animatePageTransition()
            workspaceController.clearAttachmentSelection()
        }
        .onChange(of: viewModel.isCanvasInputEnabled) { _, isEnabled in
            if isEnabled {
                workspaceController.clearAttachmentSelection()
            }
        }
        .sheet(isPresented: $isShowingAnalyzeSheet) {
            BlankNoteAnalyzePreviewSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isShowingShareSheet) {
            WritingDocumentShareSheet(items: WritingDocumentShareSource.activityItems(for: viewModel.document))
        }
        .sheet(item: $documentBeingRenamed) { document in
            DocumentRenameSheet(
                title: document.title,
                onCancel: {
                    documentBeingRenamed = nil
                },
                onSave: { newTitle in
                    do {
                        let savedDocument = try libraryViewModel.renameDocument(document, to: newTitle)
                        if savedDocument.id == viewModel.document.id {
                            viewModel.updateDocument(savedDocument)
                        }
                    } catch {
                        viewModel.errorMessage = error.localizedDescription
                    }
                    documentBeingRenamed = nil
                }
            )
        }
        .sheet(isPresented: $isShowingTextComposer) {
            WritingTextComposerSheet(pageLabel: currentPageLabel) { text in
                workspaceController.addTextEntry(text)
                withAnimation(PharTheme.AnimationToken.toolbarVisibility) {
                    isBottomPanelExpanded = true
                }
            }
        }
        .sheet(isPresented: $isShowingPhotoPicker) {
            WritingPhotoLibraryPicker { data, fileName in
                isShowingPhotoPicker = false
                viewModel.deactivateToolSelection()
                DispatchQueue.main.async {
                    guard let draft = workspaceController.makeImageDraft(from: data, suggestedFileName: fileName) else { return }
                    imageEditorContext = WritingImageEditorContext(
                        draft: draft,
                        attachmentID: nil,
                        basePlacement: nil
                    )
                }
            } onCancel: {
                isShowingPhotoPicker = false
            }
        }
        .fullScreenCover(item: $imageEditorContext) { context in
            WritingImageInsertionEditorSheet(
                draft: context.draft,
                basePlacement: context.basePlacement
            ) { data, fileName, placement in
                if let attachmentID = context.attachmentID {
                    workspaceController.replaceImageAttachmentData(
                        id: attachmentID,
                        data: data,
                        suggestedFileName: fileName,
                        preferredPlacement: placement
                    )
                } else {
                    workspaceController.importImageData(
                        data,
                        suggestedFileName: fileName,
                        preferredPlacement: placement
                    )
                }
            }
        }
        .sheet(isPresented: $isShowingFilePicker) {
            WritingAttachmentFilePicker { url in
                isShowingFilePicker = false
                workspaceController.importFile(from: url)
                withAnimation(PharTheme.AnimationToken.toolbarVisibility) {
                    isBottomPanelExpanded = true
                }
            } onCancel: {
                isShowingFilePicker = false
            }
        }
        .sheet(isPresented: $isShowingPageStyleSheet) {
            BlankNotePageStyleSheet(viewModel: viewModel)
        }
        .alert("오류", isPresented: isErrorPresented) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("오디오 오류", isPresented: isAudioErrorPresented) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(audioController.errorMessage ?? "")
        }
        .alert("첨부 오류", isPresented: isWorkspaceErrorPresented) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(workspaceController.errorMessage ?? "")
        }
    }

    private var currentAnalysisResult: AnalysisResult? {
        guard let pageId = viewModel.currentAnalysisPageID else { return nil }
        return analysisCenter.result(for: viewModel.document.id, pageId: pageId)
    }

    private var editorCanvas: some View {
        GeometryReader { geometry in
            let pageWidth = min(772, max(640, geometry.size.width - 110))
            let paperSize = viewModel.currentPagePaperSize
            let pageHeight = pageWidth * paperSize.aspectRatio
            let railWidth = min(344, max(284, geometry.size.width * 0.28))
            let railTrailingPadding = max(16, geometry.safeAreaInsets.trailing + 16)

            ZStack(alignment: .top) {
                WritingChromePalette.paper.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: true) {
                    HStack(spacing: 24) {
                        // 기존 고정 인강 영역 제거
                        
                        VStack(spacing: 28) {
                            zoomableEditorPage(width: pageWidth, height: pageHeight)

                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.white.opacity(0.78))
                                .frame(width: pageWidth, height: 170)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .stroke(Color.black.opacity(0.03), lineWidth: 1)
                                )
                                .shadow(color: Color.black.opacity(0.04), radius: 7, x: 0, y: 4)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 166)
                    .padding(.bottom, 120)
                }
                .frame(maxWidth: .infinity)
                .scaleEffect(isShowingPageRail ? 0.988 : 1.0, anchor: .center)
                .animation(.easeInOut(duration: 0.18), value: isShowingPageRail)

                if isShowingPageRail {
                    pageRailPanel(width: railWidth)
                        .frame(maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.trailing, railTrailingPadding)
                        .padding(.top, 74)
                        .transition(.opacity)
                }

                VStack(spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        backToHomeButton
                        WritingDocumentChipStrip(
                            chips: workspaceChips,
                            onSelect: handleWorkspaceChipSelection,
                            onClose: handleWorkspaceChipClose,
                            onRename: { documentID in
                                guard documentID == viewModel.document.id else { return }
                                documentBeingRenamed = viewModel.document
                            }
                        )
                    }
                    chromeToolbar
                    if viewModel.isToolSelected(.lasso) {
                        chromeAnalyzeCallout
                    }
                }
                .padding(.top, 18)
                .padding(.horizontal, 28)

                if viewModel.isShowingNudge, let nodeId = viewModel.nudgeNodeId {
                    VStack {
                        Spacer()
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("혹시 이 부분이 헷갈리시나요?")
                                    .font(.subheadline)
                                    .bold()
                                    .foregroundStyle(WritingChromePalette.ink)
                                Text("관련 개념 검색 없이 바로 보기: \(nodeId)")
                                    .font(.caption)
                                    .foregroundStyle(WritingChromePalette.ink.opacity(0.8))
                            }
                            Spacer()
                            Button("보기") {
                                withAnimation {
                                    viewModel.isShowingNudge = false
                                }
                                // 노드 상세 보기 로집 연결
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(WritingChromePalette.hintFill)
                        )
                        .padding(.horizontal, 28)
                        .padding(.bottom, 100)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                
                // Floating Lecture Browser overlay
                if viewModel.isLectureModeEnabled {
                    LectureFloatingBrowserView(viewModel: viewModel)
                        .transition(.scale.combined(with: .opacity))
                }

                if viewModel.isHighlightStructurePanelVisible {
                    HStack {
                        Spacer(minLength: 0)
                        highlightStructureSidebar
                    }
                    .padding(.top, 132)
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
    }

    private func pageRailPanel(width: CGFloat) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: 14),
            GridItem(.flexible(), spacing: 14)
        ]

        return VStack(spacing: 12) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    pageRailTabChip(
                        title: viewModel.document.title,
                        subtitle: "\(viewModel.pages.count) pages",
                        isSelected: true
                    )

                    pageRailTabChip(
                        title: "페이지",
                        subtitle: "미리보기",
                        isSelected: false
                    )

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)

                HStack(spacing: 10) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isShowingPageRail = false
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(WritingChromePalette.accent)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)

                    railToolbarButton(systemName: "plus.square") {
                        viewModel.addPage()
                    }

                    railToolbarButton(systemName: "trash") {
                        viewModel.deleteCurrentPage()
                    }

                    Spacer(minLength: 0)

                    Text("현재 \(viewModel.currentPageNumber)/\(max(viewModel.pages.count, 1))")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.52))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(0.05))
                        )
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 2)
            }
            .padding(.top, 12)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(viewModel.pages) { page in
                        Button {
                            viewModel.selectPage(page.id)
                        } label: {
                            PageRailCell(
                                pageNumber: viewModel.pageNumber(for: page.id),
                                thumbnail: viewModel.thumbnail(for: page.id),
                                isSelected: viewModel.currentPageID == page.id,
                                isBookmarked: viewModel.isPageBookmarked(page.id)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.18), lineWidth: 1.1)
        )
        .shadow(color: Color.black.opacity(0.16), radius: 18, x: -2, y: 8)
        .padding(.bottom, 16)
    }

    private func pageRailTabChip(title: String, subtitle: String, isSelected: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? .white : WritingChromePalette.ink.opacity(0.72))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? .white.opacity(0.82) : Color.black.opacity(0.32))
                    .lineLimit(1)
            }

            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isSelected ? .white : Color.black.opacity(0.3))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(isSelected ? WritingChromePalette.accent : Color.black.opacity(0.05))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(isSelected ? WritingChromePalette.accent : Color.black.opacity(0.14), lineWidth: 1)
        )
    }

    private func railToolbarButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WritingChromePalette.accent)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(WritingChromePalette.accent.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }

    private var pageMagnificationGesture: some Gesture {
        MagnificationGesture()
            .updating($pageMagnificationDelta) { value, state, _ in
                state = value
            }
            .onEnded { value in
                let nextScale = pageZoomScale * value
                pageZoomScale = min(max(nextScale, minPageZoomScale), maxPageZoomScale)
            }
    }

    private func zoomableEditorPage(width: CGFloat, height: CGFloat) -> some View {
        let effectiveScale = min(max(pageZoomScale * pageMagnificationDelta, minPageZoomScale), maxPageZoomScale)
        let scaledWidth = width * effectiveScale
        let scaledHeight = height * effectiveScale

        return editorPage(width: width, height: height)
            .scaleEffect(effectiveScale, anchor: .topLeading)
            .frame(width: scaledWidth, height: scaledHeight, alignment: .topLeading)
            .simultaneousGesture(pageMagnificationGesture)
    }

    private func editorPage(width: CGFloat, height: CGFloat) -> some View {
        let paperSize = viewModel.currentPagePaperSize
        let backgroundStyle = viewModel.currentPageBackgroundStyle

        return ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(backgroundStyle.surfaceColor)
                .overlay {
                    BlankNotePaperPatternView(style: backgroundStyle)
                        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                }
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)

            DocumentWorkspaceAttachmentCanvasLayer(
                controller: workspaceController,
                pageKey: viewModel.currentPageID?.uuidString.lowercased(),
                allowsInteraction: !viewModel.isCanvasInputEnabled
            ) { attachmentID in
                viewModel.deactivateToolSelection()
                imageEditorContext = workspaceController.makeImageEditorContext(for: attachmentID)
            }

            if viewModel.isBindingEvidence {
                Color.black.opacity(0.4)
                    .allowsHitTesting(false)
            }

            PencilCanvasView(viewModel: viewModel)
                .background(Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            
            LiveTextEditingLayer(viewModel: viewModel)
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                .allowsHitTesting(viewModel.selectedTool == .text || viewModel.activeTextElementID != nil)

            if viewModel.isBindingEvidence {
                VStack {
                    Text("해당 사고를 적은 수식을 탭하거나 동그라미 치세요")
                        .font(PharTypography.captionStrong)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.75), in: Capsule())
                        .padding(.top, 24)
                    Spacer()
                }
                .allowsHitTesting(false)
            }

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(PharTheme.ColorToken.accentBlue.opacity(pageTransitionFlashOpacity))
                .allowsHitTesting(false)
        }
        .frame(width: width, height: height)
        .overlay(alignment: .topLeading) {
            HStack(spacing: 8) {
                Text(paperSize.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.56))

                Text(backgroundStyle.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.38))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.62))
            )
            .padding(.leading, 14)
            .padding(.top, 14)
            .allowsHitTesting(false)
        }
        .onTapGesture { point in
            if viewModel.selectedTool == .text {
                viewModel.addTextElement(at: point)
            } else {
                viewModel.activeTextElementID = nil
            }
        }
    }

    private struct PageRailCell: View {
        let pageNumber: Int
        let thumbnail: UIImage?
        let isSelected: Bool
        let isBookmarked: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("\(pageNumber)")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(WritingChromePalette.ink)

                    Spacer(minLength: 0)

                    if isBookmarked {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(WritingChromePalette.accent)
                    }
                }

                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.white)
                        .frame(height: 162)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .stroke(isSelected ? WritingChromePalette.accent : Color.black.opacity(0.26), lineWidth: isSelected ? 2 : 1)
                        )
                        .shadow(color: Color.black.opacity(isSelected ? 0.12 : 0.05), radius: isSelected ? 10 : 5, x: 0, y: 3)

                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                            .padding(4)
                    }

                    Image(systemName: "tag.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.18))
                        .padding(8)
                        .opacity(0.85)
                }
            }
            .padding(.bottom, 2)
        }
    }

    private var chromeToolbar: some View {
        WritingChromeCapsule {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    WritingChromeIconButton(systemName: "chevron.backward", accentTint: true) {
                        handleBackAction()
                    }

                    WritingChromeIconButton(systemName: "plus.square", accentTint: true) {
                        viewModel.addPage()
                    }

                    WritingToolbarDivider()

                    toolChromeButton(.pen, icon: "pencil.tip")
                    toolChromeButton(.highlighter, icon: "highlighter")
                    toolChromeButton(.paint, icon: "paintbrush")
                    toolChromeButton(.eraser, icon: "eraser")
                    toolChromeButton(.lasso, icon: "lasso")
                    toolChromeButton(.text, icon: "textformat")
                    toolChromeButton(.tape, icon: "tape")
                    WritingChromeIconButton(
                        systemName: audioController.isRecording ? "stop.circle.fill" : "mic.fill",
                        accentTint: true,
                        isSelected: audioController.isRecording
                    ) {
                        audioController.toggleRecording()
                    }
                    WritingChromeIconButton(systemName: "photo.badge.plus", accentTint: true) {
                        isShowingPhotoPicker = true
                    }
                    WritingChromeIconButton(systemName: "doc.on.clipboard", accentTint: true) {
                        handlePasteImageAction()
                    }
                    WritingChromeIconButton(systemName: "paperclip", accentTint: true) {
                        isShowingFilePicker = true
                    }
                    WritingChromeIconButton(
                        systemName: "square.grid.2x2",
                        accentTint: true
                    ) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isShowingPageRail.toggle()
                        }
                    }
                    WritingChromeIconButton(
                        systemName: "square.stack.3d.up.fill",
                        accentTint: true,
                        isSelected: viewModel.isHighlightStructurePanelVisible
                    ) {
                        withAnimation(PharTheme.AnimationToken.toolbarVisibility) {
                            viewModel.toggleHighlightStructurePanel()
                        }
                    }
                    WritingChromeIconButton(
                        systemName: "doc.text",
                        accentTint: true
                    ) {
                        isShowingPageStyleSheet = true
                    }

                    if viewModel.isToolSelected(.lasso) {
                        WritingChromeIconButton(
                            systemName: "waveform.path.ecg.text",
                            accentTint: true,
                            isSelected: true,
                            isEnabled: viewModel.canAnalyzeCurrentSelection
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
                    
                    WritingToolbarDivider()
                    
                    WritingChromeIconButton(
                        systemName: "video.fill",
                        accentTint: true,
                        isSelected: viewModel.isLectureModeEnabled
                    ) {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                            viewModel.isLectureModeEnabled.toggle()
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var backToHomeButton: some View {
        Button {
            handleBackAction()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                Text("홈")
            }
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundStyle(WritingChromePalette.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.94))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(WritingChromePalette.chromeBorder, lineWidth: 1.2)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("홈으로 돌아가기")
    }

    private var chromeAnalyzeCallout: some View {
        VStack(spacing: 10) {
            WritingAnalyzeHintBubble(text: "분석 받고 싶은 문제를 태깅하세요!")

            WritingAccentActionButton(
                title: "분석하기",
                systemName: "waveform.path.ecg.text",
                isEnabled: viewModel.canAnalyzeCurrentSelection
            ) {
                isShowingAnalyzeSheet = true
            }
        }
    }

    private var chromeInkPalette: some View {
        WritingChromeCapsule(fill: WritingChromePalette.paletteFill) {
            VStack(alignment: .leading, spacing: 10) {
                if viewModel.isToolSelected(.highlighter) {
                    HighlightStructurePaletteView(
                        mode: Binding(
                            get: { viewModel.highlightMode },
                            set: { viewModel.selectHighlightMode($0) }
                        ),
                        selectedRole: Binding(
                            get: { viewModel.selectedHighlightRole },
                            set: { viewModel.selectHighlightRole($0) }
                        ),
                        colorBinding: { role in
                            viewModel.highlightColorBinding(for: role)
                        }
                    )

                    if viewModel.highlightMode == .structured {
                        HStack(spacing: 10) {
                            ForEach(Array(viewModel.strokePresetConfiguration.values.enumerated()), id: \.offset) { index, width in
                                WritingStrokePresetButton(
                                    slotIndex: index,
                                    width: CGFloat(width),
                                    isSelected: viewModel.strokePresetConfiguration.selectedIndex == index
                                ) {
                                    viewModel.selectStrokePreset(at: index)
                                } onLongPress: {
                                    editingStrokePresetIndex = index
                                }
                            }
                        }
                    } else {
                        HStack(spacing: 10) {
                            ForEach(Array(viewModel.strokePresetConfiguration.values.enumerated()), id: \.offset) { index, width in
                                WritingStrokePresetButton(
                                    slotIndex: index,
                                    width: CGFloat(width),
                                    isSelected: viewModel.strokePresetConfiguration.selectedIndex == index
                                ) {
                                    viewModel.selectStrokePreset(at: index)
                                } onLongPress: {
                                    editingStrokePresetIndex = index
                                }
                            }

                            WritingToolbarDivider()

                            colorSwatchButton(3)
                            colorSwatchButton(2)
                            colorSwatchButton(0)
                            colorSwatchButton(4)

                            ForEach(Array(viewModel.savedColorPresets.enumerated()), id: \.offset) { index, uiColor in
                                WritingColorSwatchButton(
                                    color: Color(uiColor: uiColor),
                                    isSelected: viewModel.dynamicColor == uiColor && viewModel.selectedColorID == 999
                                ) {
                                    viewModel.dynamicColor = uiColor
                                    viewModel.updateSelectedColor(999)
                                }
                                .onLongPressGesture {
                                    viewModel.removeColorPreset(at: index)
                                }
                            }

                            HStack(spacing: 0) {
                                ColorPicker("", selection: Binding(
                                    get: { Color(uiColor: viewModel.dynamicColor ?? .black) },
                                    set: { newColor in
                                        viewModel.dynamicColor = UIColor(newColor)
                                        viewModel.updateSelectedColor(999)
                                    }
                                ))
                                .labelsHidden()
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                                .overlay(
                                    Circle().stroke(Color.black.opacity(0.15), lineWidth: 1)
                                )

                                if viewModel.selectedColorID == 999 && viewModel.dynamicColor != nil {
                                    Button {
                                        viewModel.saveCurrentDynamicColor()
                                    } label: {
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundStyle(WritingChromePalette.accent)
                                            .font(.system(size: 14))
                                            .offset(x: -8, y: -8)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if viewModel.isToolSelected(.pen) {
                    HStack(spacing: 8) {
                        ForEach(WritingPenStyle.allCases) { penStyle in
                            WritingPenStyleButton(
                                title: penStyle.rawValue,
                                systemName: penStyle.systemImage,
                                isSelected: viewModel.selectedPenStyle == penStyle
                            ) {
                                withAnimation(PharTheme.AnimationToken.toolbarVisibility) {
                                    viewModel.selectPenStyle(penStyle)
                                }
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        ForEach(Array(viewModel.strokePresetConfiguration.values.enumerated()), id: \.offset) { index, width in
                            WritingStrokePresetButton(
                                slotIndex: index,
                                width: CGFloat(width),
                                isSelected: viewModel.strokePresetConfiguration.selectedIndex == index
                            ) {
                                viewModel.selectStrokePreset(at: index)
                            } onLongPress: {
                                editingStrokePresetIndex = index
                            }
                        }

                        WritingToolbarDivider()

                        colorSwatchButton(3)
                        colorSwatchButton(2)
                        colorSwatchButton(0)
                        colorSwatchButton(4)

                        ForEach(Array(viewModel.savedColorPresets.enumerated()), id: \.offset) { index, uiColor in
                            WritingColorSwatchButton(
                                color: Color(uiColor: uiColor),
                                isSelected: viewModel.dynamicColor == uiColor && viewModel.selectedColorID == 999
                            ) {
                                viewModel.dynamicColor = uiColor
                                viewModel.updateSelectedColor(999)
                            }
                            .onLongPressGesture {
                                viewModel.removeColorPreset(at: index)
                            }
                        }

                        HStack(spacing: 0) {
                            ColorPicker("", selection: Binding(
                                get: { Color(uiColor: viewModel.dynamicColor ?? .black) },
                                set: { newColor in
                                    viewModel.dynamicColor = UIColor(newColor)
                                    viewModel.updateSelectedColor(999)
                                }
                            ))
                            .labelsHidden()
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                            .overlay(
                                Circle().stroke(Color.black.opacity(0.15), lineWidth: 1)
                            )

                            if viewModel.selectedColorID == 999 && viewModel.dynamicColor != nil {
                                Button {
                                    viewModel.saveCurrentDynamicColor()
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(WritingChromePalette.accent)
                                        .font(.system(size: 14))
                                        .offset(x: -8, y: -8)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: 508)
        .popover(
            isPresented: Binding(
                get: { editingStrokePresetIndex != nil },
                set: { isPresented in
                    if !isPresented {
                        editingStrokePresetIndex = nil
                    }
                }
            ),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            if let editingStrokePresetIndex {
                WritingStrokePresetEditorView(
                    slotIndex: editingStrokePresetIndex,
                    width: strokePresetBinding(for: editingStrokePresetIndex)
                )
                .presentationCompactAdaptation(.popover)
            }
        }
    }

    private var chromePaintPalette: some View {
        WritingChromeCapsule(fill: WritingChromePalette.paletteFill) {
            HStack(spacing: 10) {
                colorSwatchButton(3)
                colorSwatchButton(2)
                colorSwatchButton(0)
                colorSwatchButton(4)

                ColorPicker("", selection: Binding(
                    get: { Color(uiColor: viewModel.dynamicColor ?? .black) },
                    set: { newColor in
                        viewModel.dynamicColor = UIColor(newColor)
                        viewModel.updateSelectedColor(999)
                    }
                ))
                .labelsHidden()
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(Color.black.opacity(0.15), lineWidth: 1)
                )
                .buttonStyle(.plain)
            }
        }
        .frame(minWidth: 200)
    }

    private func toolChromeButton(_ tool: BlankNoteEditorViewModel.AnnotationTool, icon: String) -> some View {
        WritingChromeIconButton(
            systemName: icon,
            isSelected: viewModel.isToolSelected(tool)
        ) {
            withAnimation(PharTheme.AnimationToken.toolbarVisibility) {
                if viewModel.isToolSelected(tool) {
                    activePaletteTool = nil
                    viewModel.deactivateToolSelection()
                } else {
                    viewModel.selectTool(tool)
                    if tool == .pen || tool == .highlighter || tool == .paint || tool == .tape {
                        activePaletteTool = tool
                    } else {
                        activePaletteTool = nil
                    }
                }
            }
        }
        .popover(
            isPresented: Binding(
                get: { activePaletteTool == tool },
                set: { isOpen in
                    if !isOpen && activePaletteTool == tool {
                        activePaletteTool = nil
                    }
                }
            ),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            if tool == .paint {
                chromePaintPalette
                    .padding(8)
                    .presentationCompactAdaptation(.popover)
            } else if tool == .tape {
                chromeTapePalette
                    .padding(8)
                    .presentationCompactAdaptation(.popover)
            } else {
                chromeInkPalette
                    .padding(8)
                    .presentationCompactAdaptation(.popover)
            }
        }
    }

    private var chromeTapePalette: some View {
        WritingChromeCapsule(fill: WritingChromePalette.paletteFill) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "tape")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(WritingChromePalette.ink)
                    
                    Text("암기 테이프")
                        .font(PharTypography.captionStrong)
                        .foregroundStyle(WritingChromePalette.ink)
                    
                    Spacer()
                }
                .padding(.horizontal, 4)

                HStack(spacing: 10) {
                    ForEach(Array(viewModel.strokePresetConfiguration.values.enumerated()), id: \.offset) { index, width in
                        WritingStrokePresetButton(
                            slotIndex: index,
                            width: CGFloat(width * 2.0), // Show thicker for tape
                            isSelected: viewModel.strokePresetConfiguration.selectedIndex == index
                        ) {
                            viewModel.selectStrokePreset(at: index)
                        } onLongPress: {
                            editingStrokePresetIndex = index
                        }
                    }
                }
            }
        }
        .frame(width: 200)
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

    private var lectureArea: some View {
        VStack(spacing: 20) {
            VideoPlayer(player: player)
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
                .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
                    lectureSync.updateTimestamp(player.currentTime().seconds)
                }

            HStack {
                Button(action: captureSmartLayer) {
                    Label("스마트 레이어 캡처", systemImage: "plus.viewfinder")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(WritingChromePalette.accent)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                
                Spacer()
                
                if let nodeId = lectureSync.activeNode?.conceptNodeId {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("현재 개념")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(WritingChromePalette.ink.opacity(0.6))
                        Text(nodeId)
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(WritingChromePalette.ink)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .onAppear {
            setupPlayer()
            startSyncCheck()
        }
    }

    private func setupPlayer() {
        // 실제 운영 환경에서는 document와 연결된 영상 URL을 로드
        lectureSync.startSession(sessionId: viewModel.document.title, initialNodes: [])
    }

    private func captureSmartLayer() {
        Task {
            do {
                let cleanedImage = try await SmartLayerCaptureService.shared.captureAndCleanBoard(from: player)
                viewModel.insertCapturedImage(cleanedImage)
                print("[SmartLayer] Capture succeeded.")
            } catch {
                print("[SmartLayer] Capture failed: \(error)")
                viewModel.errorMessage = "판서 추출에 실패했습니다."
            }
        }
    }

    private func startSyncCheck() {
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { @MainActor in
                let stats = AnalysisDrawingStats(
                    strokeCount: viewModel.currentPageStrokeCount,
                    inkLengthEstimate: 100,
                    eraseRatio: 0,
                    highlightCoverage: 0,
                    activeWritingTime: 5,
                    pauseTime: 20 
                )
                
                if let nodeId = lectureSync.detectStallAndNudge(stats: stats, isWriting: false) {
                    withAnimation(.spring()) {
                        viewModel.nudgeNodeId = nodeId
                        viewModel.isShowingNudge = true
                    }
                }
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
                eraserToolButton
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

                Text(viewModel.currentToolLabel)
                    .font(PharTypography.captionStrong)
                    .foregroundStyle(PharTheme.ColorToken.subtleText)
            }
        }
    }

    private var eraserModePicker: some View {
        WritingEraserModePickerView(
            selectedMode: Binding(
                get: { viewModel.selectedEraserMode },
                set: { newMode in
                    viewModel.selectEraserMode(newMode)
                }
            ),
            onSelect: {
                isShowingEraserModePicker = false
            }
        )
        .presentationCompactAdaptation(.popover)
    }

    private var eraserToolButton: some View {
        Button {
            withAnimation(PharTheme.AnimationToken.toolbarVisibility) {
                if !viewModel.isToolSelected(.eraser) {
                    viewModel.selectTool(.eraser)
                }
                isShowingEraserModePicker = true
            }
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 2) {
                    Image(systemName: "eraser.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .offset(y: 1)
                }
                Text("지우개")
                    .font(PharTypography.eyebrow)
            }
            .frame(minWidth: 58, minHeight: PharTheme.HitArea.comfortable)
            .foregroundStyle(viewModel.isToolSelected(.eraser) ? PharTheme.ColorToken.accentBlue : PharTheme.ColorToken.inkPrimary)
            .background(
                RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                    .fill(viewModel.isToolSelected(.eraser) ? PharTheme.ColorToken.accentBlue.opacity(0.14) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .popover(
            isPresented: $isShowingEraserModePicker,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            eraserModePicker
        }
        .onChange(of: viewModel.selectedTool) { _, newTool in
            if newTool != .eraser {
                isShowingEraserModePicker = false
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

                DocumentAudioPanelView(controller: audioController)

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

    private var isAudioErrorPresented: Binding<Bool> {
        Binding(
            get: { audioController.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    audioController.errorMessage = nil
                }
            }
        )
    }

    private var isWorkspaceErrorPresented: Binding<Bool> {
        Binding(
            get: { workspaceController.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    workspaceController.errorMessage = nil
                }
            }
        )
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

    private var workspaceChips: [WritingWorkspaceDocumentChip] {
        libraryViewModel.workspaceDocumentChips(currentDocument: viewModel.document)
    }

    private func strokePresetBinding(for index: Int) -> Binding<Double> {
        Binding(
            get: { viewModel.strokePresetConfiguration.values[index] },
            set: { newValue in
                viewModel.updateStrokePreset(newValue, at: index)
            }
        )
    }

    private var currentPageLabel: String? {
        viewModel.currentPageNumber > 0 ? "페이지 \(viewModel.currentPageNumber)" : nil
    }

    private func handleBackAction() {
        navigateBackPreservingCurrentTab()
    }

    private func navigateBackPreservingCurrentTab() {
        isManagedTransition = true
        audioController.tearDown()
        presentationMode.wrappedValue.dismiss()

        Task {
            await viewModel.closeDocument()
            libraryViewModel.loadDocuments()
        }
    }

    private func closeCurrentWorkspaceTab() {
        isManagedTransition = true
        audioController.tearDown()
        
        let documentID = viewModel.document.id
        if libraryViewModel.openDocumentTabs.contains(where: { $0.document.id == documentID }) {
            libraryViewModel.closeDocumentTab(documentID)
        } else {
            presentationMode.wrappedValue.dismiss()
        }

        Task {
            await viewModel.closeDocument()
            libraryViewModel.loadDocuments()
        }
    }

    private func handleWorkspaceChipSelection(_ documentID: UUID) {
        guard documentID != viewModel.document.id else { return }

        Task {
            isManagedTransition = true
            audioController.tearDown()
            await viewModel.closeDocument()
            libraryViewModel.loadDocuments()
            libraryViewModel.activateDocumentTab(documentID)
        }
    }

    private func handleWorkspaceChipClose(_ documentID: UUID) {
        guard documentID != viewModel.document.id else {
            closeCurrentWorkspaceTab()
            return
        }
        libraryViewModel.closeDocumentTab(documentID)
    }

    private func handlePasteImageAction() {
        viewModel.deactivateToolSelection()
        guard let draft = workspaceController.pastedImageDraft() else { return }
        imageEditorContext = WritingImageEditorContext(
            draft: draft,
            attachmentID: nil,
            basePlacement: nil
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
            .foregroundStyle(viewModel.isToolSelected(tool) ? PharTheme.ColorToken.accentBlue : PharTheme.ColorToken.inkPrimary)
            .background(
                RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                    .fill(viewModel.isToolSelected(tool) ? PharTheme.ColorToken.accentBlue.opacity(0.14) : Color.clear)
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

    private var highlightStructureSidebar: some View {
        HighlightStructureSidebarView(snapshot: viewModel.currentHighlightSnapshot) { role in
            if viewModel.highlightMode != .structured {
                viewModel.selectHighlightMode(.structured)
            }
            viewModel.selectHighlightRole(role)
            if !viewModel.isToolSelected(.highlighter) {
                viewModel.selectTool(.highlighter)
            }
        }
        .frame(width: 320)
    }
}

#Preview("BlankNoteEditor") {
    NavigationStack {
        BlankNoteEditorView(document: PreviewDocumentFactory.blankNoteDocument())
    }
    .environmentObject(LibraryViewModel())
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

private struct BlankNotePaperPatternView: View {
    let style: BlankNoteBackgroundStyle

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                drawPattern(in: context, size: size, style: style)
            }
            .opacity(style.patternOpacity)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
    }

    private func drawPattern(in context: GraphicsContext, size: CGSize, style: BlankNoteBackgroundStyle) {
        let minorColor = style.patternColor
        let majorColor = style.patternColor.opacity(0.45)
        let lineWidth: CGFloat = 1
        let horizontalStep: CGFloat = style == .ruled ? 30 : 28
        let dotStep: CGFloat = 18

        switch style {
        case .plain:
            break
        case .ruled:
            for y in stride(from: horizontalStep * 1.8, through: size.height, by: horizontalStep) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(minorColor), lineWidth: lineWidth)
            }
        case .grid:
            for y in stride(from: 0, through: size.height, by: horizontalStep) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(minorColor), lineWidth: lineWidth)
            }
            for x in stride(from: 0, through: size.width, by: horizontalStep) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(minorColor), lineWidth: lineWidth)
            }
            for x in stride(from: 0, through: size.width, by: horizontalStep * 5) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(majorColor), lineWidth: 1.1)
            }
            for y in stride(from: 0, through: size.height, by: horizontalStep * 5) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(majorColor), lineWidth: 1.1)
            }
        case .dotGrid:
            for x in stride(from: 0, through: size.width, by: dotStep) {
                for y in stride(from: 0, through: size.height, by: dotStep) {
                    let rect = CGRect(x: x - 1, y: y - 1, width: 2, height: 2)
                    context.fill(Path(ellipseIn: rect), with: .color(minorColor))
                }
            }
        }
    }
}

private struct BlankNotePageStyleSheet: View {
    @ObservedObject var viewModel: BlankNoteEditorViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    styleSection(
                        title: "페이지 용지",
                        subtitle: "현재 페이지의 비율과 여백 감각을 바꿉니다.",
                        content: {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 12)], spacing: 12) {
                                ForEach(BlankNotePaperSize.allCases, id: \.self) { size in
                                    StyleOptionTile(
                                        title: size.title,
                                        subtitle: size.subtitle,
                                        isSelected: viewModel.currentPagePaperSize == size,
                                        preview: {
                                            PaperPreviewShape(
                                                aspectRatio: size.aspectRatio,
                                                accent: viewModel.currentPagePaperSize == size ? WritingChromePalette.accent : Color.black.opacity(0.18)
                                            )
                                        }
                                    ) {
                                        viewModel.updateCurrentPagePaperSize(size)
                                    }
                                }
                            }
                        }
                    )

                    styleSection(
                        title: "노트 배경",
                        subtitle: "굿노트처럼 무지, 줄, 격자, 도트 배경을 고릅니다.",
                        content: {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 12)], spacing: 12) {
                                ForEach(BlankNoteBackgroundStyle.allCases, id: \.self) { style in
                                    StyleOptionTile(
                                        title: style.title,
                                        subtitle: style.subtitle,
                                        isSelected: viewModel.currentPageBackgroundStyle == style,
                                        preview: {
                                            PaperBackgroundPreview(style: style)
                                        }
                                    ) {
                                        viewModel.updateCurrentPageBackgroundStyle(style)
                                    }
                                }
                            }
                        }
                    )
                }
                .padding(20)
            }
            .background(PharTheme.ColorToken.appBackground.ignoresSafeArea())
            .navigationTitle("페이지 스타일")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func styleSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(PharTheme.ColorToken.inkSecondary)
            }

            content()
        }
    }
}

private struct StyleOptionTile<Preview: View>: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let preview: () -> Preview
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                preview()
                    .frame(height: 76)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? WritingChromePalette.accent : Color.black.opacity(0.10), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: Color.black.opacity(isSelected ? 0.12 : 0.04), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

private struct PaperPreviewShape: View {
    let aspectRatio: CGFloat
    let accent: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(accent.opacity(0.8), lineWidth: 1.5)
            )
            .overlay {
                VStack(spacing: 6) {
                    Rectangle().fill(accent.opacity(0.22)).frame(height: 2)
                    Rectangle().fill(accent.opacity(0.12)).frame(height: 2)
                    Rectangle().fill(accent.opacity(0.08)).frame(height: 2)
                }
                .padding(14)
            }
            .aspectRatio(aspectRatio, contentMode: .fit)
    }
}

private struct PaperBackgroundPreview: View {
    let style: BlankNoteBackgroundStyle

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(style.surfaceColor)
            .overlay {
                BlankNotePaperPatternView(style: style)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct BlankNoteAnalyzePreviewSheet: View {
    @ObservedObject var viewModel: BlankNoteEditorViewModel
    @EnvironmentObject private var analysisCenter: AnalysisCenter
    @Environment(\.dismiss) private var dismiss
    @State private var selectedStudyIntent: AnalysisStudyIntent = .summary
    @State private var ocrSummary: OCRPreviewSummary?
    @State private var isLoadingOCRSummary = false
    @State private var reviewDraft: AnalysisPostSolveReviewDraft
    @State private var isReviewFlowComplete = false

    init(viewModel: BlankNoteEditorViewModel) {
        self.viewModel = viewModel
        _reviewDraft = State(
            initialValue: AnalysisPostSolveReviewDraft(
                subject: viewModel.document.studyMaterial?.subject
            )
        )
    }

    private var currentResult: AnalysisResult? {
        guard let pageId = viewModel.currentAnalysisPageID else { return nil }
        return analysisCenter.result(for: viewModel.document.id, pageId: pageId)
    }

    @State private var sheetDetent: PresentationDetent = .large

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

                            PreviewRow(title: "범위", value: viewModel.currentAnalysisScope.title)

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

                    AnalysisPostSolveReviewSection(
                        draft: $reviewDraft,
                        isComplete: $isReviewFlowComplete,
                        onBindEvidence: { stepId, callback in
                            viewModel.evidenceBindingStepId = stepId
                            viewModel.onEvidenceBound = { strokeId, delayMs in
                                callback(strokeId, delayMs)
                                viewModel.isBindingEvidence = false
                                viewModel.evidenceBindingStepId = nil
                            }
                            viewModel.isBindingEvidence = true
                        }
                    )

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

                    if !isReviewFlowComplete {
                        Text("확신도부터 단계별 복기를 마치면 분석 번들 적재가 열립니다.")
                            .font(PharTypography.caption)
                            .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                    }

                    Button {
                        Task {
                            guard var source = viewModel.analysisSource else { return }
                            source.postSolveReview = reviewDraft.makePayload()
                            await analysisCenter.enqueueBlankNote(
                                source: source,
                                scope: viewModel.currentAnalysisScope,
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
                    .disabled(
                        analysisCenter.isEnqueuing
                            || viewModel.analysisSource == nil
                            || !isReviewFlowComplete
                    )

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
        .presentationDetents([.fraction(0.35), .medium, .large], selection: $sheetDetent)
        .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.35)))
        .onChange(of: viewModel.isBindingEvidence) { _, isBinding in
            sheetDetent = isBinding ? .fraction(0.35) : .large
        }
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

private enum AnalysisPostSolveReviewFlowStage: Equatable {
    case confidence
    case firstApproach
    case step(Int)
    case stuckPoint
    case memo
    case complete
}

struct AnalysisPostSolveReviewSection: View {
    @Binding var draft: AnalysisPostSolveReviewDraft
    @Binding var isComplete: Bool
    var onBindEvidence: ((String, @escaping (String, Int) -> Void) -> Void)? = nil
    
    @State private var reviewStage: AnalysisPostSolveReviewFlowStage = .confidence
    @State private var answeredStepIDs: Set<String> = []

    init(draft: Binding<AnalysisPostSolveReviewDraft>, isComplete: Binding<Bool>, onBindEvidence: ((String, @escaping (String, Int) -> Void) -> Void)? = nil) {
        _draft = draft
        _isComplete = isComplete
        self.onBindEvidence = onBindEvidence
    }

    var body: some View {
        PharSurfaceCard {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                HStack(alignment: .top, spacing: PharTheme.Spacing.medium) {
                    VStack(alignment: .leading, spacing: PharTheme.Spacing.xxSmall) {
                        Text("풀이 직후 복기")
                            .font(PharTypography.cardTitle)
                            .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                        Text(progressLabel)
                            .font(PharTypography.captionStrong)
                            .foregroundStyle(PharTheme.ColorToken.accentBlue)
                    }

                    Spacer(minLength: 0)

                    PharTagPill(
                        text: draft.promptSet.subject.title,
                        tint: PharTheme.ColorToken.accentMint.opacity(0.20)
                    )
                }

                Text(
                    draft.promptSet.overviewText
                        ?? "문항을 막 푼 직후의 생각을 한 번에 다 쓰게 하지 않고, 확신도부터 한 단계씩 정리합니다."
                )
                    .font(PharTypography.caption)
                    .foregroundStyle(PharTheme.ColorToken.inkSecondary)

                VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
                    Text(stageTitle)
                        .font(PharTypography.sectionTitle)
                        .foregroundStyle(PharTheme.ColorToken.inkPrimary)

                    stageContent
                }

                navigationControls
            }
        }
        .onAppear {
            syncCompletionState()
        }
    }

    private var progressLabel: String {
        switch reviewStage {
        case .complete:
            return "복기 완료"
        default:
            return "복기 \(currentStageNumber) / \(totalInteractiveStages)"
        }
    }

    private var totalInteractiveStages: Int {
        draft.promptSet.stepDefinitions.count + 4
    }

    private var currentStageNumber: Int {
        switch reviewStage {
        case .confidence:
            return 1
        case .firstApproach:
            return 2
        case .step(let index):
            return index + 3
        case .stuckPoint:
            return draft.promptSet.stepDefinitions.count + 3
        case .memo, .complete:
            return totalInteractiveStages
        }
    }

    private var stageTitle: String {
        switch reviewStage {
        case .confidence:
            return "풀이 직후 확신도"
        case .firstApproach:
            return "문제를 보자마자 먼저 한 생각"
        case .step(let index):
            guard let step = draft.resolvedStepDefinition(at: index) else {
                return "단계별 복기"
            }
            return step.title
        case .stuckPoint:
            return "가장 막혔던 지점"
        case .memo:
            return "짧은 메모"
        case .complete:
            return "복기 입력 준비 완료"
        }
    }

    @ViewBuilder
    private var stageContent: some View {
        switch reviewStage {
        case .confidence:
            confidenceStage
        case .firstApproach:
            firstApproachStage
        case .step:
            if let step = currentStepDefinition {
                reviewStepStage(for: step)
            }
        case .stuckPoint:
            stuckPointStage
        case .memo:
            memoStage
        case .complete:
            completionStage
        }
    }

    private var confidenceStage: some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
            HStack {
                Text("지금 답에 얼마나 확신이 있었나요?")
                    .font(PharTypography.captionStrong)
                    .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                Spacer(minLength: 0)
                Text("\(Int(draft.confidenceAfter.rounded()))")
                    .font(PharTypography.bodyStrong.monospacedDigit())
                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)
            }

            Slider(value: $draft.confidenceAfter, in: 0 ... 100, step: 1)

            HStack {
                Text("거의 감")
                Spacer(minLength: 0)
                Text("거의 확신")
            }
            .font(PharTypography.caption)
            .foregroundStyle(PharTheme.ColorToken.inkSecondary)
        }
    }

    private var firstApproachStage: some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
            Text(
                draft.promptSet.firstApproachGuidance
                    ?? "처음 떠올린 접근 하나를 고르면 다음 복기 단계로 넘어갑니다."
            )
                .font(PharTypography.caption)
                .foregroundStyle(PharTheme.ColorToken.inkSecondary)

            LazyVGrid(columns: reviewColumns, alignment: .leading, spacing: PharTheme.Spacing.small) {
                ForEach(draft.promptSet.firstApproachOptions) { option in
                    AnalysisReviewChoiceButton(
                        title: option.title,
                        isSelected: draft.firstApproachID == option.id
                    ) {
                        draft.setFirstApproachID(option.id)
                        resetAnsweredSteps(afterStepIndex: -1)
                    }
                }
            }
        }
    }

    private func reviewStepStage(for step: AnalysisResolvedReviewStepDefinition) -> some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
            Text(
                step.guidance
                    ?? draft.promptSet.guidance(for: step.id)
                    ?? "이 단계의 상태를 먼저 고르고, 시도했다면 가장 가까운 행동 신호를 하나 남깁니다."
            )
                .font(PharTypography.caption)
                .foregroundStyle(PharTheme.ColorToken.inkSecondary)

            LazyVGrid(columns: reviewColumns, alignment: .leading, spacing: PharTheme.Spacing.small) {
                ForEach(reviewStatusOptions, id: \.rawValue) { status in
                    AnalysisReviewChoiceButton(
                        title: status.title,
                        isSelected: answeredStepIDs.contains(step.id) && draft.stepStatus(for: step.id) == status
                    ) {
                        answeredStepIDs.insert(step.id)
                        draft.setStepStatus(status, for: step.id, stepIndex: currentStepIndex)
                    }
                }
            }

            if answeredStepIDs.contains(step.id) {
                if draft.stepStatus(for: step.id) == .notTried {
                    Text("이 단계는 시도하지 않은 것으로 기록됩니다.")
                        .font(PharTypography.caption)
                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                } else {
                    LazyVGrid(columns: reviewColumns, alignment: .leading, spacing: PharTheme.Spacing.small) {
                        ForEach(step.options) { option in
                            AnalysisReviewChoiceButton(
                                title: option.title,
                                isSelected: draft.selectedOptionID(for: step.id) == option.id,
                                boundDelayMs: draft.stepCalculatedDelays[step.id],
                                onBindEvidence: {
                                    onBindEvidence?(step.id) { strokeId, delayMs in
                                        draft.stepLinkedStrokeIds[step.id] = strokeId
                                        draft.stepCalculatedDelays[step.id] = delayMs
                                    }
                                }
                            ) {
                                draft.setSelectedOptionID(option.id, for: step.id, stepIndex: currentStepIndex)
                                resetAnsweredSteps(afterStepIndex: currentStepIndex)
                            }
                        }
                    }
                }
            }
        }
    }

    private var stuckPointStage: some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
            Text("가장 막혔다고 느낀 단계를 고르세요. 비워두면 복기 결과를 보고 자동으로 추론합니다.")
                .font(PharTypography.caption)
                .foregroundStyle(PharTheme.ColorToken.inkSecondary)

            AnalysisReviewChoiceButton(
                title: "자동 추론에 맡기기",
                isSelected: draft.primaryStuckPointID == nil
            ) {
                draft.primaryStuckPointID = nil
            }

            LazyVGrid(columns: reviewColumns, alignment: .leading, spacing: PharTheme.Spacing.small) {
                ForEach(draft.preferredStuckSteps) { step in
                    AnalysisReviewChoiceButton(
                        title: step.title,
                        isSelected: draft.primaryStuckPointID == step.id
                    ) {
                        draft.primaryStuckPointID = step.id
                    }
                }
            }
        }
    }

    private var memoStage: some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
            Text("남겨둘 한 줄이 있으면 적고, 없으면 바로 완료해도 됩니다.")
                .font(PharTypography.caption)
                .foregroundStyle(PharTheme.ColorToken.inkSecondary)

            TextEditor(text: $draft.freeMemo)
                .frame(minHeight: 96)
                .scrollContentBackground(.hidden)
                .padding(PharTheme.Spacing.xSmall)
                .background(PharTheme.ColorToken.surfaceSecondary.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous))
        }
    }

    private var completionStage: some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
            Text("확신도와 사고과정 복기가 모두 정리됐습니다. 아래 적재 버튼으로 분석 큐에 보낼 수 있습니다.")
                .font(PharTypography.body)
                .foregroundStyle(PharTheme.ColorToken.inkSecondary)

            PreviewRow(title: "확신도", value: "\(Int(draft.confidenceAfter.rounded())) / 100")
            PreviewRow(title: "첫 접근", value: firstApproachTitle)
            PreviewRow(title: "단계 요약", value: stepStatusSummary)
            PreviewRow(title: "막힌 지점", value: stuckPointTitle)

            if trimmedMemo.isEmpty {
                Text("메모 없음")
                    .font(PharTypography.caption)
                    .foregroundStyle(PharTheme.ColorToken.inkSecondary)
            } else {
                Text(trimmedMemo)
                    .font(PharTypography.body)
                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                    .padding(PharTheme.Spacing.small)
                    .background(PharTheme.ColorToken.surfaceSecondary.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var navigationControls: some View {
        if case .complete = reviewStage {
            Button("이전 단계 수정") {
                moveToPreviousStage()
            }
            .buttonStyle(PharSoftButtonStyle())
        } else {
            HStack(spacing: PharTheme.Spacing.small) {
                if reviewStage != .confidence {
                    Button("이전") {
                        moveToPreviousStage()
                    }
                    .buttonStyle(PharSoftButtonStyle())
                }

                Button(nextButtonTitle) {
                    moveToNextStage()
                }
                .buttonStyle(PharPrimaryButtonStyle())
                .disabled(!canAdvanceToNextStage)
            }
        }
    }

    private var currentStepDefinition: AnalysisResolvedReviewStepDefinition? {
        guard case let .step(index) = reviewStage,
              draft.promptSet.stepDefinitions.indices.contains(index) else {
            return nil
        }
        return draft.resolvedStepDefinition(at: index)
    }

    private var currentRawStepDefinition: AnalysisReviewStepDefinition? {
        guard case let .step(index) = reviewStage,
              draft.promptSet.stepDefinitions.indices.contains(index) else {
            return nil
        }
        return draft.promptSet.stepDefinitions[index]
    }

    private var currentStepIndex: Int {
        guard case let .step(index) = reviewStage else {
            return 0
        }
        return index
    }

    private var reviewStatusOptions: [AnalysisReviewStepStatus] {
        guard let currentRawStepDefinition,
              !currentRawStepDefinition.variants.isEmpty else {
            return AnalysisReviewStepStatus.allCases
        }
        return [.clear, .partial, .failed]
    }

    private var canAdvanceToNextStage: Bool {
        switch reviewStage {
        case .confidence:
            return true
        case .firstApproach:
            return draft.firstApproachID != nil
        case .step:
            guard let step = currentStepDefinition,
                  answeredStepIDs.contains(step.id) else {
                return false
            }
            if let currentRawStepDefinition,
               !currentRawStepDefinition.variants.isEmpty {
                return draft.selectedOptionID(for: step.id) != nil
            }
            return draft.stepStatus(for: step.id) == .notTried || draft.selectedOptionID(for: step.id) != nil
        case .stuckPoint, .memo:
            return true
        case .complete:
            return false
        }
    }

    private var nextButtonTitle: String {
        switch reviewStage {
        case .confidence:
            return "첫 접근 고르기"
        case .firstApproach:
            return draft.promptSet.stepDefinitions.first.map { "\($0.title)으로 이동" } ?? "막힌 지점 고르기"
        case .step(let index):
            return index + 1 < draft.promptSet.stepDefinitions.count ? "다음 단계" : "막힌 지점 고르기"
        case .stuckPoint:
            return "메모로 이동"
        case .memo:
            return "복기 완료"
        case .complete:
            return "완료"
        }
    }

    private var firstApproachTitle: String {
        guard let optionID = draft.firstApproachID,
              let option = draft.promptSet.firstApproachOptions.first(where: { $0.id == optionID }) else {
            return "선택 안 함"
        }
        return option.title
    }

    private var stepStatusSummary: String {
        let failedCount = draft.promptSet.stepDefinitions.filter {
            draft.stepStatus(for: $0.id) == .failed
        }.count
        let partialCount = draft.promptSet.stepDefinitions.filter {
            draft.stepStatus(for: $0.id) == .partial
        }.count

        if failedCount == 0 && partialCount == 0 {
            return "막힘 없이 기록됨"
        }

        return "막힘 \(failedCount)단계 · 애매 \(partialCount)단계"
    }

    private var stuckPointTitle: String {
        guard let stepID = draft.primaryStuckPointID else {
            return "자동 추론"
        }
        return draft.promptSet.stepTitle(for: stepID)
    }

    private var trimmedMemo: String {
        draft.freeMemo.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var reviewColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: PharTheme.Spacing.small),
            GridItem(.flexible(), spacing: PharTheme.Spacing.small)
        ]
    }

    private func moveToNextStage() {
        guard canAdvanceToNextStage else { return }

        switch reviewStage {
        case .confidence:
            setStage(.firstApproach)
        case .firstApproach:
            if draft.promptSet.stepDefinitions.isEmpty {
                setStage(.stuckPoint)
            } else {
                setStage(.step(0))
            }
        case .step(let index):
            if index + 1 < draft.promptSet.stepDefinitions.count {
                setStage(.step(index + 1))
            } else {
                setStage(.stuckPoint)
            }
        case .stuckPoint:
            setStage(.memo)
        case .memo:
            setStage(.complete)
        case .complete:
            break
        }
    }

    private func moveToPreviousStage() {
        switch reviewStage {
        case .confidence:
            break
        case .firstApproach:
            setStage(.confidence)
        case .step(let index):
            if index == 0 {
                setStage(.firstApproach)
            } else {
                setStage(.step(index - 1))
            }
        case .stuckPoint:
            if draft.promptSet.stepDefinitions.isEmpty {
                setStage(.firstApproach)
            } else {
                setStage(.step(draft.promptSet.stepDefinitions.count - 1))
            }
        case .memo:
            setStage(.stuckPoint)
        case .complete:
            setStage(.memo)
        }
    }

    private func setStage(_ stage: AnalysisPostSolveReviewFlowStage) {
        reviewStage = stage
        syncCompletionState()
    }

    private func syncCompletionState() {
        isComplete = reviewStage == .complete
    }

    private func resetAnsweredSteps(afterStepIndex index: Int) {
        let stepIDsToReset = draft.promptSet.stepDefinitions
            .enumerated()
            .filter { $0.offset > index }
            .map(\.element.id)
        answeredStepIDs.subtract(stepIDsToReset)
    }
}

private struct AnalysisReviewChoiceButton: View {
    let title: String
    let isSelected: Bool
    var boundDelayMs: Int? = nil
    var onBindEvidence: (() -> Void)? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.xxSmall) {
                Text(title)
                    .font(PharTypography.bodyStrong)
                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                    .multilineTextAlignment(.leading)

                if isSelected, onBindEvidence != nil {
                    Spacer(minLength: 8)
                    HStack {
                        Spacer()
                        if let delay = boundDelayMs {
                            let formatted = String(format: "%02d:%02d", (delay / 1000) / 60, (delay / 1000) % 60)
                            Text("⏱️ +\(formatted)에 도출됨")
                                .font(PharTypography.captionStrong)
                                .foregroundStyle(PharTheme.ColorToken.accentBlue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(PharTheme.ColorToken.accentBlue.opacity(0.1), in: Capsule())
                        } else {
                            Text("📎 내 필기에서 증거 찾기 (선택)")
                                .font(PharTypography.captionStrong)
                                .foregroundStyle(PharTheme.ColorToken.accentBlue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.clear)
                                .overlay(
                                    Capsule().stroke(PharTheme.ColorToken.accentBlue.opacity(0.3), lineWidth: 1)
                                )
                                .onTapGesture {
                                    onBindEvidence?()
                                }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .padding(.horizontal, PharTheme.Spacing.small)
            .padding(.vertical, PharTheme.Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                    .fill(isSelected ? PharTheme.ColorToken.accentBlue.opacity(0.14) : PharTheme.ColorToken.surfaceSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                    .stroke(
                        isSelected ? PharTheme.ColorToken.accentBlue.opacity(0.34) : PharTheme.ColorToken.borderSoft,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
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

struct WritingEraserModePickerView: View {
    @Binding var selectedMode: WritingEraserMode
    var onSelect: (() -> Void)? = nil

    private let cardWidth: CGFloat = 132

    var body: some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.large) {
            Text("지우개 유형")
                .font(PharTypography.sectionTitle)
                .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(alignment: .top, spacing: PharTheme.Spacing.medium) {
                ForEach(WritingEraserMode.allCases) { mode in
                    Button {
                        selectedMode = mode
                        onSelect?()
                    } label: {
                        VStack(spacing: PharTheme.Spacing.small) {
                            ZStack {
                                RoundedRectangle(cornerRadius: PharTheme.CornerRadius.large, style: .continuous)
                                    .fill(selectedMode == mode ? PharTheme.ColorToken.surfacePrimary : PharTheme.ColorToken.surfaceSecondary.opacity(0.7))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: PharTheme.CornerRadius.large, style: .continuous)
                                            .stroke(
                                                selectedMode == mode ? PharTheme.ColorToken.accentBlue.opacity(0.36) : PharTheme.ColorToken.border.opacity(0.34),
                                                lineWidth: selectedMode == mode ? 2 : 1
                                            )
                                    )
                                    .shadow(
                                        color: PharTheme.ColorToken.overlayShadow.opacity(selectedMode == mode ? 0.18 : 0.06),
                                        radius: selectedMode == mode ? 14 : 8,
                                        x: 0,
                                        y: selectedMode == mode ? 8 : 4
                                    )

                                VStack(spacing: 10) {
                                    Image(systemName: "eraser")
                                        .font(.system(size: eraserIconSize(for: mode), weight: .semibold))
                                        .foregroundStyle(eraserIconColor(for: mode))
                                        .rotationEffect(.degrees(mode == .stroke ? -6 : 0))
                                    Text(mode.rawValue)
                                        .font(PharTypography.bodyStrong)
                                        .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                                    Text(mode.subtitle)
                                        .font(PharTypography.caption)
                                        .foregroundStyle(PharTheme.ColorToken.subtleText)
                                }
                                .padding(.vertical, PharTheme.Spacing.medium)
                                .padding(.horizontal, PharTheme.Spacing.small)
                            }
                            .frame(width: cardWidth, height: 146)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("터치 방식과 지우개 모양에 맞게 고를 수 있습니다.")
                .font(PharTypography.caption)
                .foregroundStyle(PharTheme.ColorToken.subtleText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(PharTheme.Spacing.large)
        .frame(width: 470)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(PharTheme.ColorToken.surfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(PharTheme.ColorToken.border.opacity(0.28), lineWidth: 1)
        )
    }

    private func eraserIconSize(for mode: WritingEraserMode) -> CGFloat {
        switch mode {
        case .precise:
            return 22
        case .standard:
            return 28
        case .stroke:
            return 34
        }
    }

    private func eraserIconColor(for mode: WritingEraserMode) -> Color {
        switch mode {
        case .precise:
            return PharTheme.ColorToken.inkPrimary.opacity(0.86)
        case .standard:
            return PharTheme.ColorToken.inkPrimary
        case .stroke:
            return PharTheme.ColorToken.accentBlue
        }
    }
}
