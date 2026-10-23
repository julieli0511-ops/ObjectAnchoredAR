import ARKit
import RealityKit
import UIKit

/// Object display: the answer as a 3D card anchored on the object, with a connector line, a dashed ring and a confidence bar.
extension ViewController {
    /// Fallback when detection fails: the participant (or researcher) taps the object.
    @objc func handleSceneTap(_ gesture: UITapGestureRecognizer) {
        view.endEditing(true)
        guard mode == .object, awaitingTap else { return }
        guard let result = arView.raycast(from: gesture.location(in: arView), allowing: .estimatedPlane, alignment: .any).first else { hint.text = "No surface detected yet. Move slowly and try again."; return }
        let t = result.worldTransform.columns.3
        present(at: [t.x, t.y, t.z], placement: "tap")
    }
    // MARK: Object-anchored panel
    func placePanel(at position: SIMD3<Float>) {
        removePanel()
        let item = InterpretationStore.shared.value, anchor = AnchorEntity(world: position)
        // The anchor sits where the object meets the table: dot on the object, line up to the card above it.
        let dot = ModelEntity(mesh: .generateSphere(radius: 0.012), materials: [UnlitMaterial(color: InterfaceStyle.accent)]); dot.position = [0, 0.07, 0]
        let connector = ModelEntity(mesh: .generateBox(size: [0.004, 0.20, 0.004]), materials: [UnlitMaterial(color: InterfaceStyle.accent)]); connector.position = [0, 0.17, 0]
        let p = Entity(); p.position = [0, 0.32, 0]
        // Dashed ring on the surface around the object (the dashed outline in the design), so it is clear which object the card belongs to.
        for i in 0..<20 {
            let angle = Float(i) / 20 * 2 * .pi
            let dash = ModelEntity(mesh: .generateSphere(radius: 0.004), materials: [UnlitMaterial(color: .white)])
            dash.position = [0.07 * cos(angle), 0.003, 0.07 * sin(angle)]; anchor.addChild(dash)
        }
        let background = ModelEntity(mesh: .generateBox(size: [0.30, 0.13, 0.008], cornerRadius: 0.02), materials: [UnlitMaterial(color: InterfaceStyle.panel)])
        let title = textEntity(item.interpretedTarget, size: 0.026, weight: .bold, color: UIColor(white: 0.12, alpha: 1)); title.position.y += 0.038
        let subtitle = textEntity(item.interpretedLocation, size: 0.016, weight: .regular, color: UIColor(white: 0.42, alpha: 1)); subtitle.position.y += 0.008
        var parts: [Entity] = [background, title, subtitle] + confidenceEntities(item, y: -0.022)
        if let badge = sourceBadgeText { let b = textEntity(badge, size: 0.011, weight: .semibold, color: InterfaceStyle.accent); b.position.y -= 0.048; parts.append(b) }
        parts.forEach { p.addChild($0) }; [dot, connector, p].forEach { anchor.addChild($0) }
        arView.scene.addAnchor(anchor); worldAnchor = anchor; panel = p
        // Keep the panel upright and facing the camera.
        if billboard == nil { billboard = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            guard let self, let p = self.panel else { return }
            let x = p.position(relativeTo: nil); var c = self.arView.cameraTransform.translation; c.y = x.y
            guard simd_distance(c, x) > 0.01 else { return }
            p.look(at: c, from: x, upVector: [0, 1, 0], relativeTo: nil) } }
    }
    /// The confidence bar in 3D. The panel's -Z faces the camera, so the viewer's left is local +x: the bar fills from +x towards -x.
    func confidenceEntities(_ item: AIInterpretation, y: Float) -> [Entity] {
        guard let score = item.confidenceScore else {
            let caption = textEntity(item.confidence, size: 0.012, weight: .medium, color: UIColor(white: 0.42, alpha: 1)); caption.position.y += y; return [caption]
        }
        let width: Float = 0.17, left: Float = 0.12, filled = max(width * Float(min(max(score, 0), 1)), 0.009)
        let track = ModelEntity(mesh: .generateBox(size: [width, 0.005, 0.005], cornerRadius: 0.0025), materials: [UnlitMaterial(color: InterfaceStyle.track)])
        track.position = [left - width / 2, y, -0.007]
        let fill = ModelEntity(mesh: .generateBox(size: [filled, 0.009, 0.009], cornerRadius: 0.0045), materials: [UnlitMaterial(color: InterfaceStyle.accent)])
        fill.position = [left - filled / 2, y, -0.009]
        let text = (item.scoreName == "Detection" ? "Det. " : "") + "\(Int((score * 100).rounded()))%"  // as on the 2D bar: what the score measures
        let percent = textEntity(text, size: 0.013, weight: .medium, color: UIColor(white: 0.25, alpha: 1)); percent.position.x -= 0.09; percent.position.y += y
        return [track, fill, percent]
    }
    func removePanel(){if let worldAnchor{arView.scene.removeAnchor(worldAnchor)};worldAnchor = nil;panel = nil}
    /// Text centred on its parent. look(at:) points the panel's -Z at the camera, while generated text faces +Z, so it is turned around.
    func textEntity(_ string:String,size:CGFloat,weight:UIFont.Weight,color:UIColor)->ModelEntity {
        let mesh = MeshResource.generateText(string, extrusionDepth: 0.001, font: .systemFont(ofSize: size, weight: weight))
        let e = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: color)]); e.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        let c = mesh.bounds.center; e.position = [c.x, -c.y, -0.005]; return e
    }
}
