import SwiftUI

struct BlankNotePageGridView: View {
    @ObservedObject var viewModel: BlankNoteEditorViewModel
    @Environment(\.dismiss) private var dismiss
    
    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 24)
    ]
    @State private var pullToAddProgress: CGFloat = 0
    @State private var didTriggerAddDuringDrag = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    LazyVGrid(columns: columns, spacing: 32) {
                        ForEach(viewModel.pages) { page in
                            PageGridCell(
                                page: page,
                                thumbnail: viewModel.thumbnail(for: page.id),
                                pageNumber: viewModel.pageNumber(for: page.id),
                                isSelected: viewModel.currentPageID == page.id,
                                isBookmarked: viewModel.isPageBookmarked(page.id)
                            )
                            .onTapGesture {
                                viewModel.selectPage(page.id)
                                dismiss()
                            }
                            .contextMenu {
                                Button {
                                    viewModel.duplicatePage(page.id)
                                } label: {
                                    Label("복제", systemImage: "doc.on.doc")
                                }
                                
                                Button(role: .destructive) {
                                    viewModel.deletePage(page.id)
                                } label: {
                                    Label("삭제", systemImage: "trash")
                                }
                            }
                        }
                    }

                    PullToAddPageFooter(
                        progress: pullToAddProgress,
                        didTriggerAddDuringDrag: didTriggerAddDuringDrag
                    )
                    .gesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { value in
                                guard value.translation.height > 0 else {
                                    pullToAddProgress = 0
                                    didTriggerAddDuringDrag = false
                                    return
                                }

                                pullToAddProgress = min(value.translation.height, 120)
                                if pullToAddProgress > 52 {
                                    didTriggerAddDuringDrag = true
                                }
                            }
                            .onEnded { _ in
                                if didTriggerAddDuringDrag {
                                    viewModel.addPage(atEnd: true)
                                }
                                pullToAddProgress = 0
                                didTriggerAddDuringDrag = false
                            }
                    )
                }
                .padding(32)
            }
            .background(PharTheme.ColorToken.appBackground.ignoresSafeArea())
            .navigationTitle("모든 페이지")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") {
                        dismiss()
                    }
                    .font(PharTypography.bodyStrong)
                    .foregroundStyle(PharTheme.ColorToken.accentBlue)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.addPage()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .font(PharTypography.bodyStrong)
                    .foregroundStyle(PharTheme.ColorToken.accentBlue)
                }
            }
        }
    }
}

private struct PullToAddPageFooter: View {
    let progress: CGFloat
    let didTriggerAddDuringDrag: Bool

    var body: some View {
        VStack(spacing: 12) {
            Capsule(style: .continuous)
                .fill(PharTheme.ColorToken.accentBlue.opacity(0.18))
                .frame(width: 78, height: 8)
                .offset(y: -progress * 0.12)

            VStack(spacing: 8) {
                Image(systemName: "arrow.down.to.line.compact")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(PharTheme.ColorToken.accentBlue)

                Text(didTriggerAddDuringDrag ? "새 페이지 추가" : "아래로 당겨 새 페이지 추가")
                    .font(PharTypography.bodyStrong)
                    .foregroundStyle(PharTheme.ColorToken.inkPrimary)

                Text("마지막 페이지 아래에서 끌어내리면 새 페이지가 생깁니다.")
                    .font(PharTypography.caption)
                    .foregroundStyle(PharTheme.ColorToken.subtleText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 124)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(PharTheme.ColorToken.surfacePrimary.opacity(0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(PharTheme.ColorToken.border.opacity(0.45), lineWidth: 1.2)
            )
            .scaleEffect(1 + min(progress, 120) / 720.0)
            .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
        }
        .frame(maxWidth: .infinity)
        .opacity(0.92 + min(progress, 120) / 800.0)
    }
}

private struct PageGridCell: View {
    let page: BlankNotePage
    let thumbnail: UIImage?
    let pageNumber: Int
    let isSelected: Bool
    let isBookmarked: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(PharTheme.ColorToken.canvasBackground)
                    .shadow(color: Color.black.opacity(isSelected ? 0.15 : 0.05), radius: isSelected ? 12 : 6, x: 0, y: 4)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                isSelected ? PharTheme.ColorToken.accentBlue : PharTheme.ColorToken.border.opacity(0.3),
                                lineWidth: isSelected ? 3 : 1
                            )
                    }
                
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                } else {
                    Image(systemName: "doc.text")
                        .font(.system(size: 40))
                        .foregroundStyle(PharTheme.ColorToken.subtleText)
                }
                
                if isBookmarked {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(PharTheme.ColorToken.accentBlue)
                        .padding(8)
                }
            }
            .aspectRatio(0.75, contentMode: .fit)
            .frame(maxWidth: .infinity)
            
            Text("\(pageNumber)")
                .font(PharTypography.bodyStrong)
                .foregroundStyle(isSelected ? PharTheme.ColorToken.accentBlue : PharTheme.ColorToken.inkPrimary)
        }
    }
}
