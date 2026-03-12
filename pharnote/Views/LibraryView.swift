import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var analysisCenter: AnalysisCenter
    @EnvironmentObject private var authManager: PharnodeSupabaseAuthManager
    @EnvironmentObject private var cloudSyncManager: PharnodeCloudSyncManager
    @StateObject private var viewModel = LibraryViewModel()
    @State private var isShowingPDFImportPicker = false
    @State private var isShowingAnalysisHistory = false
    @State private var isShowingCatalogManagement = false
    @State private var isShowingDashboardPreview = false
    @State private var isShowingStudyMaterialAdmin = false
    @State private var isShowingReviewQueue = false
    @State private var isShowingCloudSync = false

    private let gridColumns = [
        GridItem(.adaptive(minimum: 250), spacing: PharTheme.Spacing.medium, alignment: .top)
    ]

    private var showsInternalTools: Bool {
        PharFeatureFlags.showsInternalTools
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 290, max: 320)
        } detail: {
            NavigationStack(path: $viewModel.navigationPath) {
                ScrollView {
                    VStack(alignment: .leading, spacing: PharTheme.Spacing.large) {
                        heroCard

                        if viewModel.totalDocumentCount == 0 {
                            emptyStateCard
                        } else if viewModel.hasSearchQuery {
                            if !viewModel.continueStudyingDocuments.isEmpty {
                                continueStudyingSection
                            }

                            if !viewModel.ocrSearchResults.isEmpty {
                                ocrSearchSection
                            }

                            if viewModel.continueStudyingDocuments.isEmpty && viewModel.ocrSearchResults.isEmpty {
                                searchEmptyStateCard
                            }
                        } else {
                            continueStudyingSection
                            pharnodeLoopCard
                            if !viewModel.materialShelves.isEmpty || !viewModel.availableStudyProviders.isEmpty || !viewModel.availableStudySubjects.isEmpty {
                                materialOrganizerSection
                            }
                            collectionsSection
                        }
                    }
                    .padding(PharTheme.Spacing.large)
                }
                .background(PharTheme.GradientToken.appBackdrop.ignoresSafeArea())
                .navigationTitle(viewModel.selectedFolderTitle)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        PharToolbarIconButton(
                            systemName: "square.and.arrow.down",
                            accessibilityLabel: "문서 가져오기"
                        ) {
                            isShowingPDFImportPicker = true
                        }

                        PharToolbarIconButton(
                            systemName: "square.and.pencil",
                            accessibilityLabel: "빈 노트 만들기"
                        ) {
                            viewModel.createBlankNote()
                        }

                        if showsInternalTools {
                            Menu {
                                Button("분석 기록 보기") {
                                    isShowingAnalysisHistory = true
                                }
                                Button("교재 카탈로그 관리") {
                                    isShowingCatalogManagement = true
                                }
                                Button("교재 운영") {
                                    isShowingStudyMaterialAdmin = true
                                }
                                Button("파르노드 연결 설정") {
                                    isShowingCloudSync = true
                                }
                                Button("복습 큐 보기") {
                                    isShowingReviewQueue = true
                                }
                                Button("대시보드 미리보기") {
                                    viewModel.refreshDashboardSnapshot()
                                    isShowingDashboardPreview = true
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.system(size: PharTheme.Icon.medium, weight: .semibold))
                                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                                    .frame(minWidth: PharTheme.HitArea.comfortable, minHeight: PharTheme.HitArea.comfortable)
                            }
                        }
                    }
                }
                .searchable(text: $viewModel.searchQuery, prompt: "문서 제목 또는 OCR 텍스트 검색")
                .navigationDestination(for: DocumentEditorLaunchTarget.self) { target in
                    DocumentEditorView(document: target.document, initialPageKey: target.initialPageKey)
                }
            }
        }
        .environmentObject(viewModel)
        .navigationSplitViewStyle(.balanced)
        .background(PharTheme.GradientToken.appBackdrop)
        .alert("오류", isPresented: isErrorPresented) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $isShowingPDFImportPicker) {
            PDFImportPicker { urls in
                isShowingPDFImportPicker = false
                guard let firstURL = urls.first else { return }
                viewModel.importDocument(from: firstURL)
            } onCancelled: {
                isShowingPDFImportPicker = false
            }
        }
        .sheet(isPresented: $isShowingAnalysisHistory) {
            AnalysisHistoryView()
        }
        .sheet(isPresented: $isShowingReviewQueue) {
            AnalysisReviewQueueView()
        }
        .sheet(isPresented: $isShowingCloudSync) {
            PharnodeCloudSyncView()
        }
        .sheet(isPresented: $isShowingStudyMaterialAdmin) {
            StudyMaterialLibraryAdminSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isShowingDashboardPreview) {
            PharnodeDashboardPreviewSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isShowingCatalogManagement) {
            StudyMaterialCatalogManagementView(viewModel: viewModel)
        }
        .sheet(item: $viewModel.pendingPDFImportSelection) { pending in
            StudyMaterialImportSheet(
                pending: pending,
                onSave: { title, provider, subject in
                    viewModel.applyImportedPDFSelection(
                        documentID: pending.document.id,
                        title: title,
                        provider: provider,
                        subject: subject
                    )
                },
                onSkip: {
                    viewModel.dismissImportedPDFSelection(openDocument: true)
                }
            )
        }
        .onAppear {
            viewModel.loadDocuments()
        }
        .onChange(of: viewModel.searchQuery) { _, _ in
            viewModel.refreshOCRSearchResults()
        }
        .onChange(of: viewModel.selectedFolder) { _, _ in
            viewModel.refreshOCRSearchResults()
        }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                PharSurfaceCard(fill: PharTheme.GradientToken.accentWash, shadow: PharTheme.ShadowToken.lifted) {
                    VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
                        HStack(spacing: PharTheme.Spacing.small) {
                            Image("BrandMark")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous))

                            VStack(alignment: .leading, spacing: PharTheme.Spacing.xxxSmall) {
                                Text("pharnote")
                                    .font(PharTypography.cardTitle)
                                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                                Text("by pharnode")
                                    .font(PharTypography.captionStrong)
                                    .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                            }
                        }

                        Text("Write beautifully. Capture quietly. Understand later.")
                            .font(PharTypography.caption)
                            .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: PharTheme.Spacing.xSmall) {
                    Text("Library")
                        .font(PharTypography.eyebrow)
                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, PharTheme.Spacing.xSmall)

                    ForEach(LibraryFolder.allCases) { folder in
                        SidebarFolderButton(
                            folder: folder,
                            count: viewModel.count(for: folder),
                            isSelected: (viewModel.selectedFolder ?? .all) == folder
                        ) {
                            withAnimation(PharTheme.AnimationToken.panelReveal) {
                                viewModel.selectedFolder = folder
                            }
                        }
                    }
                }

                PharSurfaceCard(fill: PharTheme.ColorToken.surfacePrimary.opacity(0.92)) {
                    VStack(alignment: .leading, spacing: PharTheme.Spacing.xSmall) {
                        PharTagPill(
                            text: "TODAY",
                            tint: PharTheme.ColorToken.accentMint.opacity(0.28)
                        )
                        Text("최근 기록과 연결 상태를 바로 확인할 수 있게 정리했습니다.")
                            .font(PharTypography.bodyStrong)
                            .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                        Text("분석 \(analysisCenter.completedCount)개, 대기 \(analysisCenter.queuedCount)개, 동기화 상태 \(cloudSyncManager.syncState.title)")
                            .font(PharTypography.caption)
                            .foregroundStyle(PharTheme.ColorToken.inkSecondary)

                        Button {
                            isShowingCloudSync = true
                        } label: {
                            Label(authManager.isAuthenticated ? "파르노드 연결 확인" : "파르노드 연결", systemImage: "person.crop.circle.badge.checkmark")
                        }
                        .buttonStyle(PharSoftButtonStyle())

                        if showsInternalTools {
                            Button {
                                isShowingAnalysisHistory = true
                            } label: {
                                Label("분석 기록 보기", systemImage: "list.bullet.rectangle.portrait")
                            }
                            .buttonStyle(PharSoftButtonStyle())
                        }
                    }
                }
            }
            .padding(PharTheme.Spacing.medium)
        }
        .background(PharTheme.ColorToken.sidebarBackground.ignoresSafeArea())
    }

    private var heroCard: some View {
        PharSurfaceCard(fill: PharTheme.GradientToken.heroPanel, stroke: .white.opacity(0.14), shadow: PharTheme.ShadowToken.lifted) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 180, height: 180)
                    .offset(x: 70, y: -90)

                VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                    PharTagPill(text: "STUDY DESK", tint: Color.white.opacity(0.14), foreground: .white)

                    HStack(alignment: .top, spacing: PharTheme.Spacing.large) {
                        VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
                            Text("pharnote")
                                .font(PharTypography.heroDisplay)
                                .foregroundStyle(Color.white)

                            Text("기록을 놓치지 않는 iPad 노트 워크스페이스")
                                .font(PharTypography.heroSubtitle)
                                .foregroundStyle(Color.white.opacity(0.9))

                            Text("노트를 쓰고, PDF를 풀고, 정리하는 동안 메타인지에 필요한 흔적을 조용히 수집하고 필요한 순간 페이지 인사이트로 다시 읽게 합니다.")
                                .font(PharTypography.body)
                                .foregroundStyle(Color.white.opacity(0.86))
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: PharTheme.Spacing.small) {
                                Button {
                                    viewModel.createBlankNote()
                                } label: {
                                    Label("빈 노트 시작", systemImage: "square.and.pencil")
                                }
                                .buttonStyle(PharSoftButtonStyle())

                                Button {
                                    isShowingPDFImportPicker = true
                                } label: {
                                    Label("문서 가져오기", systemImage: "square.and.arrow.down")
                                }
                                .buttonStyle(PharSoftButtonStyle())
                            }
                        }

                        Spacer(minLength: 0)

                        VStack(alignment: .trailing, spacing: PharTheme.Spacing.small) {
                            HeroMetricPill(title: "문서", value: "\(viewModel.totalDocumentCount)", tint: PharTheme.ColorToken.accentButter)
                            HeroMetricPill(title: "노트", value: "\(viewModel.blankNoteCount)", tint: PharTheme.ColorToken.accentMint)
                            HeroMetricPill(title: "PDF", value: "\(viewModel.pdfCount)", tint: PharTheme.ColorToken.accentPeach)
                        }
                    }
                }
            }
        }
    }

    private var continueStudyingSection: some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
            sectionHeader(
                eyebrow: "Continue",
                title: viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "이어쓰기 좋은 문서" : "검색 결과"
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PharTheme.Spacing.medium) {
                    ForEach(viewModel.continueStudyingDocuments) { document in
                        Button {
                            viewModel.openDocument(document)
                        } label: {
                            FeaturedDocumentCard(document: document)
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.highlight)
                    }
                }
                .padding(.vertical, PharTheme.Spacing.xxxSmall)
            }
        }
    }

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
            sectionHeader(eyebrow: "Collections", title: "학습 재료 둘러보기")

            LazyVGrid(columns: gridColumns, spacing: PharTheme.Spacing.medium) {
                CollectionCard(
                    title: "빈 노트",
                    subtitle: "정리, 풀이, 개념 요약을 위한 자유 노트",
                    count: viewModel.highlightedBlankNotes.count,
                    accent: PharTheme.ColorToken.accentMint
                ) {
                    ForEach(viewModel.highlightedBlankNotes) { document in
                        Button {
                            viewModel.openDocument(document)
                        } label: {
                            CompactDocumentRow(document: document)
                        }
                        .buttonStyle(.plain)
                    }
                }

                CollectionCard(
                    title: "PDF",
                    subtitle: "문제집, 프린트, 교재를 바로 불러와 풉니다",
                    count: viewModel.highlightedPDFs.count,
                    accent: PharTheme.ColorToken.accentPeach
                ) {
                    ForEach(viewModel.highlightedPDFs) { document in
                        Button {
                            viewModel.openDocument(document)
                        } label: {
                            CompactDocumentRow(document: document)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var ocrSearchSection: some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
            sectionHeader(eyebrow: "OCR Search", title: "OCR 인식 결과")

            PharSurfaceCard(fill: PharTheme.ColorToken.surfacePrimary.opacity(0.96)) {
                VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                    Text("필기와 스캔 PDF에서 인식한 텍스트를 함께 보여줍니다.")
                        .font(PharTypography.caption)
                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)

                    VStack(spacing: PharTheme.Spacing.small) {
                        ForEach(viewModel.ocrSearchResults) { result in
                            Button {
                                viewModel.openOCRSearchResult(result)
                            } label: {
                                OCRSearchResultCard(result: result)
                            }
                            .buttonStyle(.plain)
                            .hoverEffect(.highlight)
                        }
                    }
                }
            }
        }
    }

    private var materialOrganizerSection: some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
            sectionHeader(eyebrow: "Materials", title: "교재별로 정리된 라이브러리")

            PharSurfaceCard(fill: PharTheme.ColorToken.surfacePrimary.opacity(0.96)) {
                VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                    HStack(alignment: .top, spacing: PharTheme.Spacing.medium) {
                        VStack(alignment: .leading, spacing: PharTheme.Spacing.xxxSmall) {
                            Text("PDF 교재를 출처와 과목 기준으로 정리합니다.")
                                .font(PharTypography.bodyStrong)
                                .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                            Text("자동 인식 뒤 수동 확정한 메타데이터를 기준으로 깔끔하게 묶습니다.")
                                .font(PharTypography.caption)
                                .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                        }

                        Spacer(minLength: 0)

                        if viewModel.hasActiveMaterialFilters {
                            Button("필터 초기화") {
                                withAnimation(PharTheme.AnimationToken.panelReveal) {
                                    viewModel.clearStudyMaterialFilters()
                                }
                            }
                            .buttonStyle(PharSoftButtonStyle())
                        }

                        if showsInternalTools {
                            Button("카탈로그 관리") {
                                isShowingCatalogManagement = true
                            }
                            .buttonStyle(PharSoftButtonStyle())

                            Button("교재 운영") {
                                isShowingStudyMaterialAdmin = true
                            }
                            .buttonStyle(PharSoftButtonStyle())
                        }
                    }

                    if !viewModel.availableStudySubjects.isEmpty {
                        VStack(alignment: .leading, spacing: PharTheme.Spacing.xSmall) {
                            Text("과목")
                                .font(PharTypography.eyebrow)
                                .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                                .textCase(.uppercase)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: PharTheme.Spacing.small) {
                                    MaterialFilterChip(
                                        title: "전체 과목",
                                        isSelected: viewModel.selectedStudySubject == nil
                                    ) {
                                        withAnimation(PharTheme.AnimationToken.panelReveal) {
                                            viewModel.toggleStudySubject(nil)
                                        }
                                    }

                                    ForEach(viewModel.availableStudySubjects) { subject in
                                        MaterialFilterChip(
                                            title: subject.title,
                                            isSelected: viewModel.selectedStudySubject == subject
                                        ) {
                                            withAnimation(PharTheme.AnimationToken.panelReveal) {
                                                viewModel.toggleStudySubject(subject)
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, PharTheme.Spacing.xxxSmall)
                            }
                        }
                    }

                    if !viewModel.availableStudyProviders.isEmpty {
                        VStack(alignment: .leading, spacing: PharTheme.Spacing.xSmall) {
                            Text("출처")
                                .font(PharTypography.eyebrow)
                                .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                                .textCase(.uppercase)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: PharTheme.Spacing.small) {
                                    MaterialFilterChip(
                                        title: "전체 출처",
                                        isSelected: viewModel.selectedStudyProvider == nil
                                    ) {
                                        withAnimation(PharTheme.AnimationToken.panelReveal) {
                                            viewModel.toggleStudyProvider(nil)
                                        }
                                    }

                                    ForEach(viewModel.availableStudyProviders) { provider in
                                        MaterialFilterChip(
                                            title: provider.title,
                                            isSelected: viewModel.selectedStudyProvider == provider
                                        ) {
                                            withAnimation(PharTheme.AnimationToken.panelReveal) {
                                                viewModel.toggleStudyProvider(provider)
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, PharTheme.Spacing.xxxSmall)
                            }
                        }
                    }

                    if viewModel.materialShelves.isEmpty {
                        Text("선택한 조건에 맞는 PDF 교재가 아직 없습니다.")
                            .font(PharTypography.caption)
                            .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                    } else {
                        VStack(spacing: PharTheme.Spacing.medium) {
                            ForEach(viewModel.materialShelves) { shelf in
                                MaterialShelfCard(shelf: shelf)
                            }
                        }
                    }
                }
            }
        }
    }

    private var pharnodeLoopCard: some View {
        PharSurfaceCard(fill: PharTheme.ColorToken.surfacePrimary.opacity(0.94)) {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                HStack {
                    VStack(alignment: .leading, spacing: PharTheme.Spacing.xxxSmall) {
                        Text("메타인지 루프")
                            .font(PharTypography.sectionTitle)
                            .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                        Text(authManager.isAuthenticated
                             ? "기록된 페이지를 다시 읽고, 정리 흐름을 pharnode와 연결해 이해 상태를 돌아볼 수 있습니다."
                             : "파르노드 계정을 연결하면 페이지 인사이트와 진도 정보가 함께 이어집니다.")
                            .font(PharTypography.body)
                            .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                    }
                    Spacer(minLength: 0)
                    PharTagPill(
                        text: analysisCenter.queuedCount == 0
                            ? (analysisCenter.completedCount == 0 ? "준비됨" : "인사이트 \(analysisCenter.completedCount)")
                            : "대기 \(analysisCenter.queuedCount)",
                        tint: PharTheme.ColorToken.accentBlue.opacity(0.12),
                        foreground: PharTheme.ColorToken.accentBlue
                    )
                }

                HStack(alignment: .top, spacing: PharTheme.Spacing.medium) {
                    LoopStepCard(number: "01", title: "기록", detail: "노트와 PDF 위에 공부 흔적을 남깁니다.")
                    LoopStepCard(number: "02", title: "수집", detail: "행동 맥락과 페이지 구조를 조용히 쌓습니다.")
                    LoopStepCard(number: "03", title: "읽기", detail: "페이지 인사이트로 지금 한 공부를 다시 읽습니다.")
                }

                if analysisCenter.queuedCount > 0 {
                    PharSurfaceCard(fill: PharTheme.ColorToken.surfaceSecondary.opacity(0.9)) {
                        VStack(alignment: .leading, spacing: PharTheme.Spacing.xSmall) {
                            PharTagPill(
                                text: "분석 대기 중",
                                tint: PharTheme.ColorToken.accentButter.opacity(0.18),
                                foreground: PharTheme.ColorToken.inkPrimary
                            )

                            Text("최근에 기록한 페이지를 분석 큐에 올려두었습니다.")
                                .font(PharTypography.bodyStrong)
                                .foregroundStyle(PharTheme.ColorToken.inkPrimary)

                            Text("백그라운드에서 메타인지용 인사이트를 준비하고 있습니다.")
                                .font(PharTypography.captionStrong)
                                .foregroundStyle(PharTheme.ColorToken.accentBlue)

                            Text("페이지를 계속 정리해도 되고, 잠시 뒤 인사이트 기록에서 결과를 확인하면 됩니다.")
                                .font(PharTypography.caption)
                                .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                                .lineLimit(2)
                        }
                    }
                } else if let latestResult = analysisCenter.latestResult {
                    PharSurfaceCard(fill: PharTheme.ColorToken.surfaceSecondary.opacity(0.9)) {
                        VStack(alignment: .leading, spacing: PharTheme.Spacing.xSmall) {
                            PharTagPill(
                                text: "최근 페이지 인사이트",
                                tint: PharTheme.ColorToken.accentBlue.opacity(0.12),
                                foreground: PharTheme.ColorToken.accentBlue
                            )

                            Text(latestResult.summary.headline)
                                .font(PharTypography.bodyStrong)
                                .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                                .lineLimit(2)

                            Text("페이지를 다시 열어 근거를 보강하거나, pharnode에서 전체 맥락과 함께 다시 읽으면 됩니다.")
                                .font(PharTypography.caption)
                                .foregroundStyle(PharTheme.ColorToken.inkSecondary)

                            HStack(spacing: PharTheme.Spacing.small) {
                                Button {
                                    isShowingCloudSync = true
                                } label: {
                                    Label("파르노드 연결", systemImage: "person.crop.circle.badge.checkmark")
                                }
                                .buttonStyle(PharPrimaryButtonStyle())

                                if showsInternalTools {
                                    Button {
                                        isShowingAnalysisHistory = true
                                    } label: {
                                        Label("분석 기록", systemImage: "list.bullet.rectangle.portrait")
                                    }
                                    .buttonStyle(PharSoftButtonStyle())
                                }
                            }
                        }
                    }
                } else {
                    PharSurfaceCard(fill: PharTheme.ColorToken.surfaceSecondary.opacity(0.9)) {
                        VStack(alignment: .leading, spacing: PharTheme.Spacing.xSmall) {
                            Text("아직 분석된 페이지가 없습니다.")
                                .font(PharTypography.bodyStrong)
                                .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                            Text("노트나 PDF에서 한 페이지를 마친 뒤 `분석` 버튼을 눌러 첫 인사이트를 만들어 보세요.")
                                .font(PharTypography.caption)
                                .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                            HStack(spacing: PharTheme.Spacing.small) {
                                Button {
                                    viewModel.createBlankNote()
                                } label: {
                                    Label("새 노트 시작", systemImage: "square.and.pencil")
                                }
                                .buttonStyle(PharPrimaryButtonStyle())

                                Button {
                                    isShowingPDFImportPicker = true
                                } label: {
                                    Label("문서 가져오기", systemImage: "square.and.arrow.down")
                                }
                                .buttonStyle(PharSoftButtonStyle())
                            }
                        }
                    }
                }

                HStack(spacing: PharTheme.Spacing.small) {
                    Button {
                        isShowingCloudSync = true
                    } label: {
                        Label(authManager.isAuthenticated ? "파르노드 연결됨" : "파르노드 연결", systemImage: authManager.isAuthenticated ? "checkmark.icloud" : "person.crop.circle.badge.plus")
                    }
                    .buttonStyle(PharSoftButtonStyle())

                    if !showsInternalTools {
                        Button {
                            isShowingAnalysisHistory = true
                        } label: {
                            Label("인사이트 기록", systemImage: "list.bullet.rectangle.portrait")
                        }
                        .buttonStyle(PharSoftButtonStyle())
                    }

                    if showsInternalTools {
                        Button {
                            viewModel.refreshDashboardSnapshot()
                            isShowingDashboardPreview = true
                        } label: {
                            Label("대시보드 미리보기", systemImage: "rectangle.3.group.bubble")
                        }
                        .buttonStyle(PharSoftButtonStyle())
                    }
                }
            }
        }
    }

    private var emptyStateCard: some View {
        PharSurfaceCard(fill: PharTheme.ColorToken.surfacePrimary.opacity(0.96)) {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                Text(viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "첫 학습 자료를 만들어 보세요" : "검색 결과가 없습니다")
                    .font(PharTypography.sectionTitle)
                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)

                Text(
                    viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "빈 노트로 바로 시작하거나 PDF를 가져와 pharnote 학습 공간을 채우세요."
                    : "다른 검색어를 입력하거나 새로운 자료를 만들어 보세요."
                )
                .font(PharTypography.body)
                .foregroundStyle(PharTheme.ColorToken.inkSecondary)

                HStack(spacing: PharTheme.Spacing.small) {
                    Button {
                        viewModel.createBlankNote()
                    } label: {
                        Label("빈 노트 시작", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(PharPrimaryButtonStyle())

                    Button {
                        isShowingPDFImportPicker = true
                    } label: {
                        Label("문서 가져오기", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(PharSoftButtonStyle())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var searchEmptyStateCard: some View {
        PharSurfaceCard(fill: PharTheme.ColorToken.surfacePrimary.opacity(0.96)) {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                Text("검색 결과가 없습니다")
                    .font(PharTypography.sectionTitle)
                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)

                Text("문서 제목, 교재 메타데이터, OCR로 인식된 텍스트까지 함께 찾아봤지만 일치하는 내용이 없었습니다.")
                    .font(PharTypography.body)
                    .foregroundStyle(PharTheme.ColorToken.inkSecondary)

                Button("검색 지우기") {
                    viewModel.searchQuery = ""
                    viewModel.refreshOCRSearchResults()
                }
                .buttonStyle(PharSoftButtonStyle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var isErrorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { shouldShow in
                if !shouldShow {
                    viewModel.errorMessage = nil
                }
            }
        )
    }

    @ViewBuilder
    private func sectionHeader(eyebrow: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.xxxSmall) {
            Text(eyebrow)
                .font(PharTypography.eyebrow)
                .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                .textCase(.uppercase)
            Text(title)
                .font(PharTypography.sectionTitle)
                .foregroundStyle(PharTheme.ColorToken.inkPrimary)
        }
    }
}

#Preview("LibraryView") {
    let analysisCenter = AnalysisCenter()
    let authManager = PharnodeSupabaseAuthManager()
    NavigationStack {
        LibraryView()
    }
    .environmentObject(analysisCenter)
    .environmentObject(authManager)
    .environmentObject(PharnodeCloudSyncManager(analysisCenter: analysisCenter, authManager: authManager))
}

private struct SidebarFolderButton: View {
    let folder: LibraryFolder
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PharTheme.Spacing.small) {
                Image(systemName: folder.systemImage)
                    .font(.system(size: PharTheme.Icon.medium, weight: .semibold))
                    .foregroundStyle(isSelected ? PharTheme.ColorToken.accentBlue : PharTheme.ColorToken.inkSecondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: PharTheme.Spacing.xxxSmall) {
                    Text(folder.title)
                        .font(PharTypography.bodyStrong)
                        .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                    Text(folder.subtitle)
                        .font(PharTypography.caption)
                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text("\(count)")
                    .font(PharTypography.captionStrong)
                    .foregroundStyle(isSelected ? PharTheme.ColorToken.accentBlue : PharTheme.ColorToken.inkSecondary)
                    .padding(.horizontal, PharTheme.Spacing.xSmall)
                    .padding(.vertical, PharTheme.Spacing.xxSmall)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isSelected ? PharTheme.ColorToken.accentBlue.opacity(0.12) : PharTheme.ColorToken.surfacePrimary.opacity(0.78))
                    )
            }
            .padding(PharTheme.Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                    .fill(isSelected ? PharTheme.ColorToken.surfacePrimary : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                    .stroke(isSelected ? PharTheme.ColorToken.borderStrong : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
    }
}

private struct HeroMetricPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.xxxSmall) {
            Text(title)
                .font(PharTypography.eyebrow)
                .foregroundStyle(Color.white.opacity(0.74))
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
        }
        .frame(width: 108, alignment: .leading)
        .padding(.horizontal, PharTheme.Spacing.medium)
        .padding(.vertical, PharTheme.Spacing.small)
        .background(
            RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                .fill(tint.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct OCRSearchResultCard: View {
    let result: LibraryViewModel.OCRSearchResultRow

    var body: some View {
        PharSurfaceCard(fill: PharTheme.ColorToken.surfaceSecondary.opacity(0.92)) {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.xSmall) {
                HStack(alignment: .top, spacing: PharTheme.Spacing.small) {
                    VStack(alignment: .leading, spacing: PharTheme.Spacing.xxxSmall) {
                        Text(result.document.title)
                            .font(PharTypography.bodyStrong)
                            .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                            .lineLimit(1)

                        Text(result.pageLabel)
                            .font(PharTypography.captionStrong)
                            .foregroundStyle(PharTheme.ColorToken.accentBlue)
                    }

                    Spacer(minLength: 0)

                    Text(result.indexedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(PharTypography.caption)
                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                        .multilineTextAlignment(.trailing)
                }

                Text(result.snippet)
                    .font(PharTypography.body)
                    .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct FeaturedDocumentCard: View {
    let document: PharDocument

    var body: some View {
        PharSurfaceCard(fill: PharTheme.ColorToken.surfacePrimary.opacity(0.94)) {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                HStack(alignment: .top) {
                    DocumentTypeIcon(document: document, size: 52)
                    Spacer(minLength: 0)
                    PharTagPill(
                        text: document.type == .blankNote ? "NOTE" : "PDF",
                        tint: badgeTint,
                        foreground: PharTheme.ColorToken.inkPrimary
                    )
                }

                VStack(alignment: .leading, spacing: PharTheme.Spacing.xxSmall) {
                    Text(document.title)
                        .font(PharTypography.cardTitle)
                        .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                        .lineLimit(2)
                    if let materialLine = document.materialSummaryLine {
                        Text(materialLine)
                            .font(PharTypography.captionStrong)
                            .foregroundStyle(PharTheme.ColorToken.accentBlue)
                    }
                    Text(subtitle)
                        .font(PharTypography.caption)
                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                    if let progressLine = document.progressSummaryLine {
                        Text(progressLine)
                            .font(PharTypography.caption)
                            .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                    }
                    if let progressDetailLine = document.progressDetailLine {
                        Text(progressDetailLine)
                            .font(PharTypography.caption)
                            .foregroundStyle(PharTheme.ColorToken.subtleText)
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: 280, alignment: .leading)
        }
    }

    private var badgeTint: Color {
        document.type == .blankNote
        ? PharTheme.ColorToken.accentMint.opacity(0.30)
        : PharTheme.ColorToken.accentPeach.opacity(0.30)
    }

    private var subtitle: String {
        let label = document.type == .blankNote ? "빈 노트" : "PDF 문서"
        return "\(label) · \(document.updatedAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

private struct CollectionCard<Rows: View>: View {
    let title: String
    let subtitle: String
    let count: Int
    let accent: Color
    let rows: Rows

    init(
        title: String,
        subtitle: String,
        count: Int,
        accent: Color,
        @ViewBuilder rows: () -> Rows
    ) {
        self.title = title
        self.subtitle = subtitle
        self.count = count
        self.accent = accent
        self.rows = rows()
    }

    var body: some View {
        PharSurfaceCard(fill: PharTheme.ColorToken.surfacePrimary.opacity(0.96)) {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: PharTheme.Spacing.xxxSmall) {
                        Text(title)
                            .font(PharTypography.cardTitle)
                            .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                        Text(subtitle)
                            .font(PharTypography.caption)
                            .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    PharTagPill(text: "\(count)", tint: accent.opacity(0.22))
                }

                VStack(spacing: PharTheme.Spacing.small) {
                    if count == 0 {
                        Text("아직 문서가 없습니다.")
                            .font(PharTypography.caption)
                            .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        rows
                    }
                }
            }
        }
    }
}

private struct CompactDocumentRow: View {
    let document: PharDocument

    var body: some View {
        HStack(spacing: PharTheme.Spacing.small) {
            DocumentTypeIcon(document: document, size: 40)

            VStack(alignment: .leading, spacing: PharTheme.Spacing.xxxSmall) {
                Text(document.title)
                    .font(PharTypography.bodyStrong)
                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                    .lineLimit(1)
                if let materialLine = document.materialSummaryLine {
                    Text(materialLine)
                        .font(PharTypography.captionStrong)
                        .foregroundStyle(PharTheme.ColorToken.accentBlue)
                        .lineLimit(1)
                }
                Text(document.progressSummaryLine ?? document.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(PharTypography.caption)
                    .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                if let progressDetailLine = document.progressDetailLine {
                    Text(progressDetailLine)
                        .font(PharTypography.caption)
                        .foregroundStyle(PharTheme.ColorToken.subtleText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PharTheme.ColorToken.inkSecondary)
        }
        .padding(PharTheme.Spacing.small)
        .background(
            RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                .fill(PharTheme.ColorToken.surfaceSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                .stroke(PharTheme.ColorToken.borderSoft, lineWidth: 1)
        )
    }
}

private struct MaterialFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(PharTypography.captionStrong)
                .foregroundStyle(isSelected ? PharTheme.ColorToken.accentBlue : PharTheme.ColorToken.inkPrimary)
                .padding(.horizontal, PharTheme.Spacing.medium)
                .padding(.vertical, PharTheme.Spacing.small)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            isSelected
                            ? PharTheme.ColorToken.accentBlue.opacity(0.12)
                            : PharTheme.ColorToken.surfaceSecondary
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            isSelected
                            ? PharTheme.ColorToken.accentBlue.opacity(0.22)
                            : PharTheme.ColorToken.borderSoft,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
    }
}

private struct MaterialShelfCard: View {
    @EnvironmentObject private var viewModel: LibraryViewModel

    let shelf: LibraryViewModel.MaterialShelf

    var body: some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
            HStack(alignment: .top, spacing: PharTheme.Spacing.small) {
                VStack(alignment: .leading, spacing: PharTheme.Spacing.xxxSmall) {
                    Text(shelf.title)
                        .font(PharTypography.cardTitle)
                        .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                    Text(shelf.subtitle)
                        .font(PharTypography.caption)
                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                }

                Spacer(minLength: 0)

                PharTagPill(
                    text: "\(shelf.documents.count)",
                    tint: PharTheme.ColorToken.accentBlue.opacity(0.14),
                    foreground: PharTheme.ColorToken.accentBlue
                )
            }

            VStack(spacing: PharTheme.Spacing.small) {
                ForEach(Array(shelf.documents.prefix(4))) { document in
                    Button {
                        viewModel.openDocument(document)
                    } label: {
                        CompactDocumentRow(document: document)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(PharTheme.Spacing.medium)
        .background(
            RoundedRectangle(cornerRadius: PharTheme.CornerRadius.large, style: .continuous)
                .fill(PharTheme.ColorToken.surfaceSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PharTheme.CornerRadius.large, style: .continuous)
                .stroke(PharTheme.ColorToken.borderSoft, lineWidth: 1)
        )
    }
}

private struct PharnodeDashboardPreviewSheet: View {
    @ObservedObject var viewModel: LibraryViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let snapshot = viewModel.dashboardSnapshot {
                    Section("개요") {
                        LabeledContent("생성 시각", value: snapshot.generatedAt.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("교재 수", value: "\(snapshot.materials.count)")
                        LabeledContent(
                            "활성 단원",
                            value: "\(snapshot.materials.filter { $0.currentSection != nil }.count)"
                        )
                    }

                    Section("교재 진도 카드") {
                        ForEach(snapshot.materials) { material in
                            VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
                                HStack(alignment: .top, spacing: PharTheme.Spacing.small) {
                                    VStack(alignment: .leading, spacing: PharTheme.Spacing.xxxSmall) {
                                        Text(material.canonicalTitle ?? material.documentTitle)
                                            .font(PharTypography.bodyStrong)
                                            .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                                        Text(
                                            [
                                                material.provider,
                                                material.subject
                                            ]
                                            .compactMap { $0 }
                                            .joined(separator: " · ")
                                        )
                                        .font(PharTypography.caption)
                                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                                    }

                                    Spacer(minLength: 0)

                                    PharTagPill(
                                        text: "\(material.percentComplete)%",
                                        tint: PharTheme.ColorToken.accentBlue.opacity(0.12),
                                        foreground: PharTheme.ColorToken.accentBlue
                                    )
                                }

                                if let sectionHeadline = material.sectionHeadline {
                                    Text(sectionHeadline)
                                        .font(PharTypography.captionStrong)
                                        .foregroundStyle(PharTheme.ColorToken.accentBlue)
                                }

                                if let sectionSubheadline = material.sectionSubheadline {
                                    Text(sectionSubheadline)
                                        .font(PharTypography.caption)
                                        .foregroundStyle(PharTheme.ColorToken.subtleText)
                                }

                                ProgressView(value: material.completionRatio ?? 0)
                                    .tint(PharTheme.ColorToken.accentBlue)

                                if !material.sections.isEmpty {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: PharTheme.Spacing.xSmall) {
                                            ForEach(material.sections.prefix(6)) { section in
                                                VStack(alignment: .leading, spacing: PharTheme.Spacing.xxxSmall) {
                                                    Text(section.title)
                                                        .font(PharTypography.captionStrong)
                                                        .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                                                        .lineLimit(1)
                                                    Text("\(section.startPage)-\(section.endPage)")
                                                        .font(PharTypography.caption)
                                                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                                                    Text("\(section.percentComplete)% · \(section.status)")
                                                        .font(PharTypography.caption)
                                                        .foregroundStyle(PharTheme.ColorToken.subtleText)
                                                }
                                                .padding(PharTheme.Spacing.small)
                                                .frame(width: 156, alignment: .leading)
                                                .background(
                                                    RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                                                        .fill(PharTheme.ColorToken.surfaceSecondary)
                                                )
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                                                        .stroke(PharTheme.ColorToken.borderSoft, lineWidth: 1)
                                                )
                                            }
                                        }
                                        .padding(.vertical, PharTheme.Spacing.xxxSmall)
                                    }
                                }
                            }
                            .padding(.vertical, PharTheme.Spacing.xxxSmall)
                        }
                    }

                    if let rawJSON = viewModel.dashboardSnapshotJSONString {
                        Section("Raw JSON") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                Text(rawJSON)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                                    .textSelection(.enabled)
                            }

                            ShareLink(item: rawJSON) {
                                Label("JSON 공유", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                } else {
                    Section {
                        Text("생성된 dashboard snapshot이 없습니다. PDF를 하나 이상 등록하거나 진도를 저장한 뒤 다시 열어 보세요.")
                            .font(PharTypography.body)
                            .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                    }
                }
            }
            .navigationTitle("pharnode 대시보드")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("새로고침") {
                        viewModel.refreshDashboardSnapshot()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct StudyMaterialLibraryAdminSheet: View {
    @ObservedObject var viewModel: LibraryViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("라이브러리에서 교재 제목, 출처, 과목, 단원 시작 페이지를 바로 수정합니다. 저장하면 진도 문구와 dashboard snapshot도 함께 갱신됩니다.")
                        .font(PharTypography.body)
                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                }

                Section("교재") {
                    if viewModel.manageablePDFDocuments.isEmpty {
                        Text("등록된 PDF 교재가 없습니다.")
                            .font(PharTypography.body)
                            .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                    } else {
                        ForEach(viewModel.manageablePDFDocuments) { document in
                            NavigationLink(value: document) {
                                StudyMaterialAdminRow(document: document)
                            }
                        }
                    }
                }
            }
            .navigationTitle("교재 운영")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: PharDocument.self) { document in
                StudyMaterialDocumentAdminView(viewModel: viewModel, document: document)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}

private struct StudyMaterialAdminRow: View {
    let document: PharDocument

    var body: some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.xxxSmall) {
            Text(document.title)
                .font(PharTypography.bodyStrong)
                .foregroundStyle(PharTheme.ColorToken.inkPrimary)
            if let materialLine = document.materialSummaryLine {
                Text(materialLine)
                    .font(PharTypography.captionStrong)
                    .foregroundStyle(PharTheme.ColorToken.accentBlue)
            }
            Text(document.progressSummaryLine ?? "진도 정보 없음")
                .font(PharTypography.caption)
                .foregroundStyle(PharTheme.ColorToken.inkSecondary)
            if let progressDetailLine = document.progressDetailLine {
                Text(progressDetailLine)
                    .font(PharTypography.caption)
                    .foregroundStyle(PharTheme.ColorToken.subtleText)
            }
        }
        .padding(.vertical, PharTheme.Spacing.xxxSmall)
    }
}

private struct StudyMaterialDocumentAdminView: View {
    @ObservedObject var viewModel: LibraryViewModel
    let document: PharDocument

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var provider: StudyMaterialProvider
    @State private var subject: StudySubject
    @State private var drafts: [LibraryViewModel.StudySectionDraft]
    @State private var isSaving = false

    init(viewModel: LibraryViewModel, document: PharDocument) {
        self.viewModel = viewModel
        self.document = document
        _title = State(initialValue: document.studyMaterial?.canonicalTitle ?? document.title)
        _provider = State(initialValue: document.studyMaterial?.provider ?? .unspecified)
        _subject = State(initialValue: document.studyMaterial?.subject ?? .unspecified)
        _drafts = State(initialValue: viewModel.sectionDrafts(for: document))
    }

    var body: some View {
        Form {
            Section("교재 메타데이터") {
                TextField("교재 제목", text: $title)

                Picker("출처", selection: $provider) {
                    ForEach(StudyMaterialProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }

                Picker("과목", selection: $subject) {
                    ForEach(StudySubject.allCases) { subject in
                        Text(subject.title).tag(subject)
                    }
                }

                if let progressLine = document.progressSummaryLine {
                    LabeledContent("현재 진도", value: progressLine)
                }
            }

            Section("단원 구간") {
                ForEach($drafts) { $draft in
                    VStack(alignment: .leading, spacing: PharTheme.Spacing.xSmall) {
                        TextField("단원명", text: $draft.title)

                        TextField("시작 페이지", value: $draft.startPage, format: .number)
                            .keyboardType(.numberPad)

                        Text("예상 범위: \(draft.startPage)-\(resolvedEndPage(for: draft.id))")
                            .font(PharTypography.caption)
                            .foregroundStyle(PharTheme.ColorToken.inkSecondary)

                        Button(role: .destructive) {
                            removeDraft(id: draft.id)
                        } label: {
                            Label("이 단원 삭제", systemImage: "trash")
                        }
                        .disabled(drafts.count == 1)
                    }
                    .padding(.vertical, PharTheme.Spacing.xxxSmall)
                }

                Button {
                    drafts.append(viewModel.suggestedSectionDraft(for: document, existingDrafts: drafts))
                } label: {
                    Label("새 단원 추가", systemImage: "plus")
                }
            }

            Section("저장 영향") {
                Text("저장하면 라이브러리 카드, PDF 헤더, pharnode dashboard snapshot JSON이 모두 새 메타데이터와 단원 구간 기준으로 갱신됩니다.")
                    .font(PharTypography.caption)
                    .foregroundStyle(PharTheme.ColorToken.inkSecondary)
            }
        }
        .navigationTitle("교재 수정")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
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

    private func resolvedEndPage(for draftID: UUID) -> Int {
        let sortedDrafts = drafts.sorted { lhs, rhs in
            if lhs.startPage == rhs.startPage {
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            return lhs.startPage < rhs.startPage
        }

        guard let index = sortedDrafts.firstIndex(where: { $0.id == draftID }) else {
            return max(document.progress?.totalPages ?? 1, 1)
        }

        let nextStart = index + 1 < sortedDrafts.count
            ? sortedDrafts[index + 1].startPage
            : max(document.progress?.totalPages ?? 1, 1) + 1

        return max(min(nextStart - 1, max(document.progress?.totalPages ?? 1, 1)), min(sortedDrafts[index].startPage, max(document.progress?.totalPages ?? 1, 1)))
    }

    private func removeDraft(id: UUID) {
        guard drafts.count > 1 else { return }
        drafts.removeAll { $0.id == id }
    }

    private func save() {
        isSaving = true
        let saved = viewModel.saveStudyMaterialAdministration(
            documentID: document.id,
            title: title,
            provider: provider,
            subject: subject,
            sectionDrafts: drafts
        )
        isSaving = false

        if saved {
            dismiss()
        }
    }
}

private struct StudyMaterialCatalogManagementView: View {
    @ObservedObject var viewModel: LibraryViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingCatalogImportPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section("상태") {
                    LabeledContent("번들 시드", value: "\(viewModel.catalogSummary.bundledEntryCount)개")
                    LabeledContent("추가 가져온 항목", value: "\(viewModel.catalogSummary.importedEntryCount)개")
                    LabeledContent("현재 병합 항목", value: "\(viewModel.catalogSummary.mergedEntryCount)개")
                    if let lastImportedAt = viewModel.catalogSummary.lastImportedAt {
                        LabeledContent("마지막 가져오기", value: lastImportedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }

                Section("출처별 분포") {
                    ForEach(viewModel.catalogSummary.providerCounts) { item in
                        HStack {
                            Text(item.title)
                            Spacer()
                            Text("\(item.count)")
                                .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                        }
                    }
                }

                Section("과목별 분포") {
                    ForEach(viewModel.catalogSummary.subjectCounts) { item in
                        HStack {
                            Text(item.title)
                            Spacer()
                            Text("\(item.count)")
                                .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                        }
                    }
                }

                Section("운영") {
                    Button {
                        isShowingCatalogImportPicker = true
                    } label: {
                        Label("카탈로그 JSON/CSV 가져오기", systemImage: "square.and.arrow.down")
                    }

                    Button(role: .destructive) {
                        viewModel.resetImportedStudyMaterialCatalog()
                    } label: {
                        Label("가져온 카탈로그 제거", systemImage: "trash")
                    }
                    .disabled(!viewModel.catalogSummary.hasImportedOverride)

                    Text("JSON은 `version`과 `entries`를 포함해야 하고, CSV는 `id,canonicalTitle,provider,subject,aliases` 순서의 헤더를 권장합니다. `aliases`는 `|`로 구분합니다. 가져온 카탈로그는 번들 시드 위에 병합됩니다.")
                        .font(PharTypography.caption)
                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                }

                if let preview = viewModel.catalogImportPreview {
                    Section("가져오기 미리보기") {
                        LabeledContent("파일", value: preview.sourceFileName)
                        LabeledContent("형식", value: preview.formatLabel)
                        LabeledContent("유효 항목", value: "\(preview.totalValidEntryCount)개")
                        LabeledContent("신규 추가", value: "\(preview.newEntryCount)개")
                        LabeledContent("기존 교체", value: "\(preview.replacingEntryCount)개")
                        LabeledContent("무효 행", value: "\(preview.invalidRows.count)개")

                        if !preview.invalidRows.isEmpty {
                            VStack(alignment: .leading, spacing: PharTheme.Spacing.xSmall) {
                                Text("무효 행 샘플")
                                    .font(PharTypography.captionStrong)
                                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)

                                ForEach(Array(preview.invalidRows.prefix(5))) { invalidRow in
                                    Text("라인 \(invalidRow.lineNumber): \(invalidRow.reason)")
                                        .font(PharTypography.caption)
                                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                                }
                            }
                        }

                        Button {
                            viewModel.confirmStudyMaterialCatalogImport()
                        } label: {
                            Label("미리보기 확정하여 저장", systemImage: "tray.and.arrow.down")
                        }

                        Button(role: .cancel) {
                            viewModel.cancelStudyMaterialCatalogImport()
                        } label: {
                            Label("미리보기 취소", systemImage: "xmark")
                        }
                    }
                }
            }
            .navigationTitle("교재 카탈로그")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingCatalogImportPicker) {
            CatalogImportPicker { url in
                isShowingCatalogImportPicker = false
                viewModel.importStudyMaterialCatalog(from: url)
            } onCancelled: {
                isShowingCatalogImportPicker = false
            }
        }
    }
}

private struct StudyMaterialImportSheet: View {
    let pending: LibraryViewModel.PendingPDFImportSelection
    let onSave: (String, StudyMaterialProvider, StudySubject) -> Void
    let onSkip: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var provider: StudyMaterialProvider
    @State private var subject: StudySubject

    init(
        pending: LibraryViewModel.PendingPDFImportSelection,
        onSave: @escaping (String, StudyMaterialProvider, StudySubject) -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.pending = pending
        self.onSave = onSave
        self.onSkip = onSkip
        _title = State(initialValue: pending.suggestion.normalizedTitle)
        _provider = State(initialValue: pending.suggestion.provider)
        _subject = State(initialValue: pending.suggestion.subject)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("자동 인식") {
                    LabeledContent("파일", value: pending.document.title)
                    if let pdfTitle = pending.suggestion.pdfTitle {
                        LabeledContent("PDF 제목", value: pdfTitle)
                    }
                    if let matchedCatalogEntry = pending.suggestion.matchedCatalogEntry {
                        LabeledContent("카탈로그 매치", value: matchedCatalogEntry.canonicalTitle)
                    }
                    LabeledContent("신뢰도", value: "\(Int((pending.suggestion.confidence * 100).rounded()))%")
                    if let totalPages = pending.suggestion.totalPages {
                        LabeledContent("전체 페이지", value: "\(totalPages)")
                    }
                    if !pending.suggestion.matchedSignals.isEmpty {
                        Text(pending.suggestion.matchedSignals.joined(separator: " · "))
                            .font(PharTypography.caption)
                            .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                    }
                }

                Section("교재 정리") {
                    TextField("교재 제목", text: $title)

                    Picker("출처", selection: $provider) {
                        ForEach(StudyMaterialProvider.allCases) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }

                    Picker("과목", selection: $subject) {
                        ForEach(StudySubject.allCases) { subject in
                            Text(subject.title).tag(subject)
                        }
                    }
                }

                Section("진도 추적") {
                    Text("이 PDF는 교재 메타데이터와 진도 스냅샷이 함께 저장됩니다. 이후 pharnode 대시보드에서 어느 교재의 몇 페이지까지 진행했는지 표시할 수 있는 export 기반이 됩니다.")
                        .font(PharTypography.caption)
                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                }
            }
            .navigationTitle("교재 등록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("나중에") {
                        onSkip()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        onSave(title, provider, subject)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct DocumentTypeIcon: View {
    let document: PharDocument
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
            .fill(iconBackground)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: document.type == .blankNote ? "square.and.pencil" : "doc.richtext")
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)
            }
    }

    private var iconBackground: LinearGradient {
        LinearGradient(
            colors: document.type == .blankNote
            ? [PharTheme.ColorToken.accentMint.opacity(0.82), PharTheme.ColorToken.accentBlue.opacity(0.18)]
            : [PharTheme.ColorToken.accentPeach.opacity(0.86), PharTheme.ColorToken.accentButter.opacity(0.24)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct LoopStepCard: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
            Text(number)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PharTheme.ColorToken.accentBlue)
            Text(title)
                .font(PharTypography.cardTitle)
                .foregroundStyle(PharTheme.ColorToken.inkPrimary)
            Text(detail)
                .font(PharTypography.caption)
                .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PharTheme.Spacing.medium)
        .background(
            RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                .fill(PharTheme.ColorToken.surfaceSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                .stroke(PharTheme.ColorToken.borderSoft, lineWidth: 1)
        )
    }
}

private struct AnalysisReviewQueueView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var analysisCenter: AnalysisCenter

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PharTheme.Spacing.large) {
                    PharSurfaceCard(fill: PharTheme.ColorToken.surfacePrimary.opacity(0.96)) {
                        VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
                            Text("Adaptive Review Queue")
                                .font(PharTypography.sectionTitle)
                                .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                            Text("분석 결과를 실제 복습 액션으로 전환한 작업 목록입니다.")
                                .font(PharTypography.body)
                                .foregroundStyle(PharTheme.ColorToken.inkSecondary)

                            HStack(spacing: PharTheme.Spacing.small) {
                                PharTagPill(
                                    text: "대기 \(analysisCenter.pendingReviewTaskCount)",
                                    tint: PharTheme.ColorToken.accentBlue.opacity(0.16)
                                )
                                PharTagPill(
                                    text: "임박 \(analysisCenter.dueSoonReviewTaskCount)",
                                    tint: PharTheme.ColorToken.accentCoral.opacity(0.16)
                                )
                                PharTagPill(
                                    text: "전체 \(analysisCenter.reviewTasks.count)",
                                    tint: PharTheme.ColorToken.accentMint.opacity(0.16)
                                )
                            }
                        }
                    }

                    if analysisCenter.reviewTasks.isEmpty {
                        PharSurfaceCard(fill: PharTheme.ColorToken.surfacePrimary.opacity(0.94)) {
                            VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
                                Text("아직 복습 큐가 없습니다")
                                    .font(PharTypography.bodyStrong)
                                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                                Text("페이지를 분석하면 자동으로 재확인, 개념 연습, 노트 재구성 작업이 생성됩니다.")
                                    .font(PharTypography.caption)
                                    .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                            }
                        }
                    } else {
                        reviewSection(
                            title: "Pending",
                            tasks: analysisCenter.reviewTasks.filter { $0.status == .pending }
                        )

                        if analysisCenter.reviewTasks.contains(where: { $0.status == .completed }) {
                            reviewSection(
                                title: "Completed",
                                tasks: analysisCenter.reviewTasks.filter { $0.status == .completed }
                            )
                        }

                        if analysisCenter.reviewTasks.contains(where: { $0.status == .dismissed }) {
                            reviewSection(
                                title: "Dismissed",
                                tasks: analysisCenter.reviewTasks.filter { $0.status == .dismissed }
                            )
                        }
                    }
                }
                .padding(PharTheme.Spacing.large)
            }
            .background(PharTheme.GradientToken.appBackdrop.ignoresSafeArea())
            .navigationTitle("복습 큐")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await analysisCenter.refreshQueue()
        }
    }

    @ViewBuilder
    private func reviewSection(title: String, tasks: [AnalysisReviewTask]) -> some View {
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                Text(title)
                    .font(PharTypography.eyebrow)
                    .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                    .textCase(.uppercase)

                ForEach(tasks) { task in
                    ReviewTaskCard(task: task)
                }
            }
        }
    }
}

