import ARKit
import Combine
import RealityKit
import UIKit

final class ViewController: UIViewController, ARSessionDelegate, UITextFieldDelegate {
    private enum Mode: Int { case chat, screen, object; var condition: String { ["2D", "Screen-Fixed AR", "Object-Anchored AR"][rawValue] } }
    private let arView = ARView(frame: .zero)
    private let modeControl = UISegmentedControl(items: ["2D Chat", "Screen AR", "Object AR"])
    private let composer = InterfaceStyle.card()
    private let questionField = UITextField(), focus = UIView(); private let modeDescription = PillLabel(), loadingLabel = UILabel()
    /// AR modes need world tracking before an answer can be placed in the scene; typing is always possible meanwhile.
    private var trackingReady = !ARWorldTrackingConfiguration.isSupported
    private static let scanMessage = "Move your phone slowly to scan the table."
    private let sendButton = UIButton(type: .system)
    private let analyzingCard = InterfaceStyle.card()
    // 2D: one conversational card with the buttons inside. Screen AR: compact card pinned to the top of the screen. Both AR modes share the bottom action stack.
    private let chatCard = InterfaceStyle.card(), screenCard = InterfaceStyle.card()
    private let chatConfidence = ConfidenceBar(), screenConfidence = ConfidenceBar()
    /// "Why: …" — the assistant's reason when it chose a tool for a task. Hidden when the question named the object (and in Evaluation mode).
    private let chatReason = UILabel(), screenReason = UILabel()
    /// Chat display as a conversation: the user's question in a bubble on the right, the assistant's answer below it.
    private let questionBubble = PillLabel(), questionRow = UIView()
    /// Chat display as a running conversation: earlier turns stay as static views above the live question and answer, and scroll.
    private let threadScroll = UIScrollView(), threadStack = UIStackView()
    /// Follow-up questions after the user responds: the last view of the thread (Chat) or in the bottom stack (Screen/Object).
    private let followUpRow = UIStackView(), arFollowUps = UIStackView()
    /// The live views at the end of the thread: question, answer, follow-ups. Earlier turns go above them.
    private static let liveThreadViews = 3
    private var threadHasHistory: Bool { threadStack.arrangedSubviews.count > Self.liveThreadViews }
    private let thinkingDots = ThinkingDots()
    /// Example questions above the input box when nothing else is shown, as chat apps do on a new conversation.
    private let suggestions = UIStackView()
    private var currentHistoryID: UUID?, focusedOnLaunch = false
    private var typingTimer: Timer?
    /// Hides the mode description 5 s after it was shown; replaced whenever the mode changes.
    private var descriptionFade: DispatchWorkItem?
    private let arActions = UIStackView(), arButtons = UIStackView(), hint = UILabel()
    private let crosshair = UIImageView(image: UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 44, weight: .light)))
    private let chatTarget = UILabel(), chatLocation = UILabel(), chatText = UILabel(), screenTarget = UILabel(), screenLocation = UILabel()
    /// AR modes: the interpreted object is located automatically; only if detection fails does the interpretation wait for a tap.
    private var mode = Mode.chat, awaitingTap = false, resultShownAt = Date()
    /// Bumped on every reset so detection callbacks from an abandoned trial are ignored.
    private var trial = 0, placement: String?
    private let locator = ObjectLocator()
    /// Rules (default) / VLM: the assistant interprets the question from the camera view.
    /// Scripted = Evaluation mode: a fixed question and an intentionally wrong answer, for user testing whether people notice AI misunderstandings.
    private enum Source { case scripted, rules, vlm }
    private var source = Source.rules, visibleObjects: [String] = [], iconViews: [UIImageView] = [], responseButtonViews: [UIButton] = []
    /// Live: the reference object of the last question ("coffee machine"), used to describe where a corrected object is.
    private var liveReference: SpatialQuery.Term?
    private var liveMode: Bool { source != .scripted }
    /// What produced the current answer, for the study record: "scripted", "live" (rules) or "vlm". VLM falls back to rules when its server is unreachable.
    private var answerSource = "scripted"
    private var sourceBadges: [UILabel] = []
    /// Live modes only: shows what produced the answer. Hidden in the study, where participants must not learn the answer is scripted.
    private var sourceBadgeText: String? {
        switch answerSource { case "vlm": return "● Vision model · Qwen2.5-VL"; case "live": return "● On-device"; default: return nil }
    }
    private let vlm = VLMClient()
    /// "Analyzing" shows how long the user has waited (the vision model takes ~15 s) and can be cancelled.
    private let cancelButton = UIButton(type: .system)
    private var analyzingTimer: Timer?, analyzingStart = Date(), analyzingTitle = "", analyzingDetail = ""
    /// Dashed, numbered boxes drawn over the camera view when the assistant asks which object the user means.
    private let highlightOverlay = UIView()
    private var worldAnchor: AnchorEntity?, panel: Entity?, billboard: Cancellable?

    override func viewDidLoad() { super.viewDidLoad(); setupCameraUI(); configureSession(); updateSettingsMenu(); updateQuestionField(); updateInputAvailability() }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Ready to type straight away, as in chat apps.
        if !focusedOnLaunch && liveMode { focusedOnLaunch = true; questionField.becomeFirstResponder() }
    }
    private func updateSettingsMenu() {
        let option = { (title: String, subtitle: String, s: Source) in
            UIAction(title: title, subtitle: subtitle, state: self.source == s ? .on : .off) { [weak self] _ in self?.setSource(s) }
        }
        // Three choices; the server address appears only while the vision model is in use (its connection is checked on selection).
        let server = UIAction(title: "Server…", subtitle: VLMClient.serverURL, image: UIImage(systemName: "network")) { [weak self] _ in self?.editVLMServer() }
        let assistant = UIMenu(title: "Assistant", options: .displayInline, children: [
            option("On-device", "Fast, works offline. Simple questions.", .rules),
            option("Vision model", "Smarter. Uses your computer over Wi-Fi.", .vlm)] + (source == .vlm ? [server] : []))
        let newChat = UIAction(title: "New conversation", image: UIImage(systemName: "square.and.pencil")) { [weak self] _ in
            guard let self else { return }; self.clearThread(); self.resetTrial(); self.refreshSuggestions(); if self.liveMode { self.continueConversation() }
        }
        let evaluation = UIMenu(title: "User testing", options: .displayInline, children: [
            option("Evaluation mode", "Fixed question and a scripted wrong answer.", .scripted)])
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "gearshape"), menu: UIMenu(title: "", children: (liveMode ? [newChat] : []) + [assistant, evaluation]))
        // History on the left, as in chat apps. Hidden in Evaluation mode, where earlier answers must not be visible to participants.
        navigationItem.leftBarButtonItem = liveMode ? UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal"), primaryAction: UIAction { [weak self] _ in self?.openHistory() }) : nil
    }
    /// Checks the vision-model server. Quiet on success when it runs automatically after choosing the vision model.
    private func testVLMConnection(quietOnSuccess: Bool = false) {
        VLMClient.checkServer { [weak self] ok, message in
            if ok && quietOnSuccess { return }
            let a = UIAlertController(title: ok ? "✓ Vision model ready" : "✗ Vision model not reachable", message: "\(message)\n\nServer: \(VLMClient.serverURL)", preferredStyle: .alert)
            if !ok { a.addAction(UIAlertAction(title: "Server settings…", style: .default) { _ in self?.editVLMServer() }) }
            a.addAction(UIAlertAction(title: "OK", style: .cancel)); self?.present(a, animated: true)
        }
    }
    /// Says plainly that the vision model could not be reached, instead of silently answering with the rules.
    private func vlmUnavailable(_ error: Error, then finish: @escaping (SIMD3<Float>?) -> Void) { vlmUnavailable(message: VLMClient.describe(error), then: finish) }
    private func vlmUnavailable(message: String, then finish: @escaping (SIMD3<Float>?) -> Void) {
        let current = trial
        let a = UIAlertController(title: "Can't reach the vision model", message: "\(message)\n\nServer: \(VLMClient.serverURL)\nCheck that Ollama is running and exposed to the network, that the iPhone and the computer are on the same Wi-Fi, and that Local Network access is on (Settings → Privacy & Security → Local Network). Some school and office networks block devices from reaching each other; a personal hotspot avoids that.", preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Answer on-device this time", style: .default) { [weak self] _ in
            guard let self, current == self.trial else { return }; self.answerSource = "live"; self.interpretLive(then: finish) })
        a.addAction(UIAlertAction(title: "Server settings…", style: .default) { [weak self] _ in self?.endTrial(with: "The vision model was not reached. Check the server, then ask again."); self?.editVLMServer() })
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in self?.endTrial(with: "The vision model was not reached.") })
        present(a, animated: true)
    }
    private func editVLMServer() {
        let a = UIAlertController(title: "VLM server", message: "Ollama on a computer on the same Wi-Fi, e.g. http://my-mac.local:11434", preferredStyle: .alert)
        a.addTextField { $0.text = VLMClient.serverURL; $0.keyboardType = .URL; $0.autocapitalizationType = .none; $0.autocorrectionType = .no }
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        a.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in VLMClient.serverURL = a.textFields?.first?.text ?? ""; self?.updateSettingsMenu(); self?.testVLMConnection() })
        present(a, animated: true)
    }
    private func setSource(_ s: Source) {
        source = s; clearThread(); let question = InterpretationStore.shared.value.question
        InterpretationStore.shared.value = .sample; InterpretationStore.shared.value.question = question
        resetTrial(); updateModeDescription(); updateSettingsMenu(); updateQuestionField()
        if s == .vlm { testVLMConnection(quietOnSuccess: true) }
        refreshSuggestions()
    }
    /// Evaluation mode: every participant asks the same question, so it is pre-filled and locked (they only press send). Otherwise free input.
    private func updateQuestionField() {
        if !liveMode { questionField.text = AIInterpretation.sample.question; questionField.resignFirstResponder() }
        else if questionField.text == AIInterpretation.sample.question { questionField.text = "" }
        // A lock shows the question is fixed; tapping it explains why and offers a Live mode (see textFieldShouldBeginEditing).
        let lock = UIImageView(image: UIImage(systemName: "lock.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)))
        lock.tintColor = .secondaryLabel; lock.contentMode = .center; lock.frame = CGRect(x: 0, y: 0, width: 24, height: 20)
        questionField.leftView = liveMode ? nil : lock; questionField.leftViewMode = liveMode ? .never : .always
    }
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        guard !liveMode else { return true }
        let a = UIAlertController(title: "Evaluation mode", message: "Everyone asks the same question here, so it can't be edited. Just tap send.\n\nTo ask your own question, leave Evaluation mode.", preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Ask my own question", style: .default) { [weak self] _ in self?.setSource(.rules); self?.questionField.becomeFirstResponder() })
        a.addAction(UIAlertAction(title: "Keep the evaluation question", style: .cancel))
        present(a, animated: true)
        return false
    }
    private func updateInputAvailability() {
        let ready = mode == .chat || trackingReady
        sendButton.isEnabled = ready
        let idle = chatCard.isHidden && screenCard.isHidden && analyzingCard.isHidden && worldAnchor == nil && !awaitingTap
        if !ready && idle { showMessage(Self.scanMessage) }
        else if ready && hint.text == Self.scanMessage && !hint.isHidden { hint.isHidden = true; arActions.isHidden = true }
        updateSuggestions()
    }
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        if case .normal = camera.trackingState { trackingReady = true } else { trackingReady = false }
        updateInputAvailability()
    }
    private func setupCameraUI() {
        view.backgroundColor = .black; arView.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(arView)
        NSLayoutConstraint.activate([arView.leadingAnchor.constraint(equalTo:view.leadingAnchor),arView.trailingAnchor.constraint(equalTo:view.trailingAnchor),arView.topAnchor.constraint(equalTo:view.topAnchor),arView.bottomAnchor.constraint(equalTo:view.bottomAnchor)])
        arView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleSceneTap(_:))))
        highlightOverlay.isUserInteractionEnabled = false;highlightOverlay.translatesAutoresizingMaskIntoConstraints = false;view.addSubview(highlightOverlay)
        NSLayoutConstraint.activate([highlightOverlay.leadingAnchor.constraint(equalTo:arView.leadingAnchor),highlightOverlay.trailingAnchor.constraint(equalTo:arView.trailingAnchor),highlightOverlay.topAnchor.constraint(equalTo:arView.topAnchor),highlightOverlay.bottomAnchor.constraint(equalTo:arView.bottomAnchor)])
        modeControl.selectedSegmentIndex = 0
        [(0,"message"),(1,"viewfinder"),(2,"mappin.and.ellipse")].forEach { modeControl.setImage(UIImage(systemName:$0.1),forSegmentAt:$0.0) }
        modeControl.backgroundColor = UIColor(white: 0.93, alpha: 0.95); modeControl.selectedSegmentTintColor = .white; modeControl.setTitleTextAttributes([.foregroundColor: UIColor.secondaryLabel, .font: UIFont.systemFont(ofSize: 13, weight: .medium)], for: .normal); modeControl.setTitleTextAttributes([.foregroundColor: UIColor.label, .font: UIFont.systemFont(ofSize: 13, weight: .semibold)], for: .selected); modeControl.translatesAutoresizingMaskIntoConstraints = false; modeControl.addTarget(self,action:#selector(modeChanged),for:.valueChanged); view.addSubview(modeControl)
        NSLayoutConstraint.activate([modeControl.leadingAnchor.constraint(equalTo:view.layoutMarginsGuide.leadingAnchor),modeControl.trailingAnchor.constraint(equalTo:view.layoutMarginsGuide.trailingAnchor),modeControl.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor,constant:12),modeControl.heightAnchor.constraint(equalToConstant:48)])
        modeDescription.textAlignment = .center; modeDescription.font = .preferredFont(forTextStyle: .footnote); modeDescription.numberOfLines = 0; modeDescription.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(modeDescription)
        NSLayoutConstraint.activate([modeDescription.centerXAnchor.constraint(equalTo: view.centerXAnchor), modeDescription.leadingAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor), modeDescription.trailingAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.trailingAnchor), modeDescription.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 8)])
        updateModeDescription()
        composer.translatesAutoresizingMaskIntoConstraints = false; questionField.placeholder = "Ask anything, e.g. What can I use to stir soup?";questionField.adjustsFontSizeToFitWidth = true;questionField.minimumFontSize = 13;questionField.text = InterpretationStore.shared.value.question;questionField.font = .preferredFont(forTextStyle:.body);questionField.returnKeyType = .send;questionField.delegate = self;questionField.addTarget(self,action:#selector(sendQuestion),for:.editingDidEndOnExit);questionField.translatesAutoresizingMaskIntoConstraints = false; composer.layer.cornerRadius = 27;var send = UIButton.Configuration.filled();send.image = UIImage(systemName:"arrow.up",withConfiguration:UIImage.SymbolConfiguration(pointSize:15,weight:.bold));send.cornerStyle = .capsule;send.baseBackgroundColor = InterfaceStyle.ink;send.baseForegroundColor = .white;sendButton.configuration = send;sendButton.configurationUpdateHandler = { b in b.configuration?.baseBackgroundColor = b.isEnabled ? InterfaceStyle.ink : UIColor(white: 0.8, alpha: 1) };sendButton.translatesAutoresizingMaskIntoConstraints = false;sendButton.addTarget(self,action:#selector(sendQuestion),for:.touchUpInside);composer.contentView.addSubview(questionField);composer.contentView.addSubview(sendButton);view.addSubview(composer)
        NSLayoutConstraint.activate([composer.leadingAnchor.constraint(equalTo:view.layoutMarginsGuide.leadingAnchor),composer.trailingAnchor.constraint(equalTo:view.layoutMarginsGuide.trailingAnchor),composer.bottomAnchor.constraint(equalTo:view.keyboardLayoutGuide.topAnchor,constant:-12),composer.heightAnchor.constraint(equalToConstant:54),questionField.leadingAnchor.constraint(equalTo:composer.contentView.leadingAnchor,constant:20),questionField.trailingAnchor.constraint(equalTo:sendButton.leadingAnchor,constant:-8),questionField.centerYAnchor.constraint(equalTo:composer.contentView.centerYAnchor),sendButton.trailingAnchor.constraint(equalTo:composer.contentView.trailingAnchor,constant:-9),sendButton.centerYAnchor.constraint(equalTo:composer.contentView.centerYAnchor),sendButton.widthAnchor.constraint(equalToConstant:36),sendButton.heightAnchor.constraint(equalToConstant:36)])
        focus.layer.cornerRadius = 28;focus.layer.borderWidth = 3;focus.layer.borderColor = UIColor.white.cgColor;focus.translatesAutoresizingMaskIntoConstraints = false;focus.isHidden = true;view.addSubview(focus);NSLayoutConstraint.activate([focus.centerXAnchor.constraint(equalTo:view.centerXAnchor),focus.centerYAnchor.constraint(equalTo:view.centerYAnchor),focus.widthAnchor.constraint(equalToConstant:56),focus.heightAnchor.constraint(equalToConstant:56)])
        loadingLabel.textColor = .label;loadingLabel.font = .systemFont(ofSize:15);loadingLabel.numberOfLines = 0;cancelButton.setTitle("Cancel",for:.normal);cancelButton.tintColor = InterfaceStyle.accent;cancelButton.titleLabel?.font = .systemFont(ofSize:15,weight:.semibold);cancelButton.setContentHuggingPriority(.required,for:.horizontal);cancelButton.setContentCompressionResistancePriority(.required,for:.horizontal);loadingLabel.setContentCompressionResistancePriority(.defaultLow,for:.horizontal);cancelButton.addTarget(self,action:#selector(cancelAnalyzing),for:.touchUpInside);thinkingDots.setContentHuggingPriority(.required,for:.horizontal);let loadingStack=UIStackView(arrangedSubviews:[thinkingDots,loadingLabel,cancelButton]);loadingStack.axis = .horizontal;loadingStack.alignment = .center;loadingStack.spacing = 12;loadingStack.translatesAutoresizingMaskIntoConstraints = false;analyzingCard.translatesAutoresizingMaskIntoConstraints = false;analyzingCard.contentView.addSubview(loadingStack);analyzingCard.isHidden = true;view.addSubview(analyzingCard);NSLayoutConstraint.activate([loadingStack.leadingAnchor.constraint(equalTo:analyzingCard.contentView.leadingAnchor,constant:18),loadingStack.trailingAnchor.constraint(equalTo:analyzingCard.contentView.trailingAnchor,constant:-18),loadingStack.topAnchor.constraint(equalTo:analyzingCard.contentView.topAnchor,constant:14),loadingStack.bottomAnchor.constraint(equalTo:analyzingCard.contentView.bottomAnchor,constant:-14),analyzingCard.leadingAnchor.constraint(equalTo:view.layoutMarginsGuide.leadingAnchor),analyzingCard.trailingAnchor.constraint(equalTo:view.layoutMarginsGuide.trailingAnchor),analyzingCard.bottomAnchor.constraint(equalTo:composer.topAnchor,constant:-14)])
        setupInterpretationViews()
    }
    private func setupInterpretationViews() {
        // 2D Chat: conversational card above the composer, buttons inside the card.
        chatText.numberOfLines = 0;chatText.font = .preferredFont(forTextStyle:.body)
        chatText.textColor = .label;[chatReason,screenReason].forEach{$0.font = .preferredFont(forTextStyle:.footnote);$0.textColor = .secondaryLabel;$0.numberOfLines = 0;$0.isHidden = true};chatText.font = .systemFont(ofSize:17);let chatStack=UIStackView(arrangedSubviews:[titleRow(chatTarget,chatLocation),chatConfidence,chatText,chatReason,chipRow()]);chatStack.axis = .vertical;chatStack.spacing = 12
        pin(chatStack,in:chatCard,padding:18)
        styleUserBubble(questionBubble); place(questionBubble, in: questionRow, trailing: true)
        // The thread sits between the mode bar and the input box, below the "Thinking" card so Cancel stays tappable.
        threadStack.axis = .vertical; threadStack.spacing = 12; threadStack.translatesAutoresizingMaskIntoConstraints = false
        [followUpRow, arFollowUps].forEach { $0.axis = .vertical; $0.alignment = .leading; $0.spacing = 8; $0.isHidden = true }
        [questionRow, chatCard, followUpRow].forEach(threadStack.addArrangedSubview)
        threadScroll.showsVerticalScrollIndicator = false; threadScroll.keyboardDismissMode = .interactive; threadScroll.translatesAutoresizingMaskIntoConstraints = false
        threadScroll.addSubview(threadStack); view.insertSubview(threadScroll, belowSubview: analyzingCard)
        view.bringSubviewToFront(modeDescription)  // the 5-second description stays readable above the conversation
        let content = threadScroll.contentLayoutGuide, frame = threadScroll.frameLayoutGuide
        let fillHeight = content.heightAnchor.constraint(equalTo: frame.heightAnchor); fillHeight.priority = .defaultLow
        NSLayoutConstraint.activate([
            threadScroll.leadingAnchor.constraint(equalTo:view.layoutMarginsGuide.leadingAnchor), threadScroll.trailingAnchor.constraint(equalTo:view.layoutMarginsGuide.trailingAnchor),
            threadScroll.topAnchor.constraint(equalTo:modeControl.bottomAnchor,constant:8), threadScroll.bottomAnchor.constraint(equalTo:composer.topAnchor,constant:-10),
            // Short conversations rest on the input box, as in chat apps; longer ones scroll.
            threadStack.leadingAnchor.constraint(equalTo:content.leadingAnchor), threadStack.trailingAnchor.constraint(equalTo:content.trailingAnchor),
            threadStack.bottomAnchor.constraint(equalTo:content.bottomAnchor), threadStack.topAnchor.constraint(greaterThanOrEqualTo:content.topAnchor),
            threadStack.widthAnchor.constraint(equalTo:frame.widthAnchor), content.heightAnchor.constraint(greaterThanOrEqualTo:frame.heightAnchor), fillHeight,
        ])
        // Screen AR: compact card fixed near the top of the screen; it never moves with the scene.
        let screenStack=UIStackView(arrangedSubviews:[titleRow(screenTarget,screenLocation),screenReason,screenConfidence]);screenStack.axis = .vertical;screenStack.spacing = 10;pin(screenStack,in:screenCard,padding:16);view.addSubview(screenCard)
        NSLayoutConstraint.activate([screenCard.leadingAnchor.constraint(equalTo:view.layoutMarginsGuide.leadingAnchor),screenCard.trailingAnchor.constraint(equalTo:view.layoutMarginsGuide.trailingAnchor),screenCard.topAnchor.constraint(equalTo:modeDescription.bottomAnchor,constant:12)])
        // Both AR modes: buttons at the bottom, separate from the interpretation itself.
        hint.textColor = .label;hint.textAlignment = .center;hint.numberOfLines = 0;hint.font = .preferredFont(forTextStyle:.footnote);hint.backgroundColor = UIColor.white.withAlphaComponent(0.88);hint.layer.cornerRadius = 10;hint.clipsToBounds = true
        responseButtons().forEach(arButtons.addArrangedSubview);arButtons.axis = .horizontal;arButtons.distribution = .fillEqually;arButtons.spacing = 10
        [hint,arFollowUps,arButtons].forEach(arActions.addArrangedSubview);arActions.axis = .vertical;arActions.spacing = 10;arActions.translatesAutoresizingMaskIntoConstraints = false;view.addSubview(arActions)
        NSLayoutConstraint.activate([arActions.leadingAnchor.constraint(equalTo:view.layoutMarginsGuide.leadingAnchor),arActions.trailingAnchor.constraint(equalTo:view.layoutMarginsGuide.trailingAnchor),arActions.bottomAnchor.constraint(equalTo:composer.topAnchor,constant:-14)])
        crosshair.tintColor = .white;crosshair.translatesAutoresizingMaskIntoConstraints = false;view.addSubview(crosshair);NSLayoutConstraint.activate([crosshair.centerXAnchor.constraint(equalTo:view.centerXAnchor),crosshair.centerYAnchor.constraint(equalTo:view.centerYAnchor)])
        [chatCard,screenCard,arActions,crosshair,questionRow].forEach{$0.isHidden = true}
        refreshSuggestions()
        suggestions.axis = .vertical; suggestions.alignment = .leading; suggestions.spacing = 8; suggestions.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(suggestions)
        NSLayoutConstraint.activate([suggestions.leadingAnchor.constraint(equalTo:view.layoutMarginsGuide.leadingAnchor),suggestions.bottomAnchor.constraint(equalTo:composer.topAnchor,constant:-14)])
    }
    /// Example questions. On-device only suggests what its rules and detector can answer; the vision model adds open-ended ones.
    private static let findQuestions = ["Where is my cup?", "Can you find the water bottle?", "Where is the bowl next to the sink?", "Is there a knife on the counter?"]
    private static let taskQuestions = ["What can I use to stir my soup?", "I need to cut some bread.", "Where can I reheat my leftovers?", "I want to wash the vegetables.", "What should I use to mix the eggs?"]
    private static let otherQuestions = ["What is this?", "I want something to drink."]
    private static let visionFind = ["Where is the wooden spoon?", "What is next to the coffee machine?", "What's in the utensil holder?"]
    private static let visionTask = ["Which tool should I use to flip a pancake?", "What can I use to drain the pasta?", "I want to make coffee. What do I need?",
                                     "What should I use to grate cheese?", "What can I use to open this jar?", "What can I use to serve the soup?"]
    /// A fresh mix each launch and whenever the assistant changes: one find question, one task question, one more at random.
    private func refreshSuggestions() {
        let vision = source == .vlm
        let find = Self.findQuestions + (vision ? Self.visionFind : []), task = Self.taskQuestions + (vision ? Self.visionTask : [])
        guard let first = find.randomElement(), let second = task.randomElement() else { return }
        let third = (find + task + Self.otherQuestions).filter { $0 != first && $0 != second }.randomElement() ?? "What is this?"
        suggestions.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for text in [first, second, third] {
            suggestions.addArrangedSubview(questionChip(text, symbol: find.contains(text) ? "magnifyingglass" : (task.contains(text) ? "lightbulb" : "questionmark.circle")))
        }
    }
    /// A tappable question: fills the input and asks it.
    private func questionChip(_ text: String, symbol: String) -> UIButton {
        var c = UIButton.Configuration.filled(); c.title = text; c.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium))
        c.imagePadding = 10; c.cornerStyle = .capsule; c.baseBackgroundColor = UIColor.white.withAlphaComponent(0.9); c.baseForegroundColor = InterfaceStyle.ink
        c.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 14, bottom: 9, trailing: 16)
        c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { var a = $0; a.font = .systemFont(ofSize: 15); return a }
        return UIButton(configuration: c, primaryAction: UIAction { [weak self] _ in self?.questionField.text = text; self?.sendQuestion() })
    }
    /// Questions that carry the topic on after the user confirms or corrects an answer. On-device only offers ones its rules can answer.
    private func followUpQuestions(about object: String) -> [String] {
        let name = object.lowercased(), label = SpatialQuery.cocoLabel(forName: object), known = label != "other"
        let neighbour = visibleObjects.map { $0.lowercased() }.first { $0 != name && SpatialQuery.cocoLabel(forName: $0) != label && SpatialQuery.cocoLabel(forName: $0) != "other" }
        var questions: [String] = []
        if source == .vlm { questions += ["What can I use the \(name) for?", "What is next to the \(name)?"] }
        if known || source == .vlm { questions.append("Is there another \(name)?") }
        if known, let neighbour { questions.append("Find the \(neighbour) next to the \(name).") }
        if let task = SpatialQuery.taskQuestion(for: label) { questions.append(task) }
        return Array(questions.prefix(3))
    }
    private func showFollowUps(about object: String) {
        let questions = followUpQuestions(about: object), row = mode == .chat ? followUpRow : arFollowUps
        row.arrangedSubviews.forEach { $0.removeFromSuperview() }
        questions.forEach { row.addArrangedSubview(questionChip($0, symbol: "arrow.turn.down.right")) }
        row.isHidden = questions.isEmpty
    }
    /// Suggestions only when the screen is otherwise empty, in the assistant modes.
    private func updateSuggestions() {
        let idle = chatCard.isHidden && screenCard.isHidden && analyzingCard.isHidden && arActions.isHidden && worldAnchor == nil && !awaitingTap
        suggestions.isHidden = !(liveMode && idle && !threadHasHistory)
    }
    /// `staticIcon` builds a fixed copy for an earlier turn of the conversation, which later answers must not update.
    private func titleRow(_ target:UILabel,_ location:UILabel,staticIcon:String? = nil,staticBadge:String? = nil)->UIStackView {
        let icon=UIImageView(image:UIImage(systemName:staticIcon ?? "waterbottle.fill") ?? UIImage(systemName:"cube.fill"));icon.tintColor = InterfaceStyle.accent;icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize:30,weight:.medium);icon.contentMode = .scaleAspectFit;icon.setContentHuggingPriority(.required,for:.horizontal);icon.setContentCompressionResistancePriority(.required,for:.horizontal);if staticIcon == nil {iconViews.append(icon)}
        target.font = .systemFont(ofSize:18,weight:.bold);location.textColor = .secondaryLabel;location.font = .preferredFont(forTextStyle:.subheadline)
        let badge=UILabel();badge.font = .systemFont(ofSize:12,weight:.semibold);badge.textColor = InterfaceStyle.accent;badge.text = staticBadge;badge.isHidden = staticBadge == nil;if staticIcon == nil {sourceBadges.append(badge)}
        let labels=UIStackView(arrangedSubviews:[target,location,badge]);labels.axis = .vertical;labels.alignment = .leading
        let row=UIStackView(arrangedSubviews:[icon,labels]);row.axis = .horizontal;row.alignment = .center;row.spacing = 12;return row
    }
    /// The response actions as a row of chips under the answer.
    private func chipRow()->UIStackView { let row=UIStackView(arrangedSubviews:responseButtons());row.axis = .horizontal;row.distribution = .fillEqually;row.spacing = 10;return row }
    private func responseButtons()->[UIButton] {
        let confirmButton=InterfaceStyle.pillButton("That's right",symbol:"checkmark",filled:true);confirmButton.addTarget(self,action:#selector(confirm),for:.touchUpInside)
        let correctButton=InterfaceStyle.pillButton("Not this one",symbol:"pencil");correctButton.addTarget(self,action:#selector(correct(sender:)),for:.touchUpInside)
        responseButtonViews += [confirmButton,correctButton];return [confirmButton,correctButton]
    }
    private func pin(_ content:UIView,in card:UIVisualEffectView,padding:CGFloat) {
        card.translatesAutoresizingMaskIntoConstraints = false;content.translatesAutoresizingMaskIntoConstraints = false;card.contentView.addSubview(content)
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo:card.contentView.leadingAnchor,constant:padding),content.trailingAnchor.constraint(equalTo:card.contentView.trailingAnchor,constant:-padding),content.topAnchor.constraint(equalTo:card.contentView.topAnchor,constant:padding),content.bottomAnchor.constraint(equalTo:card.contentView.bottomAnchor,constant:-padding)])
    }
    private func refreshInterpretation() {
        let item = InterpretationStore.shared.value
        [chatTarget,screenTarget].forEach{$0.text = item.interpretedTarget};[chatLocation,screenLocation].forEach{$0.text = item.interpretedLocation};chatText.text = item.explanation;iconViews.forEach{$0.image = UIImage(systemName:item.icon) ?? UIImage(systemName:"cube.fill")}
        sourceBadges.forEach{$0.text = sourceBadgeText;$0.isHidden = sourceBadgeText == nil}
        [chatConfidence,screenConfidence].forEach{$0.set(item.confidenceScore,caption:item.confidence)}
        [chatReason,screenReason].forEach{$0.text = item.reason.map{"Why: \($0)"};$0.isHidden = item.reason == nil}
    }
    private func configureSession(){guard ARWorldTrackingConfiguration.isSupported else{return};arView.session.delegate = self;arView.session.run(ARWorldTrackingConfiguration())}
    @objc private func modeChanged(){mode = Mode(rawValue:modeControl.selectedSegmentIndex) ?? .chat; resetTrial(); updateModeDescription() }
    /// Tells the user what each display is good for. Hidden in Evaluation mode, where it could steer participants.
    /// Shown for 5 seconds when a display is chosen (and at launch), then fades out so it does not cover the camera view.
    private func updateModeDescription() {
        descriptionFade?.cancel()
        guard liveMode else { modeDescription.text = ""; modeDescription.isHidden = true; return }
        switch mode {
        case .chat: modeDescription.text = "Chat: read the full answer as a message."
        case .screen: modeDescription.text = "Screen: keep the answer in view while you look around."
        case .object: modeDescription.text = "Object: see the answer on the object it is about."
        }
        modeDescription.isHidden = false
        UIView.animate(withDuration: 0.25) { self.modeDescription.alpha = 1 }
        let fade = DispatchWorkItem { [weak self] in
            guard let self else { return }
            UIView.animate(withDuration: 0.4, animations: { self.modeDescription.alpha = 0 }) { done in if done && self.modeDescription.alpha == 0 { self.modeDescription.isHidden = true } }
        }
        descriptionFade = fade; DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: fade)
    }
    /// Hides every interpretation view so the next question starts from the camera view.
    private func resetTrial(){trial += 1;awaitingTap = false;placement = nil;typingTimer?.invalidate();[chatCard,screenCard,arActions,crosshair,focus,analyzingCard,questionRow,followUpRow,arFollowUps].forEach{$0.isHidden = true};threadScroll.isHidden = mode != .chat;removePanel();clearHighlights();updateInputAvailability()}
    @objc private func sendQuestion(){view.endEditing(true);guard sendButton.isEnabled else{return};if liveMode && (questionField.text ?? "").trimmingCharacters(in:.whitespaces).isEmpty{showMessage("Type a question about something you see, e.g. Where is my cup?");return};let question = questionField.text.flatMap{$0.isEmpty ? nil : $0} ?? InterpretationStore.shared.value.question;if liveMode{if mode == .chat{archiveLiveTurn()};questionField.text = ""};if !liveMode{InterpretationStore.shared.value = .sample};InterpretationStore.shared.value.question = question;resetTrial();startAnalyzing(source == .vlm ? "Asking the vision model…" : "Thinking…", detail: mode != .chat || liveMode ? "Keep the camera pointed at the scene." : "");let current = trial;DispatchQueue.main.asyncAfter(deadline:.now()+0.8){[weak self] in guard let self, current == self.trial else{return};self.showResult()}}
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
    private func startAnalyzing(_ title: String, detail: String) {
        analyzingTitle = title; analyzingDetail = detail; analyzingStart = Date(); focus.isHidden = false; analyzingCard.isHidden = false; thinkingDots.start(); updateAnalyzingLabel(); updateSuggestions()
        analyzingTimer?.invalidate(); analyzingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.updateAnalyzingLabel() }
    }
    private func updateAnalyzingLabel() {
        guard !analyzingCard.isHidden else { analyzingTimer?.invalidate(); analyzingTimer = nil; return }
        let seconds = Int(Date().timeIntervalSince(analyzingStart))
        loadingLabel.text = analyzingTitle + (seconds > 0 ? " \(seconds) s" : "") + (analyzingDetail.isEmpty ? "" : "\n" + analyzingDetail)
    }
    @objc private func cancelAnalyzing() { vlm.cancel(); resetTrial(); showMessage("Cancelled. Ask again when you're ready.") }
    /// Runs detection over a few frames (~3 s) until `found` accepts them; calls back with that frame, or nil if nothing was found.
    private func detect(attempt: Int = 0, until found: @escaping ([ObjectLocator.Detection]) -> Bool, completion: @escaping (ARFrame?, [ObjectLocator.Detection]) -> Void) {
        let retry = { [weak self] in
            guard attempt < 10 else { completion(nil, []); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.detect(attempt: attempt + 1, until: found, completion: completion) }
        }
        guard let frame = arView.session.currentFrame else { retry(); return }
        locator.detect(in: frame) { detections in found(detections) ? completion(frame, detections) : retry() }
    }
    /// Where the object stands: the surface under it, or else whatever is behind its centre.
    private func worldPosition(of d: ObjectLocator.Detection, in frame: ARFrame) -> SIMD3<Float>? {
        let hit = arView.session.raycast(frame.raycastQuery(from: d.base, allowing: .estimatedPlane, alignment: .horizontal)).first
            ?? arView.session.raycast(frame.raycastQuery(from: d.center, allowing: .estimatedPlane, alignment: .any)).first
        return hit.map { t in [t.worldTransform.columns.3.x, t.worldTransform.columns.3.y, t.worldTransform.columns.3.z] }
    }
    /// Live modes: when several objects fit or the assistant is unsure, it asks instead of guessing.
    /// The candidates are numbered left to right on the camera view.
    private func askWhichOne(_ candidates: [ObjectLocator.Detection], name: String, frame: ARFrame, choose: @escaping (ObjectLocator.Detection) -> Void) {
        focus.isHidden = true; analyzingCard.isHidden = true
        let ordered = candidates.sorted { $0.box.midX < $1.box.midX }, single = ordered.count == 1
        showHighlights(ordered.enumerated().map { ($0.element.box, "\($0.offset + 1)") }, in: frame)
        let a = UIAlertController(title: single ? "Is this the \(name) you mean?" : "Which \(name) do you mean?",
                                  message: single ? "I'm not sure I found the right one. It is marked on the screen." : "\(ordered.count) could fit. They are numbered on the screen.", preferredStyle: .actionSheet)
        for (i, d) in ordered.enumerated() {
            let place = SpatialQuery.describe(d, relativeTo: nil, named: nil).location
            a.addAction(UIAlertAction(title: single ? "Yes, this one" : "\(i + 1) · \(place)", style: .default) { [weak self] _ in self?.clearHighlights(); choose(d) })
        }
        a.addAction(UIAlertAction(title: single ? "No" : "None of these", style: .cancel) { [weak self] _ in
            self?.clearHighlights(); self?.endTrial(with: "OK. Point the camera at the \(name) and ask again.") })
        a.popoverPresentationController?.sourceView = view; a.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY, width: 0, height: 0)
        present(a, animated: true)
    }
    private func showHighlights(_ items: [(box: CGRect, label: String)], in frame: ARFrame) {
        clearHighlights()
        let size = arView.bounds.size, t = frame.displayTransform(for: .portrait, viewportSize: size)
        for item in items {
            // Upright image → sensor image (as in ObjectLocator) → normalized view coordinates → points.
            let a = CGPoint(x: item.box.minY, y: 1 - item.box.minX).applying(t), b = CGPoint(x: item.box.maxY, y: 1 - item.box.maxX).applying(t)
            let r = CGRect(x: min(a.x, b.x) * size.width, y: min(a.y, b.y) * size.height, width: abs(b.x - a.x) * size.width, height: abs(b.y - a.y) * size.height)
            let outline = CAShapeLayer(); outline.path = UIBezierPath(roundedRect: r, cornerRadius: 10).cgPath; outline.fillColor = nil
            outline.strokeColor = UIColor.white.cgColor; outline.shadowColor = UIColor.black.cgColor; outline.shadowOpacity = 0.4; outline.shadowRadius = 2; outline.shadowOffset = .zero; outline.lineWidth = 3; outline.lineDashPattern = [8, 6]; highlightOverlay.layer.addSublayer(outline)
            let tag = UILabel(frame: CGRect(x: min(max(r.minX - 8, 4), size.width - 32), y: min(max(r.minY - 14, 4), size.height - 32), width: 28, height: 28));  // kept on screen tag.text = item.label; tag.font = .boldSystemFont(ofSize: 17)
            tag.textAlignment = .center; tag.textColor = .white; tag.backgroundColor = InterfaceStyle.accent; tag.layer.cornerRadius = 14; tag.clipsToBounds = true; highlightOverlay.addSubview(tag)
        }
    }
    /// Remove the number tags as views first, then only the outline layers. Removing every sublayer would also pull the tags'
    /// layers out from under UIKit and crash (EXC_BAD_ACCESS).
    private func clearHighlights() {
        highlightOverlay.subviews.forEach { $0.removeFromSuperview() }
        highlightOverlay.layer.sublayers?.filter { $0 is CAShapeLayer }.forEach { $0.removeFromSuperlayer() }
    }
    /// Live (VLM): the vision-language model on the computer decides what the question means; YOLO, run on the same frame, refines the box.
    /// If the server can't be reached, falls back to the rule-based interpretation (recorded as "live").
    private func interpretVLM(then finish: @escaping (SIMD3<Float>?) -> Void) {
        let question = InterpretationStore.shared.value.question, current = trial
        guard let frame = arView.session.currentFrame else { answerSource = "live"; interpretLive(then: finish); return }
        answerSource = "vlm"; liveReference = nil
        // Fail fast: a 5 s reachability check first, so an unreachable computer is reported in seconds, not after the 60 s request timeout.
        VLMClient.checkServer { [weak self] reachable, message in
            guard let self, current == self.trial else { return }
            guard reachable else { self.vlmUnavailable(message: message, then: finish); return }
            self.askVLM(question: question, frame: frame, then: finish)
        }
    }
    private func askVLM(question: String, frame: ARFrame, then finish: @escaping (SIMD3<Float>?) -> Void) {
        let current = trial
        vlm.interpret(question: question, frame: frame) { [weak self] result in
            guard let self, current == self.trial else { return }
            guard case let .success((answer, box)) = result else {
                if case let .failure(error) = result { self.vlmUnavailable(error, then: finish) }; return
            }
            self.locator.detect(in: frame) { detections in
                guard current == self.trial else { return }
                // Prefer a detector box of the same category near the model's box (more precise); otherwise trust the model's own box.
                let label = SpatialQuery.cocoLabel(forName: answer.object)
                // A question that names an object needs no reason; a task question ("What can I use to stir soup?") does.
                let parsed = SpatialQuery(question), namesObject = parsed.target != nil && parsed.reason == nil
                let distance = { (d: ObjectLocator.Detection) in hypot(d.box.midX - box.midX, d.box.midY - box.midY) }
                let match = detections.filter { $0.label == label && ($0.box.intersects(box) || distance($0) < 0.15) }.min { distance($0) < distance($1) }
                let target = match ?? ObjectLocator.Detection(label: label, confidence: 0.5, box: box)
                let name = answer.object.prefix(1).uppercased() + answer.object.dropFirst()
                let show = { (t: ObjectLocator.Detection, location: String, explanation: String, confidence: String) in
                    var interpretation = AIInterpretation(); interpretation.question = question
                    interpretation.interpretedTarget = name; interpretation.interpretedLocation = location
                    interpretation.explanation = explanation; interpretation.confidence = confidence; interpretation.icon = SpatialQuery.icon(forName: answer.object, label: label)
                    interpretation.reason = namesObject ? nil : answer.reason.flatMap { $0.isEmpty ? nil : $0 }
                    // The model only reports high / medium / low, so the bar shows an approximate score; nil once the user has chosen.
                    interpretation.confidenceScore = ["High": 0.85, "Medium": 0.6, "Low": 0.3][confidence]
                    InterpretationStore.shared.value = interpretation
                    finish(self.worldPosition(of: t, in: frame))
                }
                let suggested = (answer.alternatives ?? []).prefix(3).map { $0.prefix(1).uppercased() + $0.dropFirst() }
                self.visibleObjects = Array(Set(detections.map { SpatialQuery.displayName(for: $0.label) } + [name] + suggested)).sorted()
                // The model is unsure and there are several of that kind in view: ask which one rather than guess.
                let sameKind = detections.filter { $0.label == label }
                if answer.confidence == "low", sameKind.count >= 2 {
                    self.askWhichOne(sameKind, name: answer.object.lowercased(), frame: frame) { chosen in
                        let place = SpatialQuery.describe(chosen, relativeTo: nil, named: nil)
                        show(chosen, place.location, "You mean the \(answer.object.lowercased()) \(place.phrase).", "Clarified by you")
                    }
                    return
                }
                show(target, answer.location, answer.explanation, answer.confidence.capitalized)
            }
        }
    }
    /// Live: parse the question, find the matching object in the camera view, and build the interpretation from where it really is.
    private func interpretLive(then finish: @escaping (SIMD3<Float>?) -> Void) {
        let question = InterpretationStore.shared.value.question, current = trial
        let query = SpatialQuery(question); liveReference = query.reference
        guard !query.needsVisionModel else {
            endTrial(with: "On-device mode can't tell which tool suits that task. Switch to ⚙️ → Vision model, or name the object, e.g. Where is the spoon?"); return
        }
        detect(until: { query.resolve($0) != nil }) { [weak self] frame, detections in
            guard let self, current == self.trial else { return }
            guard let frame, let resolved = query.resolve(detections) else { self.endTrial(with: query.target.map { "Couldn't find a \($0.name) in view. Point the camera at it and ask again." } ?? "Couldn't recognise anything in view. Live mode knows: \(SpatialQuery.knownObjects)."); return }
            self.visibleObjects = Array(Set(detections.map { SpatialQuery.displayName(for: $0.label) })).sorted()
            let answer = { (t: ObjectLocator.Detection) in
                InterpretationStore.shared.value = query.interpretation(for: question, target: t, reference: resolved.reference)
                finish(self.worldPosition(of: t, in: frame))
            }
            // Several objects fit the question, or the detector is unsure: ask instead of guessing.
            let candidates = query.candidates(detections)
            if candidates.count >= 2 || resolved.target.confidence < 0.4 {
                let name = query.target?.name ?? SpatialQuery.displayName(for: resolved.target.label).lowercased()
                self.askWhichOne(candidates.count >= 2 ? candidates : [resolved.target], name: name, frame: frame, choose: answer)
            } else { answer(resolved.target) }
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
            guard let position = self.worldPosition(of: picked.0, in: frame) else { retry(picked.1); return }
            completion(picked.1, position)
        }
    }
    private func present(at position: SIMD3<Float>?, placement: String) {
        switch mode {
        case .chat:
            questionBubble.text = InterpretationStore.shared.value.question; questionRow.isHidden = false; chatCard.isHidden = false; typeOut(chatText); scrollThreadToBottom()
        case .screen: screenCard.isHidden = false
        case .object:
            guard let position else { awaitingTap = true; crosshair.isHidden = false; showMessage("Tap the object in the scene to show the interpretation."); return }
            placePanel(at: position); self.placement = placement
        }
        awaitingTap = false; resultShownAt = Date(); crosshair.isHidden = true; updateSuggestions()
        currentHistoryID = liveMode ? HistoryStore.shared.add(InterpretationStore.shared.value, display: mode.condition, source: answerSource) : nil
        responseButtonViews.forEach { $0.isHidden = false }
        if mode != .chat { hint.isHidden = true; arButtons.isHidden = false; arActions.isHidden = false }
    }
    // MARK: Conversation
    private func styleUserBubble(_ bubble: PillLabel) {
        bubble.backgroundColor = InterfaceStyle.userBubble; bubble.font = .systemFont(ofSize: 16); bubble.numberOfLines = 0; bubble.layer.cornerRadius = 18
    }
    /// Wraps a bubble in a full-width row, pinned right (the user) or left (the assistant) with room on the other side.
    private func place(_ bubble: UIView, in row: UIView, trailing: Bool) {
        bubble.translatesAutoresizingMaskIntoConstraints = false; row.addSubview(bubble)
        NSLayoutConstraint.activate([bubble.topAnchor.constraint(equalTo: row.topAnchor), bubble.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            trailing ? bubble.trailingAnchor.constraint(equalTo: row.trailingAnchor) : bubble.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            trailing ? bubble.leadingAnchor.constraint(greaterThanOrEqualTo: row.leadingAnchor, constant: 56) : bubble.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -40)])
    }
    private func userTurn(_ text: String) -> UIView {
        let bubble = PillLabel(); styleUserBubble(bubble); bubble.text = text; let row = UIView(); place(bubble, in: row, trailing: true); return row
    }
    private func assistantTurn(_ text: String) -> UIView {
        let bubble = PillLabel(); bubble.text = text; bubble.font = .systemFont(ofSize: 16); bubble.numberOfLines = 0; bubble.layer.cornerRadius = 18
        bubble.backgroundColor = UIColor.white.withAlphaComponent(0.92); let row = UIView(); place(bubble, in: row, trailing: false); return row
    }
    /// A fixed copy of an answer card for an earlier turn.
    private func answerTurn(_ item: AIInterpretation) -> UIView {
        let target = UILabel(), location = UILabel(), text = UILabel(), bar = ConfidenceBar(), reason = UILabel()
        target.text = item.interpretedTarget; location.text = item.interpretedLocation; text.text = item.explanation; text.numberOfLines = 0; text.font = .systemFont(ofSize: 17)
        bar.set(item.confidenceScore, caption: item.confidence)
        reason.text = item.reason.map { "Why: \($0)" }; reason.isHidden = item.reason == nil; reason.font = .preferredFont(forTextStyle: .footnote); reason.textColor = .secondaryLabel; reason.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [titleRow(target, location, staticIcon: item.icon, staticBadge: sourceBadgeText), bar, text, reason]); stack.axis = .vertical; stack.spacing = 12
        let card = InterfaceStyle.card(); pin(stack, in: card, padding: 18); return card
    }
    /// Earlier turns go above the live question, answer and follow-ups (the last views in the thread).
    private func appendToThread(_ turn: UIView) { threadStack.insertArrangedSubview(turn, at: threadStack.arrangedSubviews.count - Self.liveThreadViews) }
    /// Freezes the current question and answer into the thread so the conversation can go on below them.
    private func archiveLiveTurn() {
        typingTimer?.invalidate()
        if !questionRow.isHidden, let q = questionBubble.text { appendToThread(userTurn(q)) }
        if !chatCard.isHidden { appendToThread(answerTurn(InterpretationStore.shared.value)) }
        questionRow.isHidden = true; chatCard.isHidden = true
    }
    private func clearThread() { threadStack.arrangedSubviews.dropLast(Self.liveThreadViews).forEach { $0.removeFromSuperview() } }
    private func scrollThreadToBottom() {
        view.layoutIfNeeded()
        let bottom = max(0, threadScroll.contentSize.height - threadScroll.bounds.height + threadScroll.adjustedContentInset.bottom)
        threadScroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: true)
    }
    /// After the user answers, the conversation continues: the input is cleared and ready for the next question.
    private func continueConversation() { questionField.text = ""; questionField.becomeFirstResponder() }
    // MARK: History
    private func openHistory() {
        view.endEditing(true)
        let history = HistoryViewController(); history.modalPresentationStyle = .overFullScreen
        history.onSelect = { [weak self] entry in self?.showPast(entry) }
        present(history, animated: false)
    }
    /// Shows a past answer as a conversation in the Chat display, read-only.
    private func showPast(_ entry: HistoryEntry) {
        modeControl.selectedSegmentIndex = Mode.chat.rawValue; mode = .chat; clearThread(); resetTrial()
        var item = AIInterpretation(); item.question = entry.question; item.interpretedTarget = entry.object; item.interpretedLocation = entry.location
        item.explanation = entry.explanation; item.icon = entry.icon; item.reason = entry.reason; item.confidence = entry.confidence
        item.confidenceScore = ["High": 0.85, "Medium": 0.6, "Low": 0.3][entry.confidence]
        InterpretationStore.shared.value = item; answerSource = entry.source; refreshInterpretation()
        let when = DateFormatter.localizedString(from: entry.date, dateStyle: .medium, timeStyle: .short)
        chatReason.text = (entry.reason.map { "Why: \($0)\n" } ?? "") + "\(entry.response ?? "No response") · \(entry.display) · \(when)"; chatReason.isHidden = false
        questionBubble.text = entry.question; questionRow.isHidden = false; chatCard.isHidden = false; scrollThreadToBottom()
        responseButtonViews.forEach { $0.isHidden = true }; updateSuggestions()
    }
    /// Reveals the answer sentence a few characters at a time, as chat apps stream their replies.
    private func typeOut(_ label: UILabel) {
        typingTimer?.invalidate()
        guard let full = label.text, !full.isEmpty else { return }
        var shown = 0; label.text = ""
        typingTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak label] timer in
            shown = min(shown + 2, full.count); label?.text = String(full.prefix(shown))
            if shown == full.count { timer.invalidate() }
        }
    }
    private func showMessage(_ text: String) { hint.text = text; hint.isHidden = false; arButtons.isHidden = true; arActions.isHidden = false; updateSuggestions() }
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
        let dot = ModelEntity(mesh: .generateSphere(radius: 0.012), materials: [UnlitMaterial(color: InterfaceStyle.accent)]); dot.position = [0, 0.07, 0]
        let connector = ModelEntity(mesh: .generateBox(size: [0.004, 0.20, 0.004]), materials: [UnlitMaterial(color: InterfaceStyle.accent)]); connector.position = [0, 0.17, 0]
        let p = Entity(); p.position = [0, 0.32, 0]
        // Dashed ring on the surface around the object (the dashed outline in the design), so it is clear which object the card belongs to.
        for i in 0..<20 {
            let angle = Float(i) / 20 * 2 * .pi
            let dash = ModelEntity(mesh: .generateSphere(radius: 0.004), materials: [UnlitMaterial(color: .white)]); dash.position = [0.07 * cos(angle), 0.003, 0.07 * sin(angle)]; anchor.addChild(dash)
        }
        let background = ModelEntity(mesh: .generateBox(size: [0.30, 0.13, 0.008], cornerRadius: 0.02), materials: [UnlitMaterial(color: InterfaceStyle.panel)])
        let title = textEntity(item.interpretedTarget, size: 0.026, weight: .bold, color: UIColor(white: 0.12, alpha: 1)); title.position.y += 0.038
        let subtitle = textEntity(item.interpretedLocation, size: 0.016, weight: .regular, color: UIColor(white: 0.42, alpha: 1)); subtitle.position.y += 0.008
        var parts: [Entity] = [background, title, subtitle] + confidenceEntities(item, y: -0.022)
        if let badge = sourceBadgeText { let b = textEntity(badge, size: 0.011, weight: .semibold, color: InterfaceStyle.accent); b.position.y -= 0.048; parts.append(b) }
        parts.forEach { p.addChild($0) }; [dot, connector, p].forEach { anchor.addChild($0) }
        arView.scene.addAnchor(anchor); worldAnchor = anchor; panel = p
        // Keep the panel upright and facing the camera.
        if billboard == nil { billboard = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            guard let self, let p = self.panel else { return }
            let x = p.position(relativeTo: nil); var c = self.arView.cameraTransform.translation; c.y = x.y
            guard simd_distance(c, x) > 0.01 else { return }
            p.look(at: c, from: x, upVector: [0, 1, 0], relativeTo: nil) } }
    }
    /// The confidence bar in 3D. The panel's -Z faces the camera, so the viewer's left is local +x: the bar fills from +x towards -x.
    private func confidenceEntities(_ item: AIInterpretation, y: Float) -> [Entity] {
        guard let score = item.confidenceScore else {
            let caption = textEntity(item.confidence, size: 0.012, weight: .medium, color: UIColor(white: 0.42, alpha: 1)); caption.position.y += y; return [caption]
        }
        let width: Float = 0.17, left: Float = 0.12, filled = max(width * Float(min(max(score, 0), 1)), 0.009)
        let track = ModelEntity(mesh: .generateBox(size: [width, 0.005, 0.005], cornerRadius: 0.0025), materials: [UnlitMaterial(color: InterfaceStyle.track)])
        track.position = [left - width / 2, y, -0.007]
        let fill = ModelEntity(mesh: .generateBox(size: [filled, 0.009, 0.009], cornerRadius: 0.0045), materials: [UnlitMaterial(color: InterfaceStyle.accent)])
        fill.position = [left - filled / 2, y, -0.009]
        let percent = textEntity("\(Int((score * 100).rounded()))%", size: 0.013, weight: .medium, color: UIColor(white: 0.25, alpha: 1)); percent.position.x -= 0.09; percent.position.y += y
        return [track, fill, percent]
    }
    private func removePanel(){if let worldAnchor{arView.scene.removeAnchor(worldAnchor)};worldAnchor = nil;panel = nil}
    /// Text centred on its parent. look(at:) points the panel's -Z at the camera, while generated text faces +Z, so it is turned around.
    private func textEntity(_ string:String,size:CGFloat,weight:UIFont.Weight,color:UIColor)->ModelEntity {
        let mesh = MeshResource.generateText(string, extrusionDepth: 0.001, font: .systemFont(ofSize: size, weight: weight))
        let e = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: color)]); e.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        let c = mesh.bounds.center; e.position = [c.x, -c.y, -0.005]; return e
    }
    // MARK: Responses
    @objc private func confirm(){if !liveMode{InterpretationStore.shared.record(condition:mode.condition,outcome:"confirm",selectedIntendedTarget:false,placement:placement,source:answerSource,start:resultShownAt)};if let id = currentHistoryID { HistoryStore.shared.setResponse("Confirmed", for: id) };responseButtonViews.forEach{$0.isHidden = true}
        guard liveMode else { showCompletion("Response saved."); return }
        let object = InterpretationStore.shared.value.interpretedTarget
        if mode == .chat { archiveLiveTurn(); appendToThread(userTurn("✓ That's right")); appendToThread(assistantTurn("Great, glad that's the one. What else can I help you find?")) }
        else { showMessage("Great, glad that's the one. Ask me anything else.") }
        showFollowUps(about: object); scrollThreadToBottom(); continueConversation()
    }
    /// Scripted: the study's fixed object list. Live: the objects detected in view (there is no predefined intended target).
    @objc private func correct(sender:UIButton){let options = liveMode && !visibleObjects.isEmpty ? visibleObjects : AIInterpretation.sceneObjects;let a=UIAlertController(title:"Which object do you mean?",message:nil,preferredStyle:.actionSheet);options.forEach{option in a.addAction(UIAlertAction(title:option,style:.default){_ in if !self.liveMode{InterpretationStore.shared.record(condition:self.mode.condition,outcome:"correct",selectedObject:option,selectedIntendedTarget:!self.liveMode && option == AIInterpretation.intendedObject,placement:self.placement,source:self.answerSource,start:self.resultShownAt)};if let id = self.currentHistoryID { HistoryStore.shared.setResponse("Corrected to \(option)", for: id) };self.respondToCorrection(option)})};a.addAction(UIAlertAction(title:"Cancel",style:.cancel));a.popoverPresentationController?.sourceView = sender;present(a,animated:true)}
    /// A correction: in Chat the wrong answer stays in the thread, the user's correction follows, then the corrected answer.
    private func respondToCorrection(_ option: String) {
        guard liveMode else { applyCorrection(option); showCompletion("Understood. You mean the \(option.lowercased())."); return }
        if mode == .chat {
            archiveLiveTurn(); appendToThread(userTurn("Not this one. I meant the \(option.lowercased())."))
            applyCorrection(option); chatCard.isHidden = false
        } else { applyCorrection(option); showMessage("Got it, the \(option.lowercased()). Ask me anything else.") }
        showFollowUps(about: option); scrollThreadToBottom(); continueConversation()
    }
    private func showCompletion(_ message:String){let a=UIAlertController(title:"✓",message:message,preferredStyle:.alert);a.addAction(UIAlertAction(title:"Continue",style:.default));present(a,animated:true)}
    /// After a correction the answer shows the chosen object — name, icon, and (when it can be found in view) its location and anchor.
    /// The record has already been saved with the AI's original interpretation.
    private func applyCorrection(_ option: String) {
        responseButtonViews.forEach { $0.isHidden = true }; typingTimer?.invalidate()
        let label = SpatialQuery.cocoLabel(forName: option), referenceLabel = liveMode ? liveReference?.label : "coffee machine", referenceName = liveMode ? liveReference?.name : "coffee machine"
        var corrected = InterpretationStore.shared.value
        corrected.interpretedTarget = option; corrected.icon = SpatialQuery.icon(forName: option, label: label); corrected.confidence = "Confirmed by you"; corrected.confidenceScore = nil; corrected.reason = nil
        // Scripted: the study's intended target has a known location; anything else is located below if it is in view.
        let known = !liveMode && option == AIInterpretation.intendedObject
        corrected.interpretedLocation = known ? "Left side of coffee machine" : "Location not detected"
        corrected.explanation = known ? "Got it — you mean the \(option.lowercased()) on the left side of your coffee machine." : "Got it — you mean the \(option.lowercased())."
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
