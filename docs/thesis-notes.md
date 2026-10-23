# ObjectAnchoredAR — Thesis Notes

Detailed design, data and reporting notes for the thesis. For the project summary see the [README](../README.md).

> **Update (commit `c93b925`): the app is now framed as an assistant tool.**
> - The default mode is the on-device assistant.
> - The experiment is now **Evaluation mode**, at the end of the ⚙️ menu.
> - The modes were renamed. In the sections below, read:
>   - **Scripted (study)** as **Evaluation mode**;
>   - **Live (rules)** as **On-device**;
>   - **Live VLM** as **Vision model**.
> - The vision model (Qwen2.5-VL via Ollama) mentioned under *Generalization* as future work is now implemented.
> - Responses are saved **only in Evaluation mode**.
> - The mode descriptions now give usage guidance in normal use and are **hidden in Evaluation mode**, so they cannot steer participants.
> - **Update (commit `eb5607f`):** the scenario is now the kitchen. The question is "Can you find the cup to the left of my coffee machine?", the scripted answer is Water bottle, and the corrections are Coffee cup / Coffee machine / Water bottle / Plant. The Chat display became a conversation with follow-up questions and history. History is never kept in Evaluation mode.
> - Also added since these notes were written: a clarifying question ("Which cup do you mean?"), a confidence bar, elapsed time with Cancel, and a dashed ring under the Object card.
> - **Update (code review):**
>   - `ViewController.swift` is split into four files by feature (see section 3).
>   - Unit tests for the question parser are in `outputs/ObjectAnchoredARTests/`.
>   - History moved to the app's private folder, so it no longer appears in the Files app. Only `study_records.json` is shared.
>   - The "Which cup?" boxes now show their numbers.
>   - If the camera is not ready, the vision model reports it instead of quietly answering on-device.
>   - **Confidence means different things by source.** On-device, the bar shows the *detector's* confidence that the object is a cup. It is labelled **"Detection"** and is not confidence that the question was understood. The vision model only reports high, medium or low, shown as about 85, 60 or 30 % and labelled **"Confidence ≈"**. Evaluation mode shows the scripted 60 % as "Confidence". Do not describe the on-device score as the AI's confidence in its interpretation.
>   - **Chat in Evaluation mode:** the answer no longer types itself out, so it is readable as soon as it appears, as in Screen and Object. Chat still shows the participant's question as a bubble. Report this as part of the Chat design (a conversation format), or as a difference between conditions.

An iOS research prototype comparing three ways of presenting an AI assistant's interpretation of a user's question about the physical scene:

| Condition | How the interpretation is shown |
|---|---|
| **2D Conversational** (`2D`) | A chat-style card at the bottom of the screen, with a full sentence and the response buttons inside it. |
| **Screen-Fixed AR** (`Screen-Fixed AR`) | A compact card (icon, object, location) fixed to the top of the screen over the camera view. It stays in the same screen position wherever the camera points. |
| **Object-Anchored AR** (`Object-Anchored AR`) | A card placed in 3D above the object the AI selected, with a dot on the object and a connector line. It stays attached to that object and turns to face the user. |

**Research question.** When the AI misunderstands, which presentation helps users notice the misunderstanding and correct it?

**Scenario (desk).** The user asks *"Can you find the cup to the left of my laptop?"* The AI answers **"Water bottle, right side of laptop"**. This answer is deliberately wrong (a controlled misinterpretation). Scene objects: coffee cup (intended target, left of the laptop), laptop (reference object), water bottle (the wrong interpretation, right of the laptop).

---

## 1. Interaction flow

1. **Home.** Camera view, mode selector (2D Chat / Screen AR / Object AR) and question input.
2. **Ask.** The participant sends the question.
   - In **Scripted** mode the question is pre-filled and locked.
   - In the AR modes the send button stays disabled until ARKit world tracking is ready. Meanwhile a hint says *"Move your phone slowly to scan the table."*
