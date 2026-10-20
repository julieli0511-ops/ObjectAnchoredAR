import ARKit
import RealityKit
import UIKit

final class ScreenFixedARViewController: UIViewController {
    private let arView = ARView(frame: .zero)
    private let card = InterfaceStyle.glassCard()
    private let status = UILabel(), actions = UIStackView(), reticle = UIView()
    private let targetValue = UILabel(), locationValue = UILabel(), confidenceValue = UILabel()
    private let start = Date(); private var interpretationShown = false

    override func viewDidLoad() { super.viewDidLoad(); title = "Screen-Fixed AR"; setupLayout(); startSession() }
    private func setupLayout() {
        view.backgroundColor = .black; arView.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(arView)
        NSLayoutConstraint.activate([arView.leadingAnchor.constraint(equalTo:view.leadingAnchor),arView.trailingAnchor.constraint(equalTo:view.trailingAnchor),arView.topAnchor.constraint(equalTo:view.topAnchor),arView.bottomAnchor.constraint(equalTo:view.bottomAnchor)])
        arView.addGestureRecognizer(UITapGestureRecognizer(target:self,action:#selector(placeInterpretation(_:))))
        reticle.layer.cornerRadius = 18;reticle.layer.borderWidth = 2;reticle.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor;reticle.translatesAutoresizingMaskIntoConstraints = false;view.addSubview(reticle)
        NSLayoutConstraint.activate([reticle.centerXAnchor.constraint(equalTo:view.centerXAnchor),reticle.centerYAnchor.constraint(equalTo:view.centerYAnchor),reticle.widthAnchor.constraint(equalToConstant:36),reticle.heightAnchor.constraint(equalToConstant:36)])

        let eyebrow = UILabel();eyebrow.text = "AI INTERPRETATION";eyebrow.textColor = InterfaceStyle.accent;eyebrow.font = .systemFont(ofSize:12,weight:.bold)
        let rows = UIStackView(arrangedSubviews:[row("target",targetValue),row("mappin.and.ellipse",locationValue),row("gauge.with.dots.needle.33",confidenceValue)]);rows.axis = .vertical;rows.spacing = 12
        let contents = UIStackView(arrangedSubviews:[eyebrow,rows]);contents.axis = .vertical;contents.spacing = 16;contents.translatesAutoresizingMaskIntoConstraints = false
        card.translatesAutoresizingMaskIntoConstraints = false;card.contentView.addSubview(contents);view.addSubview(card)
        NSLayoutConstraint.activate([contents.leadingAnchor.constraint(equalTo:card.contentView.leadingAnchor,constant:20),contents.trailingAnchor.constraint(equalTo:card.contentView.trailingAnchor,constant:-20),contents.topAnchor.constraint(equalTo:card.contentView.topAnchor,constant:20),contents.bottomAnchor.constraint(equalTo:card.contentView.bottomAnchor,constant:-20),card.leadingAnchor.constraint(equalTo:view.layoutMarginsGuide.leadingAnchor),card.trailingAnchor.constraint(equalTo:view.layoutMarginsGuide.trailingAnchor),card.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor,constant:14)])

        status.numberOfLines = 0;status.textAlignment = .center;status.textColor = .white;status.font = .preferredFont(forTextStyle:.footnote)
        actions.axis = .vertical;actions.spacing = 10;[button("That's correct","checkmark.circle.fill",#selector(confirm),true),button("Correct interpretation","pencil.circle",#selector(correct))].forEach(actions.addArrangedSubview)
        let bottom = UIStackView(arrangedSubviews:[status,actions]);bottom.axis = .vertical;bottom.spacing = 10;bottom.translatesAutoresizingMaskIntoConstraints = false;view.addSubview(bottom)
        NSLayoutConstraint.activate([bottom.leadingAnchor.constraint(equalTo:view.layoutMarginsGuide.leadingAnchor),bottom.trailingAnchor.constraint(equalTo:view.layoutMarginsGuide.trailingAnchor),bottom.bottomAnchor.constraint(equalTo:view.safeAreaLayoutGuide.bottomAnchor,constant:-12)])
        card.isHidden = true;actions.isHidden = true;status.text = "Aim the circle at the AI-selected target, then tap to show the interpretation."
    }
    private func row(_ symbol:String,_ label:UILabel)->UIStackView { let image = UIImageView(image:UIImage(systemName:symbol));image.tintColor = InterfaceStyle.accent;image.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize:18,weight:.semibold);image.contentMode = .scaleAspectFit;image.widthAnchor.constraint(equalToConstant:26).isActive = true;label.textColor = .white;label.font = .systemFont(ofSize:17,weight:.medium);let stack = UIStackView(arrangedSubviews:[image,label]);stack.axis = .horizontal;stack.alignment = .center;stack.spacing = 12;return stack }
    private func button(_ title:String,_ symbol:String,_ action:Selector,_ filled:Bool = false)->UIButton { let b = InterfaceStyle.pillButton(title,symbol:symbol,filled:filled);b.addTarget(self,action:action,for:.touchUpInside);return b }
    private func startSession(){guard ARWorldTrackingConfiguration.isSupported else{status.text = "AR world tracking is unavailable on this device.";return};arView.session.run(ARWorldTrackingConfiguration())}
    private func refresh(){let item = InterpretationStore.shared.value;targetValue.text = item.interpretedTarget;locationValue.text = item.interpretedLocation;confidenceValue.text = item.confidence}
    @objc private func placeInterpretation(_ g:UITapGestureRecognizer){guard !interpretationShown else{return};guard arView.raycast(from:g.location(in:arView),allowing:.estimatedPlane,alignment:.any).first != nil else{status.text = "No surface detected yet. Move slowly and try again.";return};refresh();interpretationShown = true;reticle.isHidden = true;card.isHidden = false;actions.isHidden = false;status.text = "Interpretation shown in a fixed screen position."}
    @objc private func confirm(){InterpretationStore.shared.record(condition:"Screen-Fixed AR",outcome:"confirmed",selectedIntendedTarget:false,start:start);status.text = "Response saved"}
    @objc private func correct(){let a = UIAlertController(title:"Correct interpretation",message:"Select the intended target.",preferredStyle:.actionSheet);["Coffee cup","Water bottle","Notebook"].forEach{option in a.addAction(UIAlertAction(title:option,style:.default){_ in InterpretationStore.shared.value.interpretedTarget = option;InterpretationStore.shared.value.interpretedLocation = option == "Coffee cup" ? "Left side of the laptop" : "Right side of the laptop";InterpretationStore.shared.record(condition:"Screen-Fixed AR",outcome:"corrected",selectedIntendedTarget:option == "Coffee cup",start:self.start);self.refresh()})};a.addAction(UIAlertAction(title:"Cancel",style:.cancel));present(a,animated:true)}
}
