import SwiftUI
import AVKit

struct LessonDocumentEditorView: View {
    let document: PharDocument
    
    @StateObject private var lectureSync = LectureSyncService.shared
    @StateObject private var viewModel: BlankNoteEditorViewModel
    @State private var player = AVPlayer()
    @State private var capturedImage: UIImage?
    @State private var isShowingNudge = false
    @State private var nudgeNodeId: String?
    
    init(document: PharDocument) {
        self.document = document
        // .lesson 타입이지만 필기 캔버스는 BlankNoteEditorViewModel을 재사용하여 안정성 확보
        _viewModel = StateObject(wrappedValue: BlankNoteEditorViewModel(document: document))
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // 좌측: 인강 영역
            VStack {
                lecturePlayerView
                
                HStack {
                    Button(action: captureSmartLayer) {
                        Label("스마트 레이어 캡처", systemImage: "Plus.viewfinder")
                            .font(.headline)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    
                    Spacer()
                    
                    if let nodeId = lectureSync.activeNode?.conceptNodeId {
                        Text("현재 개념: \(nodeId)")
                            .font(.caption)
                            .padding(8)
                            .background(Color.black.opacity(0.1))
                            .cornerRadius(5)
                    }
                }
                .padding()
            }
            .frame(maxWidth: .infinity)
            
            Divider()
            
            // 우측: 필기 영역
            ZStack {
                PencilCanvasView(viewModel: viewModel)
                    .background(Color.white)
                
                // 제로 서치 넛지 UI
                if isShowingNudge, let nodeId = nudgeNodeId {
                    VStack {
                        Spacer()
                        HStack {
                            VStack(alignment: .leading) {
                                Text("혹시 이 부분이 헷갈리시나요?")
                                    .font(.subheadline)
                                    .bold()
                                Text("관련 개념 검색 없이 바로 보기: \(nodeId)")
                                    .font(.caption)
                            }
                            Spacer()
                            Button("보기") {
                                // 노드 상세 보기 로직
                                isShowingNudge = false
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                        .background(Color.yellow.opacity(0.9))
                        .cornerRadius(12)
                        .padding()
                        .transition(.move(edge: .bottom))
                    }
                }
            }
            .frame(width: 500) // 아이패드 등 대화면 기준 고정폭 필기장
        }
        .onAppear {
            setupPlayer()
            startSyncCheck()
        }
    }
    
    private var lecturePlayerView: some View {
        VideoPlayer(player: player)
            .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
                lectureSync.updateTimestamp(player.currentTime().seconds)
            }
    }
    
    private func setupPlayer() {
        // 실제 구현에서는 document.path 등에서 URL 추출
        // 여기서는 데모를 위해 샘플 URL 또는 플레이어 객체만 초기화
        lectureSync.startSession(sessionId: document.title, initialNodes: [])
    }
    
    private func captureSmartLayer() {
        Task {
            do {
                let cleanedImage = try await SmartLayerCaptureService.shared.captureAndCleanBoard(from: player)
                self.capturedImage = cleanedImage
                // TODO: 캔버스에 이미지 삽입 로직 연결
                print("[SmartLayer] Capture succeeded and background removed.")
            } catch {
                print("[SmartLayer] Capture failed: \(error)")
            }
        }
    }
    
    private func startSyncCheck() {
        // 제로 서치 넛지 감지 루프
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            // 현재 ViewModel의 드로잉 통계를 기반으로 정체 감지
            // 실제 PencilCanvasView와 연동된 통계 데이터 필요
            let mockStats = AnalysisDrawingStats(
                strokeCount: 10,
                inkLengthEstimate: 100,
                eraseRatio: 0,
                highlightCoverage: 0,
                activeWritingTime: 5,
                pauseTime: 20 // 15초 이상 정체 가정
            )
            
            if let nodeId = lectureSync.detectStallAndNudge(stats: mockStats, isWriting: false) {
                withAnimation {
                    self.nudgeNodeId = nodeId
                    self.isShowingNudge = true
                }
            }
        }
    }
}
