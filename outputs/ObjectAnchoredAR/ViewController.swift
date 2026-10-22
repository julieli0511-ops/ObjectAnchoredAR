import ARKit
import Combine
import RealityKit
import UIKit

final class ViewController: UIViewController, ARSessionDelegate {
    private enum Mode: Int { case chat, screen, object; var condition: String { ["2D", "Screen-Fixed AR", "Object-Anchored AR"][rawValue] } }
    private let arView = ARView(frame: .zero)
    private let modeControl = UISegmentedControl(items: ["2D Chat", "Screen AR", "Object AR"])
    private let composer = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialLight))
    private let questionField = UITextField(), focus = UIView(); private let modeDescription = UILabel(), loadingLabel = UILabel()
    /// AR modes need world tracking before an answer can be placed in the scene; typing is always possible meanwhile.
    private var trackingReady = !ARWorldTrackingConfiguration.isSupported
    private static let scanMessage = "Move your phone slowly to scan the table."
    private let sendButton = UIButton(type: .system)
    private let analyzingCard = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    // 2D: one conversational card with the buttons inside. Screen AR: compact card pinned to the top of the screen. Both AR modes share the bottom action stack.
    private let chatCard = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialLight))
    private let screenCard = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialLight))
    private let arActions = UIStackView(), arButtons = UIStackView(), hint = UILabel()
    private let crosshair = UIImageView(image: UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 44, weight: .light)))
    private let chatTarget = UILabel(), chatLocation = UILabel(), chatText = UILabel(), screenTarget = UILabel(), screenLocation = UILabel()
    /// AR modes: the interpreted object is located automatically; only if detection fails does the interpretation wait for a tap.
    private var mode = Mode.chat, awaitingTap = false, resultShownAt = Date()
    /// Bumped on every reset so detection callbacks from an abandoned trial are ignored.
    private var trial = 0, placement: String?
    private let locator = ObjectLocator()
    /// Scripted (study): fixed, intentionally wrong interpretation. Rules / VLM (Live): interpretation computed from the question and the camera view.
    private enum Source { case scripted, rules, vlm }
    private var source = Source.scripted, visibleObjects: [String] = [], iconViews: [UIImageView] = [], responseButtonViews: [UIButton] = []
    /// Live: the reference object of the last question ("laptop"), used to describe where a corrected object is.
    private var liveReference: SpatialQuery.Term?
    private var liveMode: Bool { source != .scripted }
    /// What produced the current answer, for the study record: "scripted", "live" (rules) or "vlm". VLM falls back to rules when its server is unreachable.
    private var answerSource = "scripted"
    private let vlm = VLMClient()
    private var worldAnchor: AnchorEntity?, panel: Entity?, billboard: Cancellable?

    override func viewDidLoad() { super.viewDidLoad(); setupCameraUI(); configureSession(); updateSettingsMenu(); updateQuestionField(); updateInputAvailability() }
    private func updateSettingsMenu() {
        let option = { (title: String, subtitle: String, s: Source) in
            UIAction(title: title, subtitle: subtitle, state: self.source == s ? .on : .off) { [weak self] _ in self?.setSource(s) }
        }
        let server = UIAction(title: "VLM server…", subtitle: VLMClient.serverURL, image: UIImage(systemName: "network")) { [weak self] _ in self?.editVLMServer() }
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "gearshape"), menu: UIMenu(title: "Interpretation", children: [
            option("Scripted (study)", "Fixed interpretation for the study", .scripted),
            option("Live: rules (on-device)", "Parses the question, finds objects with YOLO", .rules),
            option("Live: VLM (computer on Wi-Fi)", "Qwen2.5-VL via Ollama; images stay on your network", .vlm),
            server]))
    }
    private func editVLMServer() {
        let a = UIAlertController(title: "VLM server", message: "Ollama on a computer on the same Wi-Fi, e.g. http://my-mac.local:11434", preferredStyle: .alert)
        a.addTextField { $0.text = VLMClient.serverURL; $0.keyboardType = .URL; $0.autocapitalizationType = .none; $0.autocorrectionType = .no }
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        a.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in VLMClient.serverURL = a.textFields?.first?.text ?? ""; self?.updateSettingsMenu() })
        present(a, animated: true)
    }
    private func setSource(_ s: Source) {
        source = s; let question = InterpretationStore.shared.value.question
        InterpretationStore.shared.value = .sample; InterpretationStore.shared.value.question = question
        resetTrial(); updateModeDescription(); updateSettingsMenu(); updateQuestionField()
    }
    /// Scripted: every participant asks the same question, so it is pre-filled and locked (they only press send). Live: free input.
    private func updateQuestionField() {
        if !liveMode { questionField.text = AIInterpretation.sample.question; questionField.resignFirstResponder() }
        questionField.isUserInteractionEnabled = liveMode
    }
    private func updateInputAvailability() {
        let ready = mode == .chat || trackingReady
        sendButton.isEnabled = ready
        let idle = chatCard.isHidden && screenCard.isHidden && analyzingCard.isHidden && worldAnchor == nil && !awaitingTap
        if !ready && idle { showMessage(Self.scanMessage) }
        else if ready && hint.text == Self.scanMessage && !hint.isHidden { hint.isHidden = true; arActions.isHidden = true }
    }
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        if case .normal = camera.trackingState { trackingReady = true } else { trackingReady = false }
        updateInputAvailability()
    }
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
        let spinner=UIActivityIndicatorView(style:.medium);spinner.startAnimating();spinner.color = .white;loadingLabel.textColor = .white;loadingLabel.numberOfLines = 0;let loadingStack=UIStackView(arrangedSubviews:[spinner,loadingLabel]);loadingStack.axis = .horizontal;loadingStack.spacing = 10;loadingStack.translatesAutoresizingMaskIntoConstraints = false;analyzingCard.layer.cornerRadius = 18;analyzingCard.clipsToBounds = true;analyzingCard.translatesAutoresizingMaskIntoConstraints = false;analyzingCard.contentView.addSubview(loadingStack);analyzingCard.isHidden = true;view.addSubview(analyzingCard);NSLayoutConstraint.activate([loadingStack.leadingAnchor.constraint(equalTo:analyzingCard.contentView.leadingAnchor,constant:18),loadingStack.trailingAnchor.constraint(equalTo:analyzingCard.contentView.trailingAnchor,constant:-18),loadingStack.topAnchor.constraint(equalTo:analyzingCard.contentView.topAnchor,constant:14),loadingStack.bottomAnchor.constraint(equalTo:analyzingCard.contentView.bottomAnchor,constant:-14),analyzingCard.centerXAnchor.constraint(equalTo:view.centerXAnchor),analyzingCard.bottomAnchor.constraint(equalTo:composer.topAnchor,constant:-14)])
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
        let icon=UIImageView(image:UIImage(systemName:"waterbottle.fill"));icon.tintColor = .systemBlue;icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize:30,weight:.medium);icon.contentMode = .scaleAspectFit;iconViews.append(icon)
        target.font = .systemFont(ofSize:18,weight:.bold);location.textColor = .secondaryLabel;location.font = .preferredFont(forTextStyle:.subheadline)
        let labels=UIStackView(arrangedSubviews:[target,location]);labels.axis = .vertical
        let row=UIStackView(arrangedSubviews:[icon,labels]);row.axis = .horizontal;row.alignment = .center;row.spacing = 12;return row
    }
    private func responseButtons()->[UIButton] {
        let confirmButton=InterfaceStyle.pillButton("That's correct",symbol:"checkmark.circle.fill",filled:true);confirmButton.addTarget(self,action:#selector(confirm),for:.touchUpInside)
        let correctButton=InterfaceStyle.pillButton("Correct interpretation",symbol:"pencil.circle");correctButton.addTarget(self,action:#selector(correct(sender:)),for:.touchUpInside)
        responseButtonViews += [confirmButton,correctButton];return [confirmButton,correctButton]
    }
    private func pin(_ content:UIView,in card:UIVisualEffectView,padding:CGFloat) {
        card.layer.cornerRadius = 24;card.clipsToBounds = true;card.translatesAutoresizingMaskIntoConstraints = false;content.translatesAutoresizingMaskIntoConstraints = false;card.contentView.addSubview(content)
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo:card.contentView.leadingAnchor,constant:padding),content.trailingAnchor.constraint(equalTo:card.contentView.trailingAnchor,constant:-padding),content.topAnchor.constraint(equalTo:card.contentView.topAnchor,constant:padding),content.bottomAnchor.constraint(equalTo:card.contentView.bottomAnchor,constant:-padding)])
    }
    private func refreshInterpretation() {
        let item = InterpretationStore.shared.value
        [chatTarget,screenTarget].forEach{$0.text = item.interpretedTarget};[chatLocation,screenLocation].forEach{$0.text = item.interpretedLocation};chatText.text = item.explanation;iconViews.forEach{$0.image = UIImage(systemName:item.icon) ?? UIImage(systemName:"cube.fill")}
    }
    private func configureSession(){guard ARWorldTrackingConfiguration.isSupported else{return};arView.session.delegate = self;arView.session.run(ARWorldTrackingConfiguration())}
    @objc private func modeChanged(){mode = Mode(rawValue:modeControl.selectedSegmentIndex) ?? .chat; resetTrial(); updateModeDescription() }
    private func updateModeDescription(){ switch mode { case .screen: modeDescription.text = "Read the AI interpretation while viewing your surroundings."; case .object: modeDescription.text = "See which real-world location the interpretation refers to."; case .chat: modeDescription.text = "Review the AI interpretation in a conversational layout." }; if liveMode { modeDescription.text = (source == .vlm ? "LIVE VLM · " : "LIVE · ") + (modeDescription.text ?? "") } }
    /// Hides every interpretation view so the next question starts from the camera view.
    private func resetTrial(){trial += 1;awaitingTap = false;placement = nil;[chatCard,screenCard,arActions,crosshair,focus,analyzingCard].forEach{$0.isHidden = true};removePanel();updateInputAvailability()}
    @objc private func sendQuestion(){view.endEditing(true);guard sendButton.isEnabled else{return};let question = questionField.text.flatMap{$0.isEmpty ? nil : $0} ?? InterpretationStore.shared.value.question;if !liveMode{InterpretationStore.shared.value = .sample};InterpretationStore.shared.value.question = question;resetTrial();loadingLabel.text = (source == .vlm ? "Asking the vision model…" : "Analyzing your question…") + (mode != .chat || liveMode ? "\nKeep the camera pointed at the scene." : "");focus.isHidden = false;analyzingCard.isHidden = false;let current = trial;DispatchQueue.main.asyncAfter(deadline:.now()+0.8){[weak self] in guard let self, current == self.trial else{return};self.showResult()}}
    private func showResult(){
        guard !analyzingCard.isHidden else { return }
        let current = trial
        let finish: (SIMD3<Float>?) -> Void = { [weak self] position in
            guard let self, current == self.trial else { return }
            self.focus.isHidden = true; self.analyzingCard.isHidden = true; self.refreshInterpretation(); self.present(at: position, placement: "detected")
        }
        if source == .vlm { interpretVLM(then: finish); return }
        if source == .rules { answerSource = "live"; interpretLive(then: finish); return }
        answerSource = "scripted"
        // Scripted: the interpretation is fixed. AR modes still locate the scripted object (camera view → detect → raycast → card),
        // with "Analyzing" up meanwhile. Screen AR runs the same detection so both AR conditions wait equally long.
        if mode == .chat { finish(nil); return }
        locate(pick: { $0.filter { $0.label == AIInterpretation.detectorLabel }.max { $0.confidence < $1.confidence }.map { ($0, ()) } }) { _, position in finish(position) }
    }
    /// Live (VLM): the vision-language model on the computer decides what the question means; YOLO, run on the same frame, refines the box.
    /// If the server can't be reached, falls back to the rule-based interpretation (recorded as "live").
    private func interpretVLM(then finish: @escaping (SIMD3<Float>?) -> Void) {
        let question = InterpretationStore.shared.value.question, current = trial
        guard let frame = arView.session.currentFrame else { answerSource = "live"; interpretLive(then: finish); return }
        answerSource = "vlm"; liveReference = nil
        vlm.interpret(question: question, frame: frame) { [weak self] result in
            guard let self, current == self.trial else { return }
            guard case let .success((answer, box)) = result else {
                self.answerSource = "live"; self.modeDescription.text = "LIVE VLM · server unreachable, using on-device rules"
                self.interpretLive(then: finish); return
            }
            self.updateModeDescription()
            self.locator.detect(in: frame) { detections in
                guard current == self.trial else { return }
                // Prefer a detector box of the same category near the model's box (more precise); otherwise trust the model's own box.
                let distance = { (d: ObjectLocator.Detection) in hypot(d.box.midX - box.midX, d.box.midY - box.midY) }
                let match = detections.filter { $0.label == answer.coco_label && ($0.box.intersects(box) || distance($0) < 0.15) }.min { distance($0) < distance($1) }
                let target = match ?? ObjectLocator.Detection(label: answer.coco_label, confidence: 0.5, box: box)
                var interpretation = AIInterpretation(); interpretation.question = question
                interpretation.interpretedTarget = answer.object.prefix(1).uppercased() + answer.object.dropFirst(); interpretation.interpretedLocation = answer.location
                interpretation.explanation = answer.explanation; interpretation.confidence = answer.confidence.capitalized; interpretation.icon = SpatialQuery.icon(for: answer.coco_label)
                InterpretationStore.shared.value = interpretation
                self.visibleObjects = Array(Set(detections.map { SpatialQuery.displayName(for: $0.label) } + [interpretation.interpretedTarget])).sorted()
                let hit = self.arView.session.raycast(frame.raycastQuery(from: target.base, allowing: .estimatedPlane, alignment: .horizontal)).first
                    ?? self.arView.session.raycast(frame.raycastQuery(from: target.center, allowing: .estimatedPlane, alignment: .any)).first
                finish(hit.map { t in [t.worldTransform.columns.3.x, t.worldTransform.columns.3.y, t.worldTransform.columns.3.z] })
            }
        }
    }
    /// Live: parse the question, find the matching object in the camera view, and build the interpretation from where it really is.
    private func interpretLive(then finish: @escaping (SIMD3<Float>?) -> Void) {
        let question = InterpretationStore.shared.value.question, current = trial
        let query = SpatialQuery(question); liveReference = query.reference
        locate(pick: { detections in query.resolve(detections).map { r in (r.target, (query.interpretation(for: question, target: r.target, reference: r.reference), detections)) } }) { [weak self] result, position in
            guard let self, current == self.trial else { return }
            guard let result else { self.endTrial(with: query.target.map { "Couldn't find a \($0.name) in view. Point the camera at it and ask again." } ?? "Couldn't recognise anything in view. Live mode knows: \(SpatialQuery.knownObjects)."); return }
            InterpretationStore.shared.value = result.0
            self.visibleObjects = Array(Set(result.1.map { SpatialQuery.displayName(for: $0.label) })).sorted()
            finish(position)
        }
    }
    /// Runs detection over a few frames (~3 s) until `pick` chooses an object, then raycasts to its base in world space.
    /// Calls back with the last pick even when no surface was hit (position nil), and with (nil, nil) if nothing was picked.
    private func locate<T>(attempt: Int = 0, lastPick: T? = nil, pick: @escaping ([ObjectLocator.Detection]) -> (ObjectLocator.Detection, T)?, completion: @escaping (T?, SIMD3<Float>?) -> Void) {
        let retry = { [weak self] (picked: T?) in
            guard attempt < 10 else { completion(picked, nil); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.locate(attempt: attempt + 1, lastPick: picked, pick: pick, completion: completion) }
        }
        guard let frame = arView.session.currentFrame else { retry(lastPick); return }
        locator.detect(in: frame) { [weak self] detections in
            guard let self, let picked = pick(detections) else { retry(lastPick); return }
            // Prefer the surface under the object; fall back to whatever is behind its centre.
            let hit = self.arView.session.raycast(frame.raycastQuery(from: picked.0.base, allowing: .estimatedPlane, alignment: .horizontal)).first
                ?? self.arView.session.raycast(frame.raycastQuery(from: picked.0.center, allowing: .estimatedPlane, alignment: .any)).first
            guard let t = hit?.worldTransform.columns.3 else { retry(picked.1); return }
            completion(picked.1, [t.x, t.y, t.z])
        }
    }
    private func present(at position: SIMD3<Float>?, placement: String) {
        switch mode {
        case .chat: chatCard.isHidden = false
        case .screen: screenCard.isHidden = false
        case .object:
            guard let position else { awaitingTap = true; crosshair.isHidden = false; showMessage("Tap the object in the scene to show the interpretation."); return }
            placePanel(at: position); self.placement = placement
        }
        awaitingTap = false; resultShownAt = Date(); crosshair.isHidden = true
        responseButtonViews.forEach { $0.isHidden = false }
        if mode != .chat { hint.isHidden = true; arButtons.isHidden = false; arActions.isHidden = false }
    }
    private func showMessage(_ text: String) { hint.text = text; hint.isHidden = false; arButtons.isHidden = true; arActions.isHidden = false }
    private func endTrial(with message: String) { focus.isHidden = true; analyzingCard.isHidden = true; showMessage(message) }
    /// Fallback when detection fails: the participant (or researcher) taps the object.
    @objc private func handleSceneTap(_ gesture: UITapGestureRecognizer) {
        view.endEditing(true)
        guard mode == .object, awaitingTap else { return }
        guard let result = arView.raycast(from: gesture.location(in: arView), allowing: .estimatedPlane, alignment: .any).first else { hint.text = "No surface detected yet. Move slowly and try again."; return }
        let t = result.worldTransform.columns.3
        present(at: [t.x, t.y, t.z], placement: "tap")
    }
    // MARK: Object-anchored panel
    private func placePanel(at position: SIMD3<Float>) {
        removePanel()
        let item = InterpretationStore.shared.value, anchor = AnchorEntity(world: position)
        // The anchor sits where the object meets the table: dot on the object, line up to the card above it.
        let dot = ModelEntity(mesh: .generateSphere(radius: 0.012), materials: [UnlitMaterial(color: .white)]); dot.position = [0, 0.07, 0]
        let connector = ModelEntity(mesh: .generateBox(size: [0.004, 0.20, 0.004]), materials: [UnlitMaterial(color: .white)]); connector.position = [0, 0.17, 0]
        let p = Entity(); p.position = [0, 0.32, 0]
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
    @objc private func confirm(){InterpretationStore.shared.record(condition:mode.condition,outcome:"confirm",selectedIntendedTarget:false,placement:placement,source:answerSource,start:resultShownAt);responseButtonViews.forEach{$0.isHidden = true};showCompletion("Response saved.")}
    /// Scripted: the study's fixed object list. Live: the objects detected in view (there is no predefined intended target).
    @objc private func correct(sender:UIButton){let options = liveMode && !visibleObjects.isEmpty ? visibleObjects : AIInterpretation.sceneObjects;let a=UIAlertController(title:"Which object do you mean?",message:nil,preferredStyle:.actionSheet);options.forEach{option in a.addAction(UIAlertAction(title:option,style:.default){_ in InterpretationStore.shared.record(condition:self.mode.condition,outcome:"correct",selectedObject:option,selectedIntendedTarget:!self.liveMode && option == AIInterpretation.intendedObject,placement:self.placement,source:self.answerSource,start:self.resultShownAt);self.applyCorrection(option);self.showCompletion("Understood. You mean the \(option.lowercased()).")})};a.addAction(UIAlertAction(title:"Cancel",style:.cancel));a.popoverPresentationController?.sourceView = sender;present(a,animated:true)}
    private func showCompletion(_ message:String){let a=UIAlertController(title:"✓",message:message,preferredStyle:.alert);a.addAction(UIAlertAction(title:"Continue",style:.default));present(a,animated:true)}
    /// After a correction the answer shows the chosen object — name, icon, and (when it can be found in view) its location and anchor.
    /// The record has already been saved with the AI's original interpretation.
    private func applyCorrection(_ option: String) {
        responseButtonViews.forEach { $0.isHidden = true }
        let label = SpatialQuery.label(forName: option), referenceLabel = liveMode ? liveReference?.label : "laptop", referenceName = liveMode ? liveReference?.name : "laptop"
        var corrected = InterpretationStore.shared.value
        corrected.interpretedTarget = option; corrected.icon = SpatialQuery.icon(for: label); corrected.confidence = "Confirmed by you"
        // Scripted: the study's intended target has a known location; anything else is located below if it is in view.
        let known = !liveMode && option == AIInterpretation.intendedObject
        corrected.interpretedLocation = known ? "Left side of laptop" : "Location not detected"
        corrected.explanation = known ? "Got it — you mean the \(option.lowercased()) on the left side of your laptop." : "Got it — you mean the \(option.lowercased())."
        InterpretationStore.shared.value = corrected; refreshInterpretation(); if let anchor = worldAnchor { placePanel(at: anchor.position(relativeTo: nil)) }
        let current = trial
        locate(pick: { detections in SpatialQuery.mostConfident(label, in: detections).map { ($0, ($0, detections)) } }) { [weak self] found, position in
            guard let self, current == self.trial, let (target, detections) = found else { return }
            // Describe it relative to the question's reference object — unless the correction *is* that object (then: where in view).
            let reference = referenceLabel.flatMap { $0 == label ? nil : SpatialQuery.mostConfident($0, in: detections) }
            let place = SpatialQuery.describe(target, relativeTo: reference, named: referenceName)
            InterpretationStore.shared.value.interpretedLocation = place.location
            InterpretationStore.shared.value.explanation = "Got it — you mean the \(option.lowercased()) \(place.phrase)."
            self.refreshInterpretation()
            if self.mode == .object, let position { self.placePanel(at: position) }
        }
    }
}
