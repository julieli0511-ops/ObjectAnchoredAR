import CoreGraphics
import Foundation

/// Live mode: a rule-based stand-in for a language model. Understands questions shaped like
/// "the <object> [to the left of | right of | above | under | next to] <object>" for objects the detector knows (COCO labels),
/// and resolves them against the current detections. A question naming no known object ("What is this?") means the object
/// nearest the centre of the view. Unlike the scripted study mode, its answer depends on the real scene.
struct SpatialQuery {
    enum Relation { case left, right, above, below, near }
    struct Term { let name: String; let label: String }
    /// nil target: whatever is in the centre of the view.
    let target: Term?, reference: Term?, relation: Relation?

    /// Phrase the user may say → COCO label. Longer phrases are matched first ("coffee cup" before "cup").
    private static let vocabulary: [(String, String)] = [
        ("coffee cup","cup"),("mug","cup"),("cup","cup"),("water bottle","bottle"),("bottle","bottle"),("wine glass","wine glass"),("glass","wine glass"),
        ("laptop","laptop"),("computer","laptop"),("notebook","book"),("book","book"),("cell phone","cell phone"),("phone","cell phone"),("iphone","cell phone"),
        ("keyboard","keyboard"),("mouse","mouse"),("remote","remote"),("monitor","tv"),("tv","tv"),("scissors","scissors"),("clock","clock"),("vase","vase"),
        ("plant","potted plant"),("bowl","bowl"),("spoon","spoon"),("fork","fork"),("knife","knife"),("banana","banana"),("apple","apple"),("orange","orange"),
        ("carrot","carrot"),("broccoli","broccoli"),("sandwich","sandwich"),("pizza","pizza"),("donut","donut"),("cake","cake"),
        ("microwave","microwave"),("oven","oven"),("toaster","toaster"),("sink","sink"),("refrigerator","refrigerator"),("fridge","refrigerator"),
        ("table","dining table"),("chair","chair"),("sofa","couch"),("couch","couch"),("bed","bed"),
        ("backpack","backpack"),("handbag","handbag"),("bag","handbag"),("umbrella","umbrella"),("teddy bear","teddy bear"),("toothbrush","toothbrush"),
        ("ball","sports ball"),("person","person"),("dog","dog"),("cat","cat")
    ].sorted { $0.0.count > $1.0.count }
    static var knownObjects: String { Array(Set(vocabulary.map(\.0))).sorted().joined(separator: ", ") }

    /// SF Symbol for each COCO label. Labels without a close symbol use the nearest available one.
    static func icon(for label: String) -> String {
        [
            "cup":"cup.and.saucer.fill","bottle":"waterbottle.fill","wine glass":"wineglass.fill","laptop":"laptopcomputer","book":"book.closed.fill",
            "cell phone":"iphone","keyboard":"keyboard.fill","mouse":"computermouse.fill","remote":"appletvremote.gen4.fill","tv":"tv.fill",
            "scissors":"scissors","clock":"clock.fill","vase":"camera.macro","potted plant":"leaf.fill","bowl":"takeoutbag.and.cup.and.straw.fill",
            "spoon":"fork.knife","fork":"fork.knife","knife":"fork.knife","banana":"carrot.fill","apple":"apple.logo","orange":"carrot.fill",
            "carrot":"carrot.fill","broccoli":"leaf.fill","sandwich":"takeoutbag.and.cup.and.straw.fill","pizza":"takeoutbag.and.cup.and.straw.fill",
            "donut":"birthday.cake.fill","cake":"birthday.cake.fill","microwave":"microwave.fill","oven":"oven.fill","toaster":"oven.fill","sink":"sink.fill",
            "refrigerator":"refrigerator.fill","dining table":"table.furniture.fill","chair":"chair.fill","couch":"sofa.fill","bed":"bed.double.fill",
            "backpack":"backpack.fill","handbag":"handbag.fill","umbrella":"umbrella.fill","teddy bear":"teddybear.fill","toothbrush":"mouth.fill",
            "sports ball":"soccerball","person":"person.fill","dog":"dog.fill","cat":"cat.fill"
        ][label] ?? "cube.fill"
    }
    /// COCO label for a name shown to the user ("Coffee cup", "Notebook", "Cell phone").
    static func label(forName name: String) -> String {
        let n = name.lowercased(); return vocabulary.first { $0.0 == n }?.1 ?? n
    }
    static func displayName(for label: String) -> String { label.prefix(1).uppercased() + label.dropFirst() }

