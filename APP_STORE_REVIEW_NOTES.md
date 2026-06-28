# App Store Review Notes

*Please provide these notes in the App Store Connect submission fields for "App Review Information > Notes".*

---

## 1. Reviewer Access & Authentication

- **No Remote Account Required**: The application does not connect to a remote authentication server. 
- **Immediate Local Access**: The app opens directly into the local chat workspace and creates an anonymous on-device guest profile automatically. No login, account creation, email, or onboarding choice is required to test the core app.
- **Entitlements Note**: Sign in with Apple is disabled in this build as the app's core local AI capabilities do not require cloud user profiles.

---

## 2. Core Functionality & Testing Guidance

LocalAI Edge is a native SwiftUI interface for on-device AI inference. To verify the app's features without downloading large models, please follow these steps:

1. **Launch**: Open the app. It starts directly in the **Chat** tab with a local guest profile.
2. **Pre-configured Model**: The default active model is **"Apple Intelligence"** (System Foundation Model). You can immediately send text prompts (e.g., *"Hello on-device AI!"*) and receive instant replies. This requires **no downloading** and runs completely offline.
3. **Voice Input/Output**: Tap the **Microphone** icon in the chat composer to grant Speech Recognition and Microphone permissions. Speak a prompt, and the app will transcribe it on-device. The app will play back responses via standard iOS text-to-speech.
4. **Third-Party Model Downloads (Optional)**:
   - Go to the **Models** tab.
   - You can download a lightweight on-device model from the curated list. For fast testing, we recommend **LFM2.5 350M (MLX)** (~0.4 GB) or **Granite 3.3 2B (MLX)** (~1.4 GB).
   - The **Browse** action searches public Hugging Face MLX-compatible repositories. Reviewers can browse the MLX Community feed or provider-focused lanes such as Gemma, Llama, Qwen, Phi, Mistral, Granite, LFM, and Smol models. The app offers only compatible MLX LLM/VLM repositories as optional local model downloads. The **Download compatible** action queues only installable results that fit the current device tier; audio, diffusion, custom-code, and unsupported repository types are shown as experimental with a reason label and are not installable from the app.
   - Once downloaded, you can select it from the chat header dropdown and run text inference completely offline.

---

## 3. Technical Constraints & Simulator Limitations

- **Physical Device Required for MLX Runtimes**: Apple’s MLX framework does not support compilation or execution on the iOS Simulator due to hardware acceleration architecture constraints. If you run this app on the Xcode Simulator, GGUF models and Apple Intelligence models will function, but MLX models in the catalog will appear grayed out or unavailable. **Please test MLX inference on a physical iPhone (iPhone 12 or newer running iOS 17+)**.
- **Static Weights Compliance (Guideline 2.5.2)**: The downloaded GGUF/MLX weights are strictly model data files (matrices/tensors) parsed by native on-device libraries. They do not contain executable binaries, nor do they modify the app's compiled execution paths.

---

## 4. Hardware permissions & Local Storage Disclosures

- **Microphone & Speech Recognition**: Used only when the user dictates prompts. Audio transcribing is processed entirely on-device via Apple's SFSpeechRecognizer APIs.
- **Camera & Photo Library**: Used only when attaching images to prompts for local analysis (multimodal models). Photos are processed locally and downsampled before inference.
- **Face ID**: Optional. Used only for local profile confirmation actions in Settings; the app does not require biometric authentication to launch or chat.
- **Data Protection**: Chat sessions, settings, and Hugging Face tokens are stored locally on the device (tokens are secured in the secure Keychain). No analytics, user telemetry, or user prompts are uploaded to remote servers.
