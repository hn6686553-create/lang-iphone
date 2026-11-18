import UserNotifications
import Combine
import DeviceActivity
import FamilyControls
import Foundation

struct Notice: Identifiable {
    let id = UUID()
    let text: String
}

@MainActor
final class FocusModel: ObservableObject {
    static let durations = [15, 25, 50, 90]
    static let budgets = [15, 30, 45, 60, 90, 120]

    @Published private(set) var state = FocusState()
    @Published private(set) var authorized = false
    @Published private(set) var requesting = false
    @Published var notice: Notice?

    @Published var accessIssue: String?
    var canBlock: Bool { authorized && FocusDisk.sharedRoot != nil }
    private let center = DeviceActivityCenter()
    private var lastSync = Date()
    private var requestedRestore = false
    private let permissionKey = "lang.previous-permission"

    func enterForeground() {
        do { state = try FocusDisk.access(allowLocal: true) }
        catch { show(error); return }
        let status = AuthorizationCenter.shared.authorizationStatus
        authorizationChanged(status, force: true)
        // The system may publish its initial status only after an authorization request.
        if status == .notDetermined && !requestedRestore && UserDefaults.standard.bool(forKey: permissionKey) {
            requestedRestore = true
            Task { _ = await requestAccess() }
        }
    }

    func authorizationChanged(_ status: AuthorizationStatus, force: Bool = false) {
        let granted = status == .approved
        if !force && granted == authorized && status != .denied { return }
        let hadAccess = authorized
        authorized = granted
        if FocusDisk.sharedRoot == nil {
            accessIssue = "Bản ký này chưa mở được App Groups. Bạn vẫn dùng được đồng hồ và lời nhắc. Để chặn app, hãy ký Lặng và phần mở rộng Monitor với cùng App Group."
            return
        }
        if granted {
            accessIssue = nil
            UserDefaults.standard.set(true, forKey: permissionKey)
            do {
                let stored = try FocusDisk.access()
                let needed = Registration.needed(for: stored, at: Date())
                removeUnused(keeping: needed)
                let installed = Set(center.activities)
                for item in needed where !installed.contains(item.name) {
                    try item.install(in: center)
                }
                state = try FocusDisk.access(applyShield: true)
                lastSync = Date()
            } catch { show(error) }
        } else if status == .denied || (status == .notDetermined && hadAccess) {
            UserDefaults.standard.removeObject(forKey: permissionKey)
            do {
                state = try FocusDisk.access(applyShield: true) { stored in
                    let timer = stored.active(at: Date()).flatMap { $0.timerOnly == true ? $0 : nil }
                    stored.deactivate(at: Date())
                    if let timer, let index = stored.sessions.firstIndex(where: { $0.id == timer.id }) {
                        stored.sessions[index] = timer
                    }
                    stored.selection = FamilyActivitySelection()
                }
                removeUnused(keeping: [])
            } catch { show(error) }
        }
    }

    func requestBlockingAccess() async -> Bool {
        guard FocusDisk.sharedRoot != nil else {
            accessIssue = "Bản ký hiện tại thiếu App Group dùng chung với Monitor. Bạn vẫn có thể chọn Chỉ chạy đồng hồ hoặc tạo thói quen nhắc giờ."
            return false
        }
        return await requestAccess()
    }