3. **Analyzing.** A focus indicator and *"Analyzing your question…"* are shown.
   - The prototype adds a fixed 0.8 s delay to simulate analysis.
   - In the AR modes the app then looks for the interpreted object in the camera image for up to about 3 s. During this time the hint *"Keep the camera pointed at the scene"* is shown.
4. **Interpretation shown.**
   - 2D: chat card.
   - Screen AR: top card.
   - Object AR: anchored card on the detected object.
   - If detection fails in Object AR, the app falls back to tapping: a crosshair appears and the participant (or researcher) taps the object.
5. **Response.**
   - **"That's correct"** saves the response.
   - **"Correct interpretation"** opens a list (Coffee cup / Water bottle / Laptop). The choice is saved, and the answer card updates to the chosen object (name, icon, location detected when possible, and the anchor position in Object AR). A confirmation is shown: *"Understood. You mean the coffee cup."*
   - After responding, the buttons are hidden. The next question starts a fresh trial.

---

## 2. Interpretation sources: Scripted vs Live

Switch between them with the **gear (⚙️) menu** in the top-right corner. In Live mode the label `LIVE ·` appears under the mode selector.

### Scripted (study), the default
- The interpretation is **fixed**: *Water bottle / Right side of laptop / Medium confidence*. Every participant and every condition sees exactly the same wrong answer (Wizard-of-Oz).
- An **on-device object detector** is used **only to locate** the scripted object (the water bottle) in the camera image. The Object-Anchored card is then placed on the real bottle automatically, so participants do not decide where the AI's answer appears.
- Screen AR runs the same detection step, so both AR conditions have the same waiting time. Its card is shown whether or not detection succeeds.

### Live (on-device)
- Used for demos and pilots, and to show that the approach generalizes. **Not for the formal study.**
- A rule-based parser reads the question:
  - It takes the target object, a spatial relation (*left / right / above / below / next to*) and a reference object. Example: *"cup / left of / laptop"*.
  - A question with no known object (*"What is this?"*) refers to the object nearest the centre of the view.
- The detector finds all objects in view, and the app picks the instance that best matches the relation. If no instance matches, it picks the most confident one.
- The interpretation is built from **where that object really is**, so a wrong pick shows up in the text.
- Supports about 60 phrases covering 45 COCO categories. Each category has an SF Symbol icon.

**No images leave the device in either mode.**

---

## 3. Architecture

All files are in `outputs/ObjectAnchoredAR/`.

| File | Role |
|---|---|
| `ViewController.swift` | The app's single screen: state, layout, settings menu, input and sending, tracking gating. |
| `ViewController+Assistant.swift` | The assistant flow: on-device rules, vision model or scripted answer; detection, raycasting, and "Which one do you mean?". |
| `ViewController+Conversation.swift` | Showing the answer, the Chat thread, suggested and follow-up questions, history, confirm and correct. |
| `ViewController+ObjectPanel.swift` | The Object display's 3D card, ring and confidence bar. |
| `History.swift` | Saved conversations (Application Support, private to the app) and the history drawer. |
| `ObjectAnchoredARTests/SpatialQueryTests.swift` | Unit tests for the question parser against a fixed kitchen scene (10 tests). |
| `AIInterpretation.swift` | Shared data model (`AIInterpretation`): question, interpreted object, relation, confidence, explanation, icon. Also the scripted scenario constants, `StudyRecord` and `InterpretationStore`, which saves records to JSON. |
| `ObjectLocator.swift` | On-device object detection with Vision and Core ML (**YOLOv3Tiny**, 80 COCO classes, confidence ≥ 0.3). Converts bounding boxes to ARKit image coordinates for raycasting. |
| `YOLOv3Tiny.mlmodel` | Apple's Core ML YOLOv3-Tiny model (~35 MB), from Apple's Core ML model gallery. |
| `SpatialQuery.swift` | Live mode: question parsing, spatial-relation resolution, interpretation text, label-to-icon mapping. |
| `InterfaceStyle.swift` | Shared button and card styles. |

