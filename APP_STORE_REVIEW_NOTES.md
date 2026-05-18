# App Store Review Notes

Use these notes in App Store Connect for the first App Store submission.

## Reviewer Access

- The app does not require a server account to review.
- On the first screen, choose **Continue as Guest** or create a local profile with any display name.
- Sign in with Apple is intentionally not exposed in this build because the current provisioning profile does not include the Sign in with Apple entitlement.

## Core Functionality

- Private Edge Chat is a local AI chat app for iPhone and iPad.
- Installed GGUF models run through the bundled llama.cpp runtime.
- MLX models run on physical iOS hardware only; MLX execution is disabled in the simulator by compile-time guards.
- The app can download model weights selected by the user. These downloads are model data files, not executable code, and they do not add native APIs or change the app binary.

## Network Usage

- Default chat behavior is local/offline after a model is installed.
- Hugging Face network requests occur only when the user chooses to download a model. If a model is gated, the user may enter a Hugging Face token in Settings; the token is stored in Keychain.
- Live Search is optional. It is disabled unless the user enables it and configures a provider or custom gateway. Search requests send the query to the selected provider and render citations in the chat response.

## Privacy

- The app includes an in-app Privacy Policy at **Settings > Privacy > Privacy Policy**.
- Chat sessions, profile data, model installation state, and settings are stored locally on device.
- Image attachments are downsampled before persistence and local inference.
- No analytics SDK, advertising SDK, or tracking is included.
- App Store Connect Privacy Policy URL must be set before submission.

## Permissions

- Camera and Photo Library are used only when attaching an image to a prompt.
- Microphone and Speech Recognition are used only when dictating prompts.
- Face ID / Touch ID / passcode are used only for local device authentication.

## Test Coverage

- Simulator unit tests are expected to pass.
- One test is expected to skip because MLX inference does not run in the iOS simulator.
