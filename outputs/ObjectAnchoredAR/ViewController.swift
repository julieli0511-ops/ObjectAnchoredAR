import UIKit
final class ViewController: UIViewController {
 override func viewDidLoad() { super.viewDidLoad(); title = "AI Interpretation Study"; view.backgroundColor = .systemBackground
  let note = UILabel(); note.text = "Choose a presentation condition"; note.font = .preferredFont(forTextStyle:.title2); note.textAlignment = .center
  let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 14
  [("2D Conversational", "message.fill"),("Screen-Fixed AR", "viewfinder"),("Object-Anchored AR", "mappin.and.ellipse")].enumerated().forEach { i,item in let b = UIButton(type:.system); var c = UIButton.Configuration.filled(); c.title = item.0;c.image = UIImage(systemName: item.1);c.imagePlacement = .leading;c.imagePadding = 10;c.buttonSize = .large;c.cornerStyle = .large;b.accessibilityLabel = item.0;b.configuration = c;b.tag = i;b.addTarget(self,action:#selector(open(_:)),for:.touchUpInside);stack.addArrangedSubview(b) }
  let all = UIStackView(arrangedSubviews:[note,stack]);all.axis = .vertical;all.spacing = 32;all.translatesAutoresizingMaskIntoConstraints = false;view.addSubview(all);NSLayoutConstraint.activate([all.leadingAnchor.constraint(equalTo:view.layoutMarginsGuide.leadingAnchor),all.trailingAnchor.constraint(equalTo:view.layoutMarginsGuide.trailingAnchor),all.centerYAnchor.constraint(equalTo:view.centerYAnchor)]) }
 @objc func open(_ sender:UIButton) { let vc:UIViewController; switch sender.tag { case 0: vc = ChatViewController(); case 1: vc = ScreenFixedARViewController(); default: vc = ObjectAnchoredARViewController() }; navigationController?.pushViewController(vc,animated:true) }
}
