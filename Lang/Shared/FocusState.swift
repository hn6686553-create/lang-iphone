import Foundation
import FamilyControls

struct FocusSession: Codable, Identifiable {
    let id: UUID
    let start: Date
    let plannedEnd: Date
    var stoppedAt: Date?
    var timerOnly: Bool?

    init(minutes: Int, at now: Date) {
        id = UUID()
        start = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970))
        plannedEnd = start.addingTimeInterval(Double(minutes) * 60)
    }

    var end: Date { min(stoppedAt ?? plannedEnd, plannedEnd) }

    func isActive(at date: Date) -> Bool {
        stoppedAt == nil && start <= date && date < plannedEnd
    }

    func seconds(in interval: DateInterval, until now: Date) -> TimeInterval {
        lang_overlap_seconds(start.timeIntervalSince1970, min(end, now).timeIntervalSince1970,
                             interval.start.timeIntervalSince1970, interval.end.timeIntervalSince1970)
    }
}

struct DailyWindow: Codable, Identifiable {
    let id: UUID
    let start: Int
    let end: Int

    init(start: Int, end: Int) {
        self.id = UUID()
        self.start = start
        self.end = end
    }

    var minutes: Int { Int(lang_window_minutes(Int32(start), Int32(end))) }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let time = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (time.hour ?? 0) * 60 + (time.minute ?? 0)
        return lang_window_contains(Int32(start), Int32(end), Int32(minute))
    }
}

struct DailyBudget: Codable, Identifiable {
    let id: UUID
    let minutes: Int

    init(minutes: Int) {
        self.id = UUID()
        self.minutes = minutes
    }
}

struct Habit: Codable, Identifiable {
    var id: UUID { window.id }
    let title: String
    let window: DailyWindow
    let blocks: Bool
}

struct FocusState: Codable {
    var habits: [Habit]?
    var selection = FamilyActivitySelection()
    var sessions: [FocusSession] = []
    var routine: DailyWindow?
    var budget: DailyBudget?
    // Indexed by registration ID so that delayed callbacks cannot mark a replacement rule.
    var thresholdHits: [String: Date] = [:]

    func active(at now: Date) -> FocusSession? {
        guard let last = sessions.last, last.isActive(at: now) else { return nil }
        return last
    }

    mutating func endSession(at now: Date) {
        guard let last = sessions.last, last.stoppedAt == nil else { return }
        if now < last.plannedEnd {
            sessions[sessions.count - 1].stoppedAt = max(last.start, now)
        }
    }

    func budgetReached(at now: Date, calendar: Calendar = .current) -> Bool {
        guard let id = budget?.id, let hit = thresholdHits[id.uuidString] else { return false }
        return calendar.isDate(hit, inSameDayAs: now)
    }

    enum Reason: Hashable { case session, routine, budget }

    func reasons(at now: Date) -> Set<Reason> {
        var result: Set<Reason> = []
        if let session = active(at: now), session.timerOnly != true { result.insert(.session) }
        if routine?.contains(now) == true || (habits ?? []).contains(where: { $0.blocks && $0.window.contains(now) }) { result.insert(.routine) }
        if budgetReached(at: now) { result.insert(.budget) }
        return result
    }

    func shouldShield(at now: Date) -> Bool {
        selection.hasItems && !reasons(at: now).isEmpty
    }

    mutating func deactivate(at now: Date) {
        endSession(at: now)
        habits = habits?.map { Habit(title: $0.title, window: $0.window, blocks: false) }
        routine = nil
        budget = nil
        thresholdHits.removeAll()
    }
}

extension FamilyActivitySelection {
    var hasItems: Bool {
        !applicationTokens.isEmpty || !categoryTokens.isEmpty || !webDomainTokens.isEmpty
    }

    var fitsShieldLimits: Bool {
        applicationTokens.count <= 50 && categoryTokens.count <= 50 && webDomainTokens.count <= 50
    }

    var langSummary: String {
        var parts: [String] = []
        if !applicationTokens.isEmpty { parts.append("\(applicationTokens.count) ứng dụng") }
        if !categoryTokens.isEmpty { parts.append("\(categoryTokens.count) danh mục") }
        if !webDomainTokens.isEmpty { parts.append("\(webDomainTokens.count) trang web") }
        return parts.isEmpty ? "Chưa chọn mục nào" : parts.joined(separator: " · ")
    }
}
