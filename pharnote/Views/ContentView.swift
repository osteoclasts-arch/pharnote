import PDFKit
import SwiftUI
import UIKit

struct ContentView: View {
    var body: some View {
        PharnoteHomeShellView()
    }
}

private enum HomeTab: String, CaseIterable, Identifiable {
    case notes
    case analysis
    case planner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notes:
            return "노트"
        case .analysis:
            return "노드 분석"
        case .planner:
            return "플래너"
        }
    }

    var systemName: String {
        switch self {
        case .notes:
            return "pencil.and.scribble"
        case .analysis:
            return "chart.bar"
        case .planner:
            return "calendar"
        }
    }
}

private struct PharnoteHomeShellView: View {
    @StateObject private var libraryViewModel = LibraryViewModel()
    @State private var selectedTab: HomeTab = .notes

    var body: some View {
        ZStack {
            HomePalette.background.ignoresSafeArea()

            switch selectedTab {
            case .notes:
                PharnoteNotesHomeView(viewModel: libraryViewModel)
            case .analysis:
                PharnoteAnalysisHomeView()
            case .planner:
                PharnotePlannerHomeView()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: showsTabBar ? 18 : 0) {
            if showsTabBar {
                HomeBottomTabBar(selectedTab: $selectedTab)
                    .padding(.horizontal, 24)
            }
        }
    }

    private var showsTabBar: Bool {
        switch selectedTab {
        case .notes:
            return libraryViewModel.navigationPath.isEmpty
        case .analysis, .planner:
            return true
        }
    }
}

private struct PharnoteNotesHomeView: View {
    @EnvironmentObject private var analysisCenter: AnalysisCenter

    @ObservedObject var viewModel: LibraryViewModel

    @State private var isShowingPDFImportPicker = false
    @State private var isShowingPastQuestionsDebug = false
    @State private var isShowingSettings = false
    @State private var isShowingSidebar = false
    @State private var isShowingGuide = false
    @State private var documentBeingRenamed: PharDocument?
    @State private var documentBeingShared: PharDocument?
    @State private var sidebarSearchQuery = ""
    @State private var expandedSidebarSections: Set<HomeSidebarSectionID> = [.korean]

    private var continueDocuments: [PharDocument] {
        Array(viewModel.filteredDocuments.prefix(8))
    }

    private var showsInternalTools: Bool {
        PharFeatureFlags.showsInternalTools
    }

    var body: some View {
        NavigationStack(path: $viewModel.navigationPath) {
            ZStack(alignment: .leading) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 38) {
                        HomeBrandBar(
                            logoAction: {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                    isShowingSidebar = true
                                }
                            },
                            trailing: {
                                Button {
                                    isShowingSettings = true
                                } label: {
                                    Image(systemName: "gearshape")
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundStyle(HomePalette.accent)
                                        .frame(width: 40, height: 40)
                                }
                                .buttonStyle(.plain)
                            }
                        )

                        HomeScreenTitle(
                            title: "홈",
                            systemName: "house",
                            subtitle: nil
                        )

                        quickActionSection

                        if showsInternalTools {
                            internalToolsSection
                        }

                        continueSection
                    }
                    .frame(maxWidth: 920, alignment: .leading)
                    .padding(.horizontal, 36)
                    .padding(.top, 26)
                    .padding(.bottom, 36)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .background(HomePalette.background.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
                .refreshable {
                    viewModel.loadDocuments()
                    await analysisCenter.refreshQueue()
                }
                .navigationDestination(for: DocumentEditorLaunchTarget.self) { target in
                    DocumentEditorView(document: target.document, initialPageKey: target.initialPageKey)
                }
                .overlay {
                    if isShowingSidebar {
                        Rectangle()
                            .fill(Color.black.opacity(0.14))
                            .ignoresSafeArea()
                            .transition(.opacity)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                                    isShowingSidebar = false
                                }
                            }
                    }
                }

