import FamilyControls
import SwiftUI

struct RulesView: View {
    @ObservedObject var model: FocusModel
    let onRoutine: () -> Void
    let onBudget: () -> Void
    let onList: () -> Void

    var body: some View {
        Page(title: "Lịch chặn", now: Date()) {
            Panel {
                VStack(alignment: .leading, spacing: 19) {
                    RuleRow(icon: "calendar", title: "Khung giờ hằng ngày", detail: routineDetail,
                            active: model.state.routine != nil, action: onRoutine)
                    Divider().overlay(Ink.line)
                    RuleRow(icon: "hourglass", title: "Giới hạn sử dụng",
                            detail: model.state.budget.map { "\($0.minutes) phút mỗi ngày" } ?? "Đang tắt",
                            active: model.state.budget != nil, action: onBudget)
                }
            }
            Panel {
                RuleRow(icon: "square.stack.3d.up", title: "Áp dụng cho",
                        detail: model.state.selection.langSummary, active: model.state.selection.hasItems, action: onList)
            }
        }
    }

    private var routineDetail: String {
        guard let rule = model.state.routine else { return "Đang tắt" }
        let span = "\(Viet.clock(rule.start)) – \(Viet.clock(rule.end))"
        return rule.end < rule.start ? span + " · qua đêm" : span
    }
}

struct SelectionSheet: View {
    @ObservedObject var model: FocusModel
    @State private var draft: FamilyActivitySelection
    @State private var error: Notice?
    @State private var askClear = false
    let cancel: () -> Void
    let saved: (Bool) -> Void

    init(model: FocusModel, cancel: @escaping () -> Void, saved: @escaping (Bool) -> Void) {
        self.model = model
        _draft = State(initialValue: model.state.selection)
        self.cancel = cancel
        self.saved = saved
    }

    var body: some View {
        NavigationStack {
            FamilyActivityPicker(selection: $draft)
                .navigationTitle("Danh sách chặn")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Hủy", action: cancel) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Lưu") {
                            let rulesExist = model.state.active(at: Date()) != nil || model.state.routine != nil || model.state.budget != nil
                            if !draft.hasItems && rulesExist { askClear = true } else { save() }
                        }
                    }
                }
        }
        .alert(item: $error) { Alert(title: Text("Chưa lưu được"), message: Text($0.text), dismissButton: .default(Text("Đóng"))) }
        .confirmationDialog("Xóa hết mục đã chọn?", isPresented: $askClear, titleVisibility: .visible) {
            Button("Xóa danh sách và tắt chặn", role: .destructive) { save() }
            Button("Giữ lại", role: .cancel) {}
        } message: {
            Text("Phiên đang chạy sẽ kết thúc. Khung giờ chặn và giới hạn sử dụng sẽ tắt.")
        }
    }

    private func save() {
        do {
            try model.saveSelection(draft)
            saved(draft.hasItems)
        } catch { self.error = Notice(text: error.localizedDescription) }
    }
}

struct RuleEditor: View {
    enum Kind { case routine, budget }
    let kind: Kind
    @ObservedObject var model: FocusModel
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date
    @State private var budgetMinutes: Int
    @State private var error: Notice?

    init(kind: Kind, model: FocusModel) {
        self.kind = kind
        self.model = model
        _start = State(initialValue: Self.clockDate(model.state.routine?.start ?? 9 * 60))
        _end = State(initialValue: Self.clockDate(model.state.routine?.end ?? 11 * 60))
        _budgetMinutes = State(initialValue: model.state.budget?.minutes ?? 30)
    }

    private static func clockDate(_ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
    }

    private func clockMinute(_ date: Date) -> Int {
        Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
    }

    private var rule: DailyWindow { DailyWindow(start: clockMinute(start), end: clockMinute(end)) }
    private var existing: Bool { kind == .routine ? model.state.routine != nil : model.state.budget != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if kind == .routine {
                        Panel {
                            VStack(spacing: 12) {
                                DatePicker("Bắt đầu", selection: $start, displayedComponents: .hourAndMinute)
                                Divider().overlay(Ink.line)
                                DatePicker("Kết thúc", selection: $end, displayedComponents: .hourAndMinute)
                            }
                        }
                        Text(routineDescription).font(.subheadline).foregroundStyle(Ink.muted)
                    } else {
                        Panel {
                            Picker("Hạn mức mỗi ngày", selection: $budgetMinutes) {
                                ForEach(FocusModel.budgets, id: \.self) { Text("\($0) phút").tag($0) }
                            }
                            .pickerStyle(.wheel).frame(maxWidth: .infinity, minHeight: 126)
                            .accessibilityLabel("Hạn mức mỗi ngày")
                        }
                        Text("iPhone cộng thời gian dùng các mục đã chọn từ đầu ngày. Khi đủ hạn mức, các mục đó sẽ bị chặn đến hết ngày.")
                            .font(.subheadline).foregroundStyle(Ink.muted)
                    }
                    PrimaryButton(title: kind == .routine ? "Lưu khung giờ" : "Lưu giới hạn",
                                  icon: "checkmark") { save(disable: false) }
                        .disabled(kind == .routine && rule.minutes < 15)
                        .opacity(kind == .routine && rule.minutes < 15 ? 0.45 : 1)
                    if existing {
                        Button(kind == .routine ? "Tắt khung giờ này" : "Tắt giới hạn này") { save(disable: true) }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }.padding(22).frame(maxWidth: 600)
            }
            .frame(maxWidth: .infinity)
            .background(Ink.background.ignoresSafeArea())
            .foregroundStyle(Ink.text)
            .navigationTitle(kind == .routine ? "Khung giờ hằng ngày" : "Giới hạn sử dụng")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } } }
        }
        .alert(item: $error) { Alert(title: Text("Chưa lưu được"), message: Text($0.text), dismissButton: .default(Text("Đóng"))) }
    }

    private var routineDescription: String {
        if rule.minutes < 15 { return "Chọn khung giờ dài ít nhất 15 phút." }
        if rule.end < rule.start { return "Lặp lại mỗi ngày. Giờ kết thúc nằm ở sáng hôm sau." }
        return "Lặp lại mỗi ngày, từ \(Viet.clock(rule.start)) đến \(Viet.clock(rule.end))."
    }

    private func save(disable: Bool) {
        do {
            switch kind {
            case .routine: try model.setRoutine(disable ? nil : rule)
            case .budget: try model.setBudget(minutes: disable ? nil : budgetMinutes)
            }
            dismiss()
        } catch { self.error = Notice(text: error.localizedDescription) }
    }
}
