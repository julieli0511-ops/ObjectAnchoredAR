import UIKit

enum InterfaceStyle {
    static let accent = UIColor.systemBlue
    static func glassCard() -> UIVisualEffectView {
        let card = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
        card.layer.cornerRadius = 24; card.clipsToBounds = true
        card.layer.borderWidth = 0.5; card.layer.borderColor = UIColor.white.withAlphaComponent(0.22).cgColor
        return card
    }
    static func pillButton(_ title: String, symbol: String, filled: Bool = false) -> UIButton {
        let button = UIButton(type: .system)
        var config = filled ? UIButton.Configuration.filled() : UIButton.Configuration.tinted()
        config.title = title
        config.image = UIImage(systemName: symbol)
        config.imagePlacement = .leading
        config.imagePadding = 8
        config.cornerStyle = .capsule
        config.buttonSize = .medium
        config.baseBackgroundColor = accent
        config.baseForegroundColor = .white
        button.configuration = config
        button.accessibilityLabel = title
        return button
    }
}
