import Foundation

struct AIInterpretation {
    var question = "Can you find the cup to the left of my laptop?"
    let intendedTarget = "Coffee cup, left side of the laptop"
    var interpretedTarget = "Water bottle"
    var interpretedLocation = "Right side of laptop"
    var confidence = "Medium"
    var explanation = "I think you are asking about the water bottle on the right side of your laptop."
    var icon = "waterbottle.fill"
    var text: String { "My interpretation:\nTarget object: \(interpretedTarget)\nLocation: \(interpretedLocation)\nConfidence: \(confidence)" }
    var matchesIntendedTarget: Bool { interpretedTarget == "Coffee cup" && interpretedLocation == "Left side of laptop" }
    static let sample = AIInterpretation()
    static let sceneObjects = ["Coffee cup", "Water bottle", "Laptop"]
    static let intendedObject = "Coffee cup"
    /// COCO label the on-device detector looks for to place the object-anchored card on the interpreted object.
    static let detectorLabel = "bottle"
}
struct StudyRecord: Codable { let condition: String; let userInput: String; let aiObject: String; let aiRelation: String; let userResponse: String; let selectedObject: String?; let selectedIntendedTarget: Bool; let elapsedSeconds: TimeInterval; let timestamp: Date; var targetPlacement: String? = nil; var interpretationSource: String? = nil }
final class InterpretationStore {
    static let shared = InterpretationStore(); private init() { records = Self.load() }
    var value = AIInterpretation.sample; private(set) var records:[StudyRecord] = []
    /// Documents/study_records.json — visible in the Files app (UIFileSharingEnabled).
    static let fileURL = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("study_records.json")
    func record(condition:String,outcome:String,selectedObject:String? = nil,selectedIntendedTarget:Bool,placement:String? = nil,source:String? = nil,start:Date){
        records.append(StudyRecord(condition:condition,userInput:value.question,aiObject:value.interpretedTarget,aiRelation:value.interpretedLocation,userResponse:outcome,selectedObject:selectedObject,selectedIntendedTarget:selectedIntendedTarget,elapsedSeconds:Date().timeIntervalSince(start),timestamp:Date(),targetPlacement:placement,interpretationSource:source))
        save()
    }
    private func save(){let e = JSONEncoder();e.dateEncodingStrategy = .iso8601;e.outputFormatting = [.prettyPrinted,.sortedKeys];do{try e.encode(records).write(to:Self.fileURL,options:.atomic)}catch{print("Failed to save study records: \(error)")}}
    private static func load()->[StudyRecord]{let d = JSONDecoder();d.dateDecodingStrategy = .iso8601;guard let data = try? Data(contentsOf:fileURL) else{return []};return (try? d.decode([StudyRecord].self,from:data)) ?? []}
}