    func requestAccess() async -> Bool {
        if authorized { return true }
        guard !requesting else { return false }
        requesting = true
        defer { requesting = false }
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            authorizationChanged(AuthorizationCenter.shared.authorizationStatus, force: true)
            if !authorized { throw FocusError.permission }
            return true
        } catch {
            if AuthorizationCenter.shared.authorizationStatus == .denied {
                authorizationChanged(.denied)
            }
            accessIssue = AuthorizationCenter.shared.authorizationStatus == .denied
                ? "Quyền Thời gian sử dụng đã bị từ chối. Bạn có thể cho phép lại trong Cài đặt."
                : "iOS chưa cấp quyền chặn ứng dụng. Kiểm tra quyền Family Controls của bản ký Lặng và các phần mở rộng. Đồng hồ và lời nhắc vẫn dùng được."
            return false
        }
    }

    func updateFromMonitor(at now: Date) {
        guard canBlock else { return }
        let crossedBoundary = state.shouldShield(at: lastSync) != state.shouldShield(at: now)
        do {
            state = try FocusDisk.access(applyShield: crossedBoundary)
            lastSync = now
        } catch { show(error) }
    }

    func saveSelection(_ list: FamilyActivitySelection) throws {
        guard canBlock else { throw FocusError.permission }
        guard list.fitsShieldLimits else { throw FocusError.capacity }
        guard list != state.selection else { return }
        if !list.hasItems {
            try commit { stored in
                stored.selection = list
                stored.deactivate(at: Date())
            }
            return
        }
        // The OS sums the newly selected tokens from the beginning of the current day.
        let replacement = state.budget.map { DailyBudget(minutes: $0.minutes) }
        let registrations = replacement.map { [Registration.budget($0, list)] } ?? []
        try commit(installing: registrations) { stored in
            stored.selection = list
            stored.budget = replacement
        }
    }

    func start(minutes: Int) throws {
        try requireSelection()
        guard Self.durations.contains(minutes) else { throw FocusError.duration }
        let now = Date()
        guard state.active(at: now) == nil else { throw FocusError.busy }
        let session = FocusSession(minutes: minutes, at: now)
        try commit(installing: [.session(session)]) { stored in
            guard stored.active(at: now) == nil else { throw FocusError.busy }
            stored.sessions.append(session)
        }
    }

    func startTimer(minutes: Int) throws {
        guard Self.durations.contains(minutes) else { throw FocusError.duration }
        var session = FocusSession(minutes: minutes, at: Date())
        session.timerOnly = true
        state = try FocusDisk.access(allowLocal: true) {
            guard $0.active(at: Date()) == nil else { throw FocusError.busy }
            $0.sessions.append(session)
        }
    }

    func addHabit(title: String, window: DailyWindow, blocks: Bool) async throws {
        if blocks { try requireSelection() }
        let notifications = UNUserNotificationCenter.current()
        guard try await notifications.requestAuthorization(options: [.alert, .sound]) else {
            throw NSError(domain: "Lang", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bật thông báo cho Lặng trong Cài đặt để nhận lời nhắc."])
        }
        let habit = Habit(title: title, window: window, blocks: blocks)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "Đến giờ " + title.lowercased() + "."
        content.sound = .default
        let clock = DateComponents(hour: window.start / 60, minute: window.start % 60)
        let request = UNNotificationRequest(identifier: habit.id.uuidString, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: clock, repeats: true))
        try await notifications.add(request)
        do {
            if blocks { try requireSelection() }
            try commit(installing: blocks ? [.routine(window)] : []) {
                $0.habits = ($0.habits ?? []) + [habit]
            }
        } catch {
            notifications.removePendingNotificationRequests(withIdentifiers: [habit.id.uuidString])
            throw error
        }
    }

    func deleteHabit(_ habit: Habit) throws {
        try commit { $0.habits?.removeAll { $0.id == habit.id } }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [habit.id.uuidString])
    }

    func finish() throws {
        try commit { $0.endSession(at: Date()) }
    }

    func setRoutine(_ rule: DailyWindow?) throws {
        if let rule {
            try requireSelection()
            guard rule.minutes >= 15 else { throw FocusError.duration }
            if let old = state.routine, old.start == rule.start && old.end == rule.end { return }
        }
        try commit(installing: rule.map { [.routine($0)] } ?? []) { $0.routine = rule }
    }

    func setBudget(minutes: Int?) throws {
        if let minutes {
            try requireSelection()
            guard Self.budgets.contains(minutes) else { throw FocusError.duration }
        }
        guard state.budget?.minutes != minutes else { return }
        let rule = minutes.map { DailyBudget(minutes: $0) }
        try commit(installing: rule.map { [.budget($0, state.selection)] } ?? []) { $0.budget = rule }
    }

    func show(_ error: Error) { notice = Notice(text: error.localizedDescription) }

    private func requireSelection() throws {
        guard canBlock else { throw FocusError.permission }
        guard state.selection.hasItems else { throw FocusError.selection }
    }

    private func commit(installing registrations: [Registration] = [],
                        _ edit: @escaping (inout FocusState) throws -> Void) throws {
        var installed: [DeviceActivityName] = []
        do {
            for item in registrations {
                try item.install(in: center)
                installed.append(item.name)
            }
            state = try FocusDisk.access(applyShield: canBlock, allowLocal: registrations.isEmpty, edit: edit)
        } catch {
            if !installed.isEmpty { center.stopMonitoring(installed) }
            throw error
        }
        lastSync = Date()
        if canBlock { removeUnused(keeping: Registration.needed(for: state, at: lastSync)) }
    }

    private func removeUnused(keeping registrations: [Registration]) {
        let keep = Set(registrations.map(\.name))
        let unused = center.activities.filter { $0.rawValue.hasPrefix(ActivityIDs.prefix) && !keep.contains($0) }
        // An empty array tells iOS to stop *every* activity.
        if !unused.isEmpty { center.stopMonitoring(unused) }
    }
}
