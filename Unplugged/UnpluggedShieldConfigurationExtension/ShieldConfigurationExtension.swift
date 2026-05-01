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
        let primary = UIColor(red: 0, green: 53.0 / 255.0, blue: 107.0 / 255.0, alpha: 1)
        let textColor = UIColor.white

        return ShieldConfiguration(
            backgroundBlurStyle: .systemMaterialDark,
            backgroundColor: primary,
            icon: UIImage(systemName: "lock.shield.fill"),
            title: .init(text: title, color: textColor),
            subtitle: .init(text: subtitle, color: textColor.withAlphaComponent(0.82)),
            primaryButtonLabel: .init(text: "Stay Locked In", color: primary),
            primaryButtonBackgroundColor: .white,
            secondaryButtonLabel: nil
        )
    }
}