    init(_ question: String) {
        let text = question.lowercased()
        var taken: [Range<String.Index>] = [], found: [(Range<String.Index>, Term)] = []
        for (phrase, label) in Self.vocabulary {
            guard let regex = try? NSRegularExpression(pattern: "\\b\(NSRegularExpression.escapedPattern(for: phrase))s?\\b") else { continue }
            for m in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let r = Range(m.range, in: text), !taken.contains(where: { $0.overlaps(r) }) else { continue }
                taken.append(r); found.append((r, Term(name: phrase, label: label)))
            }
        }
        found.sort { $0.0.lowerBound < $1.0.lowerBound }
        guard let first = found.first else { target = nil; reference = nil; relation = nil; return }
        let second = found.dropFirst().first(where: { $0.1.label != first.1.label })
        target = first.1; reference = second?.1
        guard let second, second.0.lowerBound >= first.0.upperBound else { relation = second == nil ? nil : .near; return }
        // The relation words sit between the two objects: "cup [to the left of my] laptop".
        let between = String(text[first.0.upperBound..<second.0.lowerBound])
        if between.contains("left") { relation = .left }
        else if between.contains("right") { relation = .right }
        else if ["above", "on top", "over"].contains(where: between.contains) { relation = .above }
        else if ["under", "below", "beneath"].contains(where: between.contains) { relation = .below }
        else { relation = .near }
    }

    /// Picks the target instance that best satisfies the relation; if none does, the most confident one (its description will say where it really is).
    func resolve(_ detections: [ObjectLocator.Detection]) -> (target: ObjectLocator.Detection, reference: ObjectLocator.Detection?)? {
        guard let target else {
            let centre = { (d: ObjectLocator.Detection) in hypot(d.box.midX - 0.5, d.box.midY - 0.5) }
            return detections.min { centre($0) < centre($1) }.map { ($0, nil) }
        }
        let targets = detections.filter { $0.label == target.label }
        guard let best = targets.max(by: { $0.confidence < $1.confidence }) else { return nil }
        guard let reference, let relation, let ref = Self.mostConfident(reference.label, in: detections) else { return (best, nil) }
        let r = ref.box
        let matching = targets.filter { Self.satisfies($0, relation, ref) }
        let distance = { (t: ObjectLocator.Detection) in hypot(t.box.midX - r.midX, t.box.midY - r.midY) }
        return (matching.min { distance($0) < distance($1) } ?? best, ref)
    }
    /// Instances that answer the question equally well: those satisfying the relation, or every instance when there is none.
    /// Two or more means the question is ambiguous. Empty for "What is this?".
    func candidates(_ detections: [ObjectLocator.Detection]) -> [ObjectLocator.Detection] {
        guard let target else { return [] }
        let targets = detections.filter { $0.label == target.label }
        guard let reference, let relation, let ref = Self.mostConfident(reference.label, in: detections) else { return targets }
        return targets.filter { Self.satisfies($0, relation, ref) }
    }
    private static func satisfies(_ t: ObjectLocator.Detection, _ relation: Relation, _ ref: ObjectLocator.Detection) -> Bool {
        switch relation {
        case .left: return t.box.midX < ref.box.midX
        case .right: return t.box.midX > ref.box.midX
        case .above: return t.box.midY < ref.box.midY
        case .below: return t.box.midY > ref.box.midY
        case .near: return true
        }
    }
    static func mostConfident(_ label: String, in detections: [ObjectLocator.Detection]) -> ObjectLocator.Detection? {
        detections.filter { $0.label == label }.max { $0.confidence < $1.confidence }
    }

    /// Builds the interpretation from where the chosen object actually is, so a wrong pick is visible to the user.
    func interpretation(for question: String, target t: ObjectLocator.Detection, reference ref: ObjectLocator.Detection?) -> AIInterpretation {
        let name = target?.name ?? t.label
        let place = Self.describe(t, relativeTo: ref, named: reference?.name)
        var result = AIInterpretation()
        result.question = question; result.interpretedTarget = name.prefix(1).uppercased() + name.dropFirst(); result.interpretedLocation = place.location
        result.confidence = t.confidence >= 0.7 ? "High" : (t.confidence >= 0.4 ? "Medium" : "Low")
        result.confidenceScore = Double(t.confidence)
        result.explanation = "I think you are asking about the \(name) \(place.phrase)."
        result.icon = Self.icon(for: t.label)
        return result
    }
    /// Where `t` is, as a card title ("Left side of laptop") and as a sentence phrase ("on the left side of your laptop").
    static func describe(_ t: ObjectLocator.Detection, relativeTo ref: ObjectLocator.Detection?, named refName: String?) -> (location: String, phrase: String) {
        if let ref {
            let name = refName ?? ref.label, dx = t.box.midX - ref.box.midX, dy = t.box.midY - ref.box.midY
            if abs(dx) >= abs(dy) { let side = dx < 0 ? "left" : "right"; return ("\(side.capitalized) side of \(name)", "on the \(side) side of your \(name)") }
            return dy < 0 ? ("Above \(name)", "above your \(name)") : ("Below \(name)", "below your \(name)")
        }
        let x = t.box.midX
        if x < 0.33 { return ("Left side of view", "on the left side of the view") }
        if x > 0.66 { return ("Right side of view", "on the right side of the view") }
        return ("Center of view", "in the center of the view")
    }
}