private struct ReviewTaskCard: View {
    @EnvironmentObject private var analysisCenter: AnalysisCenter

    let task: AnalysisReviewTask

    var body: some View {
        PharSurfaceCard(fill: PharTheme.ColorToken.surfacePrimary.opacity(0.96)) {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
                HStack(alignment: .top, spacing: PharTheme.Spacing.small) {
                    VStack(alignment: .leading, spacing: PharTheme.Spacing.xxxSmall) {
                        HStack(spacing: PharTheme.Spacing.xSmall) {
                            PharTagPill(
                                text: task.kind.title,
                                tint: pillTint,
                                foreground: PharTheme.ColorToken.inkPrimary
                            )
                            PharTagPill(
                                text: task.status.title,
                                tint: statusTint,
                                foreground: task.status == .dismissed ? PharTheme.ColorToken.accentCoral : PharTheme.ColorToken.inkPrimary
                            )
                                if task.isDueSoon {
                                    PharTagPill(
                                        text: "곧 다시 보기",
                                        tint: PharTheme.ColorToken.accentCoral.opacity(0.16),
                                        foreground: PharTheme.ColorToken.accentCoral
                                    )
                                }
                        }

                        Text(task.title)
                            .font(PharTypography.bodyStrong)
                            .foregroundStyle(PharTheme.ColorToken.inkPrimary)

                        Text("\(task.documentTitle) · \(task.pageLabel)")
                            .font(PharTypography.captionStrong)
                            .foregroundStyle(PharTheme.ColorToken.accentBlue)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: PharTheme.Spacing.xxxSmall) {
                        Text(task.dueAt, style: .relative)
                            .font(PharTypography.captionStrong)
                            .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                        Text("복습 예정")
                            .font(PharTypography.caption)
                            .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                    }
                }

                Text(task.detail)
                    .font(PharTypography.caption)
                    .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: PharTheme.Spacing.xSmall) {
                    if let subject = task.subjectLabel {
                        PharTagPill(text: subject, tint: PharTheme.ColorToken.accentBlue.opacity(0.12))
                    }
                    if let unit = task.unitLabel {
                        PharTagPill(text: unit, tint: PharTheme.ColorToken.accentMint.opacity(0.12))
                    }
                    if let concept = task.conceptLabel {
                        PharTagPill(text: concept, tint: PharTheme.ColorToken.accentButter.opacity(0.16))
                    }
                }

                if task.status == .pending {
                    HStack(spacing: PharTheme.Spacing.small) {
                        Button {
                            Task {
                                await analysisCenter.markReviewTaskCompleted(task)
                            }
                        } label: {
                            Label("완료", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(PharPrimaryButtonStyle())

                        Button {
                            Task {
                                await analysisCenter.dismissReviewTask(task)
                            }
                        } label: {
                            Label("제외", systemImage: "minus.circle")
                        }
                        .buttonStyle(PharSoftButtonStyle())
                    }
                }
            }
        }
    }

