import UIKit

/// The conversation: showing an answer, the Chat thread, suggested and follow-up questions, history, and the user's responses.
extension ViewController {
    func present(at position: SIMD3<Float>?, placement: String) {
        switch mode {
        case .chat:
            questionBubble.text = InterpretationStore.shared.value.question; questionRow.isHidden = false; chatCard.isHidden = false; if liveMode { typeOut(chatText) }; scrollThreadToBottom()
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
    /// Example questions. On-device only suggests what its rules and detector can answer; the vision model adds open-ended ones.
    static let findQuestions = ["Where is my cup?", "Can you find the water bottle?", "Where is the bowl next to the sink?", "Is there a knife on the counter?"]
    static let taskQuestions = ["What can I use to stir my soup?", "I need to cut some bread.", "Where can I reheat my leftovers?", "I want to wash the vegetables.", "What should I use to mix the eggs?"]
    static let otherQuestions = ["What is this?", "I want something to drink."]
    static let visionFind = ["Where is the wooden spoon?", "What is next to the coffee machine?", "What's in the utensil holder?"]
    static let visionTask = ["Which tool should I use to flip a pancake?", "What can I use to drain the pasta?", "I want to make coffee. What do I need?",
                                     "What should I use to grate cheese?", "What can I use to open this jar?", "What can I use to serve the soup?"]
    /// A fresh mix each launch and whenever the assistant changes: one find question, one task question, one more at random.
    func refreshSuggestions() {
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
    func questionChip(_ text: String, symbol: String) -> UIButton {
        var c = UIButton.Configuration.filled(); c.title = text; c.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium))
        c.imagePadding = 10; c.cornerStyle = .capsule; c.baseBackgroundColor = UIColor.white.withAlphaComponent(0.9); c.baseForegroundColor = InterfaceStyle.ink
        c.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 14, bottom: 9, trailing: 16)
        c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { var a = $0; a.font = .systemFont(ofSize: 15); return a }
        return UIButton(configuration: c, primaryAction: UIAction { [weak self] _ in self?.questionField.text = text; self?.sendQuestion() })
    }
    /// Questions that carry the topic on after the user confirms or corrects an answer. On-device only offers ones its rules can answer.
    func followUpQuestions(about object: String) -> [String] {
        let name = object.lowercased(), label = SpatialQuery.cocoLabel(forName: object), known = label != "other"
        let neighbour = visibleObjects.map { $0.lowercased() }.first { $0 != name && SpatialQuery.cocoLabel(forName: $0) != label && SpatialQuery.cocoLabel(forName: $0) != "other" }
        var questions: [String] = []
        if source == .vlm { questions += ["What can I use the \(name) for?", "What is next to the \(name)?"] }
        if known || source == .vlm { questions.append("Is there another \(name)?") }
        if known, let neighbour { questions.append("Find the \(neighbour) next to the \(name).") }
        if let task = SpatialQuery.taskQuestion(for: label) { questions.append(task) }
        return Array(questions.prefix(3))
    }
    func showFollowUps(about object: String) {
        let questions = followUpQuestions(about: object), row = mode == .chat ? followUpRow : arFollowUps
        row.arrangedSubviews.forEach { $0.removeFromSuperview() }
        questions.forEach { row.addArrangedSubview(questionChip($0, symbol: "arrow.turn.down.right")) }
        row.isHidden = questions.isEmpty
    }
    /// Suggestions only when the screen is otherwise empty, in the assistant modes.
    func updateSuggestions() {
        let idle = chatCard.isHidden && screenCard.isHidden && analyzingCard.isHidden && arActions.isHidden && worldAnchor == nil && !awaitingTap
        suggestions.isHidden = !(liveMode && idle && !threadHasHistory)
    }
    // MARK: Conversation
    func styleUserBubble(_ bubble: PillLabel) {
        bubble.backgroundColor = InterfaceStyle.userBubble; bubble.font = .systemFont(ofSize: 16); bubble.numberOfLines = 0; bubble.layer.cornerRadius = 18
    }
    /// Wraps a bubble in a full-width row, pinned right (the user) or left (the assistant) with room on the other side.
    func place(_ bubble: UIView, in row: UIView, trailing: Bool) {
        bubble.translatesAutoresizingMaskIntoConstraints = false; row.addSubview(bubble)
        NSLayoutConstraint.activate([bubble.topAnchor.constraint(equalTo: row.topAnchor), bubble.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            trailing ? bubble.trailingAnchor.constraint(equalTo: row.trailingAnchor) : bubble.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            trailing ? bubble.leadingAnchor.constraint(greaterThanOrEqualTo: row.leadingAnchor, constant: 56) : bubble.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -40)])
    }
    func userTurn(_ text: String) -> UIView {
        let bubble = PillLabel(); styleUserBubble(bubble); bubble.text = text; let row = UIView(); place(bubble, in: row, trailing: true); return row
    }
    func assistantTurn(_ text: String) -> UIView {
        let bubble = PillLabel(); bubble.text = text; bubble.font = .systemFont(ofSize: 16); bubble.numberOfLines = 0; bubble.layer.cornerRadius = 18
        bubble.backgroundColor = UIColor.white.withAlphaComponent(0.92); let row = UIView(); place(bubble, in: row, trailing: false); return row
    }
    /// A fixed copy of an answer card for an earlier turn.
    func answerTurn(_ item: AIInterpretation) -> UIView {
        let target = UILabel(), location = UILabel(), text = UILabel(), bar = ConfidenceBar(), reason = UILabel()
        target.text = item.interpretedTarget; location.text = item.interpretedLocation; text.text = item.explanation; text.numberOfLines = 0; text.font = .systemFont(ofSize: 17)
        bar.set(item.confidenceScore, caption: item.confidence, name: item.scoreName)
        reason.text = item.reason.map { "Why: \($0)" }; reason.isHidden = item.reason == nil
        reason.font = .preferredFont(forTextStyle: .footnote); reason.textColor = .secondaryLabel; reason.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [titleRow(target, location, staticIcon: item.icon, staticBadge: sourceBadgeText), bar, text, reason]); stack.axis = .vertical; stack.spacing = 12
        let card = InterfaceStyle.card(); pin(stack, in: card, padding: 18); return card
    }
    /// Earlier turns go above the live question, answer and follow-ups (the last views in the thread).
    func appendToThread(_ turn: UIView) { threadStack.insertArrangedSubview(turn, at: threadStack.arrangedSubviews.count - Self.liveThreadViews) }
    /// Freezes the current question and answer into the thread so the conversation can go on below them.
    func archiveLiveTurn() {
        typingTimer?.invalidate()
        if !questionRow.isHidden, let q = questionBubble.text { appendToThread(userTurn(q)) }
        if !chatCard.isHidden { appendToThread(answerTurn(InterpretationStore.shared.value)) }
        questionRow.isHidden = true; chatCard.isHidden = true
    }
    func clearThread() { threadStack.arrangedSubviews.dropLast(Self.liveThreadViews).forEach { $0.removeFromSuperview() } }
    func scrollThreadToBottom() {
        view.layoutIfNeeded()
        let bottom = max(0, threadScroll.contentSize.height - threadScroll.bounds.height + threadScroll.adjustedContentInset.bottom)
        threadScroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: true)
    }
    /// After the user answers, the conversation continues: the input is cleared and ready for the next question.
    func continueConversation() { questionField.text = ""; questionField.becomeFirstResponder() }
    // MARK: History
    func openHistory() {
        view.endEditing(true)
        let history = HistoryViewController(); history.modalPresentationStyle = .overFullScreen
        history.onSelect = { [weak self] entry in self?.showPast(entry) }
        present(history, animated: false)
    }
    /// Shows a past answer as a conversation in the Chat display, read-only.
    func showPast(_ entry: HistoryEntry) {
        modeControl.selectedSegmentIndex = Mode.chat.rawValue; mode = .chat; clearThread(); resetTrial()
        var item = AIInterpretation(); item.question = entry.question; item.interpretedTarget = entry.object; item.interpretedLocation = entry.location
        item.explanation = entry.explanation; item.icon = entry.icon; item.reason = entry.reason; item.confidence = entry.confidence
        item.confidenceScore = ["High": 0.85, "Medium": 0.6, "Low": 0.3][entry.confidence]
        item.scoreName = entry.source == "live" ? "Detection ≈" : "Confidence ≈"  // history keeps only high / medium / low
        InterpretationStore.shared.value = item; answerSource = entry.source; refreshInterpretation()
        let when = DateFormatter.localizedString(from: entry.date, dateStyle: .medium, timeStyle: .short)
        chatReason.text = (entry.reason.map { "Why: \($0)\n" } ?? "") + "\(entry.response ?? "No response") · \(entry.display) · \(when)"; chatReason.isHidden = false
        questionBubble.text = entry.question; questionRow.isHidden = false; chatCard.isHidden = false; scrollThreadToBottom()
        responseButtonViews.forEach { $0.isHidden = true }; updateSuggestions()
    }
    /// Reveals the answer sentence a few characters at a time, as chat apps stream their replies.
    func typeOut(_ label: UILabel) {
        typingTimer?.invalidate()
        guard let full = label.text, !full.isEmpty else { return }
        var shown = 0; label.text = ""
        typingTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak label] timer in
            shown = min(shown + 2, full.count); label?.text = String(full.prefix(shown))
            if shown == full.count { timer.invalidate() }
        }
    }
    func showMessage(_ text: String) { hint.text = text; hint.isHidden = false; arButtons.isHidden = true; arActions.isHidden = false; updateSuggestions() }
    func endTrial(with message: String) { focus.isHidden = true; analyzingCard.isHidden = true; showMessage(message) }
    // MARK: Responses
    @objc func confirm() {
        if !liveMode {
            InterpretationStore.shared.record(condition: mode.condition, outcome: "confirm", selectedIntendedTarget: false,
                                              placement: placement, source: answerSource, start: resultShownAt)
        }
        if let id = currentHistoryID { HistoryStore.shared.setResponse("Confirmed", for: id) }
        responseButtonViews.forEach { $0.isHidden = true }
        guard liveMode else { showCompletion("Response saved."); return }
        let object = InterpretationStore.shared.value.interpretedTarget
        if mode == .chat { archiveLiveTurn(); appendToThread(userTurn("✓ That's right")); appendToThread(assistantTurn("Great, glad that's the one. What else can I help you find?")) }
        else { showMessage("Great, glad that's the one. Ask me anything else.") }
        showFollowUps(about: object); scrollThreadToBottom(); continueConversation()
    }
    /// Scripted: the study's fixed object list. Live: the objects detected in view (there is no predefined intended target).
    @objc func correct(sender: UIButton) {
        let options = liveMode && !visibleObjects.isEmpty ? visibleObjects : AIInterpretation.sceneObjects
        let a = UIAlertController(title: "Which object do you mean?", message: nil, preferredStyle: .actionSheet)
        for option in options {
            a.addAction(UIAlertAction(title: option, style: .default) { _ in
                if !self.liveMode {
                    InterpretationStore.shared.record(condition: self.mode.condition, outcome: "correct", selectedObject: option,
                                                      selectedIntendedTarget: option == AIInterpretation.intendedObject,
                                                      placement: self.placement, source: self.answerSource, start: self.resultShownAt)
                }
                if let id = self.currentHistoryID { HistoryStore.shared.setResponse("Corrected to \(option)", for: id) }
                self.respondToCorrection(option)
            })
        }
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        a.popoverPresentationController?.sourceView = sender
        present(a, animated: true)
    }
    /// A correction: in Chat the wrong answer stays in the thread, the user's correction follows, then the corrected answer.
    func respondToCorrection(_ option: String) {
        guard liveMode else { applyCorrection(option); showCompletion("Understood. You mean the \(option.lowercased())."); return }
        if mode == .chat {
            archiveLiveTurn(); appendToThread(userTurn("Not this one. I meant the \(option.lowercased())."))
            applyCorrection(option); chatCard.isHidden = false
        } else { applyCorrection(option); showMessage("Got it, the \(option.lowercased()). Ask me anything else.") }
        showFollowUps(about: option); scrollThreadToBottom(); continueConversation()
    }
    func showCompletion(_ message: String) {
        let a = UIAlertController(title: "✓", message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Continue", style: .default)); present(a, animated: true)
    }
    /// After a correction the answer shows the chosen object — name, icon, and (when it can be found in view) its location and anchor.
    /// The record has already been saved with the AI's original interpretation.
    func applyCorrection(_ option: String) {
        responseButtonViews.forEach { $0.isHidden = true }; typingTimer?.invalidate()
        let label = SpatialQuery.cocoLabel(forName: option), referenceLabel = liveMode ? liveReference?.label : "laptop", referenceName = liveMode ? liveReference?.name : "laptop"
        var corrected = InterpretationStore.shared.value
        corrected.interpretedTarget = option; corrected.icon = SpatialQuery.icon(forName: option, label: label)
        corrected.confidence = "Confirmed by you"; corrected.confidenceScore = nil; corrected.reason = nil
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
