import SwiftUI

struct FocusDial: View {
    let seconds: Int
    let fraction: Double
    let running: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var digits: CGFloat = 57

    var body: some View {
        ZStack {
            Canvas { context, size in
                let side = min(size.width, size.height)
                let mid = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = side * 0.455
                func point(_ angle: Double, radius: CGFloat) -> CGPoint {
                    CGPoint(x: mid.x + CGFloat(cos(angle)) * radius, y: mid.y + CGFloat(sin(angle)) * radius)
                }
                let halo = Path(ellipseIn: CGRect(x: mid.x-r, y: mid.y-r, width: 2*r, height: 2*r))
                context.fill(halo, with: .radialGradient(Gradient(colors: [Ink.raised, Ink.card.opacity(0.1)]),
                                                         center: mid, startRadius: 0, endRadius: r))
                for index in 0..<60 {
                    let angle = Double(index) * .pi / 30 - .pi / 2
                    let major = index.isMultiple(of: 5)
                    var tick = Path()
                    tick.move(to: point(angle, radius: r))
                    tick.addLine(to: point(angle, radius: r - (major ? 10 : 5)))
                    let lit = Double(index) / 60 < fraction
                    context.stroke(tick, with: .color(lit ? Ink.lime.opacity(major ? 0.9 : 0.55) : Ink.line),
                                   style: StrokeStyle(lineWidth: major ? 2.1 : 1.1, lineCap: .round))
                }
                let inner = r - 17
                var guide = Path()
                guide.addArc(center: mid, radius: inner, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
                context.stroke(guide, with: .color(Ink.line.opacity(0.8)), lineWidth: 1)
                let angle = fraction * 2 * .pi - .pi / 2
                let dot = point(angle, radius: inner)
                context.fill(Path(ellipseIn: CGRect(x: dot.x-3, y: dot.y-3, width: 6, height: 6)), with: .color(Ink.lime))
            }
            VStack(spacing: 4) {
                Text(running ? "CÒN LẠI" : "THỜI LƯỢNG")
                    .font(.caption2.weight(.bold)).tracking(1.5).foregroundStyle(Ink.muted)
                Text(verbatim: Viet.timer(seconds)).font(.system(size: min(digits, 72), weight: .light, design: .rounded))
                    .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                    .frame(maxWidth: 185)
            }
        }
        .aspectRatio(1, contentMode: .fit).frame(maxWidth: 238)
        .accessibilityElement(children: .ignore).accessibilityLabel(running ? "Thời gian còn lại" : "Thời lượng")
        .accessibilityValue("\(seconds / 60) phút \(seconds % 60) giây")
    }
}

struct HomeView: View {
    @ObservedObject var model: FocusModel
    @AppStorage("lang.minutes") private var minutes = 25
    @State private var confirmFinish = false
    let now: Date
    let onStart: (Int) -> Void
    let onList: () -> Void

    private var session: FocusSession? { model.state.active(at: now) }

    var body: some View {
        Page(title: "Tập trung", now: now) {
            VStack(spacing: 16) {
                if let session {
                    let remaining = max(0, session.plannedEnd.timeIntervalSince(now))
                    FocusDial(seconds: Int(ceil(remaining)),
                              fraction: min(1, remaining / session.plannedEnd.timeIntervalSince(session.start)),
                              running: true)
                    Label("Kết thúc lúc " + Viet.time.string(from: session.plannedEnd), systemImage: "clock")
                        .font(.subheadline).foregroundStyle(Ink.muted)
                    Button { confirmFinish = true } label: {
                        Text("Kết thúc sớm").font(.headline).foregroundStyle(Ink.text)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Capsule().strokeBorder(Ink.line))
                            .contentShape(Capsule())
                    }.buttonStyle(.plain)
                } else {
                    FocusDial(seconds: minutes * 60, fraction: 1, running: false)
                    HStack(spacing: 6) {
                        ForEach(FocusModel.durations, id: \.self) { value in
                            Button {
                                minutes = value
                            } label: {
                                Text("\(value)′").font(.subheadline.weight(.semibold)).monospacedDigit()
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .foregroundStyle(minutes == value ? Ink.lime : Ink.muted)
                                    .background(Capsule().fill(minutes == value ? Ink.raised : Color.clear))
                            }
                            .buttonStyle(.plain).accessibilityLabel("\(value) phút")
                            .accessibilityAddTraits(minutes == value ? .isSelected : [])
                        }
                    }
                    PrimaryButton(title: model.requesting ? "Đang xin quyền…" : "Bắt đầu \(minutes) phút",
                                  icon: "play.fill") { onStart(minutes) }
                        .disabled(model.requesting)
                }
            }
            .padding(18).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 29).fill(
                LinearGradient(colors: [Ink.raised.opacity(0.79), Ink.card], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay { RoundedRectangle(cornerRadius: 29).strokeBorder(Ink.line.opacity(0.7)) }

            Panel {
                RuleRow(icon: "square.stack.3d.up", title: "Danh sách chặn",
                        detail: model.state.selection.langSummary, active: model.state.selection.hasItems, action: onList)
            }
            if model.state.routine?.contains(now) == true || model.state.budgetReached(at: now) {
                VStack(alignment: .leading, spacing: 8) {
                    if model.state.routine?.contains(now) == true {
                        Label("Đang trong khung giờ chặn", systemImage: "calendar")
                    }
                    if model.state.budgetReached(at: now) {
                        Label("Đã dùng hết hạn mức hôm nay", systemImage: "hourglass")
                    }
                }.font(.subheadline).foregroundStyle(Ink.lime)
            }
        }
        .confirmationDialog("Kết thúc phiên tập trung?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Kết thúc phiên", role: .destructive) {
                do { try model.finish() } catch { model.show(error) }
            }
            Button("Tiếp tục tập trung", role: .cancel) {}
        } message: {
            Text("Lặng sẽ lưu thời gian bạn đã tập trung. Các quy tắc hằng ngày vẫn áp dụng.")
        }
    }
}
