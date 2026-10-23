import UIKit

/// Light, neutral chat-app look (in the spirit of ChatGPT and Claude, without their branding): white cards, near-black primary
/// actions, a capsule composer, chip buttons. The slate accent (the app's logo colour) marks AI output: icons, confidence, source.
enum InterfaceStyle {
    static let accent = UIColor(red: 0.39, green: 0.47, blue: 0.56, alpha: 1)
    static let track = UIColor(red: 0.85, green: 0.87, blue: 0.88, alpha: 1)
    static let panel = UIColor(red: 0.96, green: 0.97, blue: 0.97, alpha: 1)
    /// Near-black for primary actions (send, "That's right").
    static let ink = UIColor(white: 0.1, alpha: 1)
    /// The user's own message bubble.
    static let userBubble = UIColor(red: 0.93, green: 0.93, blue: 0.93, alpha: 0.96)
    static let cornerRadius: CGFloat = 14

    static func card() -> UIVisualEffectView {
        let card = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterialLight))
        card.layer.cornerRadius = cornerRadius; card.layer.cornerCurve = .continuous; card.clipsToBounds = true
        card.layer.borderWidth = 0.5; card.layer.borderColor = UIColor.black.withAlphaComponent(0.12).cgColor
        return card
    }
    static func pillButton(_ title: String, symbol: String, filled: Bool = false) -> UIButton {
        let button = UIButton(type: .system)
        var config = filled ? UIButton.Configuration.filled() : UIButton.Configuration.gray()
        config.title = title
        config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium))
        config.imagePlacement = .leading
        config.imagePadding = 6
        config.cornerStyle = .capsule
        config.buttonSize = .medium
        config.baseBackgroundColor = filled ? ink : UIColor(red: 0.93, green: 0.93, blue: 0.94, alpha: 1)  // opaque: also sits on the camera view
        config.baseForegroundColor = filled ? .white : .label
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { var a = $0; a.font = .systemFont(ofSize: 15, weight: .medium); return a }
        button.configuration = config
        button.accessibilityLabel = title
        return button
    }
}

/// Confidence as a slate bar on a light track with a dot at the end, plus the percentage — or a caption when there is no score.
final class ConfidenceBar: UIView {
    private let label = UILabel(), track = UIView(), fill = UIView(), dot = UIView()
    private(set) var value: Double?
    private var caption = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 13, weight: .medium); label.textColor = .secondaryLabel
        track.backgroundColor = InterfaceStyle.track; fill.backgroundColor = InterfaceStyle.accent; dot.backgroundColor = InterfaceStyle.accent
        [label, track, fill, dot].forEach(addSubview)
        isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func set(_ value: Double?, caption: String) {
        self.value = value.map { min(max($0, 0), 1) }; self.caption = caption
        label.text = self.value.map { "Confidence \(Int(($0 * 100).rounded()))%" } ?? caption
        [track, fill, dot].forEach { $0.isHidden = self.value == nil }
        accessibilityLabel = label.text
        invalidateIntrinsicContentSize(); setNeedsLayout()
    }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: value == nil ? 18 : 34) }
    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 18)
        let barY: CGFloat = 24, trackHeight: CGFloat = 6, fillHeight: CGFloat = 10
        track.frame = CGRect(x: 0, y: barY + (fillHeight - trackHeight) / 2, width: bounds.width, height: trackHeight); track.layer.cornerRadius = trackHeight / 2
        fill.frame = CGRect(x: 0, y: barY, width: max(fillHeight, bounds.width * (value ?? 0)), height: fillHeight); fill.layer.cornerRadius = fillHeight / 2
        dot.frame = CGRect(x: bounds.width - 7, y: barY + fillHeight / 2 - 2.5, width: 5, height: 5); dot.layer.cornerRadius = 2.5
    }
}

/// A label on a light translucent pill, so dark text stays readable on any camera background (bright kitchens included).
final class PillLabel: UILabel {
    private let inset = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
    override init(frame: CGRect) {
        super.init(frame: frame)
        textColor = .label; backgroundColor = UIColor.white.withAlphaComponent(0.85)
        layer.cornerRadius = 10; layer.cornerCurve = .continuous; clipsToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: inset)) }
    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize; return CGSize(width: s.width + inset.left + inset.right, height: s.height + inset.top + inset.bottom)
    }
    override func textRect(forBounds bounds: CGRect, limitedToNumberOfLines n: Int) -> CGRect {
        super.textRect(forBounds: bounds.inset(by: inset), limitedToNumberOfLines: n).inset(by: UIEdgeInsets(top: -inset.top, left: -inset.left, bottom: -inset.bottom, right: -inset.right))
    }
}

/// Three dots that pulse in turn while the assistant is working, like a chat app's "thinking" indicator.
final class ThinkingDots: UIView {
    private let dots = (0..<3).map { _ in UIView() }
    override init(frame: CGRect) {
        super.init(frame: frame)
        dots.forEach { $0.backgroundColor = InterfaceStyle.accent; $0.layer.cornerRadius = 4; addSubview($0) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize { CGSize(width: 36, height: 8) }
    override func layoutSubviews() { super.layoutSubviews(); for (i, d) in dots.enumerated() { d.frame = CGRect(x: CGFloat(i) * 14, y: 0, width: 8, height: 8) } }
    /// Animations are dropped when the app goes to the background, so restart them each time the indicator is shown.
    func start() {
        for (i, d) in dots.enumerated() {
            d.layer.removeAllAnimations()
            let pulse = CABasicAnimation(keyPath: "opacity"); pulse.fromValue = 1; pulse.toValue = 0.25
            pulse.duration = 0.5; pulse.autoreverses = true; pulse.repeatCount = .infinity
            pulse.beginTime = CACurrentMediaTime() + Double(i) * 0.18; pulse.fillMode = .backwards
            d.layer.add(pulse, forKey: "pulse")
        }
    }
}
