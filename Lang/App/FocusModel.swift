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

    private let center = DeviceActivityCenter()
    private var lastSync = Date()
    private var requestedRestore = false
    private let permissionKey = "lang.previous-permission"

    func enterForeground() {
        do { state = try FocusDisk.access() }
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
        if granted {
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
                    stored.deactivate(at: Date())
                    stored.selection = FamilyActivitySelection()
                }
                removeUnused(keeping: [])
            } catch { show(error) }
        }
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
            notice = Notice(text: "Lặng cần quyền Thời gian sử dụng để chặn ứng dụng. Bạn có thể kiểm tra quyền trong Cài đặt → Thời gian sử dụng.\n\n" + error.localizedDescription)
            return false
        }
    }

    func updateFromMonitor(at now: Date) {
        guard authorized else { return }
        let crossedBoundary = state.shouldShield(at: lastSync) != state.shouldShield(at: now)
        do {
            state = try FocusDisk.access(applyShield: crossedBoundary)
            lastSync = now
        } catch { show(error) }
    }

    func saveSelection(_ list: FamilyActivitySelection) throws {
        guard authorized else { throw FocusError.permission }
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
        guard authorized else { throw FocusError.permission }
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
            state = try FocusDisk.access(applyShield: true, edit: edit)
        } catch {
            if !installed.isEmpty { center.stopMonitoring(installed) }
            throw error
        }
        lastSync = Date()
        removeUnused(keeping: Registration.needed(for: state, at: lastSync))
    }

    private func removeUnused(keeping registrations: [Registration]) {
        let keep = Set(registrations.map(\.name))
        let unused = center.activities.filter { $0.rawValue.hasPrefix(ActivityIDs.prefix) && !keep.contains($0) }
        // An empty array tells iOS to stop *every* activity.
        if !unused.isEmpty { center.stopMonitoring(unused) }
    }
}
