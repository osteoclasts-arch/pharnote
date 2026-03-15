import Foundation

/// [Schema: LessonSyncNode]
/// 인강의 타임라인과 학생의 사고 노드를 연결하는 핵심 데이터 구조입니다.
nonisolated struct LessonSyncNode: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    
    /// 세션 ID (예: "math_sat_01")
    var sessionId: String
    
    /// 영상 내 타임스탬프 (예: "12:45")
    var videoTimestamp: String
    
    /// 인강의 해당 시점 초 단위 (정렬 및 동기화 용도)
    var timestampSeconds: Double
    
    /// PharNode의 Node Ontology와 매핑되는 개념 노드 ID
    var conceptNodeId: String?
    
    /// 강사의 음성에서 추출된 텍스트 (on-device STT 결과)
    var sttTranscript: String?
    
    /// 현재 프레임의 판서 영역 캡처 URL (클린업된 이미지)
    var ocrBoardCaptureURL: String?
    
    /// 필기 속도 및 휴지 시간을 계산한 실시간 확신도 (0.0 ~ 1.0)
    var studentConfidence: Double?
    
    /// 필기 데이터 통계
    var pencilData: LessonPencilData?
    
    static func == (lhs: LessonSyncNode, rhs: LessonSyncNode) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

nonisolated struct LessonPencilData: Codable, Hashable, Sendable {
    /// 획수
    var strokeCount: Int
    
    /// 실제 펜이 닿은 시간 (Active Writing Time)
    var activeTimeSec: Double
    
    /// 고민하거나 멈춘 시간
    var pauseTimeSec: Double
}

nonisolated struct LessonMetadata: Codable, Hashable, Sendable {
    var videoURL: URL?
    var lectureTitle: String
    var totalDuration: Double
    var lastWatchedTimestamp: Double
    var syncNodes: [LessonSyncNode]
}
