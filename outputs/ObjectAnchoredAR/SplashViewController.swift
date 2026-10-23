import UIKit

/// Brand page shown after the system launch screen (same logo and background, so the hand-over is seamless):
/// the name and tagline fade in, then the camera screen takes over.
final class SplashViewController: UIViewController {
    private let logo = UIImageView(image: UIImage(named: "Logo")), name = UILabel(), tagline = UILabel()
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(named: "LaunchBackground") ?? InterfaceStyle.panel
        name.text = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "ObjectAnchoredAR"
        name.font = .systemFont(ofSize: 24, weight: .semibold); name.textColor = UIColor(white: 0.12, alpha: 1)
        tagline.text = "Ask about what you see. See what the AI means."
        tagline.font = .systemFont(ofSize: 15); tagline.textColor = .secondaryLabel; tagline.numberOfLines = 0; tagline.textAlignment = .center
        let text = UIStackView(arrangedSubviews: [name, tagline]); text.axis = .vertical; text.alignment = .center; text.spacing = 6
        [logo, text].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
        // The logo sits exactly where the launch screen draws it (centred, at its asset size), so it does not jump.
        NSLayoutConstraint.activate([
            logo.centerXAnchor.constraint(equalTo: view.centerXAnchor), logo.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            text.topAnchor.constraint(equalTo: logo.bottomAnchor, constant: 24), text.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            text.leadingAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor),
        ])
        text.alpha = 0; text.transform = CGAffineTransform(translationX: 0, y: 8)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIView.animate(withDuration: 0.5, delay: 0.1, options: .curveEaseOut) {
            self.text.alpha = 1; self.text.transform = .identity
        } completion: { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { self.onFinish() }
        }
    }
    private var text: UIView { name.superview ?? name }
}
