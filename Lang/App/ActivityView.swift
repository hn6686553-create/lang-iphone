import DeviceActivity
import SwiftUI

struct DayTotal: Identifiable {
    let date: Date
    let seconds: TimeInterval
    var id: Date { date }
}

enum FocusHistory {
    static func week(sessions: [FocusSession], ending now: Date, calendar: Calendar = .current) -> [DayTotal] {
        let today = calendar.startOfDay(for: now)
        return (-6...0).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let range = calendar.dateInterval(of: .day, for: day) else { return nil }
            let sum = sessions.reduce(0.0) { $0 + $1.seconds(in: range, until: now) }
            return DayTotal(date: day, seconds: sum)
        }
    }
}

struct ActivityView: View {
    let state: FocusState
    let now: Date
    let authorized: Bool
    let onAccess: () -> Void
    @State private var showUsage = false
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 85
    @ScaledMetric(relativeTo: .body) private var reportHeight: CGFloat = 265

    var body: some View {
        Page(title: "Hoạt động", now: now) {
            Picker("Loại hoạt động", selection: $showUsage) {
                Text("Phiên tập trung").tag(false)
                Text("Dùng iPhone").tag(true)
            }.pickerStyle(.segmented)
            if showUsage {
                if authorized, let today = Calendar.current.dateInterval(of: .day, for: now) {
                    let filter = DeviceActivityFilter(segment: .daily(during: today), users: .all, devices: .init([.iPhone]))
                    DeviceActivityReport(.langToday, filter: filter)
                        .frame(height: reportHeight)
                        .background(Ink.card).clipShape(RoundedRectangle(cornerRadius: 23))
                    Text("Thời gian sử dụng do iOS cập nhật trong ngày.").font(.footnote).foregroundStyle(Ink.muted)
                } else {
                    Panel {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Cho phép Lặng dùng Thời gian sử dụng để xem báo cáo hôm nay.")
                                .font(.subheadline).foregroundStyle(Ink.muted)
                            PrimaryButton(title: "Cho phép truy cập", icon: "hand.raised", action: onAccess)
                        }
                    }
                }
            } else { focusHistory }
        }
    }

    @ViewBuilder private var focusHistory: some View {
        let days = FocusHistory.week(sessions: state.sessions, ending: now)
        let peak = max(60, days.map(\.seconds).max() ?? 0)
        let firstDay = days.first?.date ?? now
        let weekSessions = state.sessions.filter { $0.start >= firstDay && $0.start <= now }.count
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Text("7 ngày gần nhất").font(.headline).foregroundStyle(Ink.muted)
                Text(Viet.duration(days.reduce(0) { $0 + $1.seconds }))
                    .font(.system(.largeTitle, design: .serif)).foregroundStyle(Ink.lime)
                Text("\(weekSessions) phiên đã bắt đầu").font(.subheadline).foregroundStyle(Ink.muted)
                HStack(alignment: .bottom, spacing: 7) {
                    ForEach(days) { day in
                        let isToday = Calendar.current.isDate(day.date, inSameDayAs: now)
                        VStack(spacing: 7) {
                            ZStack(alignment: .bottom) {
                                Capsule().fill(Ink.raised)
                                if day.seconds > 0 {
                                    Capsule().fill(isToday ? Ink.lime : Ink.muted)
                                        .frame(height: max(3, chartHeight * CGFloat(day.seconds / peak)))
                                }
                            }
                            .frame(maxWidth: 16).frame(height: chartHeight)
                            Text(shortDay(day.date)).font(.caption2.weight(isToday ? .bold : .regular))
                                .foregroundStyle(isToday ? Ink.lime : Ink.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Viet.weekday.string(from: day.date))
                        .accessibilityValue(Viet.duration(day.seconds))
                    }
                }.padding(.top, 7)
                Text("Tính theo các phiên bạn bấm bắt đầu.")
                    .font(.footnote).foregroundStyle(Ink.muted)
            }
        }
        VStack(alignment: .leading, spacing: 12) {
            Text("Phiên gần đây").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Panel {
                if state.sessions.isEmpty {
                    Text("Phiên tập trung đầu tiên của bạn sẽ xuất hiện ở đây.")
                        .font(.subheadline).foregroundStyle(Ink.muted)
                } else {
                    VStack(spacing: 14) {
                        ForEach(Array(state.sessions.suffix(12).reversed())) { session in
                            if session.id != state.sessions.last?.id { Divider().overlay(Ink.line) }
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(Viet.day.string(from: session.start) + " · " + Viet.time.string(from: session.start))
                                        .font(.subheadline.weight(.semibold))
                                    Text(session.isActive(at: now) ? "Đang tập trung" : session.stoppedAt == nil ? "Hoàn thành" : "Kết thúc sớm")
                                        .font(.caption).foregroundStyle(Ink.muted)
                                }
                                Spacer()
                                Text(Viet.duration(max(0, min(session.end, now).timeIntervalSince(session.start))))
                                    .font(.subheadline).foregroundStyle(Ink.lime)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }

    private func shortDay(_ day: Date) -> String {
        let weekday = Calendar.current.component(.weekday, from: day)
        return weekday == 1 ? "CN" : "T\(weekday)"
    }
}
