import DeviceActivity
import FamilyControls
import ManagedSettings
import SwiftUI

@main
struct UsageReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        TodayScene { TodaySummaryView(summary: $0) }
    }
}

struct UsageRow: Identifiable {
    let token: ApplicationToken
    let seconds: TimeInterval
    var id: ApplicationToken { token }
}

struct UsageSummary {
    let hasData: Bool
    let total: TimeInterval
    let rows: [UsageRow]
}

struct TodayScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .langToday
    let content: (UsageSummary) -> TodaySummaryView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> UsageSummary {
        var total: TimeInterval = 0
        var hasData = false
        var apps: [ApplicationToken: TimeInterval] = [:]
        for await device in data {
            for await segment in device.activitySegments {
                hasData = true
                total += segment.totalActivityDuration
                for await category in segment.categories {
                    for await entry in category.applications {
                        guard let token = entry.application.token, entry.totalActivityDuration > 0 else { continue }
                        apps[token, default: 0] += entry.totalActivityDuration
                    }
                }
            }
        }
        let top = apps.map { UsageRow(token: $0.key, seconds: $0.value) }.sorted { $0.seconds > $1.seconds }
        return UsageSummary(hasData: hasData, total: total, rows: Array(top.prefix(3)))
    }
}

struct TodaySummaryView: View {
    let summary: UsageSummary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Sử dụng iPhone hôm nay").font(.headline).foregroundStyle(Ink.muted)
                if summary.hasData {
                    Text(Viet.duration(summary.total)).font(.system(.largeTitle, design: .serif)).foregroundStyle(Ink.lime)
                    if !summary.rows.isEmpty {
                        Text("Ứng dụng dùng nhiều nhất").font(.subheadline).foregroundStyle(Ink.muted)
                        ForEach(summary.rows) { row in
                            HStack(spacing: 8) {
                                Label(row.token).labelStyle(.titleAndIcon).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(Viet.duration(row.seconds)).font(.footnote).monospacedDigit()
                            }.foregroundStyle(Ink.text).accessibilityElement(children: .combine)
                        }
                    }
                } else {
                    Text("iOS chưa có dữ liệu sử dụng cho hôm nay.").foregroundStyle(Ink.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(18)
        }
        .background(Ink.card)
        .environment(\.locale, Locale(identifier: "vi_VN"))
        .preferredColorScheme(.dark)
    }
}
