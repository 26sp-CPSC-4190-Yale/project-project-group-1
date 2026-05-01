import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }

    private func makeConfiguration() -> ShieldConfiguration {
        let context = ScreenTimeShared.loadActiveContext()
        let title = context?.sessionTitle.isEmpty == false ? context?.sessionTitle ?? "Unplugged" : "Unplugged"
        let subtitle = context?.shieldSubtitle ?? "Stay present with your lock-in."
        let textColor = UIColor.white
        let accent = UIColor(red: 0.12, green: 0.55, blue: 0.42, alpha: 1)
        let background = UIColor(red: 0.05, green: 0.07, blue: 0.08, alpha: 1)

        return ShieldConfiguration(
            backgroundBlurStyle: .systemMaterialDark,
            backgroundColor: background,
            icon: UIImage(systemName: "lock.shield.fill"),
            title: .init(text: title, color: textColor),
            subtitle: .init(text: subtitle, color: textColor.withAlphaComponent(0.82)),
            primaryButtonLabel: .init(text: "Stay Locked In", color: .white),
            primaryButtonBackgroundColor: accent
        )
    }
}
