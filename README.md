# Edge Mind Ai

A **privacy-first, on-device AI assistant** for iOS and iPadOS. All inference runs locally on Apple Silicon and no data leaves your device unless you explicitly enable live web search.

Now includes a first-run authentication landing flow with local credentials, device authentication (Face ID / Touch ID / passcode), and guest access. Sign in with Apple code is present but hidden in the App Store-ready build until the App ID entitlement is enabled.

Built with **SwiftUI**, powered by **llama.cpp** (GGUF models), **Apple MLX** (MLX models), **LiteRT-LM**, and Apple Foundation Models, with a curated chat catalog of 21 runtime-backed models.

---

## Features

### On-Device Inference
- **Local runtimes**: llama.cpp for GGUF models, Apple MLX for MLX-optimized models, LiteRT-LM for Gemma image models, and Apple Foundation Models when available
- **Streaming responses**: Token-by-token output via `AsyncStream`
- **Device-aware context window**: 2048 tokens on A14 (iPhone 12), 4096 on A15/A16, 8192 on A17/A18 and iPad — prevents KV cache OOM crashes
- **Flash attention**: Automatically enabled on A15+ for ~20-30% speedup
- **Configurable system prompt** for customizing assistant behavior
- **Stop generation**: Cancel in-progress responses at any time

### Model Library
- **21 chat models** across Apple Intelligence, Gemma, Granite, Llama, Phi, DeepSeek, Mistral, SmolLM, Qwen, and LFM families
- **2 GGUF models** (llama.cpp runtime), **16 MLX models** (Apple MLX runtime), **2 LiteRT-LM models**, and **1 Apple Foundation Models entry**
- Filter by lab, capability (Thinking, Vision, Tool Calling), runtime type, iPhone compatibility
- Capability badges are grounded in verified app runtime behavior, not just upstream model-card claims
- LFM text models run through the documented ChatML-style template; verified VLM/LiteRT entries expose image input
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
EdgeMindAi/
├── App/
│   ├── EdgeMindAiApp.swift          # @main entry point, auth gate + injects AppStateStore/AuthStateStore
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
│   ├── AuthStateStore.swift           # @Observable auth/session state for local/device/guest login
│   └── MockCatalogData.swift          # 15 curated chat model entries with runtime-grounded capability flags
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
│       └── PrivacyExplainerView.swift # In-app Privacy Policy
│
├── DesignSystem/
│   └── AppTheme.swift                 # Colors, gradients, shadows, view modifiers
│
└── Resources/                         # Assets, app icon

EdgeMindAiTests/
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
| Apple | Apple Intelligence | 1 | Foundation Models |
| Google DeepMind | Gemma | 4 | MLX, LiteRT-LM |
| IBM | Granite | 1 | MLX |
| Meta | Llama | 1 | MLX |
| Microsoft | Phi | 1 | MLX |
| DeepSeek | DeepSeek | 1 | MLX |
| Mistral AI | Mistral | 1 | MLX |
| Hugging Face | SmolLM | 1 | MLX |
| Alibaba Cloud | Qwen | 6 | GGUF, MLX |
| Liquid AI | LFM | 4 | MLX |

### Capabilities
- **Thinking**: Native Qwen thinking blocks plus Gemma channel-style thinking output are parsed into the chat thinking lane.
- **Vision**: Verified Qwen 3.5 VL, LFM2.5 VL, and Gemma 4 LiteRT-LM entries accept image + text. Text-only models stay text/document-only.
- **Tool Calling**: Runtime profiles enable tool-call handling only for catalog entries with a verified app-side parser path.
- **Reasoning**: Enhanced logical reasoning and instruction following

### Quantization
GGUF models use **Q4_K_M** quantization for optimal size/quality balance on mobile devices. MLX models use curated 4-bit or 6-bit quantization from `mlx-community`; LiteRT-LM entries use INT4 packaged model assets.

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
xcodebuild -project EdgeMindAi.xcodeproj -scheme EdgeMindAi \
  -destination 'generic/platform=iOS' build \
  DEVELOPMENT_TEAM=43NV5DTHKG CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates 2>&1 | tail -25

# Step 2: Re-sign the vendored llama.framework + install on device
APP_PATH="/Users/vinothrajalingam/Library/Developer/Xcode/DerivedData/EdgeMindAi-gllewxtrntbibwghleczjzxazpss/Build/Products/Debug-iphoneos/EdgeMindAi.app"
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
> | DerivedData folder | `EdgeMindAi-gllewxtrntbibwghleczjzxazpss` |
> | Simulator destination | `platform=iOS Simulator,name=iPhone 16 Pro Test` |

### Sign in with Apple Capability (Optional)

The App Store-ready build hides Sign in with Apple because the current entitlements file does not enable `com.apple.developer.applesignin`. This avoids exposing a broken login path to App Review.

To re-enable Apple ID login for a paid developer team:
1. Uncomment `com.apple.developer.applesignin` in `EdgeMindAi/EdgeMindAi.entitlements`.
2. Open Apple Developer portal → **Identifiers** → your App ID.
3. Enable **Sign In with Apple**.
4. Regenerate or refresh provisioning profiles.
5. Restore the Apple sign-in section in `AuthLandingView`.

If device build fails with provisioning errors like:
- `doesn't include the Sign In with Apple capability`
- `doesn't include the com.apple.developer.applesignin entitlement`
confirm the App ID and provisioning profile both include this capability.

### Build for Simulator (GGUF only, no MLX)

```bash
xcodebuild -project EdgeMindAi.xcodeproj \
  -scheme EdgeMindAi \
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
- **Credentials** (local profile)
- **Device auth** (Face ID / Touch ID / passcode)
- **Guest**

Profile details are shown in **Settings → Profile**. Session is persisted locally on-device.

### App Review Notes

`APP_STORE_REVIEW_NOTES.md` contains reviewer instructions for guest access, optional model downloads, MLX-on-device behavior, Live Search, and privacy disclosures. Paste the relevant sections into App Store Connect before submitting.

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
| Model catalog entries | 15 |
| GGUF models | 4 |
| MLX models | 11 |
| AI Labs | 4 |
| Search providers | 4 |
| Unit tests | 40+ XCTest coverage across device capability, prompting, streaming, runtime profiles, and catalog migration |
| Bundle ID | `com.vinothrajalingam.EdgeMindAi` |
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
- In-app Privacy Policy is available at **Settings → Privacy → Privacy Policy**.
- `PrivacyInfo.xcprivacy` declares required-reason API usage for app-local `UserDefaults` and disk-space checks.

---

## License

Repository sanitized for public distribution. Set your own bundle identifier, signing team, and deployment settings before release.
