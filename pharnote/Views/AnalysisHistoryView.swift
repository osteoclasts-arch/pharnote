import SwiftUI

struct AnalysisHistoryView: View {
    @EnvironmentObject private var analysisCenter: AnalysisCenter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                summarySection
                historySection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Analysis History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await analysisCenter.refreshQueue() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .navigationDestination(for: UUID.self) { bundleId in
                AnalysisRecordDetailView(bundleId: bundleId)
            }
            .task {
                await analysisCenter.refreshQueue()
            }
            .overlay {
                if analysisCenter.queueEntries.isEmpty {
                    ContentUnavailableView(
                        "분석 기록이 아직 없습니다",
                        systemImage: "waveform.path.ecg",
                        description: Text("노트나 PDF 페이지에서 분석 버튼을 눌러 첫 기록을 만드세요.")
                    )
                }
            }
        }
        .presentationDetents([.large])
    }

    private var summarySection: some View {
        Section {
            PharSurfaceCard(fill: PharTheme.GradientToken.accentWash) {
                VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                    Text("Queue overview")
                        .font(PharTypography.cardTitle)
                        .foregroundStyle(PharTheme.ColorToken.inkPrimary)

                    HStack(spacing: PharTheme.Spacing.xSmall) {
                        AnalysisMetricPill(
                            title: "Queued",
                            value: "\(analysisCenter.queuedCount)",
                            tint: PharTheme.ColorToken.accentBlue.opacity(0.16)
                        )
                        AnalysisMetricPill(
                            title: "Done",
                            value: "\(analysisCenter.completedCount)",
                            tint: PharTheme.ColorToken.accentMint.opacity(0.26)
                        )
                        AnalysisMetricPill(
                            title: "Failed",
                            value: "\(analysisCenter.failedCount)",
                            tint: PharTheme.ColorToken.accentPeach.opacity(0.22)
                        )
                    }

                    if let latest = analysisCenter.latestResult {
                        Text(latest.summary.headline)
                            .font(PharTypography.captionStrong)
                            .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                            .lineLimit(2)
                    }
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    private var historySection: some View {
        Section("Records") {
            ForEach(analysisCenter.queueEntries) { entry in
                NavigationLink(value: entry.bundleId) {
                    AnalysisHistoryRow(
                        entry: entry,
                        result: analysisCenter.result(for: entry.bundleId)
                    )
                }
            }
        }
    }
}

private struct AnalysisHistoryRow: View {
    let entry: AnalysisQueueEntry
    let result: AnalysisResult?

    var body: some View {
        VStack(alignment: .leading, spacing: PharTheme.Spacing.xSmall) {
            HStack(alignment: .center, spacing: PharTheme.Spacing.small) {
                VStack(alignment: .leading, spacing: PharTheme.Spacing.xxxSmall) {
                    Text(entry.documentTitle)
                        .font(PharTypography.bodyStrong)
                        .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                        .lineLimit(1)
                    Text("\(entry.pageLabel) · \(entry.studyIntent.title)")
                        .font(PharTypography.caption)
                        .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                }

                Spacer(minLength: 0)

                PharTagPill(
                    text: statusTitle(entry.status),
                    tint: statusTint(entry.status),
                    foreground: PharTheme.ColorToken.inkPrimary
                )
            }

            if let result {
                Text(result.summary.headline)
                    .font(PharTypography.captionStrong)
                    .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                    .lineLimit(2)

                HStack(spacing: PharTheme.Spacing.xSmall) {
                    AnalysisMetricPill(
                        title: "이해 상태",
                        value: masteryLabel(result.summary.masteryScore),
                        tint: PharTheme.ColorToken.accentMint.opacity(0.22)
                    )
                    AnalysisMetricPill(
                        title: "근거 상태",
                        value: confidenceLabel(result.summary.confidenceScore),
                        tint: PharTheme.ColorToken.accentBlue.opacity(0.14)
                    )
                }
            } else if let error = entry.lastErrorMessage {
                Text(error)
                    .font(PharTypography.caption)
                    .foregroundStyle(PharTheme.ColorToken.destructive)
                    .lineLimit(2)
            } else {
                Text("결과 생성 대기 중")
                    .font(PharTypography.caption)
                    .foregroundStyle(PharTheme.ColorToken.inkSecondary)
            }

            Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(PharTypography.caption)
                .foregroundStyle(PharTheme.ColorToken.subtleText)
        }
        .padding(.vertical, PharTheme.Spacing.xxxSmall)
    }

    private func statusTitle(_ status: AnalysisRequestStatus) -> String {
        switch status {
        case .queued:
            return "대기 중"
        case .failed:
            return "실패"
        case .completed:
            return "완료"
        }
    }

    private func statusTint(_ status: AnalysisRequestStatus) -> Color {
        switch status {
        case .queued:
            return PharTheme.ColorToken.accentBlue.opacity(0.16)
        case .failed:
            return PharTheme.ColorToken.accentPeach.opacity(0.26)
        case .completed:
            return PharTheme.ColorToken.accentMint.opacity(0.28)
        }
    }

}

private struct AnalysisRecordDetailView: View {
    @EnvironmentObject private var analysisCenter: AnalysisCenter

    let bundleId: UUID

    @State private var inspection: AnalysisInspection?
    @State private var selectedJSONTab: AnalysisJSONTab = .bundle
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.large) {
                if let inspection {
                    metadataCard(for: inspection)

                    if let result = inspection.result {
                        AnalysisResultDetailCard(result: result)
                    } else {
                        PharSurfaceCard {
                            VStack(alignment: .leading, spacing: PharTheme.Spacing.small) {
                                Text("Result pending")
                                    .font(PharTypography.cardTitle)
                                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                                Text("이 기록은 아직 결과가 없거나 실패 상태입니다.")
                                    .font(PharTypography.body)
                                    .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                            }
                        }
                    }

                    bundleQuickLook(for: inspection)
                    jsonCard(for: inspection)
                } else if isLoading {
                    ProgressView("기록 불러오는 중...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, PharTheme.Spacing.xxLarge)
                } else {
                    ContentUnavailableView(
                        "기록을 찾을 수 없습니다",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("이 분석 번들이 삭제되었거나 로드에 실패했습니다.")
                    )
                }
            }
            .padding(PharTheme.Spacing.large)
        }
        .background(PharTheme.GradientToken.appBackdrop.ignoresSafeArea())
        .navigationTitle("Record Detail")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: bundleId) {
            await loadInspection()
        }
    }

    private func metadataCard(for inspection: AnalysisInspection) -> some View {
        PharSurfaceCard(fill: PharTheme.ColorToken.surfacePrimary.opacity(0.96)) {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                HStack(alignment: .top, spacing: PharTheme.Spacing.small) {
                    VStack(alignment: .leading, spacing: PharTheme.Spacing.xxxSmall) {
                        Text(inspection.entry.documentTitle)
                            .font(PharTypography.sectionTitle)
                            .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                        Text("\(inspection.entry.pageLabel) · \(inspection.entry.studyIntent.title) · \(inspection.entry.scope.title)")
                            .font(PharTypography.body)
                            .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                    }
                    Spacer(minLength: 0)
                    PharTagPill(
                        text: statusTitle(inspection.entry.status),
                        tint: statusTint(inspection.entry.status),
                        foreground: PharTheme.ColorToken.inkPrimary
                    )
                }

                HStack(spacing: PharTheme.Spacing.xSmall) {
                    AnalysisMetricPill(title: "Bundle", value: shortID(inspection.entry.bundleId), tint: PharTheme.ColorToken.surfaceTertiary)
                    AnalysisMetricPill(title: "생성", value: inspection.entry.createdAt.formatted(date: .omitted, time: .shortened), tint: PharTheme.ColorToken.accentBlue.opacity(0.12))
                    AnalysisMetricPill(title: "문서 유형", value: inspection.entry.documentType.rawValue, tint: PharTheme.ColorToken.accentButter.opacity(0.2))
                }
            }
        }
    }

    private func bundleQuickLook(for inspection: AnalysisInspection) -> some View {
        PharSurfaceCard {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                Text("Bundle quick look")
                    .font(PharTypography.cardTitle)
                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)

                HStack(spacing: PharTheme.Spacing.xSmall) {
                    AnalysisMetricPill(title: "Stroke", value: "\(inspection.bundle.content.drawingStats.strokeCount)", tint: PharTheme.ColorToken.accentMint.opacity(0.24))
                    AnalysisMetricPill(title: "Dwell", value: "\(inspection.bundle.behavior.dwellMs / 1000)s", tint: PharTheme.ColorToken.accentBlue.opacity(0.12))
                    AnalysisMetricPill(title: "Revisit", value: "\(inspection.bundle.behavior.revisitCount)", tint: PharTheme.ColorToken.accentPeach.opacity(0.22))
                }

                VStack(alignment: .leading, spacing: PharTheme.Spacing.xxSmall) {
                    DetailRow(title: "Assets", value: assetSummary(inspection.bundle))
                    DetailRow(title: "Page state", value: inspection.bundle.page.pageState.joined(separator: ", ").isEmpty ? "none" : inspection.bundle.page.pageState.joined(separator: ", "))
                    DetailRow(title: "Navigation path", value: inspection.bundle.behavior.navigationPath.isEmpty ? "none" : inspection.bundle.behavior.navigationPath.joined(separator: " → "))
                    DetailRow(title: "PDF text blocks", value: "\(inspection.bundle.content.pdfTextBlocks.count)")
                    DetailRow(title: "Bookmarks", value: inspection.bundle.content.bookmarks.isEmpty ? "none" : inspection.bundle.content.bookmarks.joined(separator: ", "))
                }
            }
        }
    }

    private func jsonCard(for inspection: AnalysisInspection) -> some View {
        PharSurfaceCard(fill: PharTheme.ColorToken.surfacePrimary.opacity(0.96)) {
            VStack(alignment: .leading, spacing: PharTheme.Spacing.medium) {
                HStack {
                    Text("Raw JSON")
                        .font(PharTypography.cardTitle)
                        .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                    Spacer(minLength: 0)
                    Picker("JSON", selection: $selectedJSONTab) {
                        ForEach(AnalysisJSONTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                }

                ScrollView([.vertical, .horizontal], showsIndicators: true) {
                    Text(jsonText(for: inspection))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 280)
                .padding(PharTheme.Spacing.small)
                .background(
                    RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                        .fill(PharTheme.ColorToken.surfaceSecondary)
                )
            }
        }
    }

    private func loadInspection() async {
        isLoading = true
        inspection = await analysisCenter.inspection(for: bundleId)
        if inspection?.result == nil {
            selectedJSONTab = .bundle
        }
        isLoading = false
    }

    private func jsonText(for inspection: AnalysisInspection) -> String {
        switch selectedJSONTab {
        case .bundle:
            return inspection.bundleJSON
        case .result:
            return inspection.resultJSON ?? "No result.json available for this bundle yet."
        }
    }

    private func assetSummary(_ bundle: AnalysisBundle) -> String {
        let preview = bundle.content.previewImageRef == nil ? "preview 없음" : "preview 있음"
        let drawing = bundle.content.drawingRef == nil ? "drawing 없음" : "drawing 있음"
        return "\(preview), \(drawing)"
    }

    private func statusTitle(_ status: AnalysisRequestStatus) -> String {
        switch status {
        case .queued:
            return "QUEUED"
        case .failed:
            return "FAILED"
        case .completed:
            return "DONE"
        }
    }

    private func statusTint(_ status: AnalysisRequestStatus) -> Color {
        switch status {
        case .queued:
            return PharTheme.ColorToken.accentBlue.opacity(0.16)
        case .failed:
            return PharTheme.ColorToken.accentPeach.opacity(0.26)
        case .completed:
            return PharTheme.ColorToken.accentMint.opacity(0.28)
        }
    }

    private func shortID(_ value: UUID) -> String {
        String(value.uuidString.prefix(8)) + "…"
    }
}

private struct DetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: PharTheme.Spacing.small) {
            Text(title)
                .font(PharTypography.captionStrong)
                .foregroundStyle(PharTheme.ColorToken.inkSecondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(PharTypography.caption)
                .foregroundStyle(PharTheme.ColorToken.inkPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private enum AnalysisJSONTab: String, CaseIterable, Identifiable {
    case bundle
    case result

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bundle:
            return "Bundle"
        case .result:
            return "Result"
        }
    }
}