                if isShowingSidebar {
                    HomeSidebarPanel(
                        searchQuery: $sidebarSearchQuery,
                        expandedSections: $expandedSidebarSections,
                        documents: viewModel.documents,
                        onSelectDocument: { document in
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                                isShowingSidebar = false
                            }
                            viewModel.openDocument(document)
                        },
                        onClose: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                                isShowingSidebar = false
                            }
                        }
                    )
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
                
                if isShowingGuide {
                    AppGuidePopupView(isPresented: $isShowingGuide)
                        .transition(.opacity)
                        .zIndex(100)
                }
            }
        }
        .environmentObject(viewModel)
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
        .sheet(isPresented: $isShowingSettings) {
            HomeSettingsSheet(
                totalDocuments: viewModel.totalDocumentCount,
                blankNotes: viewModel.blankNoteCount,
                pdfDocuments: viewModel.pdfCount
            )
        }
        .sheet(isPresented: $isShowingPastQuestionsDebug) {
            PastQuestionsDebugView()
        }
        .sheet(item: $documentBeingRenamed) { document in
            DocumentRenameSheet(
                title: document.title,
                onCancel: {
                    documentBeingRenamed = nil
                },
                onSave: { newTitle in
                    do {
                        let savedDocument = try viewModel.renameDocument(document, to: newTitle)
                        if documentBeingShared?.id == document.id {
                            documentBeingShared = savedDocument
                        }
                        documentBeingRenamed = nil
                    } catch {
                        viewModel.errorMessage = error.localizedDescription
                    }
                }
            )
        }
        .sheet(item: $documentBeingShared) { document in
            WritingDocumentShareSheet(items: WritingDocumentShareSource.activityItems(for: document))
        }
        .sheet(item: $viewModel.pendingPDFImportSelection) { pending in
            HomeStudyMaterialImportSheet(
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
        .onChange(of: viewModel.navigationPath.count) { _, newCount in
            if newCount > 0 {
                isShowingSidebar = false
            }
        }
    }

    private var quickActionSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 28) {
                HomeQuickActionCard(
                    title: "새 노트",
                    systemName: "plus",
                    cardWidth: 218,
                    action: {
                        viewModel.createBlankNote()
                    }
                )

                HomeQuickActionCard(
                    title: "불러오기",
                    systemName: "square.and.arrow.down",
                    cardWidth: 218,
                    action: {
                        isShowingPDFImportPicker = true
                    }
                )
                
                HomeQuickActionCard(
                    title: "사용 가이드",
                    systemName: "lightbulb.fill",
                    cardWidth: 218,
                    action: {
                        withAnimation { isShowingGuide = true }
                    }
                )
            }

            VStack(alignment: .leading, spacing: 18) {
                HomeQuickActionCard(
                    title: "새 노트",
                    systemName: "plus",
                    action: {
                        viewModel.createBlankNote()
                    }
                )

                HomeQuickActionCard(
                    title: "불러오기",
                    systemName: "square.and.arrow.down",
                    action: {
                        isShowingPDFImportPicker = true
                    }
                )
                
                HomeQuickActionCard(
                    title: "사용 가이드",
                    systemName: "lightbulb.fill",
                    action: {
                        withAnimation { isShowingGuide = true }
                    }
                )
            }
        }
    }

    private var internalToolsSection: some View {
        HomeSurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("TutorHub 기출 DB")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(HomePalette.textPrimary)

                Text("`public.past_questions`를 read-only로 조회하는 내부 디버그 패널입니다. exact lookup, text search, image_url 렌더링을 여기서 바로 확인할 수 있습니다.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(HomePalette.textSecondary)

                Button("기출 DB 열기") {
                    isShowingPastQuestionsDebug = true
                }
                .buttonStyle(HomeFilledButtonStyle())
            }
        }
    }

    private var continueSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 8) {
                Text("이어쓰기")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(HomePalette.textPrimary)

                Image(systemName: "square.and.pencil")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(HomePalette.textPrimary)
            }

            if continueDocuments.isEmpty {
                HomeEmptyContinueCard(
                    createNoteAction: {
                        viewModel.createBlankNote()
                    },
                    importPDFAction: {
                        isShowingPDFImportPicker = true
                    }
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 22) {
                        ForEach(continueDocuments) { document in
                            HomeContinueDocumentCard(
                                document: document,
                                onOpen: {
                                    viewModel.openDocument(document)
                                },
                                onRename: {
                                    documentBeingRenamed = document
                                },
                                onShare: {
                                    documentBeingShared = document
                                }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
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
}

private struct PharnoteAnalysisHomeView: View {
    var body: some View {
        NodeAnalysisWorkspaceView()
    }
}

private struct PharnotePlannerHomeView: View {
    @EnvironmentObject private var plannerCenter: PlannerCenter
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isShowingPlannerOptions = false
    @State private var isShowingTaskEditor = false
    @State private var shouldOpenTaskEditorAfterOptionsDismiss = false
    @State private var taskDraft = PlannerTaskDraft()

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HomeBrandBar(
                    trailing: {
                        Button {
                            isShowingPlannerOptions = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 25, weight: .semibold))
                                .foregroundStyle(HomePalette.accent)
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
                    }
                )

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text(plannerCenter.monthLabel)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(HomePalette.textPrimary)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(HomePalette.textPrimary)
                            .offset(y: 1)
                    }
                }
                .padding(.top, 34)

                HomePlannerDateStrip(
                    dates: plannerCenter.dayStripDates,
                    selectedDate: plannerCenter.selectedDate,
                    onSelectDate: { plannerCenter.selectDate($0) }
                )
                .padding(.top, 24)

                HomePlannerDaySnapshotCard()
                    .padding(.top, 30)

                HomePlannerProgressCard(
                    progressFraction: plannerCenter.progressFraction,
                    caption: "오늘 할 일",
                    completionText: "\(Int((plannerCenter.progressFraction * 100).rounded()))%",
                    summaryText: "완료했습니다."
                ) {
                    Button {
                        taskDraft = PlannerTaskDraft(dueDate: plannerCenter.selectedDate)
                        isShowingTaskEditor = true
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .semibold))
                            Text("수정")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(HomePalette.textSecondary)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(HomePalette.border, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 24)

                if plannerCenter.selectedDateHasTasks {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(plannerCenter.groupedSelectedTasks) { section in
                            HomePlannerSubjectSection(section: section)
                        }
                    }
                    .padding(.top, 22)
                } else {
                    HomePlannerEmptyStateCard {
                        taskDraft = PlannerTaskDraft(dueDate: plannerCenter.selectedDate)
                        isShowingTaskEditor = true
                    }
                    .padding(.top, 22)
                }
            }
            .frame(maxWidth: 1040, alignment: .leading)
            .padding(.horizontal, horizontalSizeClass == .regular ? 58 : 24)
            .padding(.top, 22)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(HomePalette.background.ignoresSafeArea())
        .task {
            await plannerCenter.refresh()
        }
        .sheet(isPresented: $isShowingPlannerOptions) {
            HomePlannerOptionsSheet(
                addTaskAction: {
                    shouldOpenTaskEditorAfterOptionsDismiss = true
                },
                resetAction: {
                    plannerCenter.resetToSeed()
                }
            )
        }
        .onChange(of: isShowingPlannerOptions) { _, isPresented in
            guard !isPresented, shouldOpenTaskEditorAfterOptionsDismiss else { return }
            shouldOpenTaskEditorAfterOptionsDismiss = false
            taskDraft = PlannerTaskDraft(dueDate: plannerCenter.selectedDate)
            isShowingTaskEditor = true
        }
        .sheet(isPresented: $isShowingTaskEditor) {
            HomePlannerTaskEditorSheet(
                draft: $taskDraft,
                onSave: { draft in
                    plannerCenter.addTask(from: draft)
                }
            )
        }
    }
}