    private var pillTint: Color {
        switch task.kind {
        case .revisitPage:
            return PharTheme.ColorToken.accentBlue.opacity(0.14)
        case .practiceConcept:
            return PharTheme.ColorToken.accentMint.opacity(0.16)
        case .restructureNotes:
            return PharTheme.ColorToken.accentButter.opacity(0.18)
        }
    }

    private var statusTint: Color {
        switch task.status {
        case .pending:
            return PharTheme.ColorToken.surfaceSecondary
        case .completed:
            return PharTheme.ColorToken.accentMint.opacity(0.16)
        case .dismissed:
            return PharTheme.ColorToken.accentCoral.opacity(0.12)
        }
    }
}

private struct PharnodeCloudSyncView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: PharnodeSupabaseAuthManager
    @EnvironmentObject private var cloudSyncManager: PharnodeCloudSyncManager

    @State private var baseURLString: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isEnabled: Bool = false
    @State private var isSaving = false
    @State private var isSigningIn = false

    private var showsInternalTools: Bool {
        PharFeatureFlags.showsInternalTools
    }

    var body: some View {
        NavigationStack {
            List {
                Section("연결") {
                    Toggle("pharnode Supabase 동기화 사용", isOn: $isEnabled)

                    if showsInternalTools {
                        TextField("Supabase Project URL", text: $baseURLString)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    } else {
                        LabeledContent("연결 대상", value: "pharnode cloud")
                    }

                    LabeledContent("로그인 상태", value: authManager.isAuthenticated ? "연결됨" : "로그인 필요")

                    HStack {
                        Text("상태")
                        Spacer()
                        Text(cloudSyncManager.syncState.title)
                            .foregroundStyle(statusColor)
                    }

                    if let lastSuccessfulSyncAt = cloudSyncManager.lastSuccessfulSyncAt {
                        LabeledContent("마지막 성공", value: lastSuccessfulSyncAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }

                Section("안내") {
                    Text("로그인만 완료하면 페이지 인사이트와 교재 진도 정보가 pharnode와 함께 이어집니다.")
                        .font(PharTypography.caption)
                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                }

                Section("계정") {
                    if let authenticatedEmail = authManager.authenticatedEmail {
                        LabeledContent("사용자", value: authenticatedEmail)
                        if showsInternalTools, let userID = authManager.userID {
                            LabeledContent("User ID", value: userID)
                        }
                        Button("로그아웃", role: .destructive) {
                            Task {
                                await authManager.signOut()
                            }
                        }
                    } else {
                        TextField("pharnode 이메일", text: $email)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)

                        SecureField("비밀번호", text: $password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Button {
                            signIn()
                        } label: {
                            if isSigningIn {
                                ProgressView()
                            } else {
                                Label("로그인", systemImage: "person.badge.key")
                            }
                        }
                        .disabled(isSigningIn)
                    }
                }

                Section(showsInternalTools ? "아웃박스" : "동기화 상태") {
                    LabeledContent("대기", value: "\(cloudSyncManager.pendingCount)")
                    LabeledContent("실패", value: "\(cloudSyncManager.failedCount)")

                    if showsInternalTools, let nextPendingItem = cloudSyncManager.nextPendingItem {
                        VStack(alignment: .leading, spacing: PharTheme.Spacing.xxxSmall) {
                            Text("다음 전송")
                                .font(PharTypography.captionStrong)
                                .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                            Text("\(nextPendingItem.kind.title) · \(nextPendingItem.title)")
                                .font(PharTypography.caption)
                                .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                        }
                    }

                    Button {
                        Task {
                            await cloudSyncManager.syncNow()
                        }
                    } label: {
                        Label("지금 동기화", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(!isEnabled)
                }

                if showsInternalTools, !cloudSyncManager.outboxItems.isEmpty {
                    Section("최근 항목") {
                        ForEach(cloudSyncManager.outboxItems.prefix(8)) { item in
                            VStack(alignment: .leading, spacing: PharTheme.Spacing.xxxSmall) {
                                HStack {
                                    Text(item.kind.title)
                                        .font(PharTypography.captionStrong)
                                        .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                                    Spacer()
                                    Text(item.status.title)
                                        .font(PharTypography.caption)
                                        .foregroundStyle(color(for: item.status))
                                }

                                Text(item.title)
                                    .font(PharTypography.caption)
                                    .foregroundStyle(PharTheme.ColorToken.inkSecondary)

                                if let lastErrorMessage = item.lastErrorMessage, !lastErrorMessage.isEmpty {
                                    Text(lastErrorMessage)
                                        .font(PharTypography.caption)
                                        .foregroundStyle(PharTheme.ColorToken.accentCoral)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section(showsInternalTools ? "운영 원칙" : "동작 방식") {
                    Text("분석 번들과 dashboard snapshot은 로컬 outbox에 먼저 적재한 뒤 Supabase Edge Functions로 비동기 전송합니다. 같은 bundle은 stable dedupe key로 재시도되며, 서버는 idempotent하게 처리합니다.")
                        .font(PharTypography.caption)
                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                }
            }
            .navigationTitle("파르노드 연결")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
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
                }
            }
        }
        .task {
            baseURLString = cloudSyncManager.configuration.baseURLString
            isEnabled = cloudSyncManager.configuration.isEnabled
            await cloudSyncManager.refreshOutbox()
        }
        .alert("연결 오류", isPresented: errorPresented) {
            Button("확인", role: .cancel) {
                cloudSyncManager.clearError()
                authManager.clearError()
            }
        } message: {
            Text(cloudSyncManager.errorMessage ?? authManager.errorMessage ?? "")
        }
    }

    private var statusColor: Color {
        switch cloudSyncManager.syncState {
        case .paused:
            return PharTheme.ColorToken.inkSecondary
        case .idle:
            return PharTheme.ColorToken.accentBlue
        case .syncing:
            return PharTheme.ColorToken.accentMint
        case .error:
            return PharTheme.ColorToken.accentCoral
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { cloudSyncManager.errorMessage != nil || authManager.errorMessage != nil },
            set: { shouldShow in
                if !shouldShow {
                    cloudSyncManager.clearError()
                    authManager.clearError()
                }
            }
        )
    }

    private func color(for status: PharnodeCloudSyncItemStatus) -> Color {
        switch status {
        case .queued:
            return PharTheme.ColorToken.inkSecondary
        case .syncing:
            return PharTheme.ColorToken.accentBlue
        case .synced:
            return PharTheme.ColorToken.accentMint
        case .failed:
            return PharTheme.ColorToken.accentCoral
        }
    }

    private func save() {
        isSaving = true
        Task {
            await cloudSyncManager.updateConfiguration(
                baseURLString: baseURLString,
                isEnabled: isEnabled
            )
            await MainActor.run {
                isSaving = false
            }
        }
    }

    private func signIn() {
        isSigningIn = true
        Task {
            let success = await authManager.signIn(
                email: email,
                password: password,
                baseURLString: baseURLString
            )
            if success {
                await cloudSyncManager.updateConfiguration(
                    baseURLString: baseURLString,
                    isEnabled: isEnabled
                )
                await cloudSyncManager.syncNow()
                await MainActor.run {
                    password = ""
                }
            }
            await MainActor.run {
                isSigningIn = false
            }
        }
    }
}
