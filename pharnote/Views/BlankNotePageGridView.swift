import SwiftUI

struct BlankNotePageGridView: View {
    @ObservedObject var viewModel: BlankNoteEditorViewModel
    @Environment(\.dismiss) private var dismiss
    
    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 24)
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
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