### Object-Anchored placement pipeline
```
ARFrame.capturedImage
  → YOLOv3Tiny (Vision, image oriented .right for portrait)
  → bounding box of the target label
  → bottom-centre of the box (where the object meets the table)
  → ARFrame.raycastQuery(estimatedPlane, horizontal)   [fallback: box centre, any alignment]
  → AnchorEntity(world:)
  → white dot (7 cm up) + connector line + 30 × 10 cm dark card (32 cm up)
  → card rotates about the vertical axis each frame to face the camera (billboarding)
```

Placement details:
- The card uses unlit materials, so its readability does not depend on room lighting.
- Virtual content is **not occluded** by real objects.
- The UI is **portrait-only**, because the detection-to-raycast coordinate conversion assumes portrait.

---

## 4. Study data

Every response is appended to **`Documents/study_records.json`** on the device. Records accumulate across app launches. File sharing is enabled, so the file can be copied off the iPhone with the **Files** app or with **Finder → iPhone → Files**.

| Field | Meaning |
|---|---|
| `condition` | `2D`, `Screen-Fixed AR` or `Object-Anchored AR` |
| `userInput` | The question asked |
| `aiObject`, `aiRelation` | The interpretation shown, **before** any correction (e.g. `Water bottle`, `Right side of laptop`) |
| `userResponse` | `confirm` or `correct` |
| `selectedObject` | The object chosen when correcting (otherwise `null`) |
| `selectedIntendedTarget` | `true` if the participant corrected to the intended target (`Coffee cup`). Always `false` for `confirm` and in Live mode. |
| `elapsedSeconds` | Time from **the moment the interpretation became visible** to the response. Excludes typing and analysis time. |
| `timestamp` | ISO-8601 time of the response |
| `targetPlacement` | Object AR only: `detected` (placed automatically) or `tap` (detection failed, so someone tapped). `null` in other conditions. |
| `interpretationSource` | `scripted` or `live` |

**Analysis notes**
- Keep only `interpretationSource == "scripted"` rows for the study.
- Report, and possibly exclude, Object AR trials with `targetPlacement == "tap"`.
- `selectedIntendedTarget == true` means the participant noticed the error and fixed it correctly.
- `confirm` on the scripted trial means the misinterpretation **went unnoticed**.

The file has no participant ID field. Note the participant ID and timestamp in your session log, or ask for an ID field to be added.

---

## 5. Running the app

- Xcode 26, iOS 17 or later, and a **physical iPhone with ARKit**. The simulator has no camera or world tracking.
- Open `outputs/ObjectAnchoredAR.xcodeproj`, choose your signing team, and run on the device.
- Grant camera permission on first launch.

### Researcher checklist for each session
1. Arrange the desk: coffee cup **left** of the laptop, water bottle **right** of the laptop, all in view from where the participant will hold the phone.
2. Select **⚙️ → Evaluation mode**. The app starts in the on-device assistant, which does **not** save responses.
3. Before each condition, select the mode and let the participant sweep the phone over the table until the send button is enabled.
4. Order of conditions: counterbalance it (e.g. Latin square). The app does not do this for you.
5. After the session, copy `study_records.json` off the device.

---

## 6. What to report in the thesis

### Method: apparatus
- **Platform:** iPhone (state model and iOS version), ARKit world tracking, RealityKit rendering, UIKit overlays, portrait orientation.
- **Interpretation (Wizard-of-Oz):** The interpretation is predefined, not generated by a model. Explain why: it controls the **type**, **content** and **timing** of the AI error, so every condition shows the same misinterpretation. A real model could answer correctly, or be wrong in a different way for each participant.
- **Same content, different presentation:** All three conditions show the same object name, relation and confidence. They differ only in layout:
  - 2D additionally shows a full explanatory sentence.
  - Screen AR shows icon, object and relation.
  - Object AR shows object and relation.

  Decide whether to report this text difference as part of each condition's design or remove it. It is a possible confound.
