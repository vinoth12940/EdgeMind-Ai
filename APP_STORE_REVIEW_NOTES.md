# App Store Review Notes

*Please provide these notes in the App Store Connect submission fields for "App Review Information > Notes".*

---

## 1. Reviewer Access & Authentication

- **No Remote Account Required**: The application does not connect to a remote authentication server. 
- **Immediate Local Access**: The app opens directly into the local chat workspace and creates an anonymous on-device guest profile automatically. No login, account creation, email, or onboarding choice is required to test the core app.
- **Entitlements Note**: Sign in with Apple is disabled in this build as the app's core local AI capabilities do not require cloud user profiles.

---

## 2. Core Functionality & Testing Guidance

Edge Mind Ai is a native SwiftUI interface for on-device AI inference. To verify the app's features without downloading large models, please follow these steps:

1. **Launch**: Open the app. It starts directly in the **Chat** tab with a local guest profile.
2. **Pre-configured Model**: The default active model is **"Apple Intelligence"** (System Foundation Model). You can immediately send text prompts (e.g., *"Hello on-device AI!"*) and receive instant replies. This requires **no downloading** and runs completely offline.
3. **Voice Dictation & Playback**: Tap the **Microphone** icon in the chat composer to grant Speech Recognition and Microphone permissions. Speak a prompt, and the app will transcribe it through Apple's speech APIs. The app can play back text responses through standard iOS text-to-speech; downloaded AI models do not process audio.
4. **Third-Party Model Downloads (Optional)**:
   - Go to the **Models** tab.
   - You can download a lightweight on-device model from the curated list. For fast testing, we recommend **LFM2.5 350M (MLX)** (~0.4 GB) or **Granite 3.3 2B (MLX)** (~1.4 GB).
   - The Models tab contains a curated, device-audited catalog only. It does not expose arbitrary community repository discovery or unsupported audio/video model downloads.
   - Once downloaded, you can select it from the chat header dropdown and run text or document prompts completely offline. Verified vision models also expose camera/photo attachment for local image understanding.
5. **Optional Tools & Web Search**:
   - Version 0.2.0 adds local tool support for capable models, including calculator, device information, attached document reading, and local chat-history search.
   - Live Web Search remains optional and is OFF by default. Users must configure their own search provider and explicitly enable search before a prompt is sent to a web search gateway.
6. **Prompt Library**:
   - The chat composer includes a built-in prompt library for writing, coding, learning, and productivity prompts. These templates are bundled locally and do not require an account or network service.

---

## 3. Technical Constraints & Simulator Limitations

- **Physical Device Required for MLX Runtimes**: Apple’s MLX framework does not support compilation or execution on the iOS Simulator due to hardware acceleration architecture constraints. If you run this app on the Xcode Simulator, GGUF models and Apple Intelligence models will function, but MLX models in the catalog will appear grayed out or unavailable. **Please test MLX inference on a physical iPhone (iPhone 12 or newer running iOS 17+)**.
- **Static Weights Compliance (Guideline 2.5.2)**: The downloaded GGUF/MLX weights are strictly model data files (matrices/tensors) parsed by native on-device libraries. They do not contain executable binaries, nor do they modify the app's compiled execution paths.

---

## 4. Hardware permissions & Local Storage Disclosures

- **Microphone & Speech Recognition**: Used only when the user dictates prompts. This is an iOS speech input feature, not downloaded model audio inference.
- **Camera & Photo Library**: Used only when attaching images to prompts for local analysis (multimodal models). Photos are processed locally and downsampled before inference.
- **Face ID**: Optional. Used only for local profile confirmation actions in Settings; the app does not require biometric authentication to launch or chat.
- **Data Protection**: Chat sessions, settings, and Hugging Face tokens are stored locally on the device (tokens are secured in the secure Keychain). No analytics, user telemetry, or user prompts are uploaded to remote servers.
- **Search Provider Keys**: Optional search-provider keys are stored in the iOS Keychain. They are used only if the user enables Live Web Search.

---

## 5. China Mainland Availability

China mainland has been removed from app availability for this version. The app is not distributed in China mainland.

Metadata wording that referenced third-party AI branding has been removed. Edge Mind Ai is not affiliated with any third-party AI service provider.
