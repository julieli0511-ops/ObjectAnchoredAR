import ARKit
import Combine
import RealityKit
import UIKit

final class ViewController: UIViewController, ARSessionDelegate, UITextFieldDelegate {
    enum Mode: Int { case chat, screen, object; var condition: String { ["2D", "Screen-Fixed AR", "Object-Anchored AR"][rawValue] } }
    let arView = ARView(frame: .zero)
    let modeControl = UISegmentedControl(items: ["2D Chat", "Screen AR", "Object AR"])
    let composer = InterfaceStyle.card()
    let questionField = UITextField(), focus = UIView(); let modeDescription = PillLabel(), loadingLabel = UILabel()
    /// AR modes need world tracking before an answer can be placed in the scene; typing is always possible meanwhile.
    var trackingReady = !ARWorldTrackingConfiguration.isSupported
    static let scanMessage = "Move your phone slowly to scan the table."
    let sendButton = UIButton(type: .system)
    let analyzingCard = InterfaceStyle.card()
    // 2D: one conversational card with the buttons inside. Screen AR: compact card pinned to the top of the screen. Both AR modes share the bottom action stack.
    let chatCard = InterfaceStyle.card(), screenCard = InterfaceStyle.card()
    let chatConfidence = ConfidenceBar(), screenConfidence = ConfidenceBar()
    /// "Why: …" — the assistant's reason when it chose a tool for a task. Hidden when the question named the object (and in Evaluation mode).
    let chatReason = UILabel(), screenReason = UILabel()
    /// Chat display as a conversation: the user's question in a bubble on the right, the assistant's answer below it.
    let questionBubble = PillLabel(), questionRow = UIView()
    /// Chat display as a running conversation: earlier turns stay as static views above the live question and answer, and scroll.
    let threadScroll = UIScrollView(), threadStack = UIStackView()
    /// Follow-up questions after the user responds: the last view of the thread (Chat) or in the bottom stack (Screen/Object).
    let followUpRow = UIStackView(), arFollowUps = UIStackView()
    /// The live views at the end of the thread: question, answer, follow-ups. Earlier turns go above them.
    static let liveThreadViews = 3
    var threadHasHistory: Bool { threadStack.arrangedSubviews.count > Self.liveThreadViews }
    let thinkingDots = ThinkingDots()
    /// Example questions above the input box when nothing else is shown, as chat apps do on a new conversation.
    let suggestions = UIStackView()
    var currentHistoryID: UUID?, focusedOnLaunch = false
    var typingTimer: Timer?
    /// Hides the mode description 5 s after it was shown; replaced whenever the mode changes.
    var descriptionFade: DispatchWorkItem?
    let arActions = UIStackView(), arButtons = UIStackView(), hint = UILabel()
    let crosshair = UIImageView(image: UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 44, weight: .light)))
    let chatTarget = UILabel(), chatLocation = UILabel(), chatText = UILabel(), screenTarget = UILabel(), screenLocation = UILabel()
    /// AR modes: the interpreted object is located automatically; only if detection fails does the interpretation wait for a tap.
    var mode = Mode.chat, awaitingTap = false, resultShownAt = Date()
    /// Bumped on every reset so detection callbacks from an abandoned trial are ignored.
    var trial = 0, placement: String?
    let locator = ObjectLocator()
    /// Rules (default) / VLM: the assistant interprets the question from the camera view.
    /// Scripted = Evaluation mode: a fixed question and an intentionally wrong answer, for user testing whether people notice AI misunderstandings.
    enum Source { case scripted, rules, vlm }
    var source = Source.rules, visibleObjects: [String] = [], iconViews: [UIImageView] = [], responseButtonViews: [UIButton] = []
    /// Live: the reference object of the last question ("coffee machine"), used to describe where a corrected object is.
    var liveReference: SpatialQuery.Term?
    var liveMode: Bool { source != .scripted }
    /// What produced the current answer, for the study record: "scripted", "live" (rules) or "vlm". "live" after a VLM failure only when the user chose "Answer on-device this time".
    var answerSource = "scripted"
    var sourceBadges: [UILabel] = []
    /// Live modes only: shows what produced the answer. Hidden in the study, where participants must not learn the answer is scripted.
    var sourceBadgeText: String? {
        switch answerSource { case "vlm": return "● Vision model · Qwen2.5-VL"; case "live": return "● On-device"; default: return nil }
    }
    let vlm = VLMClient()
    /// "Analyzing" shows how long the user has waited (the vision model takes ~15 s) and can be cancelled.
    let cancelButton = UIButton(type: .system)
    var analyzingTimer: Timer?, analyzingStart = Date(), analyzingTitle = "", analyzingDetail = ""
    /// Dashed, numbered boxes drawn over the camera view when the assistant asks which object the user means.
    let highlightOverlay = UIView()
    var worldAnchor: AnchorEntity?, panel: Entity?, billboard: Cancellable?

    override func viewDidLoad() { super.viewDidLoad(); setupCameraUI(); configureSession(); updateSettingsMenu(); updateQuestionField(); updateInputAvailability() }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Ready to type straight away, as in chat apps.
        if !focusedOnLaunch && liveMode { focusedOnLaunch = true; questionField.becomeFirstResponder() }
    }
    func updateSettingsMenu() {
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
    func setSource(_ s: Source) {
        source = s; clearThread(); let question = InterpretationStore.shared.value.question
        InterpretationStore.shared.value = .sample; InterpretationStore.shared.value.question = question
        resetTrial(); updateModeDescription(); updateSettingsMenu(); updateQuestionField()
        if s == .vlm { testVLMConnection(quietOnSuccess: true) }
        refreshSuggestions()
    }
    /// Evaluation mode: every participant asks the same question, so it is pre-filled and locked (they only press send). Otherwise free input.
    func updateQuestionField() {
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
    func updateInputAvailability() {
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
    func setupCameraUI() {
        view.backgroundColor = .black
        add(arView); fill(arView, in: view)
        arView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleSceneTap(_:))))
        highlightOverlay.isUserInteractionEnabled = false
        add(highlightOverlay); fill(highlightOverlay, in: arView)

        // Display picker at the top.
        modeControl.selectedSegmentIndex = 0
        [(0, "message"), (1, "viewfinder"), (2, "mappin.and.ellipse")].forEach { modeControl.setImage(UIImage(systemName: $0.1), forSegmentAt: $0.0) }
        modeControl.backgroundColor = UIColor(white: 0.93, alpha: 0.95); modeControl.selectedSegmentTintColor = .white
        modeControl.setTitleTextAttributes([.foregroundColor: UIColor.secondaryLabel, .font: UIFont.systemFont(ofSize: 13, weight: .medium)], for: .normal)
        modeControl.setTitleTextAttributes([.foregroundColor: UIColor.label, .font: UIFont.systemFont(ofSize: 13, weight: .semibold)], for: .selected)
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        add(modeControl)
        let margins = view.layoutMarginsGuide
        NSLayoutConstraint.activate([
            modeControl.leadingAnchor.constraint(equalTo: margins.leadingAnchor), modeControl.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            modeControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12), modeControl.heightAnchor.constraint(equalToConstant: 48),
        ])
        modeDescription.textAlignment = .center; modeDescription.font = .preferredFont(forTextStyle: .footnote); modeDescription.numberOfLines = 0
        add(modeDescription)
        NSLayoutConstraint.activate([
            modeDescription.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            modeDescription.leadingAnchor.constraint(greaterThanOrEqualTo: margins.leadingAnchor), modeDescription.trailingAnchor.constraint(lessThanOrEqualTo: margins.trailingAnchor),
            modeDescription.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 8),
        ])
        updateModeDescription()

        // Input box: a capsule with the question field and a round send button, above the keyboard.
        questionField.placeholder = "Ask anything, e.g. What can I use to stir soup?"
        questionField.adjustsFontSizeToFitWidth = true; questionField.minimumFontSize = 13; questionField.font = .preferredFont(forTextStyle: .body)
        questionField.text = InterpretationStore.shared.value.question
        questionField.returnKeyType = .send; questionField.delegate = self
        questionField.addTarget(self, action: #selector(sendQuestion), for: .editingDidEndOnExit)
        composer.layer.cornerRadius = 27
        var send = UIButton.Configuration.filled()
        send.image = UIImage(systemName: "arrow.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold))
        send.cornerStyle = .capsule; send.baseBackgroundColor = InterfaceStyle.ink; send.baseForegroundColor = .white
        sendButton.configuration = send
        sendButton.configurationUpdateHandler = { b in b.configuration?.baseBackgroundColor = b.isEnabled ? InterfaceStyle.ink : UIColor(white: 0.8, alpha: 1) }
        sendButton.addTarget(self, action: #selector(sendQuestion), for: .touchUpInside)
        add(composer); add(questionField, to: composer.contentView); add(sendButton, to: composer.contentView)
        let box = composer.contentView
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: margins.leadingAnchor), composer.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            composer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12), composer.heightAnchor.constraint(equalToConstant: 54),
            questionField.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 20), questionField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            questionField.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            sendButton.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -9), sendButton.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 36), sendButton.heightAnchor.constraint(equalToConstant: 36),
        ])

        // Focus ring in the middle of the camera view while the assistant looks for the object.
        focus.layer.cornerRadius = 28; focus.layer.borderWidth = 3; focus.layer.borderColor = UIColor.white.cgColor; focus.isHidden = true
        add(focus)
        NSLayoutConstraint.activate([
            focus.centerXAnchor.constraint(equalTo: view.centerXAnchor), focus.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            focus.widthAnchor.constraint(equalToConstant: 56), focus.heightAnchor.constraint(equalToConstant: 56),
        ])

        // "Thinking" card: dots, elapsed time and Cancel.
        loadingLabel.textColor = .label; loadingLabel.font = .systemFont(ofSize: 15); loadingLabel.numberOfLines = 0
        loadingLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        cancelButton.setTitle("Cancel", for: .normal); cancelButton.tintColor = InterfaceStyle.accent
        cancelButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        cancelButton.setContentHuggingPriority(.required, for: .horizontal); cancelButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        cancelButton.addTarget(self, action: #selector(cancelAnalyzing), for: .touchUpInside)
        thinkingDots.setContentHuggingPriority(.required, for: .horizontal)
        let loadingStack = UIStackView(arrangedSubviews: [thinkingDots, loadingLabel, cancelButton])
        loadingStack.axis = .horizontal; loadingStack.alignment = .center; loadingStack.spacing = 12
        analyzingCard.isHidden = true
        add(analyzingCard); add(loadingStack, to: analyzingCard.contentView)
        let card = analyzingCard.contentView
        NSLayoutConstraint.activate([
            loadingStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18), loadingStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            loadingStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14), loadingStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            analyzingCard.leadingAnchor.constraint(equalTo: margins.leadingAnchor), analyzingCard.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            analyzingCard.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -14),
        ])
        setupInterpretationViews()
    }
    func setupInterpretationViews() {
        let margins = view.layoutMarginsGuide
        // Chat: the answer card in a scrolling conversation above the input box, with the response buttons inside the card.
        chatText.numberOfLines = 0; chatText.textColor = .label; chatText.font = .systemFont(ofSize: 17)
        [chatReason, screenReason].forEach { $0.font = .preferredFont(forTextStyle: .footnote); $0.textColor = .secondaryLabel; $0.numberOfLines = 0; $0.isHidden = true }
        let chatStack = UIStackView(arrangedSubviews: [titleRow(chatTarget, chatLocation), chatConfidence, chatText, chatReason, chipRow()])
        chatStack.axis = .vertical; chatStack.spacing = 12
        pin(chatStack, in: chatCard, padding: 18)
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
            threadScroll.leadingAnchor.constraint(equalTo: margins.leadingAnchor), threadScroll.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            threadScroll.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 8), threadScroll.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -10),
            // Short conversations rest on the input box, as in chat apps; longer ones scroll.
            threadStack.leadingAnchor.constraint(equalTo: content.leadingAnchor), threadStack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            threadStack.bottomAnchor.constraint(equalTo: content.bottomAnchor), threadStack.topAnchor.constraint(greaterThanOrEqualTo: content.topAnchor),
            threadStack.widthAnchor.constraint(equalTo: frame.widthAnchor), content.heightAnchor.constraint(greaterThanOrEqualTo: frame.heightAnchor), fillHeight,
        ])

        // Screen: compact card fixed near the top of the screen; it never moves with the scene.
        let screenStack = UIStackView(arrangedSubviews: [titleRow(screenTarget, screenLocation), screenReason, screenConfidence])
        screenStack.axis = .vertical; screenStack.spacing = 10
        pin(screenStack, in: screenCard, padding: 16); view.addSubview(screenCard)
        NSLayoutConstraint.activate([
            screenCard.leadingAnchor.constraint(equalTo: margins.leadingAnchor), screenCard.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            screenCard.topAnchor.constraint(equalTo: modeDescription.bottomAnchor, constant: 12),
        ])

        // Screen and Object: messages and buttons at the bottom, separate from the answer itself.
        hint.textColor = .label; hint.textAlignment = .center; hint.numberOfLines = 0; hint.font = .preferredFont(forTextStyle: .footnote)
        hint.backgroundColor = UIColor.white.withAlphaComponent(0.88); hint.layer.cornerRadius = 10; hint.clipsToBounds = true
        responseButtons().forEach(arButtons.addArrangedSubview)
        arButtons.axis = .horizontal; arButtons.distribution = .fillEqually; arButtons.spacing = 10
        [hint, arFollowUps, arButtons].forEach(arActions.addArrangedSubview)
        arActions.axis = .vertical; arActions.spacing = 10
        add(arActions)
        NSLayoutConstraint.activate([
            arActions.leadingAnchor.constraint(equalTo: margins.leadingAnchor), arActions.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            arActions.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -14),
        ])
        crosshair.tintColor = .white
        add(crosshair)
        NSLayoutConstraint.activate([crosshair.centerXAnchor.constraint(equalTo: view.centerXAnchor), crosshair.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
        [chatCard, screenCard, arActions, crosshair, questionRow].forEach { $0.isHidden = true }

        // Suggested questions above the input box.
        refreshSuggestions()
        suggestions.axis = .vertical; suggestions.alignment = .leading; suggestions.spacing = 8
        add(suggestions)
        NSLayoutConstraint.activate([
            suggestions.leadingAnchor.constraint(equalTo: margins.leadingAnchor), suggestions.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -14),
        ])
    }
    /// Adds a view for Auto Layout (to the main view unless another parent is given).
    func add(_ subview: UIView, to parent: UIView? = nil) {
        subview.translatesAutoresizingMaskIntoConstraints = false; (parent ?? view).addSubview(subview)
    }
    /// Pins all four edges of `subview` to `other`.
    func fill(_ subview: UIView, in other: UIView) {
        NSLayoutConstraint.activate([
            subview.leadingAnchor.constraint(equalTo: other.leadingAnchor), subview.trailingAnchor.constraint(equalTo: other.trailingAnchor),
            subview.topAnchor.constraint(equalTo: other.topAnchor), subview.bottomAnchor.constraint(equalTo: other.bottomAnchor),
        ])
    }
    /// `staticIcon` builds a fixed copy for an earlier turn of the conversation, which later answers must not update.
    func titleRow(_ target: UILabel, _ location: UILabel, staticIcon: String? = nil, staticBadge: String? = nil) -> UIStackView {
        let icon = UIImageView(image: UIImage(systemName: staticIcon ?? "waterbottle.fill") ?? UIImage(systemName: "cube.fill"))
        icon.tintColor = InterfaceStyle.accent; icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 30, weight: .medium)
        icon.contentMode = .scaleAspectFit
        icon.setContentHuggingPriority(.required, for: .horizontal); icon.setContentCompressionResistancePriority(.required, for: .horizontal)
        if staticIcon == nil { iconViews.append(icon) }
        target.font = .systemFont(ofSize: 18, weight: .bold); location.textColor = .secondaryLabel; location.font = .preferredFont(forTextStyle: .subheadline)
        let badge = UILabel(); badge.font = .systemFont(ofSize: 12, weight: .semibold); badge.textColor = InterfaceStyle.accent
        badge.text = staticBadge; badge.isHidden = staticBadge == nil
        if staticIcon == nil { sourceBadges.append(badge) }
        let labels = UIStackView(arrangedSubviews: [target, location, badge]); labels.axis = .vertical; labels.alignment = .leading
        let row = UIStackView(arrangedSubviews: [icon, labels]); row.axis = .horizontal; row.alignment = .center; row.spacing = 12
        return row
    }
    /// The response actions as a row of chips under the answer.
    func chipRow() -> UIStackView {
        let row = UIStackView(arrangedSubviews: responseButtons()); row.axis = .horizontal; row.distribution = .fillEqually; row.spacing = 10; return row
    }
    func responseButtons() -> [UIButton] {
        let confirmButton = InterfaceStyle.pillButton("That's right", symbol: "checkmark", filled: true)
        confirmButton.addTarget(self, action: #selector(confirm), for: .touchUpInside)
        let correctButton = InterfaceStyle.pillButton("Not this one", symbol: "pencil")
        correctButton.addTarget(self, action: #selector(correct(sender:)), for: .touchUpInside)
        responseButtonViews += [confirmButton, correctButton]
        return [confirmButton, correctButton]
    }
    func pin(_ content: UIView, in card: UIVisualEffectView, padding: CGFloat) {
        card.translatesAutoresizingMaskIntoConstraints = false; add(content, to: card.contentView)
        let box = card.contentView
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: padding), content.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -padding),
            content.topAnchor.constraint(equalTo: box.topAnchor, constant: padding), content.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -padding),
        ])
    }
    func refreshInterpretation() {
        let item = InterpretationStore.shared.value
        [chatTarget, screenTarget].forEach { $0.text = item.interpretedTarget }
        [chatLocation, screenLocation].forEach { $0.text = item.interpretedLocation }
        chatText.text = item.explanation
        iconViews.forEach { $0.image = UIImage(systemName: item.icon) ?? UIImage(systemName: "cube.fill") }
        sourceBadges.forEach { $0.text = sourceBadgeText; $0.isHidden = sourceBadgeText == nil }
        [chatConfidence, screenConfidence].forEach { $0.set(item.confidenceScore, caption: item.confidence, name: item.scoreName) }
        [chatReason, screenReason].forEach { $0.text = item.reason.map { "Why: \($0)" }; $0.isHidden = item.reason == nil }
    }
    func configureSession() {
        guard ARWorldTrackingConfiguration.isSupported else { return }
        arView.session.delegate = self; arView.session.run(ARWorldTrackingConfiguration())
    }
    @objc func modeChanged() { mode = Mode(rawValue: modeControl.selectedSegmentIndex) ?? .chat; resetTrial(); updateModeDescription() }
    /// Tells the user what each display is good for. Hidden in Evaluation mode, where it could steer participants.
    /// Shown for 5 seconds when a display is chosen (and at launch), then fades out so it does not cover the camera view.
    func updateModeDescription() {
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
    func resetTrial() {
        trial += 1; awaitingTap = false; placement = nil; typingTimer?.invalidate()
        [chatCard, screenCard, arActions, crosshair, focus, analyzingCard, questionRow, followUpRow, arFollowUps].forEach { $0.isHidden = true }
        threadScroll.isHidden = mode != .chat
        removePanel(); clearHighlights(); updateInputAvailability()
    }
    @objc func sendQuestion() {
        view.endEditing(true)
        guard sendButton.isEnabled else { return }
        let typed = (questionField.text ?? "").trimmingCharacters(in: .whitespaces)
        if liveMode && typed.isEmpty { showMessage("Type a question about something you see, e.g. Where is my cup?"); return }
        let question = questionField.text.flatMap { $0.isEmpty ? nil : $0 } ?? InterpretationStore.shared.value.question
        if liveMode {
            if mode == .chat { archiveLiveTurn() }
            questionField.text = ""
        } else {
            InterpretationStore.shared.value = .sample  // Evaluation mode: every trial starts from the same scripted answer
        }
        InterpretationStore.shared.value.question = question
        resetTrial()
        startAnalyzing(source == .vlm ? "Asking the vision model…" : "Thinking…", detail: mode != .chat || liveMode ? "Keep the camera pointed at the scene." : "")
        let current = trial
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, current == self.trial else { return }
            self.showResult()
        }
    }
}