- **Object localization:** On-device YOLOv3-Tiny (COCO) finds the scripted object, and an ARKit raycast from the bottom of its bounding box gives the anchor position. State that:
  - the AI's *location* is computed from the real scene, while its *interpretation* is scripted;
  - images are processed **only on the device** (relevant for ethics approval and consent);
  - there is a fallback tap when detection fails, and these trials are logged as `targetPlacement = "tap"`.
- **Object-Anchored card geometry:** 30 × 10 cm card, 32 cm above the object's base, with a connector line and a dot on the object, billboarded about the vertical axis, unlit material, no occlusion by real objects.
- **Timing:** simulated analysis delay of 0.8 s, plus up to about 3 s of detection in the AR conditions. Screen AR runs the same detection so both AR conditions wait equally long. 2D does not wait for detection, so its latency is shorter: report this or equalize it.

### Method: procedure
- The question is **pre-filled and locked**. Participants only press send, so the input is identical across participants and conditions.
- In the AR conditions, sending is disabled until world tracking is ready, and a scanning hint is shown.
- Response options: confirm, or correct by choosing from a list (Coffee cup / Water bottle / Laptop). After a correction the answer updates to the chosen object.
- Counterbalancing scheme, number of trials per condition, instructions given to participants.
- Participant instructions about where to point the phone.

### Measures
- **Error detection:** whether participants corrected the misinterpretation (`userResponse = correct`).
- **Correction accuracy:** whether they chose the intended target (`selectedIntendedTarget`).
- **Response time:** `elapsedSeconds`, measured from when the interpretation became visible to the response.
- Any questionnaires you add, such as SUS, NASA-TLX, trust, or preference.

### Design rationale
Justify each condition:
- **Screen-fixed:** stays readable while the user looks around.
- **Object-anchored:** makes the spatial reference of the interpretation explicit, linking the AI's answer to a place in the scene.

Explain why a deliberately wrong interpretation is used: the study is about how users *detect* AI misunderstandings.

**Mode descriptions shown in the app:** The line under the mode selector currently states what each mode is *for*, for example *"See which real-world location the interpretation refers to."* This can prime participants. Either change it to neutral, appearance-only descriptions, or hide it during the study, and say which you did.

### Limitations
- The interpretation is scripted, so the results show how people detect a known, single type of error. They do not cover a real model's error distribution.
- The detector covers only the 80 COCO categories. Small or occluded objects can be missed, which is why the tap fallback exists.
- Virtual content is not occluded by real objects. AR tracking quality depends on lighting and surface texture.
- One scenario (desk) with one error type (wrong object on the opposite side of the reference object).

### Generalization (optional section or discussion)
Live mode shows the same three presentations working with interpretations computed from the actual scene: a rule-based spatial parser plus on-device detection. A future system could replace the parser with a vision-language model, or the detector with an open-vocabulary model, without changing the interface. The data model (`AIInterpretation`) is shared by all conditions.

### Figures to update
- **System diagram, section 6 (AR processing):**
  - Object-Anchored AR now uses **object detection** instead of a user tap. The tap is only a fallback.
  - Screen-Fixed AR has no tap step.
- **Section 4 correction list:** Coffee cup / Water bottle / **Laptop**.

---

## 7. Not yet verified on a device

The project builds, and the Live-mode parser was tested with simulated detections on a Mac. The following must be checked on an iPhone:

- [x] The Object-Anchored card lands on the water bottle (confirmed by the author).
- [ ] Detection success rate under the actual study lighting and desk arrangement.
- [ ] The send button enables after scanning. The locked question cannot be edited in Scripted mode.
- [ ] Live mode: swapping the cup and the bottle changes the answer, and *"What is this?"* names the object in the centre of the view.
- [ ] After a correction, the card (and in Object AR, the anchor) moves to the corrected object.
