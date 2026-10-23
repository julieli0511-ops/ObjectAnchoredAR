import ARKit
import UIKit

/// The assistant flow: interpreting the question (on-device rules, the vision model, or the scripted Evaluation answer),
/// finding the object in the camera view, and asking which one the user means when unsure.
extension ViewController {
    func showResult(){
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
    func startAnalyzing(_ title: String, detail: String) {
        analyzingTitle = title; analyzingDetail = detail; analyzingStart = Date()
        focus.isHidden = false; analyzingCard.isHidden = false; thinkingDots.start(); updateAnalyzingLabel(); updateSuggestions()
        analyzingTimer?.invalidate(); analyzingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.updateAnalyzingLabel() }
    }
    func updateAnalyzingLabel() {
        guard !analyzingCard.isHidden else { analyzingTimer?.invalidate(); analyzingTimer = nil; return }
        let seconds = Int(Date().timeIntervalSince(analyzingStart))
        loadingLabel.text = analyzingTitle + (seconds > 0 ? " \(seconds) s" : "") + (analyzingDetail.isEmpty ? "" : "\n" + analyzingDetail)
    }
    @objc func cancelAnalyzing() { vlm.cancel(); resetTrial(); showMessage("Cancelled. Ask again when you're ready.") }
    /// Runs detection over a few frames (~3 s) until `found` accepts them; calls back with that frame, or nil if nothing was found.
    func detect(attempt: Int = 0, until found: @escaping ([ObjectLocator.Detection]) -> Bool, completion: @escaping (ARFrame?, [ObjectLocator.Detection]) -> Void) {
        let retry = { [weak self] in
            guard attempt < 10 else { completion(nil, []); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.detect(attempt: attempt + 1, until: found, completion: completion) }
        }
        guard let frame = arView.session.currentFrame else { retry(); return }
        locator.detect(in: frame) { detections in found(detections) ? completion(frame, detections) : retry() }
    }
    /// Where the object stands: the surface under it, or else whatever is behind its centre.
    func worldPosition(of d: ObjectLocator.Detection, in frame: ARFrame) -> SIMD3<Float>? {
        let hit = arView.session.raycast(frame.raycastQuery(from: d.base, allowing: .estimatedPlane, alignment: .horizontal)).first
            ?? arView.session.raycast(frame.raycastQuery(from: d.center, allowing: .estimatedPlane, alignment: .any)).first
        return hit.map { t in [t.worldTransform.columns.3.x, t.worldTransform.columns.3.y, t.worldTransform.columns.3.z] }
    }
    /// Live modes: when several objects fit or the assistant is unsure, it asks instead of guessing.
    /// The candidates are numbered left to right on the camera view.
    func askWhichOne(_ candidates: [ObjectLocator.Detection], name: String, frame: ARFrame, choose: @escaping (ObjectLocator.Detection) -> Void) {
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
    func showHighlights(_ items: [(box: CGRect, label: String)], in frame: ARFrame) {
        clearHighlights()
        let size = arView.bounds.size, t = frame.displayTransform(for: .portrait, viewportSize: size)
        for item in items {
            // Upright image → sensor image (as in ObjectLocator) → normalized view coordinates → points.
            let a = CGPoint(x: item.box.minY, y: 1 - item.box.minX).applying(t), b = CGPoint(x: item.box.maxY, y: 1 - item.box.maxX).applying(t)
            let r = CGRect(x: min(a.x, b.x) * size.width, y: min(a.y, b.y) * size.height, width: abs(b.x - a.x) * size.width, height: abs(b.y - a.y) * size.height)
            let outline = CAShapeLayer(); outline.path = UIBezierPath(roundedRect: r, cornerRadius: 10).cgPath; outline.fillColor = nil
            outline.strokeColor = UIColor.white.cgColor; outline.lineWidth = 3; outline.lineDashPattern = [8, 6]
            outline.shadowColor = UIColor.black.cgColor; outline.shadowOpacity = 0.4; outline.shadowRadius = 2; outline.shadowOffset = .zero
            highlightOverlay.layer.addSublayer(outline)
            let tag = UILabel(frame: CGRect(x: min(max(r.minX - 8, 4), size.width - 32), y: min(max(r.minY - 14, 4), size.height - 32), width: 28, height: 28))  // kept on screen
            tag.text = item.label; tag.font = .boldSystemFont(ofSize: 17)
            tag.textAlignment = .center; tag.textColor = .white; tag.backgroundColor = InterfaceStyle.accent; tag.layer.cornerRadius = 14; tag.clipsToBounds = true; highlightOverlay.addSubview(tag)
        }
    }
    /// Remove the number tags as views first, then only the outline layers. Removing every sublayer would also pull the tags'
    /// layers out from under UIKit and crash (EXC_BAD_ACCESS).
    func clearHighlights() {
        highlightOverlay.subviews.forEach { $0.removeFromSuperview() }
        highlightOverlay.layer.sublayers?.filter { $0 is CAShapeLayer }.forEach { $0.removeFromSuperlayer() }
    }
    /// Live (VLM): the vision-language model on the computer decides what the question means; YOLO, run on the same frame, refines the box.
    /// If the server can't be reached, the user is told and chooses what to do; it never silently answers on-device.
    func interpretVLM(then finish: @escaping (SIMD3<Float>?) -> Void) {
        let question = InterpretationStore.shared.value.question, current = trial
        guard let frame = arView.session.currentFrame else { endTrial(with: "The camera isn't ready yet. Point it at the scene and ask again."); return }
        answerSource = "vlm"; liveReference = nil
        // Fail fast: a 5 s reachability check first, so an unreachable computer is reported in seconds, not after the 60 s request timeout.
        VLMClient.checkServer { [weak self] reachable, message in
            guard let self, current == self.trial else { return }
            guard reachable else { self.vlmUnavailable(message: message, then: finish); return }
            self.askVLM(question: question, frame: frame, then: finish)
        }
    }
    func askVLM(question: String, frame: ARFrame, then finish: @escaping (SIMD3<Float>?) -> Void) {
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
                    interpretation.confidenceScore = ["High": 0.85, "Medium": 0.6, "Low": 0.3][confidence]; interpretation.scoreName = "Confidence ≈"
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
    func interpretLive(then finish: @escaping (SIMD3<Float>?) -> Void) {
        let question = InterpretationStore.shared.value.question, current = trial
        let query = SpatialQuery(question); liveReference = query.reference
        guard !query.needsVisionModel else {
            endTrial(with: "On-device mode can't tell which tool suits that task. Switch to ⚙️ → Vision model, or name the object, e.g. Where is the spoon?"); return
        }
        detect(until: { query.resolve($0) != nil }) { [weak self] frame, detections in
            guard let self, current == self.trial else { return }
            guard let frame, let resolved = query.resolve(detections) else {
                self.endTrial(with: query.target.map { "Couldn't find a \($0.name) in view. Point the camera at it and ask again." }
                              ?? "Couldn't recognise anything in view. On-device mode knows: \(SpatialQuery.knownObjects).")
                return
            }
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
    func locate<T>(attempt: Int = 0, lastPick: T? = nil, pick: @escaping ([ObjectLocator.Detection]) -> (ObjectLocator.Detection, T)?, completion: @escaping (T?, SIMD3<Float>?) -> Void) {
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
    /// Checks the vision-model server. Quiet on success when it runs automatically after choosing the vision model.
    func testVLMConnection(quietOnSuccess: Bool = false) {
        VLMClient.checkServer { [weak self] ok, message in
            if ok && quietOnSuccess { return }
            let a = UIAlertController(title: ok ? "✓ Vision model ready" : "✗ Vision model not reachable", message: "\(message)\n\nServer: \(VLMClient.serverURL)", preferredStyle: .alert)
            if !ok { a.addAction(UIAlertAction(title: "Server settings…", style: .default) { _ in self?.editVLMServer() }) }
            a.addAction(UIAlertAction(title: "OK", style: .cancel)); self?.present(a, animated: true)
        }
    }
    /// Says plainly that the vision model could not be reached, instead of silently answering with the rules.
    func vlmUnavailable(_ error: Error, then finish: @escaping (SIMD3<Float>?) -> Void) { vlmUnavailable(message: VLMClient.describe(error), then: finish) }
    static let vlmChecklist = "Check that Ollama is running and exposed to the network, that the iPhone and the computer are on the same Wi-Fi, "
        + "and that Local Network access is on (Settings → Privacy & Security → Local Network). "
        + "Some school and office networks block devices from reaching each other; a personal hotspot avoids that."
    func vlmUnavailable(message: String, then finish: @escaping (SIMD3<Float>?) -> Void) {
        let current = trial
        let a = UIAlertController(title: "Can't reach the vision model", message: "\(message)\n\nServer: \(VLMClient.serverURL)\n" + Self.vlmChecklist, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Answer on-device this time", style: .default) { [weak self] _ in
            guard let self, current == self.trial else { return }; self.answerSource = "live"; self.interpretLive(then: finish) })
        a.addAction(UIAlertAction(title: "Server settings…", style: .default) { [weak self] _ in self?.endTrial(with: "The vision model was not reached. Check the server, then ask again."); self?.editVLMServer() })
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in self?.endTrial(with: "The vision model was not reached.") })
        present(a, animated: true)
    }
    func editVLMServer() {
        let a = UIAlertController(title: "VLM server", message: "Ollama on a computer on the same Wi-Fi, e.g. http://my-mac.local:11434", preferredStyle: .alert)
        a.addTextField { $0.text = VLMClient.serverURL; $0.keyboardType = .URL; $0.autocapitalizationType = .none; $0.autocorrectionType = .no }
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        a.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in VLMClient.serverURL = a.textFields?.first?.text ?? ""; self?.updateSettingsMenu(); self?.testVLMConnection() })
        present(a, animated: true)
    }
}
