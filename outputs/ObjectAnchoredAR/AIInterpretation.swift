import Foundation

struct AIInterpretation {
    var question = "Can you find the cup to the left of my coffee machine?"
    let intendedTarget = "Coffee cup, left side of the coffee machine"
    var interpretedTarget = "Water bottle"
    var interpretedLocation = "Right side of coffee machine"
    var confidence = "Medium"
    /// Shown as the confidence bar; nil once the user has confirmed or chosen the object (the label is shown instead).
    var confidenceScore: Double? = 0.6
    /// What the score measures, shown before the percentage. On-device it is the detector's confidence that the object is
    /// what it says ("Detection"), not confidence that the question was understood; the vision model only reports
    /// high / medium / low, so its score is approximate ("Confidence ≈").
    var scoreName = "Confidence"
    var explanation = "I think you are asking about the water bottle on the right side of your coffee machine."
    var icon = "waterbottle.fill"
    /// Why this object fits the user's task ("A spoon is good for stirring."); nil when the question just names an object.
    var reason: String? = nil
    static let sample = AIInterpretation()
    static let sceneObjects = ["Coffee cup", "Coffee machine", "Water bottle", "Plant"]
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
