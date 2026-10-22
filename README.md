# ObjectAnchoredAR

**Word count:** 539 words

An iOS research prototype that compares three ways of presenting an AI assistant's interpretation of a question about the physical scene: **2D Conversational**, **Screen-Fixed AR** and **Object-Anchored AR**. The study asks which presentation best helps users notice and correct an AI misunderstanding.

In the study scenario the user asks *"Can you find the cup to the left of my laptop?"* and the AI deliberately misinterprets it as *"Water bottle, right side of laptop"*. The user can confirm the answer or correct it. Every response is logged for analysis.

Design rationale, data fields and thesis reporting notes are in [docs/thesis-notes.md](docs/thesis-notes.md).

---

## Project status

**Working prototype.** All features below build and run in Xcode. On-device testing is still in progress.

| Area | Status |
|---|---|
| Three presentation conditions (2D, Screen-Fixed AR, Object-Anchored AR) on one screen | ✅ Done |
| Scripted (Wizard-of-Oz) interpretation, identical across conditions | ✅ Done |
| Automatic placement of the Object-Anchored card on the interpreted object (on-device detection) | ✅ Done; placement confirmed on device |
| Confirm / correct responses; the answer and icon update after a correction | ✅ Done |
| Study records saved locally as JSON (exportable via the Files app) | ✅ Done |
| Locked study question; send disabled until AR tracking is ready; scanning hints | ✅ Done |
| Live mode: rule-based interpretation of questions from the camera view | ✅ Done (demo only, not used in the study) |
| Detection success rate under study conditions; Live-mode device test | 🔄 In progress |
| Participant ID in records; counterbalancing support | ⏳ Not started |
| Neutral wording of mode descriptions; equal waiting time across all three conditions | ⏳ To decide (see thesis notes) |
| Remove legacy, unused screens | ⏳ Not started |

---

## Technology stack

| Layer | Technology |
|---|---|
| Language | Swift 5 |
| IDE / build | Xcode 26, iOS 17+ deployment target |
| UI | UIKit (programmatic layout, SF Symbols) |
| AR tracking | ARKit: `ARWorldTrackingConfiguration`, raycasting |
| 3D rendering | RealityKit: `ARView`, `AnchorEntity`, generated text meshes, billboarding |
| Object detection | Vision + Core ML: Apple's **YOLOv3-Tiny** model (80 COCO classes), runs on the device |
| Question parsing (Live mode) | Rule-based spatial-relation parser (`NSRegularExpression`) |
| Data storage | `Codable` + JSON in the app's Documents folder |
| Version control | Git / GitHub |
| Device | iPhone with ARKit support. The simulator cannot be used: it has no camera or world tracking. |

### Repository structure
```
outputs/ObjectAnchoredAR.xcodeproj    Xcode project
outputs/ObjectAnchoredAR/
  ViewController.swift                Main screen: camera, three conditions, responses
  AIInterpretation.swift              Shared interpretation model, study records (JSON)
  ObjectLocator.swift                 On-device object detection (YOLOv3-Tiny)
  SpatialQuery.swift                  Live-mode question parser and icons
  YOLOv3Tiny.mlmodel                  Core ML model
  InterfaceStyle.swift                Shared styles
  *ViewController.swift (others)      Legacy screens, not used
docs/thesis-notes.md                  Design and reporting notes
```

### How to run
1. Open `outputs/ObjectAnchoredAR.xcodeproj` in Xcode.
2. Select your signing team.
3. Run on a physical iPhone and allow camera access.
4. Use the gear menu (top right) to switch between **Scripted (study)** and **Live** mode.

---

## Development record

| Date | Commit | Changes |
|---|---|---|
| 2026-10-20 | [`0fc9075`](https://github.com/julieli0511-ops/ObjectAnchoredAR/commit/0fc9075c07d3de463f8cb72f03ef4c1f7a4eb1b1) | Xcode project and `.gitignore`. First prototype: camera view, simulated AI interpretation, and separate screens for the 2D, Screen-Fixed AR and Object-Anchored AR conditions. |
| 2026-10-22 | [`6bbdd37`](https://github.com/julieli0511-ops/ObjectAnchoredAR/commit/6bbdd37dc19abafeb465157c747bac859c7851fb) | All three conditions combined on one camera screen with a mode selector. Screen-Fixed and 2D presentations separated. Object-Anchored card with connector line and billboarding. Study records extended and saved as JSON. YOLOv3-Tiny model added to the project. |
| 2026-10-22 | [`c68394d`](https://github.com/julieli0511-ops/ObjectAnchoredAR/commit/c68394dacd74aebabcdde302d8c5f5b47ddd4889) | On-device object detection places the Object-Anchored card on the interpreted object automatically (`ObjectLocator.swift`), with a tap fallback logged as `targetPlacement`. Live mode (`SpatialQuery.swift`): rule-based parsing of spatial questions, an SF Symbol icon for each object, and a Scripted/Live switch in the gear menu. The answer card and icon update after a correction (options: Coffee cup / Water bottle / Laptop). Study question locked in Scripted mode; send disabled until AR tracking is ready; scanning hints. |
| 2026-10-22 | *this commit* | README in assignment format; design and reporting notes moved to `docs/thesis-notes.md`. |
