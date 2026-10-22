import ARKit
import Combine
import RealityKit
import UIKit

final class ViewController: UIViewController {
    private enum Mode: Int { case chat, screen, object; var condition: String { ["2D", "Screen-Fixed AR", "Object-Anchored AR"][rawValue] } }
    private let arView = ARView(frame: .zero)
    private let modeControl = UISegmentedControl(items: ["2D Chat", "Screen AR", "Object AR"])
    private let composer = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialLight))
    private let questionField = UITextField(), focus = UIView(); private let modeDescription = UILabel()
    private let sendButton = UIButton(type: .system)
    private let analyzingCard = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    // 2D: one conversational card with the buttons inside. Screen AR: compact card pinned to the top of the screen. Both AR modes share the bottom action stack.
    private let chatCard = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialLight))
    private let screenCard = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialLight))
    private let arActions = UIStackView(), arButtons = UIStackView(), hint = UILabel()
    private let crosshair = UIImageView(image: UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 44, weight: .light)))
    private let chatTarget = UILabel(), chatLocation = UILabel(), chatText = UILabel(), screenTarget = UILabel(), screenLocation = UILabel()
    /// AR modes: after analysing, the interpretation waits until the user taps the object/position in the scene.
    private var mode = Mode.chat, awaitingTap = false, resultShownAt = Date()
    private var worldAnchor: AnchorEntity?, panel: Entity?, billboard: Cancellable?

    override func viewDidLoad() { super.viewDidLoad(); setupCameraUI(); configureSession() }
    private func setupCameraUI() {
        view.backgroundColor = .black; arView.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(arView)
        NSLayoutConstraint.activate([arView.leadingAnchor.constraint(equalTo:view.leadingAnchor),arView.trailingAnchor.constraint(equalTo:view.trailingAnchor),arView.topAnchor.constraint(equalTo:view.topAnchor),arView.bottomAnchor.constraint(equalTo:view.bottomAnchor)])
        arView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleSceneTap(_:))))
        modeControl.selectedSegmentIndex = 0
        [(0,"message"),(1,"viewfinder"),(2,"mappin.and.ellipse")].forEach { modeControl.setImage(UIImage(systemName:$0.1),forSegmentAt:$0.0) }
        modeControl.backgroundColor = UIColor.white.withAlphaComponent(0.92); modeControl.selectedSegmentTintColor = .systemBlue; modeControl.translatesAutoresizingMaskIntoConstraints = false; modeControl.addTarget(self,action:#selector(modeChanged),for:.valueChanged); view.addSubview(modeControl)
        NSLayoutConstraint.activate([modeControl.leadingAnchor.constraint(equalTo:view.layoutMarginsGuide.leadingAnchor),modeControl.trailingAnchor.constraint(equalTo:view.layoutMarginsGuide.trailingAnchor),modeControl.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor,constant:12),modeControl.heightAnchor.constraint(equalToConstant:48)])
        modeDescription.textAlignment = .center; modeDescription.textColor = .white; modeDescription.font = .preferredFont(forTextStyle: .footnote); modeDescription.numberOfLines = 0; modeDescription.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(modeDescription)
        NSLayoutConstraint.activate([modeDescription.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor), modeDescription.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor), modeDescription.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 8)])
        updateModeDescription()
        composer.layer.cornerRadius = 22;composer.clipsToBounds = true;composer.translatesAutoresizingMaskIntoConstraints = false; questionField.placeholder = "Ask about something you see…";questionField.text = InterpretationStore.shared.value.question;questionField.font = .preferredFont(forTextStyle:.body);questionField.returnKeyType = .send;questionField.addTarget(self,action:#selector(sendQuestion),for:.editingDidEndOnExit);questionField.translatesAutoresizingMaskIntoConstraints = false; sendButton.setImage(UIImage(systemName:"arrow.up.circle.fill"),for:.normal);sendButton.tintColor = .systemBlue;sendButton.translatesAutoresizingMaskIntoConstraints = false;sendButton.addTarget(self,action:#selector(sendQuestion),for:.touchUpInside);composer.contentView.addSubview(questionField);composer.contentView.addSubview(sendButton);view.addSubview(composer)
        NSLayoutConstraint.activate([composer.leadingAnchor.constraint(equalTo:view.layoutMarginsGuide.leadingAnchor),composer.trailingAnchor.constraint(equalTo:view.layoutMarginsGuide.trailingAnchor),composer.bottomAnchor.constraint(equalTo:view.keyboardLayoutGuide.topAnchor,constant:-12),composer.heightAnchor.constraint(equalToConstant:54),questionField.leadingAnchor.constraint(equalTo:composer.contentView.leadingAnchor,constant:16),questionField.trailingAnchor.constraint(equalTo:sendButton.leadingAnchor,constant:-8),questionField.centerYAnchor.constraint(equalTo:composer.contentView.centerYAnchor),sendButton.trailingAnchor.constraint(equalTo:composer.contentView.trailingAnchor,constant:-12),sendButton.centerYAnchor.constraint(equalTo:composer.contentView.centerYAnchor)])
        focus.layer.cornerRadius = 28;focus.layer.borderWidth = 3;focus.layer.borderColor = UIColor.white.cgColor;focus.translatesAutoresizingMaskIntoConstraints = false;focus.isHidden = true;view.addSubview(focus);NSLayoutConstraint.activate([focus.centerXAnchor.constraint(equalTo:view.centerXAnchor),focus.centerYAnchor.constraint(equalTo:view.centerYAnchor),focus.widthAnchor.constraint(equalToConstant:56),focus.heightAnchor.constraint(equalToConstant:56)])
        let spinner=UIActivityIndicatorView(style:.medium);spinner.startAnimating();spinner.color = .white;let loading=UILabel();loading.text = "Analyzing your question…";loading.textColor = .white;let loadingStack=UIStackView(arrangedSubviews:[spinner,loading]);loadingStack.axis = .horizontal;loadingStack.spacing = 10;loadingStack.translatesAutoresizingMaskIntoConstraints = false;analyzingCard.layer.cornerRadius = 18;analyzingCard.clipsToBounds = true;analyzingCard.translatesAutoresizingMaskIntoConstraints = false;analyzingCard.contentView.addSubview(loadingStack);analyzingCard.isHidden = true;view.addSubview(analyzingCard);NSLayoutConstraint.activate([loadingStack.leadingAnchor.constraint(equalTo:analyzingCard.contentView.leadingAnchor,constant:18),loadingStack.trailingAnchor.constraint(equalTo:analyzingCard.contentView.trailingAnchor,constant:-18),loadingStack.topAnchor.constraint(equalTo:analyzingCard.contentView.topAnchor,constant:14),loadingStack.bottomAnchor.constraint(equalTo:analyzingCard.contentView.bottomAnchor,constant:-14),analyzingCard.centerXAnchor.constraint(equalTo:view.centerXAnchor),analyzingCard.bottomAnchor.constraint(equalTo:composer.topAnchor,constant:-14)])
        setupInterpretationViews()
    }
    private func setupInterpretationViews() {
        // 2D Chat: conversational card above the composer, buttons inside the card.
        chatText.numberOfLines = 0;chatText.font = .preferredFont(forTextStyle:.body)
        let chatStack=UIStackView(arrangedSubviews:[titleRow(chatTarget,chatLocation),chatText]+responseButtons());chatStack.axis = .vertical;chatStack.spacing = 14
        pin(chatStack,in:chatCard,padding:18);view.addSubview(chatCard)
        NSLayoutConstraint.activate([chatCard.leadingAnchor.constraint(equalTo:view.layoutMarginsGuide.leadingAnchor),chatCard.trailingAnchor.constraint(equalTo:view.layoutMarginsGuide.trailingAnchor),chatCard.bottomAnchor.constraint(equalTo:composer.topAnchor,constant:-14)])
        // Screen AR: compact card fixed near the top of the screen; it never moves with the scene.
        pin(titleRow(screenTarget,screenLocation),in:screenCard,padding:16);view.addSubview(screenCard)
        NSLayoutConstraint.activate([screenCard.leadingAnchor.constraint(equalTo:view.layoutMarginsGuide.leadingAnchor),screenCard.trailingAnchor.constraint(equalTo:view.layoutMarginsGuide.trailingAnchor),screenCard.topAnchor.constraint(equalTo:modeDescription.bottomAnchor,constant:12)])
        // Both AR modes: buttons at the bottom, separate from the interpretation itself.
        hint.textColor = .white;hint.textAlignment = .center;hint.numberOfLines = 0;hint.font = .preferredFont(forTextStyle:.footnote);hint.backgroundColor = UIColor.black.withAlphaComponent(0.55);hint.layer.cornerRadius = 10;hint.clipsToBounds = true
        responseButtons().forEach(arButtons.addArrangedSubview);arButtons.axis = .vertical;arButtons.spacing = 10
        [hint,arButtons].forEach(arActions.addArrangedSubview);arActions.axis = .vertical;arActions.spacing = 10;arActions.translatesAutoresizingMaskIntoConstraints = false;view.addSubview(arActions)
        NSLayoutConstraint.activate([arActions.leadingAnchor.constraint(equalTo:view.layoutMarginsGuide.leadingAnchor),arActions.trailingAnchor.constraint(equalTo:view.layoutMarginsGuide.trailingAnchor),arActions.bottomAnchor.constraint(equalTo:composer.topAnchor,constant:-14)])
        crosshair.tintColor = .white;crosshair.translatesAutoresizingMaskIntoConstraints = false;view.addSubview(crosshair);NSLayoutConstraint.activate([crosshair.centerXAnchor.constraint(equalTo:view.centerXAnchor),crosshair.centerYAnchor.constraint(equalTo:view.centerYAnchor)])
        [chatCard,screenCard,arActions,crosshair].forEach{$0.isHidden = true}
    }
    private func titleRow(_ target:UILabel,_ location:UILabel)->UIStackView {
        let icon=UIImageView(image:UIImage(systemName:"waterbottle.fill"));icon.tintColor = .systemBlue;icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize:30,weight:.medium);icon.contentMode = .scaleAspectFit
        target.font = .systemFont(ofSize:18,weight:.bold);location.textColor = .secondaryLabel;location.font = .preferredFont(forTextStyle:.subheadline)
        let labels=UIStackView(arrangedSubviews:[target,location]);labels.axis = .vertical
        let row=UIStackView(arrangedSubviews:[icon,labels]);row.axis = .horizontal;row.alignment = .center;row.spacing = 12;return row
    }
    private func responseButtons()->[UIButton] {
        let confirmButton=InterfaceStyle.pillButton("That's correct",symbol:"checkmark.circle.fill",filled:true);confirmButton.addTarget(self,action:#selector(confirm),for:.touchUpInside)
        let correctButton=InterfaceStyle.pillButton("Correct interpretation",symbol:"pencil.circle");correctButton.addTarget(self,action:#selector(correct(sender:)),for:.touchUpInside)
        return [confirmButton,correctButton]
    }
    private func pin(_ content:UIView,in card:UIVisualEffectView,padding:CGFloat) {
        card.layer.cornerRadius = 24;card.clipsToBounds = true;card.translatesAutoresizingMaskIntoConstraints = false;content.translatesAutoresizingMaskIntoConstraints = false;card.contentView.addSubview(content)
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo:card.contentView.leadingAnchor,constant:padding),content.trailingAnchor.constraint(equalTo:card.contentView.trailingAnchor,constant:-padding),content.topAnchor.constraint(equalTo:card.contentView.topAnchor,constant:padding),content.bottomAnchor.constraint(equalTo:card.contentView.bottomAnchor,constant:-padding)])
    }
    private func refreshInterpretation() {
        let item = InterpretationStore.shared.value
        [chatTarget,screenTarget].forEach{$0.text = item.interpretedTarget};[chatLocation,screenLocation].forEach{$0.text = item.interpretedLocation};chatText.text = item.explanation
    }
    private func configureSession(){guard ARWorldTrackingConfiguration.isSupported else{return};arView.session.run(ARWorldTrackingConfiguration())}
    @objc private func modeChanged(){mode = Mode(rawValue:modeControl.selectedSegmentIndex) ?? .chat; resetTrial(); updateModeDescription() }
    private func updateModeDescription(){ switch mode { case .screen: modeDescription.text = "Read the AI interpretation while viewing your surroundings."; case .object: modeDescription.text = "See which real-world location the interpretation refers to."; case .chat: modeDescription.text = "Review the AI interpretation in a conversational layout." } }
    /// Hides every interpretation view so the next question starts from the camera view.
    private func resetTrial(){awaitingTap = false;[chatCard,screenCard,arActions,crosshair,focus,analyzingCard].forEach{$0.isHidden = true};removePanel()}
    @objc private func sendQuestion(){view.endEditing(true);if let text=questionField.text,!text.isEmpty{InterpretationStore.shared.value.question=text};resetTrial();focus.isHidden = false;analyzingCard.isHidden = false;DispatchQueue.main.asyncAfter(deadline:.now()+0.8){[weak self] in self?.showResult()}}
    private func showResult(){
        guard !analyzingCard.isHidden else { return }
        focus.isHidden = true; analyzingCard.isHidden = true; refreshInterpretation()
        if mode == .chat { chatCard.isHidden = false; resultShownAt = Date(); return }
        // AR modes: camera view → user tap → raycast → show the card (see handleSceneTap).
        awaitingTap = true; crosshair.isHidden = false; hint.text = "Tap the object in the scene to show the interpretation."; hint.isHidden = false; arButtons.isHidden = true; arActions.isHidden = false
    }
    @objc private func handleSceneTap(_ gesture: UITapGestureRecognizer) {
        view.endEditing(true)
        guard mode != .chat, awaitingTap || worldAnchor != nil else { return }
        guard let result = arView.raycast(from: gesture.location(in: arView), allowing: .estimatedPlane, alignment: .any).first else { hint.text = "No surface detected yet. Move slowly and try again."; hint.isHidden = false; return }
        let t = result.worldTransform.columns.3
        switch mode {
        case .screen: screenCard.isHidden = false
        case .object: placePanel(at: [t.x, t.y, t.z])  // tapping again moves the card
        case .chat: return
        }
        if awaitingTap { awaitingTap = false; resultShownAt = Date() }
        crosshair.isHidden = true; hint.isHidden = true; arButtons.isHidden = false
    }
    // MARK: Object-anchored panel
    private func placePanel(at position: SIMD3<Float>) {
        removePanel()
        let item = InterpretationStore.shared.value, anchor = AnchorEntity(world: position)
        let dot = ModelEntity(mesh: .generateSphere(radius: 0.012), materials: [UnlitMaterial(color: .white)])
        let connector = ModelEntity(mesh: .generateBox(size: [0.004, 0.12, 0.004]), materials: [UnlitMaterial(color: .white)]); connector.position = [0, 0.06, 0]
        let p = Entity(); p.position = [0, 0.17, 0]
        let background = ModelEntity(mesh: .generateBox(size: [0.30, 0.10, 0.008], cornerRadius: 0.02), materials: [UnlitMaterial(color: UIColor(red: 0.11, green: 0.13, blue: 0.17, alpha: 1))])
        let title = textEntity(item.interpretedTarget, size: 0.026, weight: .bold, color: .white); title.position.y += 0.017
        let subtitle = textEntity(item.interpretedLocation, size: 0.016, weight: .regular, color: UIColor(white: 0.8, alpha: 1)); subtitle.position.y -= 0.02
        [background, title, subtitle].forEach { p.addChild($0) }; [dot, connector, p].forEach { anchor.addChild($0) }
        arView.scene.addAnchor(anchor); worldAnchor = anchor; panel = p
        // Keep the panel upright and facing the camera.
        if billboard == nil { billboard = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            guard let self, let p = self.panel else { return }
            let x = p.position(relativeTo: nil); var c = self.arView.cameraTransform.translation; c.y = x.y
            guard simd_distance(c, x) > 0.01 else { return }
            p.look(at: c, from: x, upVector: [0, 1, 0], relativeTo: nil) } }
    }
    private func removePanel(){if let worldAnchor{arView.scene.removeAnchor(worldAnchor)};worldAnchor = nil;panel = nil}
    /// Text centred on its parent. look(at:) points the panel's -Z at the camera, while generated text faces +Z, so it is turned around.
    private func textEntity(_ string:String,size:CGFloat,weight:UIFont.Weight,color:UIColor)->ModelEntity {
        let mesh = MeshResource.generateText(string, extrusionDepth: 0.001, font: .systemFont(ofSize: size, weight: weight))
        let e = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: color)]); e.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        let c = mesh.bounds.center; e.position = [c.x, -c.y, -0.005]; return e
    }
    // MARK: Responses
    @objc private func confirm(){InterpretationStore.shared.record(condition:mode.condition,outcome:"confirm",selectedIntendedTarget:false,start:resultShownAt);showCompletion("Response saved.")}
    @objc private func correct(sender:UIButton){let a=UIAlertController(title:"Which object do you mean?",message:nil,preferredStyle:.actionSheet);AIInterpretation.sceneObjects.forEach{option in a.addAction(UIAlertAction(title:option,style:.default){_ in InterpretationStore.shared.record(condition:self.mode.condition,outcome:"correct",selectedObject:option,selectedIntendedTarget:option == AIInterpretation.intendedObject,start:self.resultShownAt);self.showCompletion("Understood. You mean the \(option.lowercased()).")})};a.addAction(UIAlertAction(title:"Cancel",style:.cancel));a.popoverPresentationController?.sourceView = sender;present(a,animated:true)}
    private func showCompletion(_ message:String){let a=UIAlertController(title:"✓",message:message,preferredStyle:.alert);a.addAction(UIAlertAction(title:"Continue",style:.default){_ in self.resetTrial()});present(a,animated:true)}
}
