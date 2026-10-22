import ARKit
import CoreImage
import Foundation
import ImageIO

/// Live (VLM) mode: asks a free, open vision-language model (Qwen2.5-VL 7B) served by Ollama on a computer on the same Wi-Fi.
/// The camera image goes only to that computer, never to a cloud service. The model decides which object the question means;
/// `ObjectLocator` then refines where it is.
final class VLMClient {
    struct Answer: Decodable { let object: String, coco_label: String, location: String, explanation: String, confidence: String, bbox: [Double] }
    enum Failure: Error { case noServer, badReply }

    /// Multiples of 28 with at least 1024·28·28 pixels: Qwen2.5-VL then does not rescale the image, so its bbox is in pixels of this image.
    /// 3:4 matches the upright camera image.
    static let imageSize = CGSize(width: 840, height: 1120)
    static let model = "qwen2.5vl:7b"
    /// e.g. http://my-mac.local:11434 — set in the gear menu; the default comes from Info.plist (VLMServerURL).
    static var serverURL: String {
        get { UserDefaults.standard.string(forKey: "vlmServerURL") ?? (Bundle.main.object(forInfoDictionaryKey: "VLMServerURL") as? String ?? "") }
        set { UserDefaults.standard.set(newValue, forKey: "vlmServerURL") }
    }
    private static let labels = ["cup","bottle","wine glass","laptop","book","cell phone","keyboard","mouse","remote","tv","scissors","clock","vase",
        "potted plant","bowl","spoon","fork","knife","banana","apple","orange","carrot","broccoli","sandwich","pizza","donut","cake","microwave","oven",
        "toaster","sink","refrigerator","dining table","chair","couch","bed","backpack","handbag","umbrella","teddy bear","toothbrush","sports ball",
        "person","dog","cat","other"]
    private let context = CIContext()
    private var task: URLSessionDataTask?
    func cancel() { task?.cancel() }

    /// Calls back on the main queue with the answer and its box (upright image, normalized, origin top-left — same as `ObjectLocator.Detection.box`).
    func interpret(question: String, frame: ARFrame, completion: @escaping (Result<(Answer, CGRect), Error>) -> Void) {
        let done = { (r: Result<(Answer, CGRect), Error>) in DispatchQueue.main.async { completion(r) } }
        guard let url = URL(string: Self.serverURL)?.appendingPathComponent("api/chat"), url.host != nil else { done(.failure(Failure.noServer)); return }
        guard let jpeg = jpeg(from: frame) else { done(.failure(Failure.badReply)); return }
        let (w, h) = (Int(Self.imageSize.width), Int(Self.imageSize.height))
        let prompt = """
        This is a \(w)x\(h) pixel photo from the user's phone camera. The user asks: "\(question)"
        Identify the single object the user is asking about. Reply with JSON:
        - object: short name of that object
        - coco_label: the closest category from the allowed list, or "other"
        - location: where it is relative to another visible object, as a short title such as "Left side of laptop"
        - explanation: one sentence starting "I think you are asking about"
        - confidence: high, medium or low
        - bbox: [x1, y1, x2, y2] bounding box of that object in pixels of this \(w)x\(h) image
        """
        let schema: [String: Any] = [
            "type": "object",
            "properties": ["object": ["type": "string"], "coco_label": ["type": "string", "enum": Self.labels], "location": ["type": "string"],
                           "explanation": ["type": "string"], "confidence": ["type": "string", "enum": ["high", "medium", "low"]],
                           "bbox": ["type": "array", "items": ["type": "integer"], "minItems": 4, "maxItems": 4]],
            "required": ["object", "coco_label", "location", "explanation", "confidence", "bbox"],
        ]
        let body: [String: Any] = [
            "model": Self.model, "stream": false, "format": schema, "keep_alive": "30m", "options": ["temperature": 0],
            "messages": [["role": "user", "content": prompt, "images": [jpeg.base64EncodedString()]]],
        ]
        var request = URLRequest(url: url, timeoutInterval: 60)  // the first request also loads the model (~20 s)
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        task = URLSession.shared.dataTask(with: request) { data, _, error in
            struct Reply: Decodable { struct Message: Decodable { let content: String }; let message: Message }
            guard error == nil, let data, let reply = try? JSONDecoder().decode(Reply.self, from: data),
                  let answer = try? JSONDecoder().decode(Answer.self, from: Data(reply.message.content.utf8)), answer.bbox.count == 4
            else { done(.failure(error ?? Failure.badReply)); return }
            let b = answer.bbox
            let box = CGRect(x: b[0] / Double(w), y: b[1] / Double(h), width: (b[2] - b[0]) / Double(w), height: (b[3] - b[1]) / Double(h)).standardized
            done(.success((answer, box)))
        }
        task?.resume()
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case Failure.noServer: return "No server address is set."
        case Failure.badReply: return "The server answered, but not with a usable result. Is \(model) downloaded on the computer (ollama pull \(model))?"
        case let e as URLError where e.code == .timedOut: return "The request timed out. The computer may be unreachable on this network."
        default: return error.localizedDescription
        }
    }
    /// Quick check for the gear menu: is Ollama reachable at `serverURL`, and is the model downloaded?
    static func checkServer(completion: @escaping (Bool, String) -> Void) {
        let done = { (ok: Bool, message: String) in DispatchQueue.main.async { completion(ok, message) } }
        guard let url = URL(string: serverURL)?.appendingPathComponent("api/tags"), url.host != nil else { done(false, describe(Failure.noServer)); return }
        URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 5)) { data, _, error in
            struct Tags: Decodable { struct Model: Decodable { let name: String }; let models: [Model] }
            if let error { done(false, describe(error)) }
            else if let data, let tags = try? JSONDecoder().decode(Tags.self, from: data) {
                tags.models.contains { $0.name == model } ? done(true, "Connected. \(model) is ready.") : done(false, "Connected, but \(model) is not downloaded. On the computer run: ollama pull \(model)")
            } else { done(false, "Something answered at this address, but it is not Ollama.") }
        }.resume()
    }

    /// The camera image turned upright for the portrait UI and scaled to `imageSize`.
    private func jpeg(from frame: ARFrame) -> Data? {
        let upright = CIImage(cvPixelBuffer: frame.capturedImage).oriented(.right)
        let scaled = upright.transformed(by: CGAffineTransform(scaleX: Self.imageSize.width / upright.extent.width, y: Self.imageSize.height / upright.extent.height))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return context.jpegRepresentation(of: scaled, colorSpace: colorSpace, options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.7])
    }
}
