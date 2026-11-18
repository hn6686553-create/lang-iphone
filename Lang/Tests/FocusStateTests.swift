import FamilyControls
import XCTest
@testable import Lang

final class FocusStateTests: XCTestCase {
    func testEarlyExitKeepsActualTimeAcrossMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Ho_Chi_Minh"))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 23, minute: 55)))
        let stop = start.addingTimeInterval(12 * 60)
        var state = FocusState()
        state.sessions = [FocusSession(minutes: 25, at: start)]
        state.endSession(at: stop)
        state.endSession(at: stop.addingTimeInterval(300))
        XCTAssertNil(state.active(at: stop))
        let days = FocusHistory.week(sessions: state.sessions, ending: stop, calendar: calendar)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.suffix(2).map(\.seconds), [300, 420])
        let copy = try JSONDecoder().decode(FocusState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(copy.sessions.first?.id, state.sessions.first?.id)
        XCTAssertEqual(copy.sessions.first?.end, stop)
    }

    func testOnlyElapsedPartOfRunningSessionCounts() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let session = FocusSession(minutes: 15, at: start)
        let now = start.addingTimeInterval(71)
        let span = DateInterval(start: start, duration: 900)
        XCTAssertTrue(session.isActive(at: now))
        XCTAssertEqual(session.seconds(in: span, until: now), 71)
        XCTAssertFalse(session.isActive(at: start.addingTimeInterval(900)))
    }

    func testPriorBudgetCallbackAndPriorDayCannotBlockToday() throws {
        let now = Date(), current = DailyBudget(minutes: 30), old = DailyBudget(minutes: 15)
        var state = FocusState()
        state.budget = current
        state.thresholdHits[old.id.uuidString] = now
        XCTAssertFalse(state.budgetReached(at: now))
        let yesterday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: now))
        state.thresholdHits[current.id.uuidString] = yesterday
        XCTAssertFalse(state.budgetReached(at: now))
        state.thresholdHits[current.id.uuidString] = now
        XCTAssertTrue(state.budgetReached(at: now))
        XCTAssertEqual(ActivityIDs.budgetID(for: ActivityIDs.budget(current.id)), current.id)
        XCTAssertNil(ActivityIDs.budgetID(for: ActivityIDs.routine(old.id)))
    }

    func testEndingOneRulePreservesOtherRules() throws {
        let now = try XCTUnwrap(Calendar.current.date(bySettingHour: 12, minute: 30, second: 0, of: Date()))
        var state = FocusState()
        state.routine = DailyWindow(start: 12 * 60, end: 13 * 60)
        let budget = DailyBudget(minutes: 30)
        state.budget = budget
        state.thresholdHits[budget.id.uuidString] = now
        state.sessions = [FocusSession(minutes: 25, at: now)]
        XCTAssertEqual(state.reasons(at: now), [.session, .routine, .budget])
        state.endSession(at: now.addingTimeInterval(30))
        XCTAssertEqual(state.reasons(at: now.addingTimeInterval(31)), [.routine, .budget])
        state.routine = nil
        XCTAssertEqual(state.reasons(at: now.addingTimeInterval(31)), [.budget])
        state.deactivate(at: now.addingTimeInterval(40))
        XCTAssertTrue(state.reasons(at: now.addingTimeInterval(40)).isEmpty)
        XCTAssertEqual(state.sessions.count, 1)
    }
}
