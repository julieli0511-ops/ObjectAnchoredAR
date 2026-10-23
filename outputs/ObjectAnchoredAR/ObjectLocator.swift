import ARKit
import CoreML
import Vision

/// On-device object detection (YOLOv3Tiny, 80 COCO labels such as "bottle", "cup", "laptop", "book"). Nothing leaves the device.
/// Scripted mode uses it only to find where the scripted object is; live mode also uses it to decide which object the question means.
final class ObjectLocator {
    struct Detection {
        let label: String, confidence: Float
        /// Upright (portrait) image, normalized, origin top-left — what the user sees, so "left of" can be compared directly.
        let box: CGRect
        /// Bottom-centre of the box, where the object meets its surface, in ARKit's normalized image coordinates
        /// (landscape sensor image, origin top-left), ready for `ARFrame.raycastQuery(from:allowing:alignment:)`.
        var base: CGPoint { Self.sensorPoint(box.midX, box.maxY - box.height * 0.1) }
        var center: CGPoint { Self.sensorPoint(box.midX, box.midY) }
        /// The sensor image is rotated 90° clockwise for portrait, so upright (u, v) comes from sensor (v, 1 - u).
        private static func sensorPoint(_ u: CGFloat, _ v: CGFloat) -> CGPoint { CGPoint(x: v, y: 1 - u) }
    }
    private let model = try? VNCoreMLModel(for: YOLOv3Tiny(configuration: MLModelConfiguration()).model)
    private let queue = DispatchQueue(label: "ObjectLocator")

    /// All detections above the confidence threshold. Calls back on the main queue.
    func detect(in frame: ARFrame, minimumConfidence: Float = 0.3, completion: @escaping ([Detection]) -> Void) {
        guard let model else { completion([]); return }
        let buffer = frame.capturedImage
        queue.async {
            let request = VNCoreMLRequest(model: model); request.imageCropAndScaleOption = .scaleFill
            // .right: the sensor image turned upright for the portrait-only UI.
            try? VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .right).perform([request])
            let detections = (request.results as? [VNRecognizedObjectObservation] ?? []).compactMap { o -> Detection? in
                guard let label = o.labels.first?.identifier, o.confidence >= minimumConfidence else { return nil }
                let b = o.boundingBox  // Vision: origin bottom-left
                return Detection(label: label, confidence: o.confidence, box: CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height))
            }
            DispatchQueue.main.async { completion(detections) }
        }
    }
}
