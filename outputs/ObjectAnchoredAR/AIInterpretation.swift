import Foundation

struct AIInterpretation {
    let question = "Can you find the cup to the left of my laptop?"
    let intendedTarget = "Coffee cup, left side of the laptop"
    var interpretedTarget = "Water bottle"
    var interpretedLocation = "Right side of the laptop"
    let confidence = "Medium"
    var text: String { "My interpretation:\nTarget object: \(interpretedTarget)\nLocation: \(interpretedLocation)\nConfidence: \(confidence)" }
    var matchesIntendedTarget: Bool { interpretedTarget == "Coffee cup" && interpretedLocation == "Left side of the laptop" }
    static let sample = AIInterpretation()
}
struct StudyRecord { let condition: String; let outcome: String; let selectedIntendedTarget: Bool; let elapsedSeconds: TimeInterval }
final class InterpretationStore { static let shared = InterpretationStore(); private init() {}; var value = AIInterpretation.sample; private(set) var records:[StudyRecord] = []; func record(condition:String,outcome:String,selectedIntendedTarget:Bool,start:Date){records.append(StudyRecord(condition:condition,outcome:outcome,selectedIntendedTarget:selectedIntendedTarget,elapsedSeconds:Date().timeIntervalSince(start))) } }
