import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldAppearance: ShieldConfigurationDataSource {
    private func appearance(for name: String?) -> ShieldConfiguration {
        let lime = UIColor(red: 0.827, green: 0.955, blue: 0.59, alpha: 1)
        let ink = UIColor(red: 0.055, green: 0.086, blue: 0.075, alpha: 1)
        let icon = UIImage(systemName: "moon.haze.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 40))
        return ShieldConfiguration(
            backgroundBlurStyle: nil,
            backgroundColor: ink,
            icon: icon?.withTintColor(lime, renderingMode: .alwaysOriginal),
            title: .init(text: name.map { "\($0) đang tạm khóa" } ?? "Mục này đang tạm khóa", color: .white),
            subtitle: .init(text: "Quy tắc tập trung của Lặng đang bật. Bạn có thể xem thời gian và lịch chặn trong Lặng.",
                            color: UIColor(white: 0.82, alpha: 1)),
            primaryButtonLabel: .init(text: "Đóng", color: ink),
            primaryButtonBackgroundColor: lime
        )
    }

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        appearance(for: application.localizedDisplayName)
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        appearance(for: application.localizedDisplayName)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        appearance(for: webDomain.domain)
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        appearance(for: webDomain.domain)
    }
}
