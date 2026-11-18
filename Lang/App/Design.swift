import SwiftUI

enum Ink {
    static let background = Color(red: 0.055, green: 0.086, blue: 0.075)
    static let card = Color(red: 0.096, green: 0.139, blue: 0.115)
    static let raised = Color(red: 0.145, green: 0.195, blue: 0.162)
    static let line = Color(red: 0.235, green: 0.297, blue: 0.25)
    static let text = Color(red: 0.944, green: 0.956, blue: 0.901)
    static let muted = Color(red: 0.679, green: 0.735, blue: 0.683)
    static let lime = Color(red: 0.827, green: 0.955, blue: 0.59)
}

enum Viet {
    private static func formatter(_ pattern: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.setLocalizedDateFormatFromTemplate(pattern)
        return formatter
    }

    static let date = formatter("EEEdMMM")
    static let day = formatter("ddMMM")
    static let weekday = formatter("EEEE")
    static let time = formatter("HHmm")

    static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    static func timer(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    static func duration(_ seconds: Double) -> String {
        if seconds > 0 && seconds < 60 { return "Dưới 1 phút" }
        let minutes = max(0, Int(seconds) / 60)
        if minutes < 60 { return "\(minutes) phút" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) giờ" : "\(hours) giờ \(rest) phút"
    }
}

/// Four nested horizon lines. The same mark is used in the app icon.
struct HorizonMark: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - s / 2, y: rect.midY - s / 2)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + s * x, y: origin.y + s * y)
        }
        var path = Path()
        for i in 0..<4 {
            let inset = CGFloat(i) * 0.085
            path.move(to: point(0.08 + inset, 0.72))
            path.addQuadCurve(to: point(0.92 - inset, 0.72), control: point(0.50, -0.24 + CGFloat(i) * 0.20))
        }
        path.move(to: point(0.08, 0.82))
        path.addLine(to: point(0.92, 0.82))
        return path
    }
}

struct Page<Content: View>: View {
    let title: String
    let now: Date
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 9) {
                    HorizonMark().stroke(Ink.lime, style: StrokeStyle(lineWidth: 1.65, lineCap: .round))
                        .frame(width: 29, height: 29).accessibilityHidden(true)
                    Text("Lặng").font(.system(.title3, design: .serif).italic())
                    Spacer()
                    Text(Viet.date.string(from: now)).font(.subheadline).foregroundStyle(Ink.muted)
                }
                Text(title).font(.system(.largeTitle, design: .serif).weight(.medium))
                    .accessibilityAddTraits(.isHeader)
                content()
            }
            .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 28)
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Ink.background.ignoresSafeArea())
        .foregroundStyle(Ink.text)
    }
}

struct Panel<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 23).fill(Ink.card))
            .overlay { RoundedRectangle(cornerRadius: 23).strokeBorder(Ink.line.opacity(0.52)) }
    }
}

struct PrimaryButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(Ink.background).background(Capsule().fill(Ink.lime))
        }
        .buttonStyle(.plain)
    }
}

struct RuleRow: View {
    let icon: String
    let title: String
    let detail: String
    var active = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.headline)
                    .foregroundStyle(active ? Ink.lime : Ink.muted)
                    .frame(width: 39, height: 39).background(Circle().fill(Ink.raised))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(Ink.text)
                    Text(detail).font(.subheadline).foregroundStyle(Ink.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Ink.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityElement(children: .combine)
    }
}
