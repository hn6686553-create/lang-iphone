import DeviceActivity
import FamilyControls
import Foundation

enum Registration {
    case session(FocusSession)
    case routine(DailyWindow)
    case budget(DailyBudget, FamilyActivitySelection)

    var name: DeviceActivityName {
        switch self {
        case .session(let item): return ActivityIDs.session(item.id)
        case .routine(let item): return ActivityIDs.routine(item.id)
        case .budget(let item, _): return ActivityIDs.budget(item.id)
        }
    }

    static func needed(for state: FocusState, at now: Date) -> [Registration] {
        guard state.selection.hasItems else { return [] }
        var result: [Registration] = []
        if let session = state.active(at: now), session.timerOnly != true { result.append(.session(session)) }
        if let routine = state.routine { result.append(.routine(routine)) }
        if let budget = state.budget { result.append(.budget(budget, state.selection)) }
        result += (state.habits ?? []).filter(\.blocks).map { .routine($0.window) }
        return result
    }

    func install(in center: DeviceActivityCenter) throws {
        let schedule: DeviceActivitySchedule
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        switch self {
        case .session(let session):
            // Use absolute dates, including the end date of a session that crosses midnight.
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(secondsFromGMT: 0)!
            let parts: Set<Calendar.Component> = [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second]
            schedule = DeviceActivitySchedule(intervalStart: utc.dateComponents(parts, from: session.start),
                                              intervalEnd: utc.dateComponents(parts, from: session.plannedEnd),
                                              repeats: false)
        case .routine(let rule):
            schedule = DeviceActivitySchedule(intervalStart: clock(rule.start), intervalEnd: clock(rule.end),
                                              repeats: true)
        case .budget(let rule, let selection):
            guard selection.hasItems else { throw FocusError.selection }
            schedule = DeviceActivitySchedule(intervalStart: DateComponents(hour: 0, minute: 0),
                                              intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
                                              repeats: true)
            events[ActivityIDs.threshold] = DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
                threshold: DateComponents(minute: rule.minutes),
                includesPastActivity: true
            )
        }
        try center.startMonitoring(name, during: schedule, events: events)
    }

    private func clock(_ minute: Int) -> DateComponents {
        DateComponents(hour: minute / 60, minute: minute % 60)
    }
}
