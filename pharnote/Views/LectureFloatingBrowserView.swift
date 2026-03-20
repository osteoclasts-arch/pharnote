import SwiftUI

struct LectureFloatingBrowserView<ViewModel: LectureFloatingBrowserState>: View {
    @ObservedObject var viewModel: ViewModel
    @State private var isLoading = false
    @State private var urlInput: String = ""
    @State private var allowsPopups = false
    
    // 드래그를 위한 임시 오프셋
    @State private var dragOffset: CGSize = .zero
    
    var body: some View {
        VStack(spacing: 0) {
            // Header / Drag Handle
            HStack {
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(PharTheme.ColorToken.inkSecondary)
                    .font(.system(size: 14, weight: .bold))
                
                Text("인강 브라우저")
                    .font(PharTypography.captionStrong)
                    .foregroundColor(PharTheme.ColorToken.inkPrimary)
                
                Spacer()

                Button {
                    setPopupAllowance(!allowsPopups)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: allowsPopups ? "rectangle.on.rectangle.fill" : "rectangle.on.rectangle")
                        Text("팝업 허용")
                        Text("차단 시 켜기")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(PharTheme.ColorToken.inkSecondary)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(allowsPopups ? PharTheme.ColorToken.accentBlue : PharTheme.ColorToken.inkSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(allowsPopups ? PharTheme.ColorToken.accentBlue.opacity(0.12) : Color.clear)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(allowsPopups ? PharTheme.ColorToken.accentBlue.opacity(0.28) : PharTheme.ColorToken.borderSoft, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                Button {
                    viewModel.isLectureWindowPinned.toggle()
                } label: {
                    Image(systemName: viewModel.isLectureWindowPinned ? "pin.fill" : "pin")
                        .foregroundColor(viewModel.isLectureWindowPinned ? PharTheme.ColorToken.accentBlue : PharTheme.ColorToken.inkSecondary)
                }
                .buttonStyle(.plain)
                
                Button {
                    withAnimation {
                        viewModel.isLectureModeEnabled = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(PharTheme.ColorToken.inkSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(PharTheme.ColorToken.surfaceSecondary)
            .contentShape(Rectangle())
            .gesture(
                viewModel.isLectureWindowPinned ? nil : 
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        viewModel.lectureWindowPosition.x += value.translation.width
                        viewModel.lectureWindowPosition.y += value.translation.height
                        dragOffset = .zero
                    }
            )
            
            // Address Bar
            HStack(spacing: 8) {
                TextField("URL 입력 (예: megastudy.net)", text: $urlInput)
                    .textFieldStyle(.plain)
                    .font(PharTypography.caption)
                    .padding(8)
                    .background(Color.white.opacity(0.8))
                    .cornerRadius(8)
                    .onSubmit {
                        navigateToURL()
                    }
                
                Button {
                    navigateToURL()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundColor(PharTheme.ColorToken.accentBlue)
                }
            }
            .padding(8)
            .background(PharTheme.ColorToken.surfaceTertiary)
            
            // Shortcuts
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ShortcutButton(title: "메가스터디", url: "https://m.megastudy.net", icon: "m.square.fill", color: .blue) {
                        navigateTo(url: $0)
                    }
                    ShortcutButton(title: "대성마이맥", url: "https://m.mimacstudy.com", icon: "d.square.fill", color: .red) {
                        navigateTo(url: $0)
                    }
                    ShortcutButton(title: "시대라이브", url: "https://sd-live.co.kr", icon: "s.square.fill", color: .purple) {
                        navigateTo(url: $0)
                    }
                    ShortcutButton(title: "이투스", url: "https://m.etoos.com", icon: "e.square.fill", color: .orange) {
                        navigateTo(url: $0)
                    }
                    ShortcutButton(title: "EBSi", url: "https://m.ebsi.co.kr", icon: "book.fill", color: .green) {
                        navigateTo(url: $0)
                    }
                    ShortcutButton(title: "유튜브", url: "https://m.youtube.com", icon: "play.rectangle.fill", color: .red) {
                        navigateTo(url: $0)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .background(PharTheme.ColorToken.surfaceTertiary)
            
            // WebView
            ZStack {
                PharWebView(
                    urlString: $viewModel.lectureWebURL,
                    isLoading: $isLoading,
                    allowsPopups: $allowsPopups
                )
                
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
        }
        .frame(width: 480, height: 320) // 기본 크기
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(PharTheme.ColorToken.borderSoft, lineWidth: 1)
        )
        .offset(x: viewModel.lectureWindowPosition.x + dragOffset.width, y: viewModel.lectureWindowPosition.y + dragOffset.height)
        .onAppear {
            urlInput = viewModel.lectureWebURL
            syncPopupAllowance()
        }
        .onChange(of: viewModel.lectureWebURL) { _, newURL in
            if urlInput != newURL {
                urlInput = newURL
            }
            syncPopupAllowance()
        }
    }
    
    private func navigateToURL() {
        navigateTo(url: urlInput)
    }
    
    private func navigateTo(url: String) {
        var finalURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalURL.lowercased().hasPrefix("http") {
            finalURL = "https://" + finalURL
        }
        viewModel.lectureWebURL = finalURL
        urlInput = finalURL
    }

    private func syncPopupAllowance() {
        allowsPopups = viewModel.lecturePopupAllowed(for: viewModel.lectureWebURL)
    }

    private func setPopupAllowance(_ allowed: Bool) {
        allowsPopups = allowed
        viewModel.setLecturePopupAllowed(allowed, for: viewModel.lectureWebURL)
    }
}

struct ShortcutButton: View {
    let title: String
    let url: String
    let icon: String
    let color: Color
    let action: (String) -> Void
    
    var body: some View {
        Button {
            action(url)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.1))
            .foregroundColor(color)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(color.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
