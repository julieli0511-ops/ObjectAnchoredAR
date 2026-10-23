import XCTest
@testable import ObjectAnchoredAR

/// The on-device assistant's question parser, tested against a fixed kitchen scene instead of the camera.
/// Boxes are normalised image coordinates (0–1, origin top-left), as ObjectLocator returns them.
final class SpatialQueryTests: XCTestCase {
    private func object(_ label: String, x: CGFloat, confidence: Float = 0.8) -> ObjectLocator.Detection {
        ObjectLocator.Detection(label: label, confidence: confidence, box: CGRect(x: x - 0.05, y: 0.45, width: 0.1, height: 0.1))
    }
    private lazy var kitchen = [object("cup", x: 0.15), object("spoon", x: 0.35), object("knife", x: 0.4),
                                object("bottle", x: 0.85), object("microwave", x: 0.6), object("sink", x: 0.7)]

    // MARK: Where-is questions

    func testParsesTargetReferenceAndRelation() {
        let query = SpatialQuery("Can you find the cup to the left of my coffee machine?")
        XCTAssertEqual(query.target?.label, "cup")
        XCTAssertEqual(query.reference?.name, "coffee machine")
        XCTAssertEqual(query.relation, .left)
        XCTAssertNil(query.reason, "A question that names the object needs no reason")
        XCTAssertFalse(query.needsVisionModel)
    }

    func testPicksTheCupThatMatchesTheRelation() {
        let left = object("cup", x: 0.2), right = object("cup", x: 0.8, confidence: 0.9), bottle = object("bottle", x: 0.5)
        let resolved = SpatialQuery("Where is the cup to the left of the bottle?").resolve([left, right, bottle])
        XCTAssertEqual(resolved?.target.box, left.box, "The left cup, even though the right one is more confident")
        XCTAssertEqual(resolved?.reference?.label, "bottle")
    }

    func testTwoMatchingCupsAreAmbiguous() {
        let scene = [object("cup", x: 0.1), object("cup", x: 0.3), object("bottle", x: 0.7)]
        XCTAssertEqual(SpatialQuery("Where is the cup to the left of the bottle?").candidates(scene).count, 2,
                       "Two cups fit, so the app should ask which one")
        XCTAssertEqual(SpatialQuery("Where is my cup?").candidates([object("cup", x: 0.5)]).count, 1)
    }

    func testObjectNotInViewIsNotResolved() {
        XCTAssertNil(SpatialQuery("Where is my phone?").resolve(kitchen))
    }

    func testWhatIsThisPicksTheObjectNearestTheCentre() {
        let query = SpatialQuery("What is this?")
        XCTAssertNil(query.target)
        XCTAssertEqual(query.resolve(kitchen)?.target.label, "knife")
        XCTAssertTrue(query.candidates(kitchen).isEmpty)
    }

    // MARK: Kitchen tasks

    func testTaskQuestionsChooseATool() {
        let expected = ["What can I use to stir my soup?": "spoon", "I need to cut some bread": "knife",
                        "Where can I reheat my leftovers?": "microwave", "I want to wash the vegetables": "sink"]
        for (question, tool) in expected {
            let query = SpatialQuery(question)
            XCTAssertEqual(query.target?.label, tool, question)
            XCTAssertNotNil(query.reason, "A task question explains why the tool fits: \(question)")
            XCTAssertEqual(query.resolve(kitchen)?.target.label, tool, question)
        }
    }

    func testOpenEndedTaskNeedsTheVisionModel() {
        XCTAssertTrue(SpatialQuery("Which tool should I use to flip a pancake?").needsVisionModel)
    }

    // MARK: Answers

    func testOnDeviceScoreIsDetectionConfidence() {
        let cup = object("cup", x: 0.15, confidence: 0.72), query = SpatialQuery("Where is my cup?")
        let answer = query.interpretation(for: "Where is my cup?", target: cup, reference: nil)
        XCTAssertEqual(answer.interpretedTarget, "Cup")
        XCTAssertEqual(answer.confidenceScore ?? 0, 0.72, accuracy: 0.001)
        XCTAssertEqual(answer.scoreName, "Detection", "On-device the score is the detector's, not confidence in understanding the question")
        XCTAssertEqual(answer.confidence, "High", "0.7 and above counts as high")
    }

    func testDescribesWhereTheObjectIs() {
        XCTAssertEqual(SpatialQuery.describe(object("cup", x: 0.15), relativeTo: nil, named: nil).location, "Left side of view")
        XCTAssertEqual(SpatialQuery.describe(object("sink", x: 0.85), relativeTo: nil, named: nil).location, "Right side of view")
    }

    // MARK: Names from the vision model

    func testMapsVisionModelNamesToDetectorLabels() {
        let expected = ["white mug": "cup", "blue water bottle": "bottle", "wooden spoon": "spoon", "chef's knife": "knife",
                        "Coffee machine": "coffee machine", "spatula": "other"]
        for (name, label) in expected { XCTAssertEqual(SpatialQuery.cocoLabel(forName: name), label, name) }
    }
}
