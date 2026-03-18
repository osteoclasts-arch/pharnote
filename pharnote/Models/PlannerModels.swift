import Foundation

nonisolated enum PlannerTaskStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case pending
    case completed

    var title: String {
        switch self {
        case .pending:
            return "대기"
        case .completed:
            return "완료"
        }
    }
}

nonisolated enum PlannerTaskPriority: String, Codable, CaseIterable, Hashable, Sendable {
    case high
    case normal
    case low

    var title: String {
        switch self {
        case .high:
            return "우선"
        case .normal:
            return "보통"
        case .low:
            return "여유"
        }
    }
}

nonisolated struct PlannerTask: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var title: String
    var subject: StudySubject
    var dueDate: Date
    var scheduledAt: Date?
    var status: PlannerTaskStatus
    var priority: PlannerTaskPriority
    var note: String?

    var isCompleted: Bool {
        status == .completed
    }

    var isUrgent: Bool {
        guard status == .pending else { return false }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return calendar.startOfDay(for: dueDate) <= tomorrow
    }

    func isDue(on date: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(dueDate, inSameDayAs: date)
    }

    func isAgendaItem(on date: Date, calendar: Calendar = .current) -> Bool {
        guard let scheduledAt else { return false }
        return calendar.isDate(scheduledAt, inSameDayAs: date)
    }
}

nonisolated struct PlannerDDayItem: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var title: String
    var targetDate: Date
    var note: String?
    var accentHex: UInt

    var daysRemaining: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: targetDate)
        return calendar.dateComponents([.day], from: start, to: target).day ?? 0
    }

    var displayLabel: String {
        if daysRemaining >= 0 {
            return "D-\(daysRemaining)"
        }
        return "D+\(abs(daysRemaining))"
    }
}

