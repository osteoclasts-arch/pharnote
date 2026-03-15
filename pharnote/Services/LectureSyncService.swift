import Foundation
import Combine

/// [Service: LectureSyncService]
/// 인강의 타임라인과 학생의 사고 노드를 실시간으로 연결하고 관리하는 서비스입니다.
@MainActor
final class LectureSyncService: ObservableObject {
    @Published var currentSessionId: String?
    @Published var currentTimestamp: Double = 0
    @Published var activeSyncNodes: [LessonSyncNode] = []
    
    /// 현재 재생 중인 시점과 가장 근접한 동기화 노드
    @Published var activeNode: LessonSyncNode?
    
    private var cancellables = Set<AnyCancellable>()
    
    static let shared = LectureSyncService()
    
    private init() {}
    
    func startSession(sessionId: String, initialNodes: [LessonSyncNode]) {
        self.currentSessionId = sessionId
        self.activeSyncNodes = initialNodes.sorted(by: { $0.timestampSeconds < $1.timestampSeconds })
    }
    
    /// 플레이어의 시각이 업데이트될 때 호출
    func updateTimestamp(_ seconds: Double) {
        self.currentTimestamp = seconds
        
        // 현재 시점과 가장 가까운(이전) 노드 찾기
        let nearest = activeSyncNodes
            .filter { $0.timestampSeconds <= seconds }
            .last
        
        if activeNode?.id != nearest?.id {
            activeNode = nearest
            handleNodeTransition(to: nearest)
        }
    }
    
    /// [Zero-Search] 학생의 필기 정체 시 추천 노드 제안 로직
    func detectStallAndNudge(stats: AnalysisDrawingStats, isWriting: Bool) -> String? {
        let confidence = calculateConfidence(stats: stats)
        
        // 정체 기준: 확신도가 낮고(0.3 미만), 펜이 멈춘 시간이 15초 이상인 경우
        if confidence < 0.3 && (stats.pauseTime ?? 0) > 15 && !isWriting {
            return activeNode?.conceptNodeId
        }
        return nil
    }
    
    private func calculateConfidence(stats: AnalysisDrawingStats) -> Double {
        let active = stats.activeWritingTime ?? 0
        let pause = stats.pauseTime ?? 0
        let total = active + pause
        
        guard total > 0 else { return 1.0 }
        
        // 단순 모델: 전체 시간 중 실제 필기 시간의 비율을 확신도로 환산
        return active / total
    }
    
    private func handleNodeTransition(to node: LessonSyncNode?) {
        guard let node = node else { return }
        
        // "Zero-Search Experience": 강사가 다음 개념으로 넘어갈 때 BrainTree 동기화
        print("[LectureSync] Node Transition: \(node.conceptNodeId ?? "Intro") at \(node.videoTimestamp)")
    }
}

// 헬퍼용 정렬 로직 (Swift 6 호환 대응)
private func sortNodes(_ nodes: [LessonSyncNode]) -> [LessonSyncNode] {
    nodes.sorted(by: { $0.timestampSeconds < $1.timestampSeconds })
}
