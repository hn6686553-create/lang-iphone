import Combine
import FamilyControls
import SwiftUI

@main
@MainActor
struct LangApp: App {
    @StateObject private var model = FocusModel()

    var body: some Scene {
        WindowGroup {
            LangRoot(model: model)
                .environment(\.locale, Locale(identifier: "vi_VN"))
                .tint(Ink.lime)
                .preferredColorScheme(.dark)
        }
    }
}

private enum Intent {
    case list, start(Int), routine, budget
}

private enum Editor: String, Identifiable {
    case selection, routine, budget
    var id: String { rawValue }
}

private struct LangRoot: View {
    @ObservedObject var model: FocusModel
    @Environment(\.scenePhase) private var phase
    @State private var editor: Editor?
    @State private var selectionIntent: Intent = .list
    @State private var afterDismiss: Intent?
    private let pulse = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView {
            TimelineView(.periodic(from: .now, by: 1)) { clock in
                HomeView(model: model, now: clock.date, onStart: { open(.start($0)) }, onList: { open(.list) })
            }
            .tabItem { Label("Tập trung", systemImage: "timer") }
            HabitsView(model: model)
                .tabItem { Label("Thói quen", systemImage: "bell") }
            RulesView(model: model, onRoutine: { open(.routine) },
                      onBudget: { open(.budget) }, onList: { open(.list) })
                .tabItem { Label("Lịch chặn", systemImage: "calendar") }
            TimelineView(.periodic(from: .now, by: 30)) { clock in
                ActivityView(state: model.state, now: clock.date, authorized: model.authorized) {
                    Task { _ = await model.requestAccess() }
                }
            }
            .tabItem { Label("Hoạt động", systemImage: "chart.bar") }
        }
        .toolbarBackground(Ink.background, for: .tabBar)
        .onAppear { model.enterForeground() }
        .onChange(of: phase) { _, newPhase in
            if newPhase == .active { model.enterForeground() }
        }
        .onReceive(AuthorizationCenter.shared.$authorizationStatus.receive(on: RunLoop.main)) {
            if $0 == AuthorizationCenter.shared.authorizationStatus { model.authorizationChanged($0) }
        }
        .onReceive(pulse) { now in if phase == .active { model.updateFromMonitor(at: now) } }
        .safeAreaInset(edge: .top) {
            if let issue = model.accessIssue {
                HStack {
                    Text(issue).font(.footnote)
                    Button("Đóng") { model.accessIssue = nil }
                }.padding(10).background(Ink.card)
            }
        }
        .sheet(item: $editor, onDismiss: resumeAfterPicker) { current in
            switch current {
            case .selection:
                SelectionSheet(model: model, cancel: { editor = nil }) { hasItems in
                    afterDismiss = hasItems ? selectionIntent : nil
                    editor = nil
                }
            case .routine: RuleEditor(kind: .routine, model: model)
            case .budget: RuleEditor(kind: .budget, model: model)
            }
        }
        .alert(item: $model.notice) { note in
            Alert(title: Text("Thông báo"), message: Text(note.text), dismissButton: .default(Text("Đóng")))
        }
    }

    @MainActor private func open(_ intent: Intent) {
        Task {
            guard await model.requestBlockingAccess() else { return }
            if case .list = intent {
                selectionIntent = .list
                editor = .selection
            } else if !model.state.selection.hasItems {
                selectionIntent = intent
                editor = .selection
            } else { perform(intent) }
        }
    }

    private func resumeAfterPicker() {
        guard let intent = afterDismiss else { return }
        afterDismiss = nil
        perform(intent)
    }

    private func perform(_ intent: Intent) {
        switch intent {
        case .list: break
        case .start(let minutes):
            do { try model.start(minutes: minutes) } catch { model.show(error) }
        case .routine: editor = .routine
        case .budget: editor = .budget
        }
    }
}
