# Private Edge Chat

A **privacy-first, on-device AI assistant** for iOS and iPadOS. All inference runs locally on Apple Silicon and no data leaves your device unless you explicitly enable live web search.

Now includes a first-run authentication landing flow with **Sign in with Apple**, local credentials, device authentication (Face ID / Touch ID / passcode), and guest access.

Built with **SwiftUI**, powered by **llama.cpp** (GGUF models) and **Apple MLX** (MLX models), with a curated catalog of 43 models from 11 AI labs.

---

## Features

### On-Device Inference
- **Dual runtime**: llama.cpp for GGUF models, Apple MLX for MLX-optimized models
- **Streaming responses**: Token-by-token output via `AsyncStream`
- **8192 context window** (`n_ctx=8192`) for long conversations
- **Configurable system prompt** for customizing assistant behavior
- **Stop generation**: Cancel in-progress responses at any time

### Model Library
- **43 models** from 11 labs: Google DeepMind, Meta, Alibaba Cloud, Microsoft, Mistral AI, DeepSeek, Hugging Face, Stability AI, Apple, StatNLP, Liquid AI
- **32 GGUF models** (llama.cpp runtime) + **11 MLX models** (Apple MLX runtime)
- Filter by lab, capability (Thinking, Vision, Tool Calling), runtime type, iPhone compatibility
- Model specs: parameter count, context window, disk size, quantization level
- Expandable cards with model descriptions and capability badges
- All download URLs verified and working against HuggingFace

### Model Management
- **Download with progress**: Real-time progress tracking for both GGUF and MLX models
- **Delete models**: Remove downloaded models from device with confirmation dialog
- **Auto-reconciliation**: On launch, scans `Application Support/Models/` to detect already-downloaded files
- **Default model selection**: Set any installed model as the default for chat
- **HuggingFace authentication**: Store HF token in iOS Keychain for gated model access

### Authentication & Profile
- **Auth landing screen** before entering chat
- **Sign in with Apple** (`AuthenticationServices`) for iCloud-backed identity
- **Local credentials** (display name + optional email)
- **Device authentication** using Face ID / Touch ID / passcode (`LocalAuthentication`)
- **Guest mode** for quick offline usage
- **Profile card in Settings** with sign-in method, last login, re-authenticate, and sign out

### Live Web Search (Optional)
- **4 search providers**: Tavily, Brave Search, Serper (Google), or custom gateway
- **On-device API key storage**: Configure API keys directly in Settings
- **Citation support**: Search results displayed with source links inline
- Per-prompt or default-on toggle for web grounding

### Chat
- **Markdown rendering** with syntax highlighting
- **Message streaming** with typing indicator animation
- **Chat sessions**: Create, rename, delete conversations
- **History view**: Browse past conversations, tap to resume
- **Model picker sheet**: Switch between installed models mid-conversation
- **Image attachments** from camera/photo library with downsampling and bounded JPEG encoding for memory-safe local vision prompts
- **Streaming stability improvements**: stop/cancel safety and reduced write churn while tokens stream

### Design System
- **Dark-mode-only** custom design system (`AppTheme`)
- Glass-morphic card styles with accent glow effects
- Lab-specific color coding (Google blue, Meta blue, Alibaba orange, etc.)
- Capability-specific colors (Thinking pink, Vision teal, Tools orange)
- Custom floating tab bar with spring animations
- Typing indicator, shimmer loading, and pulse glow animations

### Navigation
- **Tab-based**: Chat, Models, History, Settings
- **Cross-tab navigation**: History → Chat (opens selected session), Chat → Models (browse library), Chat → History (quick access)
- **Environment-driven tab switching** via `SelectedTabKey`

---

## Architecture