private struct HomePlannerDateStrip: View {
    let dates: [Date]
    let selectedDate: Date
    let onSelectDate: (Date) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Button {
                    onSelectDate(Date())
                } label: {
                    Text("Today")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(selectedDate.isToday ? Color.white : HomePalette.textPrimary)
                        .padding(.horizontal, 22)
                        .frame(height: 38)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selectedDate.isToday ? HomePalette.accent : Color.clear)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(HomePalette.tabBorder, lineWidth: 1.6)
                        )
                }
                .buttonStyle(.plain)

                ForEach(dates, id: \.self) { date in
                    Button {
                        onSelectDate(date)
                    } label: {
                        HStack(spacing: 8) {
                            Text(HomeFormatters.dayNumber.string(from: date))
                                .font(.system(size: 18, weight: .bold, design: .rounded))

                            Text(HomeFormatters.weekdayShort.string(from: date).uppercased())
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(selectedDate.isSameDay(as: date) ? Color.white : HomePalette.textPrimary)
                        .padding(.horizontal, 20)
                        .frame(height: 38)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selectedDate.isSameDay(as: date) ? HomePalette.textPrimary : Color.clear)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(HomePalette.tabBorder, lineWidth: 1.6)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct HomePlannerDaySnapshotCard: View {
    @EnvironmentObject private var plannerCenter: PlannerCenter

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(plannerCenter.weekdayLabel)
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .foregroundStyle(HomePalette.textPrimary)

                Text(plannerCenter.dayNumberLabel)
                    .font(.system(size: 68, weight: .black, design: .rounded))
                    .foregroundStyle(HomePalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 114, alignment: .leading)
            .padding(.top, 18)

            VStack(alignment: .leading, spacing: 10) {
                if let first = plannerCenter.dDayItems.first {
                    HomePlannerDDayCard(item: first, emphasis: true)
                }

                if plannerCenter.dDayItems.count > 1 {
                    ForEach(plannerCenter.dDayItems.dropFirst().prefix(2)) { item in
                        HomePlannerDDayCard(item: item, emphasis: false)
                    }
                }
            }
            .frame(width: 230, alignment: .leading)
            .padding(.top, 14)

            Rectangle()
                .fill(HomePalette.border.opacity(0.72))
                .frame(width: 1, height: 180)
                .padding(.top, 18)

            VStack(alignment: .leading, spacing: 16) {
                if plannerCenter.selectedDateAgendaItems.isEmpty {
                    Text("오늘 일정이 없습니다")
                        .font(.system(size: 19, weight: .medium, design: .rounded))
                        .foregroundStyle(HomePalette.textSecondary)
                } else {
                    ForEach(plannerCenter.selectedDateAgendaItems.prefix(4)) { task in
                        HomePlannerAgendaRow(task: task)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

private struct HomePlannerDDayCard: View {
    let item: PlannerDDayItem
    let emphasis: Bool

    private var tint: Color {
        Color(homeHex: item.accentHex)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(item.displayLabel)
                .font(.system(size: emphasis ? 28 : 20, weight: .black, design: .rounded))
                .foregroundStyle(HomePalette.textPrimary)

            Text(item.title)
                .font(.system(size: emphasis ? 19 : 15, weight: .semibold, design: .rounded))
                .foregroundStyle(HomePalette.textPrimary)
                .lineLimit(1)

            if emphasis {
                Text("☺")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(HomePalette.textPrimary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, emphasis ? 18 : 14)
        .padding(.vertical, emphasis ? 14 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: emphasis ? 96 : 48)
        .background(
            RoundedRectangle(cornerRadius: emphasis ? 14 : 12, style: .continuous)
                .fill(tint.opacity(emphasis ? 0.95 : 0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: emphasis ? 14 : 12, style: .continuous)
                .stroke(HomePalette.textPrimary.opacity(0.72), lineWidth: emphasis ? 1.7 : 1.2)
        )
    }
}

private struct HomePlannerAgendaRow: View {
    let task: PlannerTask

    private var timeText: String? {
        guard let scheduledAt = task.scheduledAt else { return nil }
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: scheduledAt)
        let minute = calendar.component(.minute, from: scheduledAt)
        let displayHour = hour % 12 == 0 ? 12 : hour % 12
        if minute == 0 {
            return "\(displayHour)시"
        }
        return "\(displayHour)시 \(String(format: "%02d", minute))분"
    }

    private var displayTitle: String {
        let note = task.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (note?.isEmpty == false ? note : nil) ?? task.title
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let timeText {
                Text(timeText)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(HomePalette.textSecondary)
                    .frame(width: 70, alignment: .leading)
            }

            Text(displayTitle)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(HomePalette.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }
}

private struct HomePlannerEmptyStateCard: View {
    var action: (() -> Void)?

    init(action: (() -> Void)? = nil) {
        self.action = action
    }

    var body: some View {
        HomeSurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("지금 처리할 복습 작업이 없습니다")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(HomePalette.textPrimary)

                Text("분석 결과에서 추천 작업이 생기면 이곳에 자동으로 쌓입니다.")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(HomePalette.textSecondary)
                    .lineSpacing(2)

                if let action {
                    Button("할 일 추가") {
                        action()
                    }
                    .buttonStyle(HomeFilledButtonStyle())
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct HomePlannerProgressCard<Trailing: View>: View {
    let progressFraction: Double
    let caption: String
    let completionText: String
    let summaryText: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(caption)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(HomePalette.textSecondary)

                Text(completionText)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(HomePalette.textPrimary)

                Text(summaryText)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(HomePalette.textSecondary)

                Spacer(minLength: 0)

                trailing
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(HomePalette.tabBorder, lineWidth: 1)
                        )

                    Rectangle()
                        .fill(HomePalette.accent.opacity(0.72))
                        .frame(width: max(0, proxy.size.width * progressFraction))
                }
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
            .frame(height: 15)
        }
    }
}

private struct HomePlannerSubjectSection: View {
    let section: PlannerSubjectGroup

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Text(section.subject.title)
                .font(.system(size: 23, weight: .black, design: .rounded))
                .foregroundStyle(HomePalette.textPrimary)
                .frame(width: 68, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(section.tasks) { task in
                    HomePlannerTaskCard(task: task)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct HomePlannerTaskCard: View {
    @EnvironmentObject private var plannerCenter: PlannerCenter

    let task: PlannerTask

    private var titleTint: Color {
        switch task.priority {
        case .high:
            return HomePalette.orangeTint
        case .normal:
            return HomePalette.yellowTint
        case .low:
            return HomePalette.greenTint
        }
    }

    private var scheduleText: String? {
        guard let scheduledAt = task.scheduledAt else { return nil }
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: scheduledAt)
        let minute = calendar.component(.minute, from: scheduledAt)
        let displayHour = hour % 12 == 0 ? 12 : hour % 12
        if minute == 0 {
            return "\(displayHour)시"
        }
        return "\(displayHour)시 \(String(format: "%02d", minute))분"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if let scheduleText {
                Text(scheduleText)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(HomePalette.textSecondary)
                    .frame(width: 58, alignment: .leading)
            }

            Text(task.title)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(HomePalette.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 2)
                .padding(.vertical, 1)
                .background {
                    if task.isCompleted {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(titleTint.opacity(0.72))
                    }
                }

            Spacer(minLength: 0)

            Text(task.isCompleted ? "✓" : "□")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(HomePalette.textPrimary)
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture {
            plannerCenter.toggleTask(task)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                plannerCenter.deleteTask(task)
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
    }
}

private struct HomePlannerOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let addTaskAction: () -> Void
    let resetAction: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HomeSurfaceCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("플래너 옵션")
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .foregroundStyle(HomePalette.textPrimary)

                            Text("할 일 추가와 샘플 데이터 재설정을 할 수 있습니다.")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(HomePalette.textSecondary)
                        }
                    }

                    HomeSurfaceCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Button("할 일 추가") {
                                addTaskAction()
                                dismiss()
                            }
                            .buttonStyle(HomeFilledButtonStyle())

                            Button("샘플 데이터로 재설정") {
                                resetAction()
                                dismiss()
                            }
                            .buttonStyle(HomeOutlineButtonStyle())

                            Button("닫기") {
                                dismiss()
                            }
                            .buttonStyle(HomeOutlineButtonStyle())
                        }
                    }
                }
                .padding(20)
            }
            .background(HomePalette.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

private struct HomePlannerTaskEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var draft: PlannerTaskDraft
    let onSave: (PlannerTaskDraft) -> Void

    @State private var usesScheduledTime: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("할 일") {
                    TextField("제목", text: $draft.title)

                    Picker("과목", selection: $draft.subject) {
                        ForEach(StudySubject.allCases) { subject in
                            Text(subject.title).tag(subject)
                        }
                    }

                    DatePicker("날짜", selection: $draft.dueDate, displayedComponents: .date)

                    Toggle("시간 지정", isOn: $usesScheduledTime)

                    if usesScheduledTime {
                        DatePicker("시간", selection: Binding(
                            get: {
                                draft.scheduledAt ?? draft.dueDate
                            },
                            set: { newValue in
                                draft.scheduledAt = newValue
                            }
                        ), displayedComponents: [.date, .hourAndMinute])
                    }
                }

                Section("우선순위") {
                    Picker("우선순위", selection: $draft.priority) {
                        ForEach(PlannerTaskPriority.allCases, id: \.self) { priority in
                            Text(priority.title).tag(priority)
                        }
                    }
                }

                Section("메모") {
                    TextField("메모", text: $draft.note, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
            }
            .navigationTitle("할 일 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                usesScheduledTime = draft.scheduledAt != nil
            }
            .onChange(of: usesScheduledTime) { _, newValue in
                if !newValue {
                    draft.scheduledAt = nil
                } else if draft.scheduledAt == nil {
                    draft.scheduledAt = draft.dueDate
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct HomeBrandBar<Trailing: View>: View {
    var logoAction: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    init(
        logoAction: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.logoAction = logoAction
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center) {
            if let logoAction {
                Button(action: logoAction) {
                    HomeBrandMark()
                }
                .buttonStyle(.plain)
            } else {
                HomeBrandMark()
            }

            Spacer(minLength: 12)
            trailing
        }
    }
}

private struct HomeBrandMark: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(HomePalette.accent)
                .frame(width: 28, height: 28)

            Text("PharNote.")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(HomePalette.accent)
        }
    }
}

private enum HomeSidebarSectionID: String, Hashable, CaseIterable {
    case all
    case korean
    case math
    case english
    case earthScience
    case biology
    case unspecified

    var title: String {
        switch self {
        case .all:
            return "모두"
        case .korean:
            return "국어"
        case .math:
            return "수학"
        case .english:
            return "영어"
        case .earthScience:
            return "지구과학1"
        case .biology:
            return "생명과학2"
        case .unspecified:
            return "미분류"
        }
    }

    var subject: StudySubject? {
        switch self {
        case .all:
            return nil
        case .korean:
            return .korean
        case .math:
            return .math
        case .english:
            return .english
        case .earthScience:
            return .earthScience
        case .biology:
            return .biology
        case .unspecified:
            return .unspecified
        }
    }
}

private struct HomeSidebarSectionData: Identifiable {
    let id: HomeSidebarSectionID
    let title: String
    let count: Int
    let documents: [PharDocument]
}

private struct HomeSidebarPanel: View {
    @Binding var searchQuery: String
    @Binding var expandedSections: Set<HomeSidebarSectionID>

    let documents: [PharDocument]
    let onSelectDocument: (PharDocument) -> Void
    let onClose: () -> Void

    private var normalizedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredDocuments: [PharDocument] {
        let sortedDocuments = documents.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            return lhs.updatedAt > rhs.updatedAt
        }

        guard !normalizedQuery.isEmpty else {
            return sortedDocuments
        }

        let query = normalizedQuery.lowercased()
        return sortedDocuments.filter { document in
            let titleMatch = document.title.lowercased().contains(query)
            let materialMatch = document.materialSummaryLine?.lowercased().contains(query) == true
            let subjectMatch = document.studyMaterial?.subject.title.lowercased().contains(query) == true
            return titleMatch || materialMatch || subjectMatch
        }
    }

    private var sections: [HomeSidebarSectionData] {
        let allDocuments = filteredDocuments

        let orderedIDs: [HomeSidebarSectionID] = [.all, .korean, .math, .english, .earthScience, .biology, .unspecified]

        return orderedIDs.compactMap { id in
            let matchedDocuments: [PharDocument]
            switch id {
            case .all:
                matchedDocuments = allDocuments
            case .unspecified:
                matchedDocuments = allDocuments.filter { ($0.studyMaterial?.subject ?? .unspecified) == .unspecified }
            default:
                matchedDocuments = allDocuments.filter { $0.studyMaterial?.subject == id.subject }
            }

            guard !matchedDocuments.isEmpty || id == .all else {
                return nil
            }

            return HomeSidebarSectionData(
                id: id,
                title: id.title,
                count: matchedDocuments.count,
                documents: matchedDocuments
            )
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let panelWidth = min(388, max(340, proxy.size.width * 0.39))

            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center, spacing: 14) {
                    HomeBrandMark()
                }
                .padding(.top, 10)

                HStack(spacing: 12) {
                    TextField("과목 폴더 검색", text: $searchQuery)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(HomePalette.textPrimary)

                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(HomePalette.accent)
                }
                .padding(.horizontal, 18)
                .frame(height: 58)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(HomePalette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(HomePalette.tabBorder, lineWidth: 1.4)
                )

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(spacing: 10) {
                            Image(systemName: "building.columns")
                                .font(.system(size: 25, weight: .semibold))
                                .foregroundStyle(HomePalette.textPrimary)

                            Text("내 폴더")
                                .font(.system(size: 28, weight: .black, design: .rounded))
                                .foregroundStyle(HomePalette.textPrimary)
                        }
                        .padding(.top, 6)

                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(sections) { section in
                                VStack(alignment: .leading, spacing: 12) {
                                    Button {
                                        toggle(section.id)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Text(section.title)
                                                .font(.system(size: 18, weight: .black, design: .rounded))
                                                .foregroundStyle(HomePalette.textPrimary)

                                            Text("\(section.count)")
                                                .font(.system(size: 18, weight: .black, design: .rounded))
                                                .foregroundStyle(HomePalette.accent)

                                            Image(systemName: expandedSections.contains(section.id) ? "chevron.up" : "chevron.down")
                                                .font(.system(size: 15, weight: .bold))
                                                .foregroundStyle(HomePalette.accent)
                                        }
                                        .padding(.horizontal, section.id == .korean ? 14 : 0)
                                        .padding(.vertical, section.id == .korean ? 9 : 0)
                                        .background(
                                            Group {
                                                if section.id == .korean {
                                                    Capsule(style: .continuous)
                                                        .fill(Color.black.opacity(0.06))
                                                }
                                            }
                                        )
                                    }
                                    .buttonStyle(.plain)

                                    if expandedSections.contains(section.id) {
                                        VStack(alignment: .leading, spacing: 12) {
                                            ForEach(section.documents.prefix(section.id == .all ? 10 : 7)) { document in
                                                Button {
                                                    onSelectDocument(document)
                                                } label: {
                                                    HStack(spacing: 10) {
                                                        Image(systemName: sidebarIcon(for: document))
                                                            .font(.system(size: 19, weight: .medium))
                                                            .foregroundStyle(HomePalette.textPrimary)
                                                            .frame(width: 22)

                                                        Text(document.title)
                                                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                                                            .foregroundStyle(HomePalette.textPrimary)
                                                            .lineLimit(1)

                                                        Spacer(minLength: 0)
                                                    }
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        .padding(.leading, 2)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 40)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 28)
            .frame(width: panelWidth, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(HomePalette.surface)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(HomePalette.border.opacity(0.9))
                    .frame(width: 1)
            }
            .shadow(color: Color.black.opacity(0.08), radius: 18, x: 8, y: 0)
        }
    }

    private func toggle(_ sectionID: HomeSidebarSectionID) {
        if expandedSections.contains(sectionID) {
            expandedSections.remove(sectionID)
        } else {
            expandedSections.insert(sectionID)
        }
    }

    private func sidebarIcon(for document: PharDocument) -> String {
        if document.type == .blankNote {
            return document.studyMaterial == nil ? "doc.text" : "folder"
        }
        return "doc.text"
    }
}

private struct HomeScreenTitle: View {
    let title: String
    let systemName: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: systemName)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(HomePalette.textPrimary)

                Text(title)
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundStyle(HomePalette.textPrimary)
            }

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(HomePalette.textSecondary)
            }
        }
    }
}

