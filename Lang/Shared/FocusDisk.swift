import Darwin
import FamilyControls
import Foundation
import ManagedSettings

enum FocusError: LocalizedError {
    case group, fileLock, permission, selection, capacity, duration, busy

    var errorDescription: String? {
        switch self {
        case .group: return "Chưa mở được vùng dữ liệu chung. Kiểm tra App Groups và chữ ký của Lặng trong Xcode."
        case .fileLock: return "Chưa thể cập nhật dữ liệu trên máy. Hãy thử lại."
        case .permission: return "Hãy cho phép Lặng dùng Thời gian sử dụng trên iPhone."
        case .selection: return "Hãy chọn ít nhất một ứng dụng, danh mục hoặc trang web."
        case .capacity: return "iOS cho phép tối đa 50 mục cho mỗi loại. Hãy bớt ứng dụng, danh mục hoặc trang web."
        case .duration: return "Giờ bắt đầu và kết thúc phải cách nhau ít nhất 15 phút."
        case .busy: return "Bạn đang có một phiên tập trung."
        }
    }
}

enum FocusDisk {
    private static let shield = ManagedSettingsStore(named: ManagedSettingsStore.Name("lang.focus"))

    static var sharedRoot: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "LangAppGroup") as? String,
              let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group),
              FileManager.default.isWritableFile(atPath: url.path) else { return nil }
        return url
    }

    /// App and monitor share a file lock. System registration calls stay outside this lock.
    @discardableResult
    static func access(applyShield: Bool = false, allowLocal: Bool = false,
                       edit: ((inout FocusState) throws -> Void)? = nil) throws -> FocusState {
        let shared = sharedRoot
        let root: URL
        if let shared { root = shared }
        else if allowLocal {
            root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        } else { throw FocusError.group }

        let lockPath = root.appendingPathComponent("focus.lock").path
        let fd = lockPath.withCString { Darwin.open($0, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR) }
        guard fd >= 0 else { throw FocusError.fileLock }
        defer { _ = Darwin.close(fd) }
        while flock(fd, LOCK_EX) != 0 {
            if errno != EINTR { throw FocusError.fileLock }
        }
        defer { _ = flock(fd, LOCK_UN) }

        let file = root.appendingPathComponent("focus-v1.json")
        var state: FocusState
        do {
            state = try JSONDecoder().decode(FocusState.self, from: Data(contentsOf: file))
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            state = FocusState()
        }
        if let edit {
            try edit(&state)
            let today = Date()
            state.thresholdHits = state.thresholdHits.filter { Calendar.current.isDate($0.value, inSameDayAs: today) }
            let bytes = try JSONEncoder().encode(state)
            try bytes.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        if applyShield && shared != nil {
            if state.shouldShield(at: Date()) {
                let list = state.selection
                shield.shield.applications = list.applicationTokens.isEmpty ? nil : list.applicationTokens
                shield.shield.applicationCategories = list.categoryTokens.isEmpty ? nil : .specific(list.categoryTokens)
                shield.shield.webDomains = list.webDomainTokens.isEmpty ? nil : list.webDomainTokens
                shield.shield.webDomainCategories = list.categoryTokens.isEmpty ? nil : .specific(list.categoryTokens)
            } else {
                shield.clearAllSettings()
            }
        }
        return state
    }
}
