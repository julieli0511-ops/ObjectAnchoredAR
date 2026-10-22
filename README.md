# ObjectAnchoredAR

**Word count:** 1377 words

An iPhone AR assistant for finding things around you. You ask a question about the scene, such as *"Can you find the cup to the left of my laptop?"*. The assistant shows its answer in the camera view and points to the object it means, so you can see at a glance whether it understood you. You can then confirm the answer or correct it.

The same answer can be shown in three ways:
- **Chat**: a message with a full sentence.
- **Screen**: a compact card fixed to the screen.
- **Object**: a card standing on the object itself.

An **Evaluation mode** uses a fixed question and a deliberately wrong answer. It is for user testing: do people notice when the AI misunderstands, and which display helps most?

More detail on the design, the data and the evaluation is in [docs/thesis-notes.md](docs/thesis-notes.md).

---

## Project status

**Working prototype on iPhone.** Everything below builds in Xcode. The cards were checked in the iOS Simulator; AR placement was checked on an iPhone where noted.

| Feature | Status |
|---|---|
| Ask a question; the answer is shown as Chat, Screen or Object display | ✅ Implemented |
| **On-device assistant** (default): parses spatial questions and finds objects with YOLOv3-Tiny | ✅ Implemented |
| **Vision model** (Qwen2.5-VL via Ollama on a computer on the same Wi-Fi) | ✅ Implemented; tested on the Mac, not yet from the iPhone |
| Object card placed on the object automatically, with a connector line and a dashed ring | ✅ Implemented; placement confirmed on iPhone |
| Asks "Which cup do you mean?" with numbered boxes when several objects fit or it is unsure | ✅ Implemented; box positions not yet checked on iPhone |
| Confidence bar, answer source label, elapsed time with Cancel, clear errors | ✅ Implemented |
| Confirm, or correct by choosing the right object; the answer updates | ✅ Implemented |
| **Evaluation mode**: fixed question, scripted wrong answer, responses saved as JSON | ✅ Implemented (the AI answer is **simulated**) |
| Counterbalanced condition order, participant ID, NASA-TLX questionnaire | ⏳ Planned |
| User testing with participants | ⏳ Planned |

---

## Technology stack