private struct HomeQuickActionCard: View {
    let title: String
    let systemName: String
    var cardWidth: CGFloat?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 24) {
                Spacer(minLength: 0)

                Image(systemName: systemName)
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(HomePalette.iconMuted)

                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(HomePalette.iconMuted)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: cardWidth == nil ? .infinity : cardWidth)
            .frame(width: cardWidth)
            .frame(height: 288)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(HomePalette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(HomePalette.border, lineWidth: 1.5)
            )
        }
        .buttonStyle(HomeScaleButtonStyle())
    }
}

private struct HomeEmptyContinueCard: View {
    let createNoteAction: () -> Void
    let importPDFAction: () -> Void

    var body: some View {
        HomeSurfaceCard {
            VStack(alignment: .leading, spacing: 18) {
                Text("최근 이어갈 문서가 없습니다")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(HomePalette.textPrimary)

                Text("새 노트를 시작하거나 기존 PDF를 불러오면 이 영역에 최근 작업이 쌓입니다.")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(HomePalette.textSecondary)

                HStack(spacing: 12) {
                    Button("새 노트") {
                        createNoteAction()
                    }
                    .buttonStyle(HomeFilledButtonStyle())

                    Button("불러오기") {
                        importPDFAction()
                    }
                    .buttonStyle(HomeOutlineButtonStyle())
                }
            }
        }
    }
}

