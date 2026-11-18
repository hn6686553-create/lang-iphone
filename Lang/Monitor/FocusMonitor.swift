import DeviceActivity
import Foundation
import OSLog

final class FocusMonitor: DeviceActivityMonitor {
    private let log = Logger(subsystem: "Lang", category: "Monitor")

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        refresh()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        // Recompute every rule. An overlapping session or daily limit can still be active.
        refresh()
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        guard event == ActivityIDs.threshold, let id = ActivityIDs.budgetID(for: activity) else { return }
        do {
            // iOS can send this before startMonitoring returns to the app.
            try FocusDisk.access(applyShield: true) { $0.thresholdHits[id.uuidString] = Date() }
        } catch {
            log.error("Could not persist a daily limit event: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func refresh() {
        do { try FocusDisk.access(applyShield: true) }
        catch { log.error("Could not update a shield: \(error.localizedDescription, privacy: .public)") }
    }
}
