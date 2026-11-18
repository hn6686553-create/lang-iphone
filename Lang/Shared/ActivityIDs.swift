import DeviceActivity
import Foundation

enum ActivityIDs {
    static let prefix = "lang."
    static let threshold = DeviceActivityEvent.Name("daily-usage")

    static func session(_ id: UUID) -> DeviceActivityName { DeviceActivityName("lang.session." + id.uuidString) }
    static func routine(_ id: UUID) -> DeviceActivityName { DeviceActivityName("lang.routine." + id.uuidString) }
    static func budget(_ id: UUID) -> DeviceActivityName { DeviceActivityName("lang.budget." + id.uuidString) }

    static func budgetID(for name: DeviceActivityName) -> UUID? {
        let prefix = "lang.budget."
        guard name.rawValue.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(name.rawValue.dropFirst(prefix.count)))
    }
}