private struct HomeContinueDocumentCard: View {
    let document: PharDocument
    let onOpen: () -> Void
    let onRename: () -> Void
    let onShare: () -> Void

    private var labelText: String {
        if let subject = document.studyMaterial?.subject, subject != .unspecified {
            return subject.title
        }
        return document.type == .blankNote ? "노트" : "PDF"
    }

    private var updatedText: String {
        HomeFormatters.documentDate.string(from: document.updatedAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeCategoryChip(
                title: labelText,
                tint: HomePalette.subjectTint(for: document.studyMaterial?.subject)
            )

            HomeDocumentThumbnailView(document: document)
                .frame(width: 168, height: 220)

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(document.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(HomePalette.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .onTapGesture(count: 2) {
                            onRename()
                        }

                    Text(updatedText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(HomePalette.textSecondary)
                }

                Spacer(minLength: 0)

                Menu {
                    Button("이름 바꾸기") {
                        onRename()
                    }

                    Button("공유") {
                        onShare()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(HomePalette.accent)
                        .padding(.top, 2)
                }
            }
        }
        .frame(width: 168, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture {
            onOpen()
        }
    }
}

private struct HomeDocumentThumbnailView: View {
    @Environment(\.displayScale) private var displayScale

    let document: PharDocument

    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(HomePalette.surface)

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(HomePalette.border, lineWidth: 1.5)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(10)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                VStack(spacing: 12) {
                    Image(systemName: document.type == .blankNote ? "note.text" : "doc.richtext")
                        .font(.system(size: 38, weight: .regular))
                        .foregroundStyle(HomePalette.iconMuted)

                    Text(isLoading ? "불러오는 중" : "미리보기")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(HomePalette.textSecondary)
                }
            }
        }
        .task(id: document.id) {
            await loadPreviewIfNeeded()
        }
    }