| Part | Technology | What it does |
|---|---|---|
| App | Swift 5, UIKit, Xcode 26, iOS 17+ | Screens, cards, menus |
| AR | ARKit world tracking + raycasting; RealityKit | Finds surfaces; places and draws the 3D Object card |
| Object detection | Vision + Core ML, Apple's **YOLOv3-Tiny** (80 COCO classes) | Finds objects in the camera image, on the device |
| On-device assistant | Rule-based parser (`SpatialQuery.swift`) | Understands "the X left of / right of / next to the Y" and "What is this?" |
| Vision model | **Qwen2.5-VL 7B** served by **Ollama** | Understands any question about the image. Free, no API key; images stay on your network |
| Data | `Codable` JSON in the app's Documents folder | Evaluation-mode records |
| AI coding assistant | Claude Code (see [AI assistance](#ai-assistance)) | Helped write the code |

**Choices not yet decided**
- Vision model size: 7B answers in about 14 s on an M3 Mac. A smaller model would be faster but less accurate.
- Whether to keep the vision model on a local computer or move it to a cloud service. The cloud option would need ethics approval, because images would leave the device.
- A product name for the app.

### Repository structure
```
outputs/ObjectAnchoredAR.xcodeproj    Xcode project
outputs/ObjectAnchoredAR/
  ViewController.swift                Main screen: camera, three displays, responses, menus
  AIInterpretation.swift              Shared answer model; evaluation records (JSON)
  ObjectLocator.swift                 On-device object detection (YOLOv3-Tiny)
  SpatialQuery.swift                  On-device question parser and icons
  VLMClient.swift                     Vision-model client (Ollama)
  InterfaceStyle.swift                Colours, cards, buttons, confidence bar
  YOLOv3Tiny.mlmodel                  Core ML model
docs/thesis-notes.md                  Design, data and evaluation notes
```

---

## Running or inspecting the work

**Requirements:** a Mac with Xcode 26, and an iPhone with ARKit. The Simulator shows the screens but has no camera or AR.

1. Open `outputs/ObjectAnchoredAR.xcodeproj`.
2. Choose your signing team.
3. Run on the iPhone and allow camera access.
4. Move the phone slowly over a table until the send button turns on.
5. Ask a question, for example *"Where is my cup?"*.

**Displays and settings**
- Switch the display with the bar at the top: Chat, Screen or Object.
- The gear menu (⚙️) chooses the assistant: **On-device** or **Vision model**. It also has **Evaluation mode**.

**Vision model (optional)**
1. Install [Ollama](https://ollama.com/download) on a Mac and run:
   ```
   ollama pull qwen2.5vl:7b
   ```
2. In Ollama's Settings, turn on **Expose Ollama to the network**. Only do this on a trusted network: the API has no password.
3. Put the Mac and the iPhone on the same Wi-Fi.
4. In the app, open **⚙️ → Server…** and enter `http://<your-mac>.local:11434`.
5. Run **Test connection** to check it.

No API key is needed. If the server cannot be reached, the app says so and offers to answer on the device.

**Evaluation mode and data**
- Choose **⚙️ → Evaluation mode**. The question is fixed and the answer is always *"Water bottle, right side of laptop"*.
- Each response is appended to `study_records.json`. Copy it off the iPhone with the Files app or Finder.
- The fields are explained in the thesis notes.

---

## Development record

| Date | Commit | What changed, why, and how it was checked |
|---|---|---|
| 2026-10-20 | [`0fc9075`](https://github.com/julieli0511-ops/ObjectAnchoredAR/commit/0fc9075c07d3de463f8cb72f03ef4c1f7a4eb1b1) | First prototype: camera view, simulated AI answer, and separate screens for the three displays. |
| 2026-10-22 | [`6bbdd37`](https://github.com/julieli0511-ops/ObjectAnchoredAR/commit/6bbdd37dc19abafeb465157c747bac859c7851fb) | All three displays on one camera screen, to match my flow storyboard. A review against my system diagram found four problems: Chat and Screen looked identical, the Object buttons disappeared, every response was logged as "2D", and records were never saved. Fixed all four and checked with Xcode builds. |
| 2026-10-22 | [`c68394d`](https://github.com/julieli0511-ops/ObjectAnchoredAR/commit/c68394dacd74aebabcdde302d8c5f5b47ddd4889) | **Object detection places the Object card** instead of the user tapping, so the user does not decide where the AI's answer appears. Confirmed on iPhone that the card lands on the water bottle. Also added the on-device assistant and answers that update after a correction. |
| 2026-10-22 | [`604ac80`](https://github.com/julieli0511-ops/ObjectAnchoredAR/commit/604ac80) | README and thesis notes. |
| 2026-10-22 | [`16112c4`](https://github.com/julieli0511-ops/ObjectAnchoredAR/commit/16112c4) | **Free vision model** (Qwen2.5-VL, local Ollama) so the assistant can understand any question. Chosen instead of a paid cloud API, so it has no cost and images stay local. A test on the Mac showed the model's boxes were scaled; sending 840×1120 images fixed this (checked against known object positions). |
| 2026-10-22 | [`c93b925`](https://github.com/julieli0511-ops/ObjectAnchoredAR/commit/c93b925182932dd4e4fe53c8e67682c0947bdc2c) | **Reframed from an experiment to a tool.** The assistant is now the default, and the scripted wrong answer became Evaluation mode. Added: a clarifying question when several objects fit; elapsed time with Cancel; a confidence bar; a macOS-like look; and an explanation when the evaluation question is locked (I could not tell why typing did not work). Removed the unused legacy screens. Checked with Simulator screenshots. |

---

## AI assistance

**Tool:** Claude Code (Anthropic, model Claude Opus 5.5), used in the terminal on this repository. This section covers help with the code.

**What I asked it to do**
- Review the prototype against my flow and system diagram, and fix what did not match (`6bbdd37`).
- Add object detection to place the Object card, and the on-device assistant (`c68394d`). It downloaded Apple's YOLOv3-Tiny model.
- Add the vision-model mode (`16112c4`). It installed Ollama, downloaded Qwen2.5-VL and tested it on the Mac.
- Review my design choices as a marker would, then make the app read as a tool rather than an experiment (`c93b925`).
- Add the improvements I chose from its suggestions: a clarifying question, Cancel with elapsed time, a confidence bar, the dashed ring, and removing the legacy screens (`c93b925`).
- Restyle the app to look more like macOS, following a reference image I gave it (`c93b925`).

**How I used or changed its suggestions**
- It changed the scene to a coffee machine. I changed it back to the laptop desk from my system diagram.
- I changed the correction options from Notebook to Laptop.
- It proposed a paid cloud model. I asked for a free one instead, which led to the local Ollama setup.
- I accepted its suggestion to place the card by detection instead of a tap.
- I chose which suggested improvements to build.
- I stopped it before it added counterbalancing and NASA-TLX; these stay planned.
- I decided to make the assistant the default and keep the experiment as Evaluation mode.

**How I checked the result**
- Xcode builds after every change, and Simulator screenshots of the cards.
- On my iPhone: the Object card lands on the water bottle.
- On the iPhone I also found two problems:
  - pointing at the laptop still answered "Water bottle", which led to *"What is this?"* questions and icons that update after a correction;
  - I could not type in the question field, which led to the lock and its explanation.
- The question parser and the clarifying-question rule were tested on the Mac with simulated detections.
- The vision model's boxes were checked against known object positions.
- Not yet checked on the iPhone: the vision model over Wi-Fi, and the numbered boxes.

---

## Additional files

- [`docs/thesis-notes.md`](docs/thesis-notes.md): design rationale, the evaluation data fields, and notes for the report.
- There is no ZIP. Everything is in this repository. The Core ML model (`YOLOv3Tiny.mlmodel`, about 35 MB) is included.