```
LocalAIEdgeApp/
├── App/
│   ├── LocalAIEdgeApp.swift          # @main entry point, auth gate + injects AppStateStore/AuthStateStore
│   └── RootView.swift                # Tab navigation (Chat, Models, History, Settings)
│
├── Models/                            # Data models (Codable structs)
│   ├── ModelCatalogItem.swift         # Model families, runtimes, capabilities
│   ├── InstalledModel.swift           # Install state, progress, file path
│   ├── ChatSession.swift              # Conversation container
│   ├── ChatMessage.swift              # Message with role, citations
│   ├── AppSettings.swift              # Search provider config, system prompt
│   └── SearchContext.swift            # Web search results
│
├── State/
│   ├── AppStateStore.swift            # @Observable central state (catalog, installed, sessions)
│   ├── AuthStateStore.swift           # @Observable auth/session state for Apple ID/device/guest login
│   └── MockCatalogData.swift          # 43 curated model entries with verified URLs
│
├── Services/
│   ├── HFTokenManager.swift           # Keychain-backed HuggingFace token storage
│   ├── Inference/
│   │   ├── InferenceService.swift     # Protocol: generateReply + generateStream
│   │   ├── LocalLlamaInferenceService.swift  # llama.cpp bridge (GGUF)
│   │   ├── LocalLlamaRuntime.swift    # Actor wrapping llama.cpp C API
│   │   ├── MLXInferenceService.swift  # Apple MLX bridge (MLX models)
│   │   └── MockInferenceService.swift # Test stub
│   ├── Models/
│   │   ├── ModelDownloadService.swift # URLSession download + file management
│   │   └── ModelCatalogService.swift  # Catalog loading protocol
│   └── Search/
│       ├── SearchGateway.swift        # Protocol + mock + custom gateway
│       ├── SearchGatewayFactory.swift # Provider selection factory
│       ├── TavilySearchGateway.swift  # Tavily API integration
│       ├── BraveSearchGateway.swift   # Brave Search API integration
│       └── SerperSearchGateway.swift  # Serper (Google) API integration
│
├── Features/
│   ├── Auth/
│   │   └── AuthLandingView.swift      # First-run login/guest screen
│   ├── Chat/
│   │   ├── ChatView.swift             # Main chat interface with streaming
│   │   ├── ChatComposerView.swift     # Input bar with search toggle
│   │   ├── MessageBubbleView.swift    # User/assistant/search message bubbles
│   │   └── MarkdownTextView.swift     # Markdown rendering
│   ├── Models/
│   │   ├── ModelLibraryView.swift     # Full model catalog with filters and download
│   │   └── InstalledModelsView.swift  # Installed model cards (standalone)
│   ├── History/
│   │   └── ChatHistoryView.swift      # Session list with delete
│   └── Settings/
│       ├── SettingsView.swift         # All app configuration
│       └── PrivacyExplainerView.swift # Privacy policy card
│
├── DesignSystem/
│   └── AppTheme.swift                 # Colors, gradients, shadows, view modifiers
│
└── Resources/                         # Assets, app icon
```

### Key Patterns
- **`@Observable` state**: `AppStateStore` + `AuthStateStore` injected via environment
- **Protocol-oriented services**: `InferenceService`, `SearchGateway`, `ModelDownloadService` are all protocol-based for testability
- **Actor isolation**: `LocalLlamaRuntime` and `MLXRuntime` are Swift actors for thread-safe C/MLX interop
- **Environment-based navigation**: `SelectedTabKey` EnvironmentKey enables cross-tab navigation without tight coupling

---

## Model Catalog

### Supported Families

| Lab | Family | Models | Runtimes |
|-----|--------|--------|----------|
| Google DeepMind | Gemma | 7 | GGUF, MLX |
| Alibaba Cloud | Qwen | 12 | GGUF, MLX |
| Meta | Llama | 5 | GGUF, MLX |
| Microsoft | Phi | 4 | GGUF, MLX |
| Hugging Face | SmolLM / SmolVLM | 4 | GGUF, MLX |
| Mistral AI | Mistral | 3 | GGUF |
| DeepSeek | DeepSeek | 3 | GGUF |
| Apple | OpenELM | 2 | GGUF |
| Stability AI | StableLM | 1 | GGUF |
| StatNLP | TinyLlama | 1 | GGUF |
| Liquid AI | LFM | 1 | GGUF |

### Capabilities
- **Thinking**: Extended chain-of-thought reasoning (DeepSeek-R1, QwQ, Phi-4-mini-reasoning)
- **Vision**: Image understanding (Gemma 3, SmolVLM, Qwen2.5-VL)
- **Tool Calling**: Function/tool invocation support
- **Reasoning**: Enhanced logical reasoning

### Quantization
All GGUF models use **Q4_K_M** quantization for optimal size/quality balance on mobile devices. MLX models use 4-bit or 8-bit quantization from `mlx-community`.

---

## Getting Started