    @MainActor
    private func loadPreviewIfNeeded() async {
        guard image == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let documentURL = URL(fileURLWithPath: document.path)

        if document.type == .pdf {
            let pdfURL = documentURL.appendingPathComponent("Original.pdf", isDirectory: false)
            if let pdfDocument = PDFDocument(url: pdfURL),
               let firstPage = pdfDocument.page(at: 0) {
                image = firstPage.thumbnail(of: CGSize(width: 320, height: 420), for: .mediaBox)
            }
            return
        }

        let blankNoteStore = BlankNoteStore()
        guard let content = try? await blankNoteStore.loadOrCreateContent(documentURL: documentURL),
              let firstPage = content.pages.first else {
            return
        }

        if let thumbnailData = await blankNoteStore.loadThumbnailData(documentURL: documentURL, pageID: firstPage.id),
           let thumbnailImage = UIImage(data: thumbnailData) {
            image = thumbnailImage
            return
        }

        if let drawingData = await blankNoteStore.loadDrawingData(documentURL: documentURL, pageID: firstPage.id),
           let generatedPNG = await blankNoteStore.generateThumbnailPNG(
                from: drawingData,
                thumbnailSize: CGSize(width: 300, height: 380),
                scale: displayScale
           ),
           let generatedImage = UIImage(data: generatedPNG) {
            image = generatedImage
        }
    }
}

