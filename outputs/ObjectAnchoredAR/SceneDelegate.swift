import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        // Brand page first, then cross-fade to the camera screen.
        window.rootViewController = SplashViewController { [weak window] in
            guard let window else { return }
            UIView.transition(with: window, duration: 0.35, options: .transitionCrossDissolve) {
                window.rootViewController = UINavigationController(rootViewController: ViewController())
            }
        }
        self.window = window
        window.makeKeyAndVisible()
    }
}
