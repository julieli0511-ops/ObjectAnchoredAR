# ObjectAnchoredAR

**Word count:** 757 words

An iPhone AR assistant for finding things around you. Ask about the scene, for example *"Can you find the cup to the left of my laptop?"*. The assistant points to the object it means, so you can see whether it understood you, and then confirm or correct it.

The answer can be shown in three ways:
- **Chat**: a message.
- **Screen**: a card fixed to the screen.
- **Object**: a card on the object itself.

**Evaluation mode** uses a fixed question and a deliberately wrong answer for user testing. Design and evaluation notes are in [docs/thesis-notes.md](docs/thesis-notes.md).

## Project status

| Feature | Status |
|---|---|
| Chat, Screen and Object displays | ✅ Implemented |
| On-device assistant (default): spatial questions + YOLOv3-Tiny detection | ✅ Implemented |
| Vision model (Qwen2.5-VL via Ollama on a computer on the same Wi-Fi) | ✅ Implemented; not yet tested from the iPhone |
| Object card placed on the object by detection, with a connector line and a dashed ring | ✅ Implemented; confirmed on iPhone |
| "Which cup do you mean?" with numbered boxes when unsure | ✅ Implemented; boxes not yet checked on iPhone |
| Confidence bar, source label, elapsed time with Cancel, clear errors | ✅ Implemented |
| Confirm, or correct by choosing the object | ✅ Implemented |
| Evaluation mode: scripted wrong answer, responses saved as JSON | ✅ Implemented (AI answer **simulated**) |
| Counterbalancing, participant ID, NASA-TLX, user testing | ⏳ Planned |

## Technology stack

| Part | Technology |
|---|---|
| App | Swift 5, UIKit, Xcode 26, iOS 17+ |
| AR | ARKit (tracking, raycasting), RealityKit (3D card) |
| Object detection | Vision + Core ML, Apple's YOLOv3-Tiny, on the device |
| On-device assistant | Rule-based question parser (`SpatialQuery.swift`) |
| Vision model | Qwen2.5-VL 7B in Ollama: free, no API key, images stay on your network |
| Data | JSON in the app's Documents folder (Evaluation mode only) |

**Not yet decided:**
- Vision model size: the 7B model takes about 14 s per answer.
- Local or cloud vision model: cloud would need ethics approval.
- App name.

## Running or inspecting the work

Requires Xcode 26 and an iPhone with ARKit. The Simulator shows the screens but has no camera.

1. Open `outputs/ObjectAnchoredAR.xcodeproj`, choose your signing team, and run on the iPhone.
2. Move the phone over a table until the send button turns on.
3. Ask a question.
4. Switch the display with the top bar.
5. The ⚙️ menu chooses **On-device**, **Vision model** or **Evaluation mode**.

**Vision model (optional):** install [Ollama](https://ollama.com/download), then run:
```
ollama pull qwen2.5vl:7b
```
- In Ollama's Settings, turn on **Expose Ollama to the network**. Only do this on a trusted network.
- In the app, set **⚙️ → Server…** to `http://<your-mac>.local:11434` and run **Test connection**.

**Evaluation data:** responses are saved to `study_records.json`. Copy it off the iPhone with the Files app.

## Development record

| Commit | Change → reason → check |
|---|---|
| [`0fc9075`](https://github.com/julieli0511-ops/ObjectAnchoredAR/commit/0fc9075c07d3de463f8cb72f03ef4c1f7a4eb1b1) | First prototype: one screen per display, simulated answer. |
| [`6bbdd37`](https://github.com/julieli0511-ops/ObjectAnchoredAR/commit/6bbdd37dc19abafeb465157c747bac859c7851fb) | Merged into one camera screen to match my storyboard. Fixed four problems found against my system diagram: identical Chat and Screen displays, missing Object buttons, wrong condition logged, records not saved. Checked with Xcode builds. |
| [`c68394d`](https://github.com/julieli0511-ops/ObjectAnchoredAR/commit/c68394dacd74aebabcdde302d8c5f5b47ddd4889) | The Object card is placed by detection instead of a tap, so users do not decide where the AI's answer appears. Confirmed on iPhone. Added the on-device assistant. |
| [`604ac80`](https://github.com/julieli0511-ops/ObjectAnchoredAR/commit/604ac80) | README and thesis notes. |
| [`16112c4`](https://github.com/julieli0511-ops/ObjectAnchoredAR/commit/16112c4) | Free local vision model instead of a paid cloud API: no cost, and images stay local. A Mac test showed scaled boxes; sending 840×1120 images fixed it. |
| [`c93b925`](https://github.com/julieli0511-ops/ObjectAnchoredAR/commit/c93b925182932dd4e4fe53c8e67682c0947bdc2c) | Reframed from an experiment to a tool: the assistant is the default and the experiment became Evaluation mode. Added clarifying questions, Cancel, a confidence bar and a macOS-like look. Explained the locked question after I could not tell why typing failed. Checked with Simulator screenshots. |

## AI assistance

**Tool:** Claude Code (Claude Opus 5.5), used for the code.

- **What I asked:**
  - review the prototype against my diagrams;
  - add object detection, the on-device assistant and the vision model;
  - critique my design choices as a marker;
  - restyle the app from a reference image I gave it.
- **What I changed or decided:**
  - I changed its coffee-machine scene back to my laptop desk.
  - I replaced Notebook with Laptop in the correction options.
  - I chose a free model over its paid cloud suggestion.
  - I picked which suggested improvements to build.
  - I paused counterbalancing and NASA-TLX.
  - I made the assistant the default.
- **How I checked:**
  - Xcode builds and Simulator screenshots;
  - on the iPhone, the Object card lands on the water bottle;
  - my iPhone testing found two problems: "Water bottle" was still shown when I pointed at the laptop, and the question field would not accept typing;
  - the parser and the clarifying-question rule were tested on the Mac.

## Additional files

- [`docs/thesis-notes.md`](docs/thesis-notes.md): design rationale, data fields, evaluation notes.
- No ZIP; everything, including the 35 MB Core ML model, is in this repository.