private struct HomeCategoryChip: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(HomePalette.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(tint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(HomePalette.border.opacity(0.7), lineWidth: 0.8)
            )
    }
}

private struct HomeMetric: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let tint: Color
}

private struct HomeMetricRow: View {
    let metrics: [HomeMetric]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                ForEach(metrics) { metric in
                    HomeMetricCard(metric: metric)
                }
            }

            VStack(spacing: 14) {
                ForEach(metrics) { metric in
                    HomeMetricCard(metric: metric)
                }
            }
        }
    }
}

private struct HomeMetricCard: View {
    let metric: HomeMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(metric.title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(HomePalette.textSecondary)
            Text(metric.value)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(HomePalette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(metric.tint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(HomePalette.border.opacity(0.7), lineWidth: 1)
        )
    }
}

private struct HomePlannerStat: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let tint: Color
}

private struct HomePlannerStatRow: View {
    let metrics: [HomePlannerStat]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                ForEach(metrics) { metric in
                    HomePlannerStatCard(metric: metric)
                }
            }

            VStack(spacing: 12) {
                ForEach(metrics) { metric in
                    HomePlannerStatCard(metric: metric)
                }
            }
        }
    }
}

private struct HomePlannerStatCard: View {
    let metric: HomePlannerStat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(metric.title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(HomePalette.textSecondary.opacity(0.95))

            Text(metric.value)
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(HomePalette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(minHeight: 116)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(metric.tint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(HomePalette.border.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.025), radius: 10, x: 0, y: 5)
    }
}

private struct HomeAnalysisEntryCard: View {
    let entry: AnalysisQueueEntry
    let result: AnalysisResult?

    private var statusTint: Color {
        switch entry.status {
        case .queued:
            return HomePalette.blueTint
        case .completed:
            return HomePalette.greenTint
        case .failed:
            return HomePalette.orangeTint
        }
    }

    private var statusText: String {
        switch entry.status {
        case .queued:
            return "대기"
        case .completed:
            return "완료"
        case .failed:
            return "실패"
        }
    }

    var body: some View {
        HomeSurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.documentTitle)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(HomePalette.textPrimary)
                        Text("\(entry.pageLabel) · \(entry.studyIntent.title)")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(HomePalette.textSecondary)
                    }

                    Spacer(minLength: 0)

                    HomeCategoryChip(title: statusText, tint: statusTint)
                }

                Text(result?.summary.headline ?? entry.lastErrorMessage ?? "분석 결과 생성 대기 중입니다.")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(HomePalette.textSecondary)
                    .lineLimit(3)

                Text(HomeFormatters.documentDate.string(from: entry.createdAt))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(HomePalette.textSecondary.opacity(0.82))
            }
        }
    }
}

private struct HomeBottomTabBar: View {
    @Binding var selectedTab: HomeTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(HomeTab.allCases.enumerated()), id: \.element.id) { index, tab in
                Button {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: tab.systemName)
                            .font(.system(size: 18, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(selectedTab == tab ? Color.white : HomePalette.textPrimary.opacity(0.72))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        ZStack {
                            if selectedTab == tab {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(HomePalette.accent)
                            }
                        }
                    )
                }
                .buttonStyle(.plain)

                if index < HomeTab.allCases.count - 1 {
                    Rectangle()
                        .fill(HomePalette.tabBorder.opacity(0.8))
                        .frame(width: 1, height: 32)
                }
            }
        }
        .padding(6)
        .frame(maxWidth: 452)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(HomePalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(HomePalette.tabBorder, lineWidth: 1.4)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 8)
    }
}