nonisolated struct PlannerState: Codable, Hashable, Sendable {
    var selectedDate: Date
    var tasks: [PlannerTask]
    var dDayItems: [PlannerDDayItem]

    static func defaultState(calendar: Calendar = .current) -> PlannerState {
        let today = calendar.startOfDay(for: Date())

        func day(_ offset: Int, hour: Int? = nil, minute: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            guard let hour else { return base }
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }

        return PlannerState(
            selectedDate: today,
            tasks: [
                PlannerTask(
                    id: UUID(),
                    createdAt: day(-2),
                    updatedAt: day(-1),
                    title: "2024학년도 수능 기출 지문 분석 (독서 2지문)",
                    subject: .korean,
                    dueDate: today,
                    scheduledAt: day(0, hour: 17),
                    status: .completed,
                    priority: .high,
                    note: "국어"
                ),
                PlannerTask(
                    id: UUID(),
                    createdAt: day(-2),
                    updatedAt: day(-1),
                    title: "EBS 수능특강 문학 현대시 3강 정독",
                    subject: .korean,
                    dueDate: today,
                    scheduledAt: nil,
                    status: .completed,
                    priority: .normal,
                    note: nil
                ),
                PlannerTask(
                    id: UUID(),
                    createdAt: day(-1),
                    updatedAt: day(-1),
                    title: "연미 개념 확인 및 실전 문제 20문항",
                    subject: .korean,
                    dueDate: today,
                    scheduledAt: nil,
                    status: .pending,
                    priority: .normal,
                    note: nil
                ),
                PlannerTask(
                    id: UUID(),
                    createdAt: day(-1),
                    updatedAt: day(-1),
                    title: "고전소설 전체 줄거리 파악 및 기출 문제 풀이",
                    subject: .korean,
                    dueDate: today,
                    scheduledAt: nil,
                    status: .completed,
                    priority: .normal,
                    note: nil
                ),
                PlannerTask(
                    id: UUID(),
                    createdAt: day(-1),
                    updatedAt: day(-1),
                    title: "간쓸개 12p~23p",
                    subject: .korean,
                    dueDate: today,
                    scheduledAt: nil,
                    status: .pending,
                    priority: .low,
                    note: nil
                ),
                PlannerTask(
                    id: UUID(),
                    createdAt: day(-1),
                    updatedAt: day(-1),
                    title: "강기원 모의고사 2회",
                    subject: .math,
                    dueDate: today,
                    scheduledAt: day(0, hour: 19, minute: 30),
                    status: .completed,
                    priority: .high,
                    note: "모의고사 상담"
                ),
                PlannerTask(
                    id: UUID(),
                    createdAt: day(-1),
                    updatedAt: day(-1),
                    title: "서바이벌 모의고사 16회",
                    subject: .math,
                    dueDate: today,
                    scheduledAt: nil,
                    status: .pending,
                    priority: .normal,
                    note: nil
                ),
                PlannerTask(
                    id: UUID(),
                    createdAt: day(-1),
                    updatedAt: day(-1),
                    title: "이해원 N제 시즌2 미적 112p ~ 125p",
                    subject: .english,
                    dueDate: today,
                    scheduledAt: nil,
                    status: .completed,
                    priority: .high,
                    note: nil
                ),
                PlannerTask(
                    id: UUID(),
                    createdAt: day(-1),
                    updatedAt: day(-1),
                    title: "수능특강 영어 독해 연습 5강 단어 암기 (50개)",
                    subject: .english,
                    dueDate: today,
                    scheduledAt: nil,
                    status: .completed,
                    priority: .normal,
                    note: nil
                ),
                PlannerTask(
                    id: UUID(),
                    createdAt: day(-1),
                    updatedAt: day(-1),
                    title: "이명학 리드 앤 로직 16강",
                    subject: .english,
                    dueDate: today,
                    scheduledAt: nil,
                    status: .completed,
                    priority: .normal,
                    note: nil
                ),
                PlannerTask(
                    id: UUID(),
                    createdAt: day(-1),
                    updatedAt: day(-1),
                    title: "이명학 일리 6강",
                    subject: .english,
                    dueDate: today,
                    scheduledAt: nil,
                    status: .pending,
                    priority: .low,
                    note: nil
                ),
                PlannerTask(
                    id: UUID(),
                    createdAt: day(-1),
                    updatedAt: day(-1),
                    title: "임정환 리밋 생활과 윤리 18강",
                    subject: .socialInquiry,
                    dueDate: today,
                    scheduledAt: nil,
                    status: .completed,
                    priority: .normal,
                    note: nil
                ),
                PlannerTask(
                    id: UUID(),
                    createdAt: day(-1),
                    updatedAt: day(-1),
                    title: "임정환 리밋 생활과 윤리 기출 1~2단원",
                    subject: .socialInquiry,
                    dueDate: today,
                    scheduledAt: nil,
                    status: .pending,
                    priority: .normal,
                    note: nil
                ),
                PlannerTask(
                    id: UUID(),
                    createdAt: day(-1),
                    updatedAt: day(-1),
                    title: "수특 생활과 윤리 개념 체크",
                    subject: .socialInquiry,
                    dueDate: today,
                    scheduledAt: nil,
                    status: .pending,
                    priority: .low,
                    note: nil
                ),
                PlannerTask(
                    id: UUID(),
                    createdAt: day(-1),
                    updatedAt: day(-1),
                    title: "생활과 윤리 리마인드 노트 정리",
                    subject: .socialInquiry,
                    dueDate: today,
                    scheduledAt: nil,
                    status: .pending,
                    priority: .low,
                    note: nil
                ),
                PlannerTask(
                    id: UUID(),
                    createdAt: day(-1),
                    updatedAt: day(-1),
                    title: "사탐 기출 선지 비교",
                    subject: .socialInquiry,
                    dueDate: today,
                    scheduledAt: nil,
                    status: .pending,
                    priority: .normal,
                    note: nil
                ),
                PlannerTask(
                    id: UUID(),
                    createdAt: day(-1),
                    updatedAt: day(-1),
                    title: "고전소설 인물 관계도 정리",
                    subject: .korean,
                    dueDate: today,
                    scheduledAt: nil,
                    status: .pending,
                    priority: .normal,
                    note: nil
                ),
                PlannerTask(
                    id: UUID(),
                    createdAt: day(-1),
                    updatedAt: day(-1),
                    title: "문학 현대시 암기 복습",
                    subject: .korean,
                    dueDate: today,
                    scheduledAt: nil,
                    status: .completed,
                    priority: .low,
                    note: nil
                ),
                PlannerTask(
                    id: UUID(),
                    createdAt: day(-1),
                    updatedAt: day(-1),
                    title: "서술형 오답 정리",
                    subject: .math,
                    dueDate: today,
                    scheduledAt: nil,
                    status: .pending,
                    priority: .normal,
                    note: nil
                ),
                PlannerTask(
                    id: UUID(),
                    createdAt: day(-1),
                    updatedAt: day(-1),
                    title: "기출 오답 노트 검토",
                    subject: .english,
                    dueDate: today,
                    scheduledAt: nil,
                    status: .pending,
                    priority: .normal,
                    note: nil
                )
            ],
            dDayItems: [
                PlannerDDayItem(
                    id: UUID(),
                    title: "3월 학평",
                    targetDate: day(6),
                    note: "최근 오답 위주 점검",
                    accentHex: 0xFFF7B8
                ),
                PlannerDDayItem(
                    id: UUID(),
                    title: "4모",
                    targetDate: day(45),
                    note: "전범위 기출 재점검",
                    accentHex: 0xF8F3DD
                ),
                PlannerDDayItem(
                    id: UUID(),
                    title: "선지 상담",
                    targetDate: day(50),
                    note: nil,
                    accentHex: 0xF5E3B0
                )
            ]
        )
    }
}

nonisolated struct PlannerTaskDraft: Hashable, Sendable {
    var title: String
    var subject: StudySubject
    var dueDate: Date
    var scheduledAt: Date?
    var priority: PlannerTaskPriority
    var note: String

    init(
        title: String = "",
        subject: StudySubject = .unspecified,
        dueDate: Date = Date(),
        scheduledAt: Date? = nil,
        priority: PlannerTaskPriority = .normal,
        note: String = ""
    ) {
        self.title = title
        self.subject = subject
        self.dueDate = dueDate
        self.scheduledAt = scheduledAt
        self.priority = priority
        self.note = note
    }
}
