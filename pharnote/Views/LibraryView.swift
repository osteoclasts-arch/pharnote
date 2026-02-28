import SwiftUI

struct LibraryView: View {
    @StateObject private var viewModel = LibraryViewModel()
    @State private var isShowingPDFImportPicker = false

    var body: some View {
        NavigationSplitView {
            List(LibraryFolder.allCases, selection: $viewModel.selectedFolder) { folder in
                Label(folder.rawValue, systemImage: iconName(for: folder))
                    .font(PharTypography.body)
            }
            .navigationTitle("파르노트")
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } detail: {
            NavigationStack(path: $viewModel.navigationPath) {
                Group {
                    if viewModel.filteredDocuments.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 34))
                                .foregroundStyle(.secondary)
                            Text(viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "문서가 없습니다" : "검색 결과가 없습니다")
                                .font(.headline)
                            Text(
                                viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "오른쪽 상단의 \"빈 노트\" 버튼으로 첫 문서를 만드세요."
                                : "다른 검색어를 입력해 보세요."
                            )
                                .font(PharTypography.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(PharTheme.Spacing.large)
                    } else {
                        List(viewModel.filteredDocuments) { document in
                            NavigationLink(value: document) {
                                DocumentRowView(document: document)
                            }
                            .buttonStyle(.plain)
                            .hoverEffect(.highlight)
                            .listRowSeparator(.hidden)
                            .listRowInsets(
                                EdgeInsets(
                                    top: PharTheme.Spacing.xSmall,
                                    leading: PharTheme.Spacing.medium,
                                    bottom: PharTheme.Spacing.xSmall,
                                    trailing: PharTheme.Spacing.medium
                                )
                            )
                        }
                        .listStyle(.insetGrouped)
                    }
                }
                .navigationTitle("라이브러리")
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        PharToolbarIconButton(
                            systemName: "square.and.arrow.down",
                            accessibilityLabel: "PDF 가져오기"
                        ) {
                            isShowingPDFImportPicker = true
                        }

                        PharToolbarIconButton(
                            systemName: "square.and.pencil",
                            accessibilityLabel: "빈 노트 만들기"
                        ) {
                            viewModel.createBlankNote()
                        }
                    }
                }
                .navigationDestination(for: PharDocument.self) { document in
                    DocumentEditorView(document: document)
                }
                .searchable(text: $viewModel.searchQuery, prompt: "문서 제목 검색")
            }
            .navigationSplitViewColumnWidth(min: 480, ideal: 760, max: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .background(PharTheme.ColorToken.appBackground)
        .alert("오류", isPresented: isErrorPresented) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $isShowingPDFImportPicker) {
            PDFImportPicker { urls in
                isShowingPDFImportPicker = false
                guard let firstURL = urls.first else { return }
                viewModel.importPDF(from: firstURL)
            } onCancelled: {
                isShowingPDFImportPicker = false
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

    private func iconName(for folder: LibraryFolder) -> String {
        switch folder {
        case .all:
            return "tray.full"
        case .blankNotes:
            return "square.and.pencil"
        case .pdfs:
            return "doc.richtext"
        }
    }
}

private struct DocumentRowView: View {
    let document: PharDocument

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        HStack(spacing: PharTheme.Spacing.small) {
            Image(systemName: document.type == .blankNote ? "square.and.pencil.circle.fill" : "doc.richtext.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(document.type == .blankNote ? Color.accentColor : Color.orange)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: PharTheme.Spacing.xxSmall) {
                Text(document.title)
                    .font(PharTypography.sectionTitle)
                HStack(spacing: PharTheme.Spacing.xSmall) {
                    Text(document.type == .blankNote ? "빈 노트" : "PDF")
                    Text(DocumentRowView.dateFormatter.string(from: document.updatedAt))
                }
                .font(PharTypography.caption)
                .foregroundStyle(PharTheme.ColorToken.subtleText)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PharTheme.Spacing.medium)
        .padding(.vertical, PharTheme.Spacing.small)
        .background(
            RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                .fill(PharTheme.ColorToken.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PharTheme.CornerRadius.medium, style: .continuous)
                .stroke(PharTheme.ColorToken.border.opacity(0.32), lineWidth: 1)
        )
    }
}
