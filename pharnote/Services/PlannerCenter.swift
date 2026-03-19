import Combine
import Foundation

@MainActor
final class PlannerCenter: ObservableObject {
    @Published private(set) var state: PlannerState
    @Published var errorMessage: String?

    private let store: PlannerStore

    init(store: PlannerStore = PlannerStore()) {
        self.store = store
        self.state = PlannerState.defaultState()
    }

    var selectedDate: Date {
        state.selectedDate
    }

    var monthLabel: String {
        Self.monthFormatter.string(from: selectedDate)
    }

    var weekdayLabel: String {
        Self.weekdayFormatter.string(from: selectedDate).uppercased()
    }

    var dayNumberLabel: String {
        Self.dayNumberFormatter.string(from: selectedDate)
    }

    var progressFraction: Double {
        let total = selectedDateTasks.count
        guard total > 0 else { return 0 }
        return Double(selectedDateTasks.filter { $0.isCompleted }.count) / Double(total)
    }

    var urgentCount: Int {
        selectedDateTasks.filter { $0.status == .pending && $0.isUrgent }.count
    }

    var waitingCount: Int {
        selectedDateTasks.filter { $0.status == .pending && !$0.isUrgent }.count
    }

    var completedCount: Int {
        selectedDateTasks.filter { $0.isCompleted }.count
    }

    var selectedDateTasks: [PlannerTask] {
        state.tasks
            .filter { $0.isDue(on: selectedDate) }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority {
                    return lhs.priority.displayOrder < rhs.priority.displayOrder
                }
                if lhs.status != rhs.status {
                    return lhs.status == .pending
                }
                if lhs.scheduledAt == rhs.scheduledAt {
                    return lhs.createdAt > rhs.createdAt
                }
                switch (lhs.scheduledAt, rhs.scheduledAt) {
                case let (lhsDate?, rhsDate?):
                    return lhsDate < rhsDate
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
            }
    }

    var selectedDateAgendaItems: [PlannerTask] {
        selectedDateTasks.filter { $0.isAgendaItem(on: selectedDate) }
    }

    var groupedSelectedTasks: [PlannerSubjectGroup] {
        let tasks = selectedDateTasks
        let subjectOrder: [StudySubject] = [
            .korean,
            .math,
            .english,
            .socialInquiry,
            .physics,
            .chemistry,
            .biology,
            .earthScience,
            .koreanHistory,
            .essay,
            .unspecified
        ]

        return subjectOrder.compactMap { subject in
            let matched = tasks.filter { $0.subject == subject }
            guard !matched.isEmpty else { return nil }
            return PlannerSubjectGroup(subject: subject, tasks: matched)
        }
    }

    var dDayItems: [PlannerDDayItem] {
        state.dDayItems.sorted { lhs, rhs in
            if lhs.daysRemaining == rhs.daysRemaining {
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            return lhs.daysRemaining < rhs.daysRemaining
        }
    }

    var dayStripDates: [Date] {
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: selectedDate)
        return (-365...365).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: anchor)
        }
    }

    var selectedDateHasTasks: Bool {
        !selectedDateTasks.isEmpty
    }

    func refresh() async {
        do {
            state = try await store.loadState()
        } catch {
            errorMessage = "플래너 상태 로드 실패: \(error.localizedDescription)"
        }
    }

    func selectDate(_ date: Date) {
        state.selectedDate = Calendar.current.startOfDay(for: date)
        persistState()
    }

    func addTask(from draft: PlannerTaskDraft) {
        let now = Date()
        let task = PlannerTask(
            id: UUID(),
            createdAt: now,
            updatedAt: now,
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            subject: draft.subject,
            dueDate: Calendar.current.startOfDay(for: draft.dueDate),
            scheduledAt: draft.scheduledAt,
            status: .pending,
            priority: draft.priority,
            note: draft.note.trimmedNilIfEmpty
        )
        state.tasks.insert(task, at: 0)
        persistState()
    }

    func toggleTask(_ task: PlannerTask) {
        guard let index = state.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        state.tasks[index].status = task.isCompleted ? .pending : .completed
        state.tasks[index].updatedAt = Date()
        persistState()
    }

    func deleteTask(_ task: PlannerTask) {
        state.tasks.removeAll { $0.id == task.id }
        persistState()
    }

    func saveDDayItem(from draft: PlannerDDayDraft) {
        let cleanedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else { return }

        let item = PlannerDDayItem(
            id: draft.id ?? UUID(),
            title: cleanedTitle,
            targetDate: Calendar.current.startOfDay(for: draft.targetDate),
            note: draft.note.trimmedNilIfEmpty,
            accentHex: draft.accentHex
        )

        if let index = state.dDayItems.firstIndex(where: { $0.id == item.id }) {
            state.dDayItems[index] = item
        } else {
            state.dDayItems.append(item)
        }
        persistState()
    }

    func deleteDDayItem(_ item: PlannerDDayItem) {
        state.dDayItems.removeAll { $0.id == item.id }
        persistState()
    }

    func resetToSeed() {
        state = PlannerState.defaultState()
        persistState()
    }

    private func persistState() {
        let snapshot = state
        Task {
            do {
                try await store.saveState(snapshot)
            } catch {
                await MainActor.run {
                    self.errorMessage = "플래너 상태 저장 실패: \(error.localizedDescription)"
                }
            }
        }
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private static let dayNumberFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "d"
        return formatter
    }()
}

nonisolated struct PlannerSubjectGroup: Identifiable, Hashable, Sendable {
    var subject: StudySubject
    var tasks: [PlannerTask]

    var id: StudySubject { subject }
}

private extension PlannerTaskPriority {
    var displayOrder: Int {
        switch self {
        case .high: return 0
        case .normal: return 1
        case .low: return 2
        }
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