private struct HomeSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var analysisCenter: AnalysisCenter
    @EnvironmentObject private var authManager: PharnodeSupabaseAuthManager
    @EnvironmentObject private var cloudSyncManager: PharnodeCloudSyncManager

    let totalDocuments: Int
    let blankNotes: Int
    let pdfDocuments: Int

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HomeSurfaceCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("라이브러리")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(HomePalette.textPrimary)

                            HomeKeyValueRow(title: "전체 문서", value: "\(totalDocuments)")
                            HomeKeyValueRow(title: "노트", value: "\(blankNotes)")
                            HomeKeyValueRow(title: "PDF", value: "\(pdfDocuments)")
                        }
                    }

                    HomeSurfaceCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("계정")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(HomePalette.textPrimary)

                            HomeKeyValueRow(
                                title: "상태",
                                value: authManager.isAuthenticated ? "연결됨" : "연결 안 됨"
                            )

                            HomeKeyValueRow(
                                title: "이메일",
                                value: authManager.authenticatedEmail ?? "-"
                            )

                            Button("세션 새로고침") {
                                Task {
                                    _ = await authManager.refreshSessionIfNeeded(force: true)
                                }
                            }
                            .buttonStyle(HomeOutlineButtonStyle())
                        }
                    }

                    HomeSurfaceCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("클라우드 동기화")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(HomePalette.textPrimary)

                            HomeKeyValueRow(
                                title: "설정",
                                value: cloudSyncManager.configuration.isEnabled ? "켜짐" : "꺼짐"
                            )
                            HomeKeyValueRow(
                                title: "상태",
                                value: cloudSyncManager.syncState.title
                            )
                            HomeKeyValueRow(
                                title: "대기 항목",
                                value: "\(cloudSyncManager.pendingCount)"
                            )
                            HomeKeyValueRow(
                                title: "마지막 성공",
                                value: cloudSyncManager.lastSuccessfulSyncAt.map(HomeFormatters.documentDate.string(from:)) ?? "-"
                            )

                            HStack(spacing: 12) {
                                Button(cloudSyncManager.configuration.isEnabled ? "동기화 끄기" : "동기화 켜기") {
                                    Task {
                                        await cloudSyncManager.updateConfiguration(
                                            baseURLString: cloudSyncManager.configuration.baseURLString,
                                            isEnabled: !cloudSyncManager.configuration.isEnabled
                                        )
                                    }
                                }
                                .buttonStyle(HomeOutlineButtonStyle())

                                Button("지금 동기화") {
                                    Task {
                                        await cloudSyncManager.syncNow()
                                    }
                                }
                                .buttonStyle(HomeFilledButtonStyle())
                            }
                        }
                    }

                    HomeSurfaceCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("분석 상태")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(HomePalette.textPrimary)

                            HomeKeyValueRow(title: "완료", value: "\(analysisCenter.completedCount)")
                            HomeKeyValueRow(title: "대기", value: "\(analysisCenter.queuedCount)")
                            HomeKeyValueRow(title: "복습 작업", value: "\(analysisCenter.reviewTasks.count)")
                        }
                    }
                }
                .padding(20)
            }
            .background(HomePalette.background.ignoresSafeArea())
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct HomeStudyMaterialImportSheet: View {
    @Environment(\.dismiss) private var dismiss

    let pending: LibraryViewModel.PendingPDFImportSelection
    let onSave: (String, StudyMaterialProvider, StudySubject) -> Void
    let onSkip: () -> Void

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
                Section("자동 인식 결과") {
                    LabeledContent("추천 제목", value: pending.suggestion.normalizedTitle)
                    LabeledContent("신뢰도", value: pending.suggestion.confidenceLabel)
                    if !pending.suggestion.matchedSignals.isEmpty {
                        Text(pending.suggestion.matchedSignals.joined(separator: ", "))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("수정") {
                    TextField("제목", text: $title)

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
            }
            .navigationTitle("가져온 PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("건너뛰기") {
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

private struct HomeKeyValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(HomePalette.textSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(HomePalette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct HomeSurfaceCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(HomePalette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(HomePalette.border, lineWidth: 1.2)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 14, x: 0, y: 8)
    }
}

private struct HomeScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

private struct HomeFilledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(HomePalette.accent.opacity(configuration.isPressed ? 0.88 : 1))
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

private struct HomeOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(HomePalette.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(HomePalette.surface.opacity(configuration.isPressed ? 0.9 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(HomePalette.border, lineWidth: 1.1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

private enum HomePalette {
    static let background = Color(homeHex: 0xF5F3ED)
    static let surface = Color(homeHex: 0xFBFAF6)
    static let border = Color(homeHex: 0xCBC6BD)
    static let tabBorder = Color(homeHex: 0x8C877C)
    static let accent = Color(homeHex: 0xFF6B00)
    static let textPrimary = Color(homeHex: 0x161311)
    static let textSecondary = Color(homeHex: 0x858075)
    static let iconMuted = Color(homeHex: 0xA5A09A)

    static let blueTint = Color(homeHex: 0xDDE7F6)
    static let greenTint = Color(homeHex: 0xDCEAB5)
    static let orangeTint = Color(homeHex: 0xF2D3CE)
    static let yellowTint = Color(homeHex: 0xEFE8A7)

    static func subjectTint(for subject: StudySubject?) -> Color {
        switch subject {
        case .korean:
            return yellowTint
        case .math:
            return greenTint
        case .earthScience:
            return orangeTint
        case .physics:
            return blueTint
        case .chemistry:
            return Color(homeHex: 0xE8D4F1)
        case .english:
            return Color(homeHex: 0xD4E6D9)
        case .biology:
            return Color(homeHex: 0xDCE8CF)
        case .socialInquiry:
            return Color(homeHex: 0xEADDC2)
        case .essay:
            return Color(homeHex: 0xE4D8D0)
        case .koreanHistory:
            return Color(homeHex: 0xE4DFC9)
        case .unspecified, .none:
            return Color(homeHex: 0xECE7DD)
        }
    }
}

private enum HomeFormatters {
    static let documentDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy. MM. dd. HH:mm"
        return formatter
    }()

    static let dayNumber: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "d"
        return formatter
    }()

    static let weekdayShort: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE"
        return formatter
    }()

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "H시"
        return formatter
    }()
}

private extension Color {
    init(homeHex: UInt, opacity: Double = 1.0) {
        let red = Double((homeHex >> 16) & 0xFF) / 255.0
        let green = Double((homeHex >> 8) & 0xFF) / 255.0
        let blue = Double(homeHex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

private extension Date {
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }
}

#Preview {
    let analysisCenter = AnalysisCenter()
    let authManager = PharnodeSupabaseAuthManager()
    let plannerCenter = PlannerCenter()
    ContentView()
        .environmentObject(analysisCenter)
        .environmentObject(authManager)
        .environmentObject(PharnodeCloudSyncManager(analysisCenter: analysisCenter, authManager: authManager))
        .environmentObject(plannerCenter)
}
