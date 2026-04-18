# Private Edge Chat

A **privacy-first, on-device AI assistant** for iOS and iPadOS. All inference runs locally on Apple Silicon and no data leaves your device unless you explicitly enable live web search.

Now includes a first-run authentication landing flow with **Sign in with Apple**, local credentials, device authentication (Face ID / Touch ID / passcode), and guest access.

Built with **SwiftUI**, powered by **llama.cpp** (GGUF models) and **Apple MLX** (MLX models), with a curated catalog of 35 models from 4 AI labs.

---

## Features

### On-Device Inference
- **Dual runtime**: llama.cpp for GGUF models, Apple MLX for MLX-optimized models
- **Streaming responses**: Token-by-token output via `AsyncStream`
- **Device-aware context window**: 2048 tokens on A14 (iPhone 12), 4096 on A15/A16, 8192 on A17/A18 and iPad — prevents KV cache OOM crashes
- **Flash attention**: Automatically enabled on A15+ for ~20-30% speedup
- **Configurable system prompt** for customizing assistant behavior
- **Stop generation**: Cancel in-progress responses at any time

### Model Library
- **35 models** from 4 labs: Google DeepMind (Gemma), Alibaba Cloud (Qwen), Liquid AI (LFM), Hexgrad (Kokoro)
- **17 GGUF models** (llama.cpp runtime) + **18 MLX models** (Apple MLX runtime, including voice assets)
- Filter by lab, capability (Thinking, Vision, Tool Calling), runtime type, iPhone compatibility
- Capability badges grounded in actual model card specs: native tool-call tokens, vision encoders in weights
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
│   └── MockCatalogData.swift          # 35 curated model entries with verified URLs and accurate capability flags
│
├── Services/
│   ├── HFTokenManager.swift           # Keychain-backed HuggingFace token storage
│   ├── Inference/
│   │   ├── InferenceService.swift          # Protocol: generateReply + generateStream
│   │   ├── DeviceCapabilityService.swift   # Chip detection → n_ctx tier + flash attention
│   │   ├── LocalLlamaInferenceService.swift  # llama.cpp bridge + PromptRenderer (GGUF)
│   │   ├── LocalLlamaRuntime.swift         # Actor: isLoading guard, ensureContext(), device n_ctx
│   │   ├── MLXInferenceService.swift       # Apple MLX bridge (MLX models)
│   │   └── MockInferenceService.swift      # Test stub
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

LocalAIEdgeAppTests/
├── DeviceCapabilityTests.swift        # n_ctx tier + flash attention for all device tiers
└── PromptRendererTests.swift          # Token budget math, HTML stripping
```

### Key Patterns
- **`@Observable` state**: `AppStateStore` + `AuthStateStore` injected via environment
- **Protocol-oriented services**: `InferenceService`, `SearchGateway`, `ModelDownloadService` are all protocol-based for testability
- **Actor isolation**: `LocalLlamaRuntime` and `MLXRuntime` are Swift actors for thread-safe C/MLX interop
- **Device-aware inference**: `DeviceCapabilityService` reads `hw.machine` via `sysctlbyname` to select n_ctx (2048/4096/8192) and enable flash attention per chip generation
- **Environment-based navigation**: `SelectedTabKey` EnvironmentKey enables cross-tab navigation without tight coupling

---

## Model Catalog

### Supported Families

| Lab | Family | Models | Runtimes |
|-----|--------|--------|----------|
| Google DeepMind | Gemma | 10 | GGUF, MLX |
| Alibaba Cloud | Qwen | 18 | GGUF, MLX |
| Liquid AI | LFM | 6 | GGUF, MLX |
| Hexgrad / MLX Community | Kokoro | 1 | MLX (voice) |

### Capabilities
- **Thinking**: Native `/think` and `/no_think` soft switches (all Qwen 3 models). Produces `<think>...</think>` chain-of-thought blocks in the response.
- **Vision**: Dedicated vision encoder in model weights. Gemma 3n (E2B/E4B): MatFormer multimodal (image + video + audio). Gemma 3 4B: SigLIP vision encoder (896×896). LFM2.5 VL 1.6B: multimodal vision-language.
- **Tool Calling**: Native `<tool_call>` tokens in chat template (Qwen 3 all sizes, Qwen 2.5 3B+), or `<|tool_call_start|>` tokens (LFM2.5 1.2B). Reliable at 3B+.
- **Reasoning**: Enhanced logical reasoning and instruction following

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
# Step 1: Build for physical iPhone (Apple Silicon MLX)
xcodebuild -project LocalAIEdgeApp.xcodeproj -scheme LocalAIEdgeApp \
  -destination 'generic/platform=iOS' build \
  DEVELOPMENT_TEAM=43NV5DTHKG CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates 2>&1 | tail -25

# Step 2: Re-sign the vendored llama.framework + install on device
APP_PATH="/Users/vinothrajalingam/Library/Developer/Xcode/DerivedData/LocalAIEdgeApp-gllewxtrntbibwghleczjzxazpss/Build/Products/Debug-iphoneos/LocalAIEdgeApp.app"
codesign --force \
  --sign "Apple Development: vinoth.rajalingam@icloud.com (3TUK6Q66NM)" \
  --deep "$APP_PATH/Frameworks/llama.framework" && echo "Signed OK" \
  && xcrun devicectl device install app \
     --device 428A7E6B-8497-56D4-B7A2-02ABAD4FC996 "$APP_PATH"
```

> **Key values (this repo)**
> | Variable | Value |
> |---|---|
> | `DEVELOPMENT_TEAM` | `43NV5DTHKG` |
> | Signing identity | `Apple Development: vinoth.rajalingam@icloud.com (3TUK6Q66NM)` |
> | Device UUID ("Vinoths") | `428A7E6B-8497-56D4-B7A2-02ABAD4FC996` |
> | DerivedData folder | `LocalAIEdgeApp-gllewxtrntbibwghleczjzxazpss` |
> | Simulator destination | `platform=iOS Simulator,name=iPhone 16 Pro Test` |

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

Set the gateway URL in **Settings → Custom Gateway URL** (default: `http://localhost:8787/api/search`).
The app also accepts the base gateway URL `http://localhost:8787` and normalizes it to the bundled `/api/search` endpoint automatically.

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
- **Device-aware n_ctx**: `DeviceCapabilityService` reads `hw.machine` via `sysctlbyname` → 2048 (A14/iPhone 12), 4096 (A15/A16), 8192 (A17/A18/iPad/Simulator)
- **Flash attention**: `LLAMA_FLASH_ATTN_TYPE_ENABLED` on A15+ for ~20-30% decode speedup
- **Context reuse**: `ensureContext()` helper avoids reloading when model and `maxGeneratedTokens` are unchanged
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
| Swift files | ~36 |
| Lines of code | ~6,000 |
| Model catalog entries | 35 |
| GGUF models | 17 |
| MLX models | 18 |
| AI Labs | 4 |
| Search providers | 4 |
| Unit tests | 14 (DeviceCapability + PromptRenderer) |
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