### Prerequisites
- **Xcode 16+** with iOS 17.0+ SDK
- **Apple Silicon Mac** (for MLX model testing on device)
- **Physical iOS/iPadOS device** recommended (MLX requires real Apple Silicon hardware, won't work in simulator)
- **Apple Developer team/profile configured for your bundle ID**
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (optional, for regenerating project)

### Generate Xcode Project (Optional)

If you need to regenerate from `project.yml`:

```bash
cd your-project-folder
xcodegen generate
```

### Build for Device

```bash
# Build for a connected device (replace device ID with yours)
xcodebuild -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'id=YOUR_DEVICE_UDID' \
  -allowProvisioningUpdates \
  build

# Install on device
xcrun devicectl device install app \
  --device YOUR_DEVICE_UDID \
  ~/Library/Developer/Xcode/DerivedData/LocalAIEdgeApp-*/Build/Products/Debug-iphoneos/LocalAIEdgeApp.app
```

### Sign in with Apple Capability (Required for Apple ID Login)

This app now includes `com.apple.developer.applesignin` entitlement.

If device build fails with provisioning errors like:
- `doesn't include the Sign In with Apple capability`
- `doesn't include the com.apple.developer.applesignin entitlement`

Do this:
1. Open Apple Developer portal → **Identifiers** → your App ID.
2. Enable **Sign In with Apple**.
3. Regenerate or refresh provisioning profiles.
4. In Xcode target → **Signing & Capabilities**, confirm **Sign In with Apple** is present.

### Build for Simulator (GGUF only, no MLX)

```bash
xcodebuild -project LocalAIEdgeApp.xcodeproj \
  -scheme LocalAIEdgeApp \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

> **Note**: MLX models require real Apple Silicon hardware. The MLX runtime is conditionally compiled with `#if canImport(MLXLLM) && !targetEnvironment(simulator)`.

---

## Configuration

### Web Search

Configure in **Settings → Web Search**:

| Provider | API Key Format | Endpoint |
|----------|----------------|----------|
| Tavily | `tvly-xxxxxxxxxx` | `api.tavily.com/search` |
| Brave Search | `BSAxxxxxxxxxx` | `api.search.brave.com/res/v1/web/search` |
| Serper | `xxxxxxxxxxxxxxxx` | `google.serper.dev/search` |
| Custom Gateway | N/A | Your own POST endpoint |

### Custom Search Gateway

The included `backend/search-gateway` provides a Node.js/TypeScript proxy:

```bash
cd backend/search-gateway
cp .env.example .env   # Add your search API key
npm install
npm run dev
```

Set the gateway URL in **Settings → Custom Gateway URL** (default: `http://localhost:8787`).

### HuggingFace Token

Some models require authentication. Configure in **Settings → HuggingFace → API Token**. Token is stored securely in iOS Keychain via `HFTokenManager`.

### System Prompt

Customize the AI assistant's behavior in **Settings → Behavior → System Prompt**. Default prompt emphasizes concise, factual responses with web citation support.

### Authentication

On launch, users land on an auth screen with:
- **Apple ID** (Sign in with Apple)
- **Credentials** (local profile)
- **Device auth** (Face ID / Touch ID / passcode)
- **Guest**

Profile details are shown in **Settings → Profile**. Session is persisted locally on-device.

---

## Technical Details

### llama.cpp Integration
- Pre-built xcframework in `Vendor/build-apple/` (llama.cpp build b8354)
- Direct C API access via Swift actors (`LocalLlamaRuntime`)
- Greedy/top-p sampling with temperature 0.7
- Batch processing for prompt ingestion
- UTF-8 safe token decoding with partial buffer handling

### MLX Integration
- Swift Package: `mlx-swift-examples` v2.30.6 (MLXLLM, MLXLMCommon)
- Model loading via `LLMModelFactory` with progress tracking
- Memory cache limit: 20MB (`Memory.cacheLimit`)
- Streaming generation via `container.generate()`
- Pre-download support for model caching

### Model Storage
- GGUF files: `Application Support/Models/{filename}.gguf`
- MLX models: Cached by HuggingFace hub client in standard cache directory
- File reconciliation on app launch detects orphaned/pre-downloaded models

### State Management
- Single `@Observable AppStateStore` injected via SwiftUI environment
- Catalog, installed models, chat sessions, and settings in one store
- Immutable model updates via `map` transforms on arrays
- `reconcileInstalledFiles()` syncs filesystem state on launch
- Image-bearing chat history is sanitized before persistence to avoid oversized `UserDefaults` writes

---

## Project Stats

| Metric | Value |
|--------|-------|
| Swift files | 33 |
| Lines of code | ~5,400 |
| Model catalog entries | 43 |
| GGUF models | 32 |
| MLX models | 11 |
| AI Labs | 11 |
| Search providers | 4 |
| Bundle ID | `io.example.LocalAIEdgeApp` |
| Min deployment target | iOS 17.0 |
| Color scheme | Dark mode only |

---

## Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| [llama.cpp](https://github.com/ggerganov/llama.cpp) | b8354 | GGUF model inference (pre-built xcframework) |
| [mlx-swift-examples](https://github.com/ml-explore/mlx-swift-examples) | 2.30.6 | MLX model inference (MLXLLM, MLXLMCommon) |
| XcodeGen | — | Xcode project generation from `project.yml` |

No other third-party dependencies. All UI, networking, and search integrations use native `SwiftUI`, `URLSession`, and Foundation APIs.

---

## Privacy

- **Default mode**: Fully offline. All inference runs on-device via llama.cpp or MLX.
- **Live Search**: Only activated when explicitly toggled per-prompt or in Settings. Sends the user's query to the configured search provider API.
- **No telemetry, no analytics, no cloud sync.**
- HuggingFace token stored in iOS Keychain (never transmitted except to HuggingFace for model downloads).
- Search API keys stored locally in app settings.

---

## License

Repository sanitized for public distribution. Set your own bundle identifier, signing team, and deployment settings before release.
