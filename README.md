# ObjectAnchoredAR

**Word count:** 1,161 words

An iPhone AR assistant for finding things in the kitchen. Ask about what the camera sees, for example *"What can I use to stir my soup?"* or *"Can you find the cup to the left of my laptop?"*. The assistant points to the object it means, so you can see whether it understood you, then confirm or correct it and carry on the conversation.

The answer can be shown in three ways:
- **Chat**: a conversation, with your questions and its answers.
- **Screen**: a card fixed to the screen.
- **Object**: a card on the object itself.

**Evaluation mode** uses a fixed question and a deliberately wrong answer for user testing.

## Project status

| Feature | Status |
|---|---|
| Chat, Screen and Object displays | ✅ Implemented |
| On-device assistant (default): where-is questions, common kitchen tasks, YOLOv3-Tiny detection | ✅ Implemented |
| Vision model (Qwen2.5-VL via Ollama on a computer on the same Wi-Fi): any question, with a reason | ✅ Implemented; works from the iPhone |
| Object card placed on the object by detection, with a connector line and a dashed ring | ✅ Implemented; confirmed on iPhone |
| Conversation continues after confirming or correcting, with follow-up questions | ✅ Implemented; confirmed on iPhone |
| "Which cup do you mean?" with numbered boxes when unsure | ✅ Implemented; confirmed on iPhone |
| History of past conversations (private to the app, not visible in the Files app) | ✅ Implemented; confirmed on iPhone |
| Confidence bar (on-device: labelled "Detection", the detector's score), source label, thinking indicator with Cancel, clear errors | ✅ Implemented |
| Unit tests for the question parser (10 tests) | ✅ Passing |
| Launch screen and logo; suggested questions | ✅ Implemented |
| Evaluation mode: scripted wrong answer, responses saved as JSON | ✅ Implemented (AI answer **simulated**) |
| Counterbalancing, participant ID, NASA-TLX, user testing | ⏳ Planned |

## Technology stack

| Part | Technology |
|---|---|
| App | Swift 5, UIKit, Xcode 26, iOS 17+ |
| AR | ARKit (tracking, raycasting), RealityKit (3D card) |
| Object detection | Vision + Core ML, Apple's YOLOv3-Tiny, on the device |
| On-device assistant | Rule-based question parser (`SpatialQuery.swift`) |
| Tests | XCTest (`outputs/ObjectAnchoredARTests/`) |
| Vision model | Qwen2.5-VL 7B in Ollama: free, no API key, images stay on your network |
| Data | JSON on the iPhone: history (assistant modes) and evaluation records (Evaluation mode) |

**Not yet decided:**
- Vision model size: the 7B model takes about 8–15 s per answer.
- Local or cloud vision model: cloud would need ethics approval.
- App name.

## Running or inspecting the work

Requires Xcode 26 and an iPhone with ARKit. The Simulator shows the screens but has no camera.

1. Open `outputs/ObjectAnchoredAR.xcodeproj`, choose your signing team, and run on the iPhone.
2. Type a question, or tap a suggestion.
3. Switch the display with the top bar.
4. The left button (☰) opens history.
5. The ⚙️ menu has **New conversation**, **On-device**, **Vision model** and **Evaluation mode**.
6. To run the tests, press **⌘U** in Xcode with an iPhone Simulator selected.

Code: `ViewController.swift` sets up the screen. `+Assistant`, `+Conversation` and `+ObjectPanel` hold the answer flow, the chat and the 3D card.

**Vision model (optional):**
1. Install [Ollama](https://ollama.com/download) on a Mac and run:
   ```
   ollama pull qwen2.5vl:7b
   ```
2. In Ollama's Settings, turn on **Expose Ollama to the network**. Only do this on a trusted network.
3. On the iPhone, allow **Settings → Privacy & Security → Local Network** for the app.
4. Choose **⚙️ → Vision model**. The app checks the connection.
5. If it cannot connect, set **⚙️ → Server…** to the Mac's address. Get it with:
   ```
   ipconfig getifaddr en0
   ```
   Then enter `http://<that address>:11434`.
6. Some school networks block phones from reaching computers. An iPhone hotspot avoids this.

**Example questions:**
- *Where is my cup?*
- *I need to cut some bread.*
- *What is this?*
- Vision model only: *Which tool should I use to flip a pancake?*

**Evaluation data:** responses are saved to `study_records.json`. Copy it off the iPhone with the Files app.

## Development record

| Commit | Change → reason → check |
|---|---|
| [`0fc9075`](https://github.com/julieli0511-ops/ObjectAnchoredAR/commit/0fc9075c07d3de463f8cb72f03ef4c1f7a4eb1b1) | First prototype: one screen per display, simulated answer. |
| [`6bbdd37`](https://github.com/julieli0511-ops/ObjectAnchoredAR/commit/6bbdd37dc19abafeb465157c747bac859c7851fb) | Merged into one camera screen to match my storyboard. Fixed four problems found against my system diagram: identical Chat and Screen displays, missing Object buttons, wrong condition logged, records not saved. Checked with Xcode builds. |
| [`c68394d`](https://github.com/julieli0511-ops/ObjectAnchoredAR/commit/c68394dacd74aebabcdde302d8c5f5b47ddd4889) | The Object card is placed by detection instead of a tap, so users do not decide where the AI's answer appears. Confirmed on iPhone. Added the on-device assistant. |
| [`604ac80`](https://github.com/julieli0511-ops/ObjectAnchoredAR/commit/604ac80) | README and thesis notes. |
| [`16112c4`](https://github.com/julieli0511-ops/ObjectAnchoredAR/commit/16112c4) | Free local vision model instead of a paid cloud API: no cost, and images stay local. A Mac test showed scaled boxes; sending 840×1120 images fixed it. |
| [`c93b925`](https://github.com/julieli0511-ops/ObjectAnchoredAR/commit/c93b925182932dd4e4fe53c8e67682c0947bdc2c) | Reframed from an experiment to a tool: the assistant is the default and the experiment became Evaluation mode. Added clarifying questions, Cancel, a confidence bar and a macOS-like look. Checked with Simulator screenshots. |
| [`eb5607f`](https://github.com/julieli0511-ops/ObjectAnchoredAR/commit/eb5607fb8282ede6228029fa43140021a22d74f9) | **Kitchen scenario**, to match my kitchen diagram: kitchen task questions and a "Why" reason. **Conversation**, so a correction no longer ends the exchange: follow-up questions, history. Chat-app layout, launch screen and logo. Fixed a crash, white-on-white text in Dark Mode, and a 60 s wait when the Mac was unreachable. All three were found on my iPhone. Checked with Simulator screenshots and on the iPhone. |
| [`368b846`](https://github.com/julieli0511-ops/ObjectAnchoredAR/commit/368b84679bf4de489dc3beee95ccaeb349b2003f) | **Code review** of the whole app. Fixed blank numbers on the "Which cup?" boxes, history visible in the Files app, and a silent switch to on-device. On-device confidence is now labelled "Detection", because it is the detector's score. Split the main file into four and added parser tests, to make the code easier to read and check. Checked with the tests, a Simulator screenshot and on the iPhone. |

## AI assistance

**Tool:** Claude Code (Claude Opus 5.5), used for the code.

**What I asked:**
- review the prototype against my diagrams;
- add object detection, the on-device assistant and the vision model;
- critique my design choices as a marker;
- restyle the app from a reference image;
- follow ChatGPT and Claude's chat-app conventions, without their branding;
- add a conversation, history, follow-up questions and a launch screen.

**What I changed or decided:**
- I first moved the scene back to my laptop desk, then chose the kitchen.
- I chose a free model over its paid cloud suggestion.
- I picked which suggested improvements to build, and paused counterbalancing and NASA-TLX.
- I made the assistant the default.
- I moved the settings back to the gear after trying its top-centre picker.
- I asked for a speech-bubble logo instead of its map pin.
- I set the mode description to disappear after 5 seconds.

**How I checked:**
- Xcode builds and Simulator screenshots.
- On my iPhone:
  - the Object card lands on the water bottle;
  - the vision model works over Wi-Fi;
  - the numbered boxes, follow-up questions and history work, and older history moved out of the Files app;
  - I found problems that were then fixed: a crash, unreadable text in Dark Mode, a locked question field, and the vision model being unreachable (caused by network settings).
- The parser has unit tests. The vision-model prompt was tested on the Mac.
- I asked it to review the whole app. It found a bug of its own, where the "Which cup?" boxes had no numbers. It also found history visible in the Files app. Both are fixed.

## Additional files

No additional documents or ZIP. Everything, including the 35 MB Core ML model, is in this repository.
